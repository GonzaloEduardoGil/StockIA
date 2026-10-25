import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/new_product.dart';
import '../models/product.dart';
import '../screens/new_product_form.dart';
import 'operation_frame.dart';

Future<ProductCreationResult?> registerStockAdjustment(
  BuildContext context,
  InventoryApi api,
  Product product,
) => showDialog<ProductCreationResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => StockAdjustmentDialog(api: api, product: product),
);

class StockAdjustmentDialog extends StatefulWidget {
  const StockAdjustmentDialog({
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
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _otherReason = TextEditingController();
  bool _subtract = true;
  String? _reason;
  bool _review = false;
  bool _saving = false;
  bool _refreshRequired = false;
  String? _error;

  String get _stockPreview {
    final quantity = parseStock(_quantity.text);
    if (quantity == null || quantity <= 0 || quantity > 2147483647) {
      return 'Stock resultante: —';
    }
    final result = widget.product.quantity + (_subtract ? -quantity : quantity);
    if (result < 0) return 'Stock insuficiente';
    if (result > 2147483647) return 'Cantidad fuera de rango';
    return 'Stock resultante: $result unidades';
  }

  int get _delta => parseStock(_quantity.text)! * (_subtract ? -1 : 1);
  String get _justification =>
      _reason == 'Otro' ? _otherReason.text.trim() : _reason!;

  @override
  void dispose() {
    _quantity.dispose();
    _otherReason.dispose();
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
      final id = await widget.api.registerStockAdjustment(
        widget.product,
        _delta,
        _justification,
      );
      if (!mounted) return;
      _finish(ProductCreationResult(id: id, adjustmentQuantity: _delta));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure
            ? error.message
            : 'No pudimos confirmar el ajuste.';
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
        _review ? 'Revisar ajuste' : 'Registrar ajuste',
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
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Restar')),
                          ButtonSegment(value: false, label: Text('Sumar')),
                        ],
                        selected: {_subtract},
                        onSelectionChanged: (selection) => setState(() {
                          _subtract = selection.single;
                          _reason = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const Key('stock-adjustment-quantity'),
                      controller: _quantity,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                      validator: (text) {
                        final value = parseStock(text ?? '');
                        if (value == null || value <= 0 || value > 2147483647) {
                          return 'Ingresá una cantidad positiva válida.';
                        }
                        if (_subtract && value > widget.product.quantity) {
                          return 'No podés restar más del stock disponible.';
                        }
                        if (!_subtract &&
                            value > 2147483647 - widget.product.quantity) {
                          return 'La cantidad supera el límite de stock.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _stockPreview,
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      key: ValueKey('stock-adjustment-reason-$_subtract'),
                      initialValue: _reason,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Motivo'),
                      items:
                          [
                                if (_subtract) ...[
                                  'Pérdida',
                                  'Rotura',
                                  'Vencimiento',
                                ],
                                'Diferencia de inventario',
                                'Otro',
                              ]
                              .map(
                                (reason) => DropdownMenuItem(
                                  value: reason,
                                  child: Text(reason),
                                ),
                              )
                              .toList(),
                      onChanged: (reason) => setState(() => _reason = reason),
                      validator: (reason) =>
                          reason == null ? 'Seleccioná un motivo.' : null,
                    ),
                    if (_reason == 'Otro') ...[
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const Key('stock-adjustment-other'),
                        controller: _otherReason,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Especificá el motivo',
                          counterText: '',
                        ),
                        validator: (text) => (text?.trim().isEmpty ?? true)
                            ? 'Ingresá el motivo.'
                            : ((text!.trim().length > 500)
                                  ? 'Usá hasta 500 caracteres.'
                                  : null),
                      ),
                    ],
                  ],
                ),
              )
            else ...[
              Text(
                'Ajuste: ${_delta > 0 ? '+' : '−'}${_delta.abs()} unidades',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Stock resultante: ${widget.product.quantity + _delta} unidades',
              ),
              const SizedBox(height: 12),
              Text('Motivo: $_justification'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFA14C20), height: 1.5),
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
                      : (_review ? 'Confirmar ajuste' : 'Revisar ajuste'),
                ),
              ),
            ],
    ),
  );
}
