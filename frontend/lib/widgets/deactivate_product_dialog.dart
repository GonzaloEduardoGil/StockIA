import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/product.dart';
import '../screens/new_product_form.dart';
import 'operation_frame.dart';

Future<ProductCreationResult?> confirmProductDeactivation(
  BuildContext context,
  InventoryApi api,
  Product product,
) => showDialog<ProductCreationResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DeactivateProductDialog(api: api, product: product),
);

class DeactivateProductDialog extends StatefulWidget {
  const DeactivateProductDialog({
    required this.api,
    required this.product,
    this.embedded = false,
    this.onCompleted,
    this.onBusyChanged,
    super.key,
  });
  final bool embedded;
  final ValueChanged<ProductCreationResult?>? onCompleted;
  final ValueChanged<bool>? onBusyChanged;
  final InventoryApi api;
  final Product product;
  @override
  State<DeactivateProductDialog> createState() =>
      _DeactivateProductDialogState();
}

class _DeactivateProductDialogState extends State<DeactivateProductDialog> {
  bool _saving = false;
  bool _refreshRequired = false;
  String? _error;

  Future<void> _confirm() async {
    if (_saving || _refreshRequired) return;
    widget.onBusyChanged?.call(true);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.api.deactivateProduct(widget.product);
      if (!mounted) return;
      setState(() => _saving = false);
      _finish(ProductCreationResult(id: id, deactivated: true));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure
            ? error.message
            : 'No pudimos confirmar la baja.';
        _refreshRequired =
            error is ApiFailure &&
            (error.mayHaveSaved || error.requiresRefresh);
      });
      widget.onBusyChanged?.call(_refreshRequired);
    }
  }

  void _finish(ProductCreationResult? result) {
    widget.onBusyChanged?.call(false);
    if (widget.onCompleted != null) {
      widget.onCompleted!(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_refreshRequired,
    child: OperationFrame(
      embedded: widget.embedded,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 500),
      title: const Text(
        '¿Dar de baja este producto?',
        style: TextStyle(color: ink, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embedded) ...[
              Text(
                widget.product.name,
                style: const TextStyle(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Código: ${widget.product.id}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 8),
              Text(
                'Stock actual: ${widget.product.quantity} unidades',
                style: const TextStyle(color: muted),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Quedará inactivo. Se conservarán sus datos e historial.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFA14C20), height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        if (_refreshRequired)
          FilledButton(
            onPressed: () =>
                _finish(const ProductCreationResult(uncertain: true)),
            child: const Text('Actualizar inventario'),
          )
        else ...[
          TextButton(
            onPressed: _saving ? null : () => _finish(null),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB23C3C),
              foregroundColor: Colors.white,
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined, size: 18),
            label: Text(_saving ? 'Procesando…' : 'Confirmar baja'),
          ),
        ],
      ],
    ),
  );
}
