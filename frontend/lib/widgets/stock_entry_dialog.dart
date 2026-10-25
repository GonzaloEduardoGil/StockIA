import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/new_product.dart';
import '../models/product.dart';
import '../screens/new_product_form.dart';
import 'operation_frame.dart';

Future<ProductCreationResult?> registerStockEntry(
  BuildContext context,
  InventoryApi api,
  Product product,
) => showDialog<ProductCreationResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => StockEntryDialog(api: api, product: product),
);

class StockEntryDialog extends StatefulWidget {
  const StockEntryDialog({
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
  State<StockEntryDialog> createState() => _StockEntryDialogState();
}

class _StockEntryDialogState extends State<StockEntryDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  final _reason = TextEditingController();
  bool _review = false;
  bool _saving = false;
  bool _refreshRequired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _prepare() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _review = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _refreshRequired) return;
    widget.onBusyChanged?.call(true);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.api.registerStockEntry(
        widget.product,
        parseStock(_quantity.text)!,
        _reason.text,
      );
      if (!mounted) return;
      _finish(
        ProductCreationResult(
          id: id,
          entryQuantity: parseStock(_quantity.text),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure
            ? error.message
            : 'No pudimos confirmar el cambio.';
        _refreshRequired =
            error is ApiFailure &&
            (error.requiresRefresh || error.mayHaveSaved);
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
      title: Text(
        _review ? 'Revisar entrada de stock' : 'Registrar entrada de stock',
        style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Código: ${widget.product.id}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              Text('Stock actual: ${widget.product.quantity} unidades'),
              const SizedBox(height: 16),
            ],
            if (!_review)
              Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('stock-entry-quantity'),
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad recibida',
                      ),
                      validator: (text) {
                        final value = parseStock(text ?? '');
                        if (value == null ||
                            value <= 0 ||
                            value > 2147483647 - widget.product.quantity) {
                          return 'Ingresá una cantidad positiva válida.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const Key('stock-entry-reason'),
                      controller: _reason,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Motivo (opcional)',
                        counterText: '',
                      ),
                      validator: (text) => (text?.trim().length ?? 0) > 500
                          ? 'El motivo puede tener hasta 500 caracteres.'
                          : null,
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                'Cantidad recibida: ${parseStock(_quantity.text)} unidades',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
            ],
            if (_review) ...[
              const SizedBox(height: 16),
              Text(
                'Stock estimado: ${widget.product.quantity + parseStock(_quantity.text)!} unidades',
              ),
              if (_reason.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Motivo: ${_reason.text.trim()}'),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
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
      actions: _refreshRequired
          ? [
              FilledButton(
                onPressed: () =>
                    _finish(const ProductCreationResult(uncertain: true)),
                child: const Text('Actualizar inventario'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => _finish(null),
                child: const Text('Cancelar'),
              ),
              if (_review)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _review = false;
                          _error = null;
                        }),
                  child: const Text('Corregir'),
                ),
              FilledButton(
                onPressed: _saving ? null : (_review ? _save : _prepare),
                child: Text(
                  _saving
                      ? 'Guardando…'
                      : (_review ? 'Confirmar entrada' : 'Revisar entrada'),
                ),
              ),
            ],
    ),
  );
}
