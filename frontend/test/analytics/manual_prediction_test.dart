import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/auth_session.dart';
import 'package:stockia/screens/product_analysis_screen.dart';
import 'package:stockia/widgets/generate_prediction_dialog.dart';

import 'product_analysis_test.dart' as fixtures;

InventoryApi api(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'Administrador',
}) {
  final result = InventoryApi(client: MockClient(handler));
  result.session.value = AuthSession(
    token: 'A' * 43,
    userId: 1,
    name: 'Prueba',
    email: 'qa@example.com',
    role: role,
    expires: DateTime(2099),
  );
  return result;
}

http.Response generated() =>
    fixtures.json({'idPrediccion': 99, 'idProducto': 7});
Future<void> dialog(WidgetTester tester, InventoryApi service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<int>(
              context: context,
              barrierDismissible: false,
              builder: (_) => GeneratePredictionDialog(
                api: service,
                productId: 7,
                productName: 'Cuaderno A4',
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Rechaza vacío, cero, fracciones y más de 30 sin enviar', (
    tester,
  ) async {
    var posts = 0;
    final service = api((_) async {
      posts++;
      return generated();
    });
    addTearDown(service.close);
    await dialog(tester, service);
    for (final value in ['', '0', '31', '1.5', '-1']) {
      await tester.enterText(find.byKey(const Key('prediction-days')), value);
      await tester.tap(find.text('Generar'));
      await tester.pump();
      expect(find.text('Ingresá un entero entre 1 y 30.'), findsOneWidget);
    }
    expect(posts, 0);
  });
  testWidgets('Envía una sola solicitud autenticada y bloquea doble clic', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var posts = 0;
    final service = api((request) {
      posts++;
      expect(request.method, 'POST');
      expect(request.url.path, '/predicciones/7/generar');
      expect(jsonDecode(request.body), {'diasPrediccion': 30});
      expect(request.headers['Authorization'], 'Bearer ${'A' * 43}');
      return response.future;
    });
    addTearDown(service.close);
    await dialog(tester, service);
    await tester.enterText(find.byKey(const Key('prediction-days')), '30');
    await tester.tap(find.text('Generar'));
    await tester.pump();
    await tester.tap(find.text('Generando…'));
    await tester.pump();
    expect(posts, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    response.complete(generated());
    await tester.pumpAndSettle();
    expect(find.byType(GeneratePredictionDialog), findsNothing);
  });
  testWidgets('Muestra historial insuficiente y conserva los días', (
    tester,
  ) async {
    final service = api(
      (_) async => http.Response(
        jsonEncode({
          'detail': 'No hay suficiente historial para entrenar el modelo.',
        }),
        422,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    addTearDown(service.close);
    await dialog(tester, service);
    await tester.enterText(find.byKey(const Key('prediction-days')), '15');
    await tester.tap(find.text('Generar'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay suficiente historial para entrenar el modelo.'),
      findsOneWidget,
    );
    expect(find.text('15'), findsOneWidget);
  });
  testWidgets('Resultado incierto exige actualizar antes de repetir', (
    tester,
  ) async {
    var posts = 0;
    final service = api((_) async {
      posts++;
      throw TimeoutException('demora');
    });
    addTearDown(service.close);
    await dialog(tester, service);
    await tester.tap(find.text('Generar'));
    await tester.pumpAndSettle();
    expect(find.text('Cerrar y actualizar'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Generar'))
          .onPressed,
      isNull,
    );
    expect(posts, 1);
  });
  testWidgets(
    'Desde análisis genera y selecciona la nueva predicción tras recargar',
    (tester) async {
      var created = false;
      var reads = 0;
      final service = api((request) async {
        if (request.method == 'POST') {
          created = true;
          return generated();
        }
        expect(request.url.path, '/productos/7/analisis');
        reads++;
        final data = fixtures.analysis();
        if (created) {
          data['predicciones'] = [
            fixtures.prediction(99, units: 123),
            ...data['predicciones'] as List,
          ];
        }
        return fixtures.json(data);
      });
      addTearDown(service.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductAnalysisScreen(
              api: service,
              productId: 7,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar predicción'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('prediction-days')), '1');
      await tester.tap(find.text('Generar'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Predicción generada.'), findsOneWidget);
      await tester.ensureVisible(find.text('123 unidades estimadas'));
      expect(find.text('123 unidades estimadas'), findsOneWidget);
    },
  );
  testWidgets('Vendedor no ve el botón y no puede invocar el cliente', (
    tester,
  ) async {
    final service = api(
      (_) async => fixtures.json(fixtures.analysis()),
      role: 'Vendedor',
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductAnalysisScreen(
            api: service,
            productId: 7,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generar predicción'), findsNothing);
    await expectLater(
      service.generatePrediction(7, 7),
      throwsA(isA<ApiFailure>()),
    );
  });
}
