import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../widgets/product_details.dart';
import 'new_product_form.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({required this.api, super.key});
  final InventoryApi api;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  List<Product> _products = [];
  Product? _selected;
  bool _loading = true;
  bool _lowOnly = false;
  String? _category;
  String? _error;
  DateTime? _updated;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    widget.api.close();
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
        content: Text(
          result.id != null
              ? (result.deactivated
                    ? 'Producto dado de baja. Se conservó su historial.'
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
              product: p,
              api: widget.api,
              onClose: () => Navigator.pop(context),
              onChanged: (result) => _afterEdit(result, closeDetail: true),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final desktop = viewport.maxWidth >= 1000;
      final mobile = viewport.maxWidth < 900;
      final wide = viewport.maxWidth >= 1280;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (desktop) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _header(desktop, mobile),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(mobile ? 20 : 32),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1700),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _title(mobile),
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
                                      if (wide && _selected != null) ...[
                                        const SizedBox(width: 20),
                                        SizedBox(
                                          width: 310,
                                          child: ProductDetails(
                                            onChanged: _afterEdit,
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
                                  style: TextStyle(fontSize: 11, color: muted),
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
      );
    },
  );
  Widget _sidebar() => Container(
    width: 224,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brand(),
          const SizedBox(height: 44),
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 16),
            child: Text(
              'GESTIÓN',
              style: TextStyle(
                color: muted,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF1F9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 21, color: navy),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Inventario',
                    style: TextStyle(color: navy, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Text(
              'Consulta de inventario',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _brand() => Row(
    children: [
      Container(
        width: 44,
        height: 44,
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
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'StockIA',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            SizedBox(height: 3),
            Text(
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
    padding: EdgeInsets.symmetric(horizontal: mobile ? 20 : 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!desktop)
          Expanded(child: _brand())
        else
          const Text(
            'StockIA  /  Gestión',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        if (desktop) const Spacer(),
        if (!mobile)
          const Text(
            'Inventario',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        const SizedBox(width: 16),
        Tooltip(
          message: 'Consulta de productos y existencias',
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFEDF2F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_outlined, color: navy, size: 19),
          ),
        ),
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
              const SizedBox(width: 22),
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
                    const Icon(Icons.chevron_right, size: 22, color: muted),
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
