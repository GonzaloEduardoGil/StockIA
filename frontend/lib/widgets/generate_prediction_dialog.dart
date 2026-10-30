import 'package:flutter/material.dart';

import '../data/inventory_api.dart';

class GeneratePredictionDialog extends StatefulWidget {
  const GeneratePredictionDialog({
    required this.api,
    required this.productId,
    required this.productName,
    super.key,
  });
  final InventoryApi api;
  final int productId;
  final String productName;
  @override
  State<GeneratePredictionDialog> createState() =>
      _GeneratePredictionDialogState();
}

class _GeneratePredictionDialogState extends State<GeneratePredictionDialog> {
  final _days = TextEditingController(text: '7');
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _uncertain = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.api.generatePrediction(
        widget.productId,
        int.parse(_days.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo confirmar la predicción. Actualizá el análisis.';
        _uncertain = error is! ApiFailure || error.mayHaveSaved;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_uncertain,
    child: AlertDialog(
      title: const Text('Generar predicción'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.productName),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('prediction-days'),
                  controller: _days,
                  enabled: !_busy && !_uncertain,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad de días',
                    helperText: 'De 1 a 30 días, desde mañana',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    final n = int.tryParse(text);
                    return !RegExp(r'^[0-9]+$').hasMatch(text) ||
                            n == null ||
                            n < 1 ||
                            n > 30
                        ? 'Ingresá un entero entre 1 y 30.'
                        : null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, _uncertain ? -1 : null),
          child: Text(_uncertain ? 'Cerrar y actualizar' : 'Cancelar'),
        ),
        FilledButton(
          onPressed: _busy || _uncertain ? null : _generate,
          child: Text(_busy ? 'Generando…' : 'Generar'),
        ),
      ],
    ),
  );
}
