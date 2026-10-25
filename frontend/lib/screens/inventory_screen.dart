import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../widgets/product_details.dart';
import '../widgets/stock_notifications.dart';
import 'new_product_form.dart';
import 'movements_screen.dart';
import 'new_sale_screen.dart';
import 'sales_screen.dart';
import 'alerts_screen.dart';
import 'recommendations_screen.dart';
import 'dashboard_screen.dart';
import 'inventory_operation_page.dart';
import '../models/inventory_action.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    required this.api,
    this.currentUserId,
    this.initialDashboard = false,
    this.currentUserRole,
    this.userName,
    this.onLogout,
    super.key,
  });
  final InventoryApi api;
  final int? currentUserId;
  final bool initialDashboard;
  final String? currentUserRole;
  final String? userName;
  final Future<void> Function()? onLogout;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool get _stockRole =>
      widget.currentUserRole == null ||
      ['Administrador', 'Encargado de stock'].contains(widget.currentUserRole);
  bool get _admin =>
      widget.currentUserRole == null ||
      widget.currentUserRole == 'Administrador';
  bool get _seller =>
      widget.currentUserRole == null || widget.currentUserRole == 'Vendedor';
  bool _canAction(InventoryAction? action) =>
      action == null ||
      (action == InventoryAction.edit || action == InventoryAction.deactivate
          ? _admin
          : _stockRole);
  final _search = TextEditingController();
  List<Product> _products = [];
  Product? _selected;
  InventoryAction? _action;
  bool _movementsVisible = false;
  bool _salesVisible = false;
  bool _salesHistory = false;
  bool _alertsVisible = false;
  bool _recommendationsVisible = false;
  int? _alertProductId;
  int _alertsVisit = 0;
  int? _notifiedLowCount;
  late bool _dashboardVisible;
  int? _analysisProductId;
  Product? _operationProduct;
  bool _operationBusy = false;
  bool _loading = true;
  bool _lowOnly = false;
  String? _category;
  String? _error;
  DateTime? _updated;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _dashboardVisible = widget.initialDashboard && _stockRole;
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.loadInventory();
      if (!mounted || generation != _generation) return;
      setState(() {
        _products = data;
        _notifiedLowCount = null;
        _updated = DateTime.now();
        _selected = null;
        if (_category != null && !data.any((p) => p.category == _category)) {
          _category = null;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo cargar el inventario.';
      });
    }
  }

  List<Product> get _filtered {
    final query = searchable(_search.text.trim());
    return _products
        .where(
          (p) =>
              (!_lowOnly || p.isLow) &&
              (_category == null || p.category == _category) &&
              (query.isEmpty ||
                  searchable('${p.id} ${p.name} ${p.category}')
                      .contains(query)),
        )
        .toList();
  }

  Future<void> _newProduct() async {
    if (!_admin) return;
    final result = await openNewProduct(context, widget.api);
    if (!mounted || result == null) return;
    setState(() {
      _search.clear();
      _lowOnly = false;
      _category = null;
    });
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.id != null ? 'Producto registrado con código ${result.id}.' : 'Revisá el inventario para comprobar el resultado del registro.',
        ),
      ),
    );
  }

  Future<void> _afterEdit(
    ProductCreationResult result, {
    bool closeDetail = false,
    InventoryAction? repeatAction,
  }) async {
    if (closeDetail) Navigator.of(context).pop();
    setState(() {
      _search.clear();
      _category = null;
      _lowOnly = false;
    });
    await _reload();
    if (!mounted) return;
    if (!closeDetail && result.id != null && !result.deactivated) {
      final matches = _products.where((p) => p.id == result.id);
      if (_error == null && matches.isNotEmpty) {
        setState(() => _selected = matches.first);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        action: repeatAction == null
            ? null
            : SnackBarAction(
                label: 'Otra operación',
                onPressed: () => _startAction(repeatAction),
              ),
        content: Text(
          result.id != null
              ? (result.deactivated
                    ? 'Producto dado de baja. Se conservó su historial.'
                    : result.adjustmentQuantity != null
                    ? 'Ajuste registrado. Stock actualizado.'
                    : result.entryQuantity != null
                    ? 'Entrada registrada: ${result.entryQuantity} unidades. Stock actualizado.'
                    : result.minimumChanged
                    ? 'Stock mínimo actualizado. Se reevaluó el estado del stock.'
                    : 'Producto actualizado con código ${result.id}.')
              : 'Revisá los datos actuales del producto en el inventario.',
        ),
      ),
    );
  }

  void _open(Product p, bool wide) {
    if (wide) {
      setState(() => _selected = p);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Producto'),
            backgroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProductDetails(
              canManageProducts: _admin,
              canManageStock: _stockRole,
              product: p,
              api: widget.api,
              onClose: () => Navigator.pop(context),
              onChanged: (result) => _afterEdit(result, closeDetail: true),
              onAction: (action, product) {
                Navigator.pop(context);
                _startAction(action, product);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _startAction(InventoryAction? action, [Product? product]) {
    if (!_canAction(action)) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _dashboardVisible = false;
      _alertsVisible = false;
      _salesVisible = false;
      _movementsVisible = false;
      _action = action;
      _operationProduct = product;
    });
  }

  Future<void> _finishOperation(ProductCreationResult? result) async {
    final previous = _action;
    setState(() {
      _operationBusy = false;
      _action = null;
      _operationProduct = null;
    });
    if (result != null) {
      await _afterEdit(result, repeatAction: previous);
      if (!mounted) return;
      // The existing result message stays visible; another operation is available in the menu.
    }
  }

  void _openMovements() {
    if (!_stockRole) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _dashboardVisible = false;
      _alertsVisible = false;
      _salesVisible = false;
      _movementsVisible = true;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openNewSale() {
    if (!_seller) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _dashboardVisible = false;
      _alertsVisible = false;
      _salesVisible = true;
      _salesHistory = false;
      _movementsVisible = false;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openSalesHistory() {
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _dashboardVisible = false;
      _alertsVisible = false;
      _salesVisible = true;
      _salesHistory = true;
      _movementsVisible = false;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openAlerts([int? productId]) {
    if (!_stockRole) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _alertProductId = productId;
      ++_alertsVisit;
      _dashboardVisible = false;
      _alertsVisible = true;
      _salesVisible = false;
      _movementsVisible = false;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openDashboard() {
    if (!_stockRole) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = false;
      _analysisProductId = null;
      _dashboardVisible = true;
      _alertsVisible = false;
      _salesVisible = false;
      _movementsVisible = false;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openRecommendations() {
    if (!_stockRole) return;
    if (_operationBusy) return;
    setState(() {
      _recommendationsVisible = true;
      _dashboardVisible = false;
      _alertsVisible = false;
      _salesVisible = false;
      _movementsVisible = false;
      _action = null;
      _operationProduct = null;
    });
  }

  void _openDashboardProduct(int id) {
    if (_operationBusy) return;
    setState(() => _analysisProductId = id);
  }

  List<Product> get _lowProducts => _loading || _error != null
      ? []
      : _products.where((p) => p.isLow).toList();

  Widget _alertButton() => StockNotifications(
    api: widget.api,
    count: _notifiedLowCount ?? _lowProducts.length,
    enabled: !_operationBusy,
    onAlert: (id) => _openAlerts(id),
    onAllAlerts: () => _openAlerts(),
    onCountChanged: (count) => setState(() => _notifiedLowCount = count),
  );

  Widget _stockNotice() => Container(
    key: const Key('stock-low-notice'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3D6),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: Color(0xFF8A651D),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Stock bajo: ${_lowProducts.take(2).map((p) => '${p.name} (#${p.id})').join(', ')}${_lowProducts.length > 2 ? ' y ${_lowProducts.length - 2} más' : ''}.',
            style: const TextStyle(color: Color(0xFF795B20)),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: _openAlerts, child: const Text('Ver alertas')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final desktop = viewport.maxWidth >= 1000;
      final mobile = viewport.maxWidth < 900;
      final wide = viewport.maxWidth >= 1280;
      return PopScope(
        canPop:
            !_recommendationsVisible &&
            !_dashboardVisible &&
            !_alertsVisible &&
            !_movementsVisible &&
            !_salesVisible,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop &&
              (_recommendationsVisible ||
                  _dashboardVisible ||
                  _alertsVisible ||
                  _movementsVisible ||
                  _salesVisible) &&
              !_operationBusy) {
            if (_dashboardVisible && _analysisProductId != null) {
              setState(() => _analysisProductId = null);
            } else {
              _startAction(null);
            }
          }
        },
        child: Scaffold(
          drawer: desktop
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(children: [_navigation(drawer: true)]),
                  ),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (desktop) _sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      _header(desktop, mobile),
                      Expanded(
                        child: _recommendationsVisible
                            ? RecommendationsScreen(
                                api: widget.api,
                                currentUserId: widget.currentUserId,
                                onBusyChanged: (busy) =>
                                    setState(() => _operationBusy = busy),
                              )
                            : _dashboardVisible
                            ? DashboardScreen(
                                api: widget.api,
                                onInventory: () => _startAction(null),
                                onAlerts: _openAlerts,
                                onSales: _openSalesHistory,
                                onProduct: _openDashboardProduct,
                                analysisProductId: _analysisProductId,
                                onAnalysisClosed: () =>
                                    setState(() => _analysisProductId = null),
                                onRefreshed: _reload,
                              )
                            : _alertsVisible
                            ? AlertsScreen(
                                key: ValueKey('alerts-$_alertsVisit'),
                                initialProductId: _alertProductId,
                                api: widget.api,
                                onEntry: (product) => _startAction(
                                  InventoryAction.entry,
                                  product,
                                ),
                                onRefreshed: _reload,
                              )
                            : _salesVisible && _salesHistory
                            ? SalesScreen(api: widget.api)
                            : _salesVisible
                            ? NewSaleScreen(
                                api: widget.api,
                                currentUserId: widget.currentUserId,
                                onBusyChanged: (busy) =>
                                    setState(() => _operationBusy = busy),
                                onSaved: _reload,
                                onInventory: () => _startAction(null),
                                onMovements: _openMovements,
                              )
                            : _movementsVisible
                            ? MovementsScreen(api: widget.api, embedded: true)
                            : _action != null
                            ? InventoryOperationPage(
                                key: ValueKey(_action),
                                action: _action!,
                                api: widget.api,
                                products: _products,
                                initialProduct: _operationProduct,
                                onFinished: _finishOperation,
                                onBusyChanged: (busy) =>
                                    setState(() => _operationBusy = busy),
                              )
                            : SingleChildScrollView(
                                padding: EdgeInsets.all(mobile ? 20 : 32),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1700,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _title(mobile),
                                        if (_stockRole &&
                                            _lowProducts.isNotEmpty)
                                          _stockNotice(),
                                        const SizedBox(height: 28),
                                        _filters(mobile),
                                        const SizedBox(height: 16),
                                        _summary(),
                                        const SizedBox(height: 20),
                                        if (_loading)
                                          _message(
                                            Icons.inventory_2_outlined,
                                            'Cargando inventario',
                                            'Estamos consultando los productos y sus existencias.',
                                            loading: true,
                                          )
                                        else if (_error != null)
                                          _message(
                                            Icons.cloud_off_outlined,
                                            'No pudimos cargar el inventario',
                                            _error!,
                                            retry: true,
                                          )
                                        else if (_products.isEmpty)
                                          _message(
                                            Icons.inventory_2_outlined,
                                            'Todavía no hay productos activos',
                                            'Los productos con stock registrado aparecerán acá.',
                                          )
                                        else if (_filtered.isEmpty)
                                          _message(
                                            Icons.search_off_outlined,
                                            'No encontramos productos',
                                            'Probá con otra búsqueda o cambiá los filtros.',
                                            reset: true,
                                          )
                                        else
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: mobile
                                                    ? _mobileList()
                                                    : _table(wide),
                                              ),
                                              if (wide &&
                                                  _selected != null) ...[
                                                const SizedBox(width: 20),
                                                SizedBox(
                                                  width: 310,
                                                  child: ProductDetails(
                                                    canManageProducts: _admin,
                                                    canManageStock: _stockRole,
                                                    onChanged: _afterEdit,
                                                    onAction: _startAction,
                                                    product: _selected!,
                                                    api: widget.api,
                                                    onClose: () => setState(
                                                      () => _selected = null,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        const SizedBox(height: 20),
                                        if (!_loading &&
                                            _error == null &&
                                            _products.isNotEmpty)
                                          Text(
                                            mobile
                                                ? 'Tocá un producto para ver su detalle.'
                                                : 'Seleccioná un producto para consultar su detalle.',
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        const SizedBox(height: 28),
                                        const Text(
                                          'StockIA · Gestión inteligente de inventario',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _sidebar() => SizedBox(
    width: 248,
    child: Material(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _brand(),
          ),
          const SizedBox(height: 32),
          _navigation(),
        ],
      ),
    ),
  );

  Widget _navigation({bool drawer = false}) {
    void select(InventoryAction? action) {
      if (_operationBusy) return;
      if (drawer) Navigator.pop(context);
      _startAction(action);
    }

    return Material(
      color: Colors.white,
      child: Column(
        children: [
          if (_stockRole)
            ListTile(
              key: const Key('nav-dashboard'),
              leading: const Icon(Icons.dashboard_outlined, color: navy),
              title: const Text('Inicio'),
              selected: _dashboardVisible,
              selectedTileColor: const Color(0xFFEBF1F9),
              enabled: !_operationBusy,
              onTap: () {
                if (drawer) Navigator.pop(context);
                _openDashboard();
              },
            ),
          ExpansionTile(
            key: const PageStorageKey('inventory-navigation'),
            initiallyExpanded: true,
            leading: const Icon(Icons.inventory_2_outlined, color: navy),
            title: const Text('Inventario'),
            children: [
              ListTile(
                key: const Key('nav-inventory'),
                contentPadding: const EdgeInsets.only(left: 36, right: 12),
                selected:
                    !_recommendationsVisible &&
                    !_dashboardVisible &&
                    !_alertsVisible &&
                    !_salesVisible &&
                    !_movementsVisible &&
                    _action == null,
                selectedTileColor: const Color(0xFFEBF1F9),
                enabled: !_operationBusy,
                title: const Text(
                  'Ver inventario',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => select(null),
              ),
              ...InventoryAction.values
                  .where(_canAction)
                  .map(
                    (action) => ListTile(
                      key: ValueKey('nav-${action.name}'),
                      contentPadding: const EdgeInsets.only(
                        left: 36,
                        right: 12,
                      ),
                      selected:
                          !_recommendationsVisible &&
                          !_dashboardVisible &&
                          !_alertsVisible &&
                          !_salesVisible &&
                          !_movementsVisible &&
                          _action == action,
                      selectedTileColor: const Color(0xFFEBF1F9),
                      enabled: !_operationBusy,
                      title: Text(action.label, style: TextStyle(fontSize: 13)),
                      onTap: () => select(action),
                    ),
                  ),
            ],
          ),
          if (_stockRole)
            ListTile(
              leading: const Icon(Icons.history, color: navy),
              title: const Text('Movimientos'),
              selected: _movementsVisible,
              selectedTileColor: const Color(0xFFEBF1F9),
              enabled: !_operationBusy,
              onTap: () {
                if (drawer) Navigator.pop(context);
                _openMovements();
              },
            ),
          if (_stockRole)
            ListTile(
              key: const Key('nav-recommendations'),
              leading: const Icon(Icons.auto_awesome_outlined, color: navy),
              title: const Text('Recomendaciones'),
              selected: _recommendationsVisible,
              selectedTileColor: const Color(0xFFEBF1F9),
              enabled: !_operationBusy,
              onTap: () {
                if (drawer) Navigator.pop(context);
                _openRecommendations();
              },
            ),
          if (_stockRole)
            ListTile(
              key: const Key('nav-alerts'),
              leading: const Icon(Icons.notifications_outlined, color: navy),
              title: const Text('Alertas'),
              selected: _alertsVisible,
              selectedTileColor: const Color(0xFFEBF1F9),
              enabled: !_operationBusy,
              onTap: () {
                if (drawer) Navigator.pop(context);
                _openAlerts();
              },
            ),
          ExpansionTile(
            key: const PageStorageKey('sales-navigation'),
            initiallyExpanded: true,
            leading: const Icon(Icons.point_of_sale_outlined, color: navy),
            title: const Text('Ventas'),
            children: [
              ListTile(
                key: const Key('nav-sales-history'),
                selected: _salesVisible && _salesHistory,
                selectedTileColor: const Color(0xFFEBF1F9),
                enabled: !_operationBusy,
                contentPadding: const EdgeInsets.only(left: 36, right: 12),
                title: const Text(
                  'Consultar ventas',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () {
                  if (drawer) Navigator.pop(context);
                  _openSalesHistory();
                },
              ),
              if (_seller)
                ListTile(
                  key: const Key('nav-new-sale'),
                  selected: _salesVisible && !_salesHistory,
                  selectedTileColor: const Color(0xFFEBF1F9),
                  enabled: !_operationBusy,
                  contentPadding: const EdgeInsets.only(left: 36, right: 12),
                  title: const Text(
                    'Registrar venta',
                    style: TextStyle(fontSize: 13),
                  ),
                  onTap: () {
                    if (drawer) Navigator.pop(context);
                    _openNewSale();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brand({bool compact = false}) => Row(
    children: [
      Container(
        width: compact ? 36 : 44,
        height: compact ? 36 : 44,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.inventory_2_outlined,
          color: Colors.white,
          size: 24,
        ),
      ),
      SizedBox(width: compact ? 8 : 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'StockIA',
              style: TextStyle(
                fontSize: compact ? 19 : 21,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (!compact) const SizedBox(height: 3),
            if (!compact)
              const Text(
                'Gestión inteligente',
                style: TextStyle(fontSize: 10, color: muted),
              ),
          ],
        ),
      ),
    ],
  );
  Widget _header(bool desktop, bool mobile) => Container(
    height: mobile ? 86 : 76,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!desktop)
          Expanded(child: _brand(compact: mobile))
        else
          const Text(
            'StockIA  /  Gestión',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        if (desktop) const Spacer(),
        if (!mobile)
          Text(
            _recommendationsVisible
                ? 'Recomendaciones'
                : _dashboardVisible
                ? (_analysisProductId == null
                      ? 'Inicio'
                      : 'Análisis del producto')
                : _alertsVisible
                ? 'Alertas'
                : _salesVisible
                ? 'Ventas'
                : (_movementsVisible ? 'Movimientos' : 'Inventario'),
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        const SizedBox(width: 16),
        if (!desktop)
          Builder(
            builder: (menuContext) => IconButton(
              tooltip: 'Menú de inventario',
              onPressed: _operationBusy
                  ? null
                  : () => Scaffold.of(menuContext).openDrawer(),
              icon: const Icon(Icons.menu, color: navy),
            ),
          ),
        if (widget.onLogout != null)
          PopupMenuButton<String>(
            key: const Key('session-account'),
            tooltip: 'Mi cuenta',
            enabled: !_operationBusy,
            icon: const Icon(Icons.account_circle_outlined, color: navy),
            onSelected: (value) async {
              if (value == 'logout') await widget.onLogout?.call();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  widget.userName ?? 'Mi cuenta',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuItem<String>(
                enabled: false,
                child: Text(widget.currentUserRole ?? ''),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Cerrar sesión'),
              ),
            ],
          ),
        if (_stockRole) _alertButton(),
      ],
    ),
  );
  Widget _title(bool mobile) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 18,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mobile ? 'Inventario' : 'Productos e inventario',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 9),
            Text(
              mobile
                  ? 'Productos y existencias.'
                  : 'Consultá tus productos y el estado del stock.',
              style: const TextStyle(color: muted, height: 1.5),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualizar'),
            ),
            if (_admin)
              FilledButton.icon(
                onPressed: _newProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo producto'),
              ),
          ],
        ),
      ],
    ),
  );
  Widget _filters(bool mobile) {
    final categories = _products.map((p) => p.category).toSet().toList()
      ..sort();
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: mobile
            ? 'Buscar producto'
            : 'Buscar por código, nombre o categoría',
        prefixIcon: const Icon(Icons.search, color: navy, size: 22),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _search.clear()),
              ),
      ),
    );
    final category = DropdownButtonFormField<String>(
      key: ValueKey('${_category}_${categories.join(',')}'),
      initialValue: _category,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Categoría'),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Todas las categorías', overflow: TextOverflow.ellipsis),
        ),
        ...categories.map(
          (c) => DropdownMenuItem(
            value: c,
            child: Text(c, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _category = value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mobile) ...[
          search,
          const SizedBox(height: 16),
          category,
        ] else
          Row(
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: category),
            ],
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: !_lowOnly,
              onSelected: (_) => setState(() => _lowOnly = false),
              showCheckmark: false,
            ),
            ChoiceChip(
              label: const Text('Stock bajo'),
              selected: _lowOnly,
              onSelected: (_) => setState(() => _lowOnly = true),
              showCheckmark: false,
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary() {
    if (_loading || _error != null) return const SizedBox.shrink();
    final time = _updated == null
        ? ''
        : '${_updated!.hour.toString().padLeft(2, '0')}:${_updated!.minute.toString().padLeft(2, '0')}';
    return Wrap(
      spacing: 22,
      runSpacing: 10,
      children: [
        Text(
          '${_filtered.length} de ${_products.length} productos',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        Text(
          '${_products.where((p) => p.isLow).length} con stock bajo',
          style: const TextStyle(color: Color(0xFFA86A15), fontSize: 12),
        ),
        Text(
          'Actualizado $time',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _table(bool wide) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          color: const Color(0xFFF9FAFD),
          child: Row(
            children: [
              _cell('Código', flex: 1, heading: true),
              _cell('Producto', flex: 3, heading: true),
              _cell('Categoría', flex: 2, heading: true),
              _cell('Stock', flex: 1, heading: true),
              _cell('Mínimo', flex: 1, heading: true),
              const SizedBox(
                width: 104,
                child: Text(
                  'Estado',
                  style: TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(
                width: 112,
                child: Text(
                  'Acciones',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
        ),
        ..._filtered.map(
          (p) => Material(
            color: _selected?.id == p.id
                ? const Color(0xFFEDF2FA)
                : Colors.white,
            child: InkWell(
              onTap: () => _open(p, wide),
              child: Container(
                constraints: const BoxConstraints(minHeight: 86),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Row(
                  children: [
                    _cell('${p.id}', flex: 1),
                    _cell(p.name, flex: 3, bold: true),
                    _cell(p.category, flex: 2),
                    _cell('${p.quantity}', flex: 1, bold: true),
                    _cell('${p.minimum}', flex: 1),
                    SizedBox(
                      width: 104,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StockBadge(p.isLow),
                      ),
                    ),
                    SizedBox(
                      width: 112,
                      child: OutlinedButton(
                        onPressed: () => _open(p, wide),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Ver detalle',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _cell(
    String text, {
    required int flex,
    bool heading = false,
    bool bold = false,
  }) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: heading ? 11 : 13,
          fontWeight: heading || bold ? FontWeight.w600 : FontWeight.w400,
          color: heading ? muted : ink,
        ),
      ),
    ),
  );
  Widget _mobileList() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: _filtered
          .map(
            (p) => Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => _open(p, false),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  'Código: ${p.id}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StockBadge(p.isLow),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(child: _quantity('Stock', p.quantity)),
                          Expanded(child: _quantity('Mínimo', p.minimum)),
                          const Icon(
                            Icons.chevron_right,
                            color: muted,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          onPressed: () => _open(p, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Ver detalle',
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
  Widget _quantity(String label, int amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 6),
      Text(
        '$amount',
        style: const TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
  Widget _message(
    IconData icon,
    String title,
    String text, {
    bool loading = false,
    bool retry = false,
    bool reset = false,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 55),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(icon, color: muted, size: 36),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            color: ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.7),
          ),
        ),
        if (loading) ...[
          const SizedBox(height: 24),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (retry) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: _reload, child: const Text('Reintentar')),
        ],
        if (reset) ...[
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => setState(() {
              _search.clear();
              _lowOnly = false;
              _category = null;
            }),
            child: const Text('Limpiar filtros'),
          ),
        ],
      ],
    ),
  );
}
