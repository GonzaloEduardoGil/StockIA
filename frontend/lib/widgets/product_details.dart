import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../screens/new_product_form.dart';
import 'deactivate_product_dialog.dart';

class StockBadge extends StatelessWidget {
  const StockBadge(this.low, {super.key});
  final bool low;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: low ? const Color(0xFFFFF1DC) : const Color(0xFFE5F5EF),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      low ? 'Bajo' : 'Normal',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: low ? const Color(0xFFA86A15) : const Color(0xFF24745C),
      ),
    ),
  );
}

class ProductDetails extends StatefulWidget {
  const ProductDetails({
    required this.product,
    required this.api,
    required this.onClose,
    this.onChanged,
    super.key,
  });
  final Product product;
  final InventoryApi api;
  final VoidCallback onClose;
  final Future<void> Function(ProductCreationResult)? onChanged;
  @override
  State<ProductDetails> createState() => _ProductDetailsState();
}

class _ProductDetailsState extends State<ProductDetails> {
  late Future<Product> _details;
  bool _editing = false;

  Future<void> _edit(Product product) async {
    if (_editing) return;
    setState(() => _editing = true);
    final result = await openEditProduct(context, widget.api, product);
    if (!mounted) return;
    setState(() => _editing = false);
    if (result != null) {
      if (widget.onChanged != null) {
        await widget.onChanged!(result);
      } else {
        setState(() => _details = widget.api.loadDetail(widget.product));
      }
    }
  }

  Future<void> _deactivate(Product product) async {
    if (_editing) return;
    setState(() => _editing = true);
    final result = await confirmProductDeactivation(
      context,
      widget.api,
      product,
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (result != null) {
      if (widget.onChanged != null) {
        await widget.onChanged!(result);
      } else {
        widget.onClose();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _details = widget.api.loadDetail(widget.product);
  }

  @override
  void didUpdateWidget(ProductDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product != widget.product) {
      _details = widget.api.loadDetail(widget.product);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Detalle del producto',
                  style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar detalle',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF2F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: navy,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          FutureBuilder<Product>(
            future: _details,
            builder: (context, snapshot) {
              final p = snapshot.data ?? widget.product;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Text('Código: ${p.id}', style: const TextStyle(color: muted)),
                  const SizedBox(height: 7),
                  Text(p.category, style: const TextStyle(color: muted)),
                  const SizedBox(height: 24),
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 2),
                  if (snapshot.hasError) ...[
                    const Text(
                      'No se pudo actualizar el detalle.',
                      style: TextStyle(color: muted),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _details = widget.api.loadDetail(widget.product),
                      ),
                      child: const Text('Reintentar detalle'),
                    ),
                  ],
                  _value('Precio de venta', money(p.price)),
                  _value('Stock actual', '${p.quantity} unidades'),
                  _value('Stock mínimo', '${p.minimum} unidades'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estado', style: TextStyle(color: muted)),
                        StockBadge(p.isLow),
                      ],
                    ),
                  ),
                  if (p.isLow)
                    const Text(
                      'El stock es menor o igual al mínimo configurado.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFA86A15),
                        height: 1.6,
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Descripción',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.description?.trim().isNotEmpty == true
                        ? p.description!
                        : 'Sin descripción registrada.',
                    style: const TextStyle(color: muted, height: 1.7),
                  ),
                  if (snapshot.hasData) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _editing ? null : () => _edit(p),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar producto'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _editing ? null : () => _deactivate(p),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB23C3C),
                        ),
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Dar de baja'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
  Widget _value(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
          ),
        ),
      ],
    ),
  );
}
