import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../models/stock_alert.dart';
import '../models/stock_movement.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    required this.api,
    required this.onEntry,
    this.onRefreshed,
    this.initialProductId,
    super.key,
  });
  final InventoryApi api;
  final int? initialProductId;
  final ValueChanged<Product> onEntry;
  final VoidCallback? onRefreshed;
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _search = TextEditingController();
  List<StockAlert> _alerts = [];
  String? _category;
  bool _loading = true;
  String? _error;
  int _request = 0;
  int _detailRequest = 0;
  int? _selectedId;
  StockAlertDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialProductId != null) _open(widget.initialProductId!);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alerts = await widget.api.loadAlerts();
      if (!mounted || request != _request) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
        if (_category != null && !alerts.any((a) => a.category == _category)) {
          _category = null;
        }
      });
      widget.onRefreshed?.call();
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar las alertas.';
      });
    }
  }

  Future<void> _open(int id) async {
    final request = ++_detailRequest;
    setState(() {
      _selectedId = id;
      _detailLoading = true;
      _detail = null;
      _detailError = null;
      _expired = false;
    });
    try {
      final detail = await widget.api.loadAlert(id);
      if (!mounted || request != _detailRequest) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _detailRequest) return;
      setState(() {
        _detailLoading = false;
        _detailError = error is ApiFailure
            ? error.message
            : 'No se pudo cargar el detalle de la alerta.';
        _expired = error is ApiFailure && error.requiresRefresh;
      });
    }
  }

  void _back() {
    ++_detailRequest;
    setState(() {
      _selectedId = null;
      _detail = null;
      _detailLoading = false;
      _detailError = null;
    });
    _load();
  }

  List<StockAlert> get _filtered {
    final query = searchable(_search.text.trim());
    return _alerts
        .where(
          (a) =>
              (_category == null || a.category == _category) &&
              (query.isEmpty ||
                  searchable('${a.productId} ${a.name} ${a.category}')
                      .contains(query)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 850;
      return SingleChildScrollView(
        key: ValueKey(_selectedId),
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inventario / Alertas', style: TextStyle(color: muted)),
            const SizedBox(height: 20),
            if (_selectedId != null) ...[
              TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver a alertas'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Detalle de alerta',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 24),
              if (_detailLoading)
                const Center(child: CircularProgressIndicator())
              else if (_detailError != null)
                _message(
                  _detailError!,
                  retry: _expired ? null : () => _open(_selectedId!),
                )
              else if (_detail != null)
                _detailView(_detail!),
            ] else ...[
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Alertas de stock',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
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
                    width: narrow ? constraints.maxWidth - 40 : 340,
                    child: Semantics(
                      container: true,
                      child: TextField(
                        key: const Key('alert-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto',
                          hintText: 'Nombre, código o categoría',
                          prefixIcon: Icon(Icons.search, size: 20),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? constraints.maxWidth - 40 : 240,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'alert-category-$_category-${_categories.join(',')}',
                      ),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas las categorías'),
                        ),
                        ..._categories.map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _category = value),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _search.clear();
                      _category = null;
                    }),
                    child: const Text('Limpiar filtros'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                _message(_error!, retry: _load)
              else if (_alerts.isEmpty)
                _message('No hay productos con stock bajo.')
              else if (_filtered.isEmpty)
                _message('No encontramos alertas con estos filtros.')
              else ...[
                Text(
                  'Alertas: ${_filtered.length}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                if (narrow)
                  ..._filtered.map(_card)
                else
                  SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('Producto')),
                        DataColumn(label: Text('Stock'), numeric: true),
                        DataColumn(label: Text('Mínimo'), numeric: true),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('')),
                      ],
                      rows: _filtered
                          .map(
                            (a) => DataRow(
                              cells: [
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 240,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${a.name} (#${a.productId})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          a.category,
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(Text('${a.quantity}')),
                                DataCell(Text('${a.minimum}')),
                                DataCell(_status(a.outOfStock)),
                                DataCell(_detailButton(a)),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );

  List<String> get _categories =>
      _alerts.map((a) => a.category).toSet().toList()..sort();

  Widget _status(bool empty) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: empty ? const Color(0xFFFFEBE9) : const Color(0xFFFFF3D6),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      empty ? 'Sin stock' : 'Stock bajo',
      style: TextStyle(
        color: empty ? const Color(0xFFA53028) : const Color(0xFF8A651D),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _detailButton(StockAlert a) => OutlinedButton(
    key: ValueKey('alert-detail-${a.productId}'),
    onPressed: () => _open(a.productId),
    child: const Text('Ver detalle'),
  );

  Widget _card(StockAlert a) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.name} (#${a.productId})',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(a.category, style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
          Text('Stock: ${a.quantity} · Mínimo: ${a.minimum}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [_status(a.outOfStock), _detailButton(a)],
          ),
        ],
      ),
    ),
  );

  Widget _detailView(StockAlertDetail detail) {
    final p = detail.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${p.name} (#${p.id})',
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(p.category, style: const TextStyle(color: muted)),
        if (p.description?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(p.description!),
        ],
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 32,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Stock actual: ${p.quantity}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Stock mínimo: ${p.minimum}',
                style: const TextStyle(fontSize: 18),
              ),
              _status(p.quantity == 0),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Precio: ${money(p.price)}'),
        if (detail.lastAlertDate != null) ...[
          const SizedBox(height: 8),
          Text(
            'Último aviso: ${movementDate(detail.lastAlertDate!)}',
            style: const TextStyle(color: muted),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('alert-register-entry'),
          onPressed: () => widget.onEntry(p),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Registrar entrada'),
        ),
      ],
    );
  }

  Widget _message(String text, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
      ],
    ),
  );
}
