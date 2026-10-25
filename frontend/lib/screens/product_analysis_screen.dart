import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/dashboard.dart';
import '../models/product.dart';
import '../models/product_analysis.dart';
import '../models/stock_movement.dart';
import '../widgets/date_filter_field.dart';
import '../widgets/prediction_card.dart';
import '../widgets/sales_trend_chart.dart';

class ProductAnalysisScreen extends StatefulWidget {
  const ProductAnalysisScreen({
    required this.api,
    required this.productId,
    required this.onBack,
    this.from,
    this.to,
    super.key,
  });
  final InventoryApi api;
  final int productId;
  final VoidCallback onBack;
  final DateTime? from;
  final DateTime? to;
  @override
  State<ProductAnalysisScreen> createState() => _ProductAnalysisScreenState();
}

class _ProductAnalysisScreenState extends State<ProductAnalysisScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  ProductAnalysis? _data;
  String? _error;
  bool _loading = true;
  int _request = 0;
  int? _selectedPrediction;
  @override
  void initState() {
    super.initState();
    _from.text = widget.from == null ? '' : movementDate(widget.from!);
    _to.text = widget.to == null ? '' : movementDate(widget.to!);
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.api.loadProductAnalysis(widget.productId);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
        final predictions = data.predictions;
        if (predictions != null &&
            !predictions.any((p) => p.id == _selectedPrediction)) {
          _selectedPrediction = predictions.isEmpty
              ? null
              : predictions.first.id;
        }
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo cargar el análisis del producto.';
      });
    }
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

  List<DailySales> get _filtered {
    final from = parseMovementDate(_from.text);
    final to = parseMovementDate(_to.text);
    return (_data?.trend ?? [])
        .where(
          (d) =>
              (from == null || !d.date.isBefore(from)) &&
              (to == null || !d.date.isAfter(to)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 650;
      final width = constraints.maxWidth - (narrow ? 40 : 64);
      return SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inicio / Análisis del producto',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver al dashboard'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _data == null
                      ? 'Análisis del producto'
                      : '${_data!.name} (#${_data!.id})',
                  style: const TextStyle(
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
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _failure(_error!)
            else if (_data != null) ...[
              Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  Text(_data!.category),
                  Text(
                    _data!.active
                        ? 'Producto activo'
                        : 'Producto inactivo · Historial disponible',
                    style: const TextStyle(color: muted),
                  ),
                  Text('Stock actual: ${_data!.stock ?? 'Sin registro'}'),
                  Text('Mínimo: ${_data!.minimum}'),
                ],
              ),
              const SizedBox(height: 24),
              _panel(
                'Ventas reales',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: narrow ? width - 40 : 200,
                          child: DateFilterField(
                            key: const Key('analysis-from'),
                            label: 'Desde',
                            controller: _from,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        SizedBox(
                          width: narrow ? width - 40 : 200,
                          child: DateFilterField(
                            key: const Key('analysis-to'),
                            label: 'Hasta',
                            controller: _to,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _from.clear();
                            _to.clear();
                          }),
                          child: const Text('Limpiar fechas'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_dateError != null)
                      Text(
                        _dateError!,
                        style: const TextStyle(color: Color(0xFFA53028)),
                      )
                    else if (_data!.trend == null)
                      _failure('No se pudo cargar la evolución de ventas.')
                    else ...[
                      Wrap(
                        spacing: 32,
                        runSpacing: 12,
                        children: [
                          Text(
                            'Unidades vendidas: ${_filtered.fold<int>(0, (sum, d) => sum + d.count)}',
                            key: const Key('analysis-units'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Total facturado: ${money(_filtered.fold<int>(0, (sum, d) => sum + (d.total * 100).round()) / 100)}',
                            key: const Key('analysis-revenue'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Facturación diaria',
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 12),
                      SalesTrendChart(
                        days: _filtered,
                        countLabel: 'unidad',
                        countPlural: 'unidades',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _panel('Predicciones de demanda guardadas', _predictions()),
              const SizedBox(height: 20),
              _panel('Recomendaciones guardadas', _recommendations()),
            ],
          ],
        ),
      );
    },
  );

  Widget _panel(String title, Widget child) => Container(
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );

  Widget _predictions() {
    final rows = _data!.predictions;
    if (rows == null) {
      return _failure('No se pudieron cargar las predicciones guardadas.');
    }
    if (rows.isEmpty) {
      return const Text('Este producto no tiene predicciones guardadas.');
    }
    final selected = rows.firstWhere(
      (p) => p.id == _selectedPrediction,
      orElse: () => rows.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey('analysis-prediction-${selected.id}'),
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Seleccionar predicción',
          ),
          items: rows
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '#${p.id} · ${movementDate(p.date)} · ${p.period}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (id) => setState(() => _selectedPrediction = id),
        ),
        const SizedBox(height: 16),
        PredictionCard(prediction: selected),
      ],
    );
  }

  Widget _recommendations() {
    final rows = _data!.recommendations;
    if (rows == null) {
      return _failure('No se pudieron cargar las recomendaciones guardadas.');
    }
    if (rows.isEmpty) {
      return const Text('No hay recomendaciones guardadas para este producto.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${movementDate(r.date)} · ${r.units} unidades sugeridas · ${r.status}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(r.reason),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _failure(String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text),
      TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar'),
      ),
    ],
  );
}
