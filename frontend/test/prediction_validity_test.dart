import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockia/models/product_analysis.dart';
import 'package:stockia/widgets/prediction_card.dart';

void main() {
  for (final state in [
    (current: true, valid: true, end: '2026-11-05', label: 'Vigente'),
    (
      current: true,
      valid: false,
      end: '2026-10-29',
      label: 'Período finalizado',
    ),
    (
      current: false,
      valid: false,
      end: '2099-11-05',
      label: 'Predicción reemplazada',
    ),
    (current: true, valid: false, end: null, label: 'Vigencia no informada'),
  ]) {
    testWidgets('Respeta el estado del servidor: ${state.label}', (
      tester,
    ) async {
      final prediction = DemandPrediction.fromApi({
        'idPrediccion': 1,
        'idProducto': 1,
        'nombreProducto': 'Producto de prueba',
        'fechaPrediccion': '2026-10-30',
        'periodoPrediccion': 'Próximos 7 días',
        'cantidadEstimada': 10,
        'fechaHasta': state.end,
        'esActual': state.current,
        'vigente': state.valid,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PredictionCard(prediction: prediction)),
        ),
      );
      expect(find.text(state.label), findsOneWidget);
      if (!state.current) expect(find.text('Vigente'), findsNothing);
    });
  }
}
