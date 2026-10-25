import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../models/inventory_action.dart';
import '../widgets/deactivate_product_dialog.dart';
import '../widgets/minimum_stock_dialog.dart';
import '../widgets/stock_entry_dialog.dart';
import '../widgets/stock_adjustment_dialog.dart';
import 'new_product_form.dart';

class InventoryOperationPage extends StatefulWidget {
  const InventoryOperationPage({
    required this.action,
    required this.api,
    required this.products,
    required this.onFinished,
    required this.onBusyChanged,
    this.initialProduct,
    super.key,
  });
  final InventoryAction action;
  final InventoryApi api;
  final List<Product> products;
  final Product? initialProduct;
  final ValueChanged<ProductCreationResult?> onFinished;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<InventoryOperationPage> createState() => _InventoryOperationPageState();
}

class _InventoryOperationPageState extends State<InventoryOperationPage> {
  final _search = TextEditingController();
  Product? _product;
  bool _busy = false;
  bool _loading = false;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) _select(widget.initialProduct!);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(Product product) async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _product = null;
      _search.clear();
    });
    try {
      final selected = await widget.api.loadDetail(product);
      if (!mounted || request != _request) return;
      setState(() {
        _product = selected;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el producto. Seleccionalo nuevamente.';
      });
    }
  }

  void _setBusy(bool busy) {
    if (!mounted) return;
    setState(() => _busy = busy);
    widget.onBusyChanged(busy);
  }

  Widget _form(Product p) => switch (widget.action) {
    InventoryAction.entry => StockEntryDialog(
      key: ValueKey('entry-${p.id}'),
      api: widget.api,
      product: p,
      embedded: true,
      onCompleted: widget.onFinished,
      onBusyChanged: _setBusy,
    ),
    InventoryAction.adjustment => StockAdjustmentDialog(
      key: ValueKey('adjustment-${p.id}'),
      api: widget.api,
      product: p,
      embedded: true,
      onCompleted: widget.onFinished,
      onBusyChanged: _setBusy,
    ),
    InventoryAction.minimum => MinimumStockDialog(
      key: ValueKey('minimum-${p.id}'),
      api: widget.api,
      product: p,
      embedded: true,
      onCompleted: widget.onFinished,
      onBusyChanged: _setBusy,
    ),
    InventoryAction.deactivate => DeactivateProductDialog(
      key: ValueKey('deactivate-${p.id}'),
      api: widget.api,
      product: p,
      embedded: true,
      onCompleted: widget.onFinished,
      onBusyChanged: _setBusy,
    ),
    InventoryAction.edit => NewProductForm(
      key: ValueKey('edit-${p.id}'),
      api: widget.api,
      product: p,
      embedded: true,
      onCompleted: widget.onFinished,
      onBusyChanged: _setBusy,
    ),
  };
  @override
  Widget build(BuildContext context) {
    final query = searchable(_search.text.trim());
    final matches = widget.products
        .where((p) => searchable('${p.id} ${p.name}').contains(query))
        .take(8)
        .toList();
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventario / ${widget.action.label}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: TextField(
                    key: const Key('operation-product-search'),
                    controller: _search,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto por nombre o código',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No se encontraron productos.'),
                    ),
                  ...matches.map(
                    (p) => Material(
                      color: Colors.white,
                      child: ListTile(
                        key: ValueKey('select-product-${p.id}'),
                        title: Text(p.name),
                        subtitle: Text('Código ${p.id} · Stock ${p.quantity}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _select(p),
                      ),
                    ),
                  ),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                if (_product != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF1F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _product!.name,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 18,
                          runSpacing: 8,
                          children: [
                            Text('Código: ${_product!.id}'),
                            Text('Stock: ${_product!.quantity}'),
                            Text('Mínimo: ${_product!.minimum}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _form(_product!),
                ] else if (!_loading && query.isEmpty && _error == null) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Seleccioná un producto para continuar.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => widget.onFinished(null),
                    child: const Text('Volver al inventario'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
