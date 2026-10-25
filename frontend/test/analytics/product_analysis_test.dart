import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/product_analysis.dart';
import 'package:stockia/screens/product_analysis_screen.dart';
import 'package:stockia/widgets/prediction_card.dart';
import 'package:stockia/widgets/sales_trend_chart.dart';

Map<String, dynamic> prediction(
  int id, {
  String date = '2026-10-23',
  int units = 83,
}) => {
  'idPrediccion': id,
  'idProducto': 7,
  'nombreProducto': 'Cuaderno A4',
  'activo': true,
  'fechaPrediccion': date,
  'periodoPrediccion': 'Próximos 25 días',
  'cantidadEstimada': units,
};
Map<String, dynamic> analysis() => {
  'producto': <String, dynamic>{
    'idProducto': 7,
    'nombre': 'Cuaderno A4',
    'categoria': 'Librería',
    'activo': true,
    'cantidadDisponible': 510,
    'stockMinimo': 30,
  },
  'resumenVentas': {
    'cantidadVentas': 2,
    'unidadesVendidas': 5,
    'totalFacturado': 17500,
  },
  'evolucionVentas': [
    {
      'fecha': '2026-10-23T23:59:00',
      'unidadesVendidas': 2,
      'totalFacturado': 7000,
    },
    {'fecha': '2026-10-24', 'unidadesVendidas': 3, 'totalFacturado': 10500},
  ],
  'predicciones': [prediction(3), prediction(1, date: '2026-10-20', units: 70)],
  'recomendaciones': [
    {
      'fecha': '2026-10-23',
      'cantidadSugerida': 50,
      'motivo': 'Reposición prevista',
      'estado': 'aceptada',
    },
  ],
};
Map<String, dynamic> dashboard() => {
  'resumenVentas': {'cantidadVentas': 2, 'totalFacturado': 17500},
  'inventario': {
    'productosActivos': 1,
    'unidadesDisponibles': 510,
    'productosStockBajo': 0,
    'productosStockNormal': 1,
  },
  'evolucionVentas': [
    {'fecha': '2026-10-23', 'cantidadVentas': 2, 'totalFacturado': 17500},
  ],
  'productosMasVendidos': [],
  'productosMenosVendidos': [],
};
http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
InventoryApi service({
  Map<String, dynamic>? data,
  List<Uri>? requests,
  bool failPredictions = false,
}) => InventoryApi(
  client: MockClient((request) async {
    expect(request.method, 'GET');
    requests?.add(request.url);
    switch (request.url.path) {
      case '/predicciones/':
        return failPredictions
            ? http.Response('', 500)
            : json({
                'predicciones': [prediction(3)],
              });
      case '/dashboard/':
        return json(dashboard());
      case '/alertas/':
        return json({'alertas': []});
      case '/productos/':
        return json({
          'productos': [
            {'idProducto': 7, 'nombre': 'Cuaderno A4', 'precio': 3500},
          ],
        });
      case '/stock/':
        return json({
          'productos': [
            {
              'idProducto': 7,
              'nombre': 'Cuaderno A4',
              'categoria': 'Librería',
              'cantidadDisponible': 510,
              'stockMinimo': 30,
            },
          ],
        });
      default:
        return json(data ?? analysis());
    }
  }),
);
Future<void> size(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> showAnalysis(
  WidgetTester tester,
  InventoryApi api, {
  double width = 1280,
}) async {
  await size(tester, width);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProductAnalysisScreen(api: api, productId: 7, onBack: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  testWidgets('las tres predicciones se muestran en una fila en escritorio', (
    tester,
  ) async {
    await size(tester, 1280);
    final api = InventoryApi(
      client: MockClient((request) async {
        if (request.url.path == '/predicciones/') {
          return json({
            'predicciones': [prediction(3), prediction(2), prediction(1)],
          });
        }
        if (request.url.path == '/dashboard/') return json(dashboard());
        if (request.url.path == '/alertas/') return json({'alertas': []});
        return json({'productos': []});
      }),
    );
    await tester.pumpWidget(StockiaApp(api: api, initialDashboard: true));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('dashboard-prediction-3')),
    );
    final last = tester.getTopLeft(
      find.byKey(const ValueKey('dashboard-prediction-1')),
    );
    expect(last.dy, first.dy);
    expect(last.dx, greaterThan(first.dx));
    expect(tester.takeException(), isNull);
  });
  test('consulta predicciones guardadas y análisis por GET, sin generar resultados', () async {
    final requests = <Uri>[];
    final api = service(requests: requests);
    final predictions = await api.loadPredictions();
    expect(predictions.single.units, 83);
    expect(predictions.single.date, DateTime(2026, 10, 23));
    final product = await api.loadProductAnalysis(7);
    expect(product.predictions!.map((p) => p.id), [3, 1]);
    expect(product.recommendations!.single.status, 'aceptada');
    expect(requests.map((u) => u.path), [
      '/predicciones/',
      '/productos/7/analisis',
    ]);
  });
  test('rechaza números inválidos sin perder ventas válidas', () {
    expect(
      () =>
          DemandPrediction.fromApi({...prediction(3), 'cantidadEstimada': -1}),
      throwsFormatException,
    );
    final raw = analysis();
    raw['predicciones'] = [
      {'cantidadEstimada': 9},
    ];
    final data = ProductAnalysis.fromApi(raw);
    expect(data.predictions, isNull);
    expect(data.trend!.last.count, 3);
    expect(demandUnits(83), '83');
    expect(demandUnits(1200.5), '1.200,50');
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'ventas reales y predicciones claramente separadas a $width px',
      (tester) async {
        await showAnalysis(tester, service(), width: width);
        expect(find.text('Ventas reales'), findsOneWidget);
        expect(find.text('Unidades vendidas: 5'), findsOneWidget);
        expect(find.text('Total facturado: \$ 17.500,00'), findsOneWidget);
        expect(find.text('3 unidades · \$ 10.500,00'), findsOneWidget);
        await tester.ensureVisible(find.byType(PredictionCard));
        await tester.pumpAndSettle();
        expect(find.text('PREDICCIÓN'), findsOneWidget);
        expect(find.text('83 unidades estimadas'), findsOneWidget);
        expect(find.text('Generada: 23/10/2026'), findsOneWidget);
        expect(find.byType(SalesTrendChart), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'filtro inclusivo de ventas no filtra el historial de predicciones',
    (tester) async {
      await showAnalysis(tester, service());
      await tester.enterText(field('analysis-from'), '23/10/2026');
      await tester.enterText(field('analysis-to'), '23/10/2026');
      await tester.pumpAndSettle();
      expect(find.text('Unidades vendidas: 2'), findsOneWidget);
      expect(find.text('Total facturado: \$ 7.000,00'), findsOneWidget);
      expect(find.text('83 unidades estimadas'), findsOneWidget);
      await tester.enterText(field('analysis-from'), '25/10/2026');
      await tester.pumpAndSettle();
      expect(
        find.text('La fecha desde debe ser anterior o igual a la fecha hasta.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analysis-units')), findsNothing);
    },
  );
  testWidgets(
    'permite seleccionar una predicción histórica y conserva su fecha',
    (tester) async {
      await showAnalysis(tester, service());
      await tap(tester, find.byType(DropdownButtonFormField<int>).last);
      await tap(tester, find.text('#1 · 20/10/2026 · Próximos 25 días').last);
      expect(find.text('70 unidades estimadas'), findsOneWidget);
      expect(find.text('Generada: 20/10/2026'), findsOneWidget);
      expect(find.textContaining('Reposición prevista'), findsOneWidget);
    },
  );
  testWidgets(
    'producto inactivo y sin stock registrado conserva su historial',
    (tester) async {
      final raw = analysis();
      (raw['producto'] as Map<String, dynamic>)['activo'] = false;
      (raw['producto'] as Map<String, dynamic>)['cantidadDisponible'] = null;
      await showAnalysis(tester, service(data: raw));
      expect(
        find.text('Producto inactivo · Historial disponible'),
        findsOneWidget,
      );
      expect(find.text('Stock actual: Sin registro'), findsOneWidget);
      expect(find.text('83 unidades estimadas'), findsOneWidget);
    },
  );
  testWidgets('sin predicciones no inventa una demanda cero', (tester) async {
    final raw = analysis();
    raw['predicciones'] = [];
    raw['recomendaciones'] = [];
    await showAnalysis(tester, service(data: raw));
    expect(
      find.text('Este producto no tiene predicciones guardadas.'),
      findsOneWidget,
    );
    expect(find.byType(PredictionCard), findsNothing);
    expect(
      find.text('No hay recomendaciones guardadas para este producto.'),
      findsOneWidget,
    );
    expect(find.text('Unidades vendidas: 5'), findsOneWidget);
  });
  testWidgets(
    'el dashboard muestra predicciones diferenciadas y permite abrir análisis por búsqueda',
    (tester) async {
      await size(tester, 1280);
      final requests = <Uri>[];
      await tester.pumpWidget(
        StockiaApp(api: service(requests: requests), initialDashboard: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Predicciones de demanda'), findsOneWidget);
      expect(find.text('PREDICCIÓN'), findsOneWidget);
      expect(find.text('83 unidades estimadas'), findsOneWidget);
      await tester.enterText(field('dashboard-from'), '23/10/2026');
      await tester.enterText(field('dashboard-to'), '23/10/2026');
      await tap(tester, find.text('Aplicar'));
      final search = find.byKey(const Key('dashboard-product-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'cuaderno');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('dashboard-analyze-7')));
      expect(find.byType(ProductAnalysisScreen), findsOneWidget);
      expect(find.text('Unidades vendidas: 2'), findsOneWidget);
      expect(find.byKey(const Key('nav-dashboard')), findsOneWidget);
      await tap(tester, find.text('Volver al dashboard'));
      expect(find.byType(ProductAnalysisScreen), findsNothing);
      expect(
        find.text('Ventas: 23/10/2026 – 23/10/2026 · Inventario actual'),
        findsOneWidget,
      );
      expect(requests.where((u) => u.path == '/dashboard/').length, 2);
      expect(
        requests
            .where((u) => u.path == '/predicciones/')
            .every((u) => u.queryParameters.isEmpty),
        isTrue,
      );
    },
  );
  testWidgets('error de predicciones conserva indicadores y ventas reales', (
    tester,
  ) async {
    await size(tester, 1280);
    await tester.pumpWidget(
      StockiaApp(api: service(failPredictions: true), initialDashboard: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudieron cargar las predicciones guardadas.'),
      findsOneWidget,
    );
    expect(find.text('\$ 17.500,00'), findsNWidgets(2));
    expect(find.byType(SalesTrendChart), findsOneWidget);
  });
  testWidgets(
    'error de análisis permite volver, sin mostrar resultados de otro producto',
    (tester) async {
      final api = InventoryApi(
        client: MockClient((_) async => http.Response('', 404)),
      );
      await showAnalysis(tester, api);
      expect(find.byType(PredictionCard), findsNothing);
      expect(find.text('Volver al dashboard'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );
  testWidgets(
    'cerrar mientras consulta no reabre la pantalla ni usa datos anteriores',
    (tester) async {
      final pending = Completer<http.Response>();
      final api = InventoryApi(client: MockClient((_) async => pending.future));
      await size(tester, 1280);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductAnalysisScreen(api: api, productId: 7, onBack: () {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: Text('Cerrado')));
      pending.complete(json(analysis()));
      await tester.pumpAndSettle();
      expect(find.text('Cerrado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
