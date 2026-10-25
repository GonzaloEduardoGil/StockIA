import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/new_product.dart';
import '../models/product.dart';
import '../screens/new_product_form.dart';
import 'operation_frame.dart';

Future<ProductCreationResult?> configureMinimumStock(
  BuildContext context,
  InventoryApi api,
  Product product,
) => showDialog<ProductCreationResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => MinimumStockDialog(api: api, product: product),
);

class MinimumStockDialog extends StatefulWidget {
  const MinimumStockDialog({
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
  State<MinimumStockDialog> createState() => _MinimumStockDialogState();
}

class _MinimumStockDialogState extends State<MinimumStockDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _minimum;
  bool _review = false;
  bool _saving = false;
  bool _refreshRequired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _minimum = TextEditingController(text: '${widget.product.minimum}');
  }

  @override
  void dispose() {
    _minimum.dispose();
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
      final id = await widget.api.updateMinimumStock(
        widget.product,
        parseStock(_minimum.text)!,
      );
      if (!mounted) return;
      _finish(ProductCreationResult(id: id, minimumChanged: true));
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
        _review ? 'Revisar stock mínimo' : 'Configurar stock mínimo',
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
              const SizedBox(height: 8),
              Text('Mínimo actual: ${widget.product.minimum} unidades'),
              const SizedBox(height: 16),
            ],
            if (!_review)
              Form(
                key: _form,
                child: TextFormField(
                  key: const Key('minimum-stock-input'),
                  controller: _minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo stock mínimo',
                  ),
                  validator: (text) {
                    final value = parseStock(text ?? '');
                    if (value == null || value > 2147483647) {
                      return 'Ingresá un entero entre 0 y 2147483647.';
                    }
                    if (value == widget.product.minimum) {
                      return 'Ingresá un mínimo distinto al actual.';
                    }
                    return null;
                  },
                ),
              )
            else ...[
              Text(
                'Nuevo mínimo: ${parseStock(_minimum.text)} unidades',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
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
                      : (_review ? 'Confirmar cambio' : 'Revisar cambio'),
                ),
              ),
            ],
    ),
  );
}
