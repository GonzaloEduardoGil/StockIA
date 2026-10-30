import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/dashboard.dart';
import '../models/product_analysis.dart';
import '../widgets/prediction_card.dart';
import 'product_analysis_screen.dart';
import '../models/product.dart';
import '../models/stock_alert.dart';
import '../models/stock_movement.dart';
import '../widgets/date_filter_field.dart';
import '../widgets/sales_trend_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.api,
    required this.onInventory,
    required this.onAlerts,
    required this.onSales,
    required this.onProduct,
    this.onRefreshed,
    this.analysisProductId,
    this.onAnalysisClosed,
    super.key,
  });
  final InventoryApi api;
  final int? analysisProductId;
  final VoidCallback? onAnalysisClosed;
  final VoidCallback onInventory;
  final VoidCallback onAlerts;
  final VoidCallback onSales;
  final ValueChanged<int> onProduct;
  final VoidCallback? onRefreshed;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _productSearch = TextEditingController();
  List<({int id, String name})> _lookupProducts = [];
  String? _lookupError;
  List<DemandPrediction>? _predictions;
  String? _predictionsError;
  bool _predictionsLoading = true;
  bool _lookupLoading = true;
  bool _showAllPredictions = false;
  final _from = TextEditingController();
  final _to = TextEditingController();
  DashboardData? _data;
  List<StockAlert>? _alerts;
  bool _loading = true;
  bool _alertsLoading = true;
  String? _error;
  String? _alertsError;
  DateTime? _appliedFrom;
  DateTime? _appliedTo;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _productSearch.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  String? get _dateError {
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    if ((_from.text.trim().isNotEmpty && from == null) ||
        (_to.text.trim().isNotEmpty && to == null)) {
      return 'Usá fechas válidas: dd/mm/aaaa.';
    }
    if (from != null && to != null && from.isAfter(to)) {
      return 'La fecha desde debe ser anterior o igual a la fecha hasta.';
    }
    return null;
  }

  Future<void> _load({bool apply = false}) async {
    if (apply && _dateError != null) return;
    if (apply) {
      _appliedFrom = parseMovementDate(_from.text);
      _appliedTo = parseMovementDate(_to.text);
    }
    final request = ++_request;
    setState(() {
      _predictionsLoading = true;
      _lookupLoading = true;
      _predictionsError = null;
      _lookupError = null;
      _predictions = null;
      _loading = true;
      _alertsLoading = true;
      _data = null;
      _alerts = null;
      _error = null;
      _alertsError = null;
    });
    await Future.wait([
      () async {
        try {
          final data = await widget.api.loadDashboard(
            from: _appliedFrom,
            to: _appliedTo,
          );
          if (!mounted || request != _request) return;
          setState(() {
            _data = data;
            _loading = false;
          });
        } catch (error) {
          if (!mounted || request != _request) return;
          setState(() {
            _loading = false;
            _error = error is ApiFailure
                ? error.message
                : 'No se pudo cargar el resumen general.';
          });
        }
      }(),
      () async {
        try {
          final alerts = await widget.api.loadAlerts();
          if (!mounted || request != _request) return;
          setState(() {
            _alerts = alerts;
            _alertsLoading = false;
          });
        } catch (_) {
          if (!mounted || request != _request) return;
          setState(() {
            _alertsLoading = false;
            _alertsError = 'No se pudieron cargar las alertas.';
          });
        }
      }(),
      () async {
        try {
          final rows = await widget.api.loadPredictions();
          if (!mounted || request != _request) return;
          setState(() {
            _predictions = rows;
            _predictionsLoading = false;
          });
        } catch (_) {
          if (!mounted || request != _request) return;
          setState(() {
            _predictionsLoading = false;
            _predictionsError =
                'No se pudieron cargar las predicciones guardadas.';
          });
        }
      }(),
      () async {
        try {
          final products = await widget.api.loadAnalysisProducts();
          if (!mounted || request != _request) return;
          setState(() {
            _lookupProducts = products;
            _lookupLoading = false;
          });
        } catch (_) {
          if (!mounted || request != _request) return;
          setState(() {
            _lookupError = 'No se pudo cargar la búsqueda de productos.';
            _lookupLoading = false;
          });
        }
      }(),
    ]);
    if (mounted && request == _request) widget.onRefreshed?.call();
  }

  String get _period {
    if (_appliedFrom == null && _appliedTo == null) return 'Todo el historial';
    if (_appliedFrom == null) return 'Hasta ${movementDate(_appliedTo!)}';
    if (_appliedTo == null) return 'Desde ${movementDate(_appliedFrom!)}';
    return '${movementDate(_appliedFrom!)} – ${movementDate(_appliedTo!)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.analysisProductId != null) {
      return ProductAnalysisScreen(
        key: ValueKey(widget.analysisProductId),
        api: widget.api,
        productId: widget.analysisProductId!,
        from: _appliedFrom,
        to: _appliedTo,
        onBack: widget.onAnalysisClosed ?? () {},
      );
    }
    return _dashboard(context);
  }

  Widget _dashboard(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 650;
      final padding = narrow ? 20.0 : 32.0;
      final width = constraints.maxWidth - padding * 2;
      final sectionWidth = width < 850 ? width : (width - 20) / 2;
      return SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inicio / Dashboard', style: TextStyle(color: muted)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Resumen general',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _alertsLoading ? null : () => _load(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: narrow ? width : 200,
                  child: DateFilterField(
                    key: const Key('dashboard-from'),
                    label: 'Desde',
                    controller: _from,
                    onChanged: () => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: narrow ? width : 200,
                  child: DateFilterField(
                    key: const Key('dashboard-to'),
                    label: 'Hasta',
                    controller: _to,
                    onChanged: () => setState(() {}),
                  ),
                ),
                OutlinedButton(
                  onPressed: _loading || _dateError != null
                      ? null
                      : () => _load(apply: true),
                  child: const Text('Aplicar'),
                ),
                TextButton(
                  onPressed: () {
                    _from.clear();
                    _to.clear();
                    _load(apply: true);
                  },
                  child: const Text('Limpiar fechas'),
                ),
              ],
            ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _dateError!,
                  style: const TextStyle(color: Color(0xFFA53028)),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Ventas: $_period · Inventario actual',
              key: const Key('dashboard-applied-period'),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _panel(title: 'Resumen general', child: _failure(_error!))
            else if (_data != null) ...[
              _metrics(width, _data!),
              const SizedBox(height: 20),
            ],
            _predictionsPanel(),
            const SizedBox(height: 20),
            _productLookup(),
            const SizedBox(height: 20),
            if (!_loading && _data != null) ...[
              _panel(
                title: 'Evolución de ventas',
                subtitle: 'Facturación por día',
                child: _data!.trend == null
                    ? _failure('No se pudo cargar la evolución de ventas.')
                    : SalesTrendChart(days: _data!.trend!),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: sectionWidth,
                    child: _ranking('Productos más vendidos', _data!.best),
                  ),
                  SizedBox(
                    width: sectionWidth,
                    child: _ranking('Productos menos vendidos', _data!.least),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                if (!_loading && _data != null)
                  SizedBox(
                    width: sectionWidth,
                    child: _inventory(_data!.inventory),
                  ),
                SizedBox(
                  width: _data == null ? width : sectionWidth,
                  child: _alertsPanel(),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _predictionsPanel() => _panel(
    title: 'Predicciones de demanda',
    subtitle: 'Actualización automática semanal',
    child: _predictionsLoading
        ? const Center(child: CircularProgressIndicator())
        : _predictionsError != null
        ? _failure(_predictionsError!)
        : _predictions!.isEmpty
        ? const Text('Todavía no hay predicciones guardadas.')
        : LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children:
                      (_showAllPredictions
                              ? _predictions!
                              : _predictions!.take(6))
                          .map(
                            (p) => SizedBox(
                              width: box.maxWidth >= 850
                                  ? ((box.maxWidth - 24) / 3).floorToDouble()
                                  : box.maxWidth >= 550
                                  ? ((box.maxWidth - 12) / 2).floorToDouble()
                                  : box.maxWidth,
                              child: PredictionCard(
                                key: ValueKey('dashboard-prediction-${p.id}'),
                                prediction: p,
                                onOpen: () => widget.onProduct(p.productId),
                              ),
                            ),
                          )
                          .toList(),
                ),
                if (_predictions!.length > 6)
                  TextButton(
                    onPressed: () => setState(
                      () => _showAllPredictions = !_showAllPredictions,
                    ),
                    child: Text(
                      _showAllPredictions
                          ? 'Ver menos'
                          : 'Ver todas las predicciones',
                    ),
                  ),
              ],
            ),
          ),
  );

  Widget _productLookup() {
    final query = searchable(_productSearch.text.trim());
    final matches = _lookupProducts
        .where((p) => searchable('${p.id} ${p.name}').contains(query))
        .take(6)
        .toList();
    final code = int.tryParse(_productSearch.text.trim());
    return _panel(
      title: 'Analizar ventas por producto',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            child: TextField(
              key: const Key('dashboard-product-search'),
              controller: _productSearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o código',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_lookupLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else if (_lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_lookupError!),
            ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...matches.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p.name} (#${p.id})'),
                trailing: OutlinedButton(
                  key: ValueKey('dashboard-analyze-${p.id}'),
                  onPressed: () => widget.onProduct(p.id),
                  child: const Text('Ver análisis'),
                ),
              ),
            ),
            if (matches.isEmpty && code != null && code > 0)
              OutlinedButton(
                onPressed: () => widget.onProduct(code),
                child: Text('Consultar producto #$code'),
              )
            else if (matches.isEmpty && !_lookupLoading && _lookupError == null)
              const Text('No encontramos productos con esta búsqueda.'),
          ],
        ],
      ),
    );
  }

  Widget _metrics(double width, DashboardData data) {
    final columns = width < 480
        ? 1
        : width < 850
        ? 2
        : 4;
    final cardWidth = (width - 12 * (columns - 1)) / columns;
    Widget metric(
      String label,
      String value,
      IconData icon, {
      VoidCallback? onTap,
    }) => SizedBox(
      width: cardWidth,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: line),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: const TextStyle(color: muted)),
                    ),
                    Icon(icon, color: navy, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        metric(
          'Facturación',
          data.sales == null ? 'No disponible' : money(data.sales!.total),
          Icons.payments_outlined,
          onTap: widget.onSales,
        ),
        metric(
          'Ventas',
          data.sales?.count.toString() ?? 'No disponible',
          Icons.receipt_long_outlined,
          onTap: widget.onSales,
        ),
        metric(
          'Unidades disponibles',
          data.inventory?.units.toString() ?? 'No disponible',
          Icons.inventory_2_outlined,
          onTap: widget.onInventory,
        ),
        metric(
          'Stock bajo',
          data.inventory?.low.toString() ?? 'No disponible',
          Icons.notifications_outlined,
          onTap: widget.onAlerts,
        ),
      ],
    );
  }

  Widget _panel({
    required String title,
    required Widget child,
    String? subtitle,
    Widget? action,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            ?action,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        child,
      ],
    ),
  );

  Widget _ranking(String title, List<RankedProduct>? items) => _panel(
    title: title,
    subtitle: 'Unidades vendidas en el período',
    child: items == null
        ? _failure('No se pudo cargar este listado.')
        : items.isEmpty
        ? const Text('No hay información disponible para este período.')
        : Column(
            children: items
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text('${p.name} (#${p.id})')),
                        const SizedBox(width: 12),
                        Text(
                          '${p.units}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          tooltip: 'Ver análisis de ${p.name}',
                          onPressed: () => widget.onProduct(p.id),
                          icon: const Icon(Icons.chevron_right, color: navy),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
  );

  Widget _inventory(DashboardInventory? inventory) => _panel(
    title: 'Estado del inventario',
    action: TextButton(
      onPressed: widget.onInventory,
      child: const Text('Ver inventario'),
    ),
    child: inventory == null
        ? _failure('No se pudo cargar el estado del inventario.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Productos activos: ${inventory.products}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (inventory.products > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: inventory.normal / inventory.products,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFFFE1A3),
                    color: navy,
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text('Normal: ${inventory.normal}'),
                  Text('Stock bajo: ${inventory.low}'),
                ],
              ),
              if (inventory.products == 0) ...[
                const SizedBox(height: 12),
                const Text('Todavía no hay productos activos.'),
              ],
            ],
          ),
  );

  Widget _alertsPanel() => _panel(
    title: 'Alertas actuales',
    action: TextButton(
      onPressed: widget.onAlerts,
      child: const Text('Ver alertas'),
    ),
    child: _alertsLoading
        ? const Center(child: CircularProgressIndicator())
        : _alertsError != null
        ? _failure(_alertsError!)
        : _alerts!.isEmpty
        ? const Text('No hay productos con stock bajo.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._alerts!
                  .take(3)
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${a.name} (#${a.productId})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${a.status} · ${a.quantity} unidades · Mínimo: ${a.minimum}',
                            style: const TextStyle(color: Color(0xFF8A651D)),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (_alerts!.length > 3)
                Text(
                  'Y ${_alerts!.length - 3} más',
                  style: const TextStyle(color: muted),
                ),
            ],
          ),
  );

  Widget _failure(String message) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(message),
      TextButton.icon(
        onPressed: () => _load(),
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
      ),
    ],
  );
}
