import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/dashboard.dart';
import 'package:stockia/screens/dashboard_screen.dart';
import 'package:stockia/screens/alerts_screen.dart';
import 'package:stockia/widgets/sales_trend_chart.dart';

Map<String, dynamic> dashboard() => {
  'resumenVentas': {'cantidadVentas': 3, 'totalFacturado': 300},
  'inventario': {
    'productosActivos': 6,
    'unidadesDisponibles': 700,
    'productosStockBajo': 1,
    'productosStockNormal': 5,
  },
  'productosMasVendidos': [
    {'idProducto': 7, 'nombre': 'Cuaderno', 'cantidadVendida': 10},
  ],
  'productosMenosVendidos': [
    {'idProducto': 8, 'nombre': 'Mouse', 'cantidadVendida': 0},
  ],
  'evolucionVentas': [
    {'fecha': '2026-10-23', 'cantidadVentas': 1, 'totalFacturado': 100},
    {'fecha': '2026-10-24', 'cantidadVentas': 2, 'totalFacturado': 200},
  ],
  'informacionInsuficiente': false,
};
Map<String, dynamic> alerts() => {
  'alertas': [
    {
      'idProducto': 7,
      'nombreProducto': 'Cuaderno',
      'categoria': 'Librería',
      'cantidadDisponible': 2,
      'stockMinimo': 10,
      'fechaCreacion': null,
    },
  ],
};
http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
InventoryApi service({
  Map<String, dynamic>? data,
  int? failDashboard,
  int? failAlerts,
  List<Uri>? requests,
}) => InventoryApi(
  client: MockClient((request) async {
    expect(request.method, 'GET');
    requests?.add(request.url);
    if (request.url.path == '/dashboard/') {
      return failDashboard == null
          ? json(data ?? dashboard())
          : http.Response('', failDashboard);
    }
    return failAlerts == null ? json(alerts()) : http.Response('', failAlerts);
  }),
);
Future<void> show(
  WidgetTester tester,
  InventoryApi api, {
  double width = 1280,
  VoidCallback? onAlerts,
  VoidCallback? onInventory,
  VoidCallback? onSales,
  ValueChanged<int>? onProduct,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          api: api,
          onInventory: onInventory ?? () {},
          onAlerts: onAlerts ?? () {},
          onSales: onSales ?? () {},
          onProduct: onProduct ?? (_) {},
        ),
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
  test('envía fechas ISO por GET y mantiene separadas las secciones', () async {
    final requests = <Uri>[];
    final api = service(requests: requests);
    final data = await api.loadDashboard(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 24),
    );
    expect(requests.single.path, '/dashboard/');
    expect(requests.single.queryParameters, {
      'fecha_desde': '2026-10-01',
      'fecha_hasta': '2026-10-24',
    });
    expect(data.sales?.total, 300);
    expect(data.inventory?.low, 1);
    expect(data.least?.single.units, 0);
    requests.clear();
    await expectLater(
      api.loadDashboard(
        from: DateTime(2026, 10, 24),
        to: DateTime(2026, 10, 1),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, isEmpty);
  });
  test('agrupa por día, ordena por fecha y suma importes en centavos', () {
    final raw = dashboard();
    raw['evolucionVentas'] = [
      {
        'fecha': '2026-10-24T23:59:00',
        'cantidadVentas': 2,
        'totalFacturado': 0.20,
      },
      {'fecha': '2026-10-23', 'cantidadVentas': 1, 'totalFacturado': 1},
      {
        'fecha': '2026-10-24T01:00:00',
        'cantidadVentas': 1,
        'totalFacturado': 0.10,
      },
    ];
    final data = DashboardData.fromApi(raw);
    expect(data.trend?.length, 2);
    expect(data.trend?.last.total, 0.3);
    expect(data.trend?.last.count, 3);
    raw['inventario'] = {'productosActivos': -1};
    raw['productosMasVendidos'] = 'incompleto';
    final partial = DashboardData.fromApi(raw);
    expect(partial.inventory, isNull);
    expect(partial.best, isNull);
    expect(partial.sales?.count, 3);
    expect(partial.trend?.length, 2);
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('resumen, gráfica y accesos sin desbordes a $width px', (
      tester,
    ) async {
      var inventoryOpened = false;
      var alertsOpened = false;
      int? product;
      await show(
        tester,
        service(),
        width: width,
        onInventory: () => inventoryOpened = true,
        onAlerts: () => alertsOpened = true,
        onProduct: (id) => product = id,
      );
      expect(find.text('Resumen general'), findsOneWidget);
      expect(find.text('\$ 300,00'), findsOneWidget);
      await tap(tester, find.byTooltip('Ver análisis de Cuaderno'));
      expect(product, 7);
      await tap(tester, find.text('Ver inventario'));
      expect(inventoryOpened, isTrue);
      await tap(tester, find.text('Ver alertas'));
      expect(alertsOpened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'las fechas se aplican al consultar y no alteran el inventario actual',
    (tester) async {
      final requests = <Uri>[];
      await show(tester, service(requests: requests));
      await tester.enterText(field('dashboard-from'), '01/10/2026');
      await tester.enterText(field('dashboard-to'), '24/10/2026');
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.path == '/dashboard/').length, 1);
      await tap(tester, find.text('Aplicar'));
      expect(
        requests
            .lastWhere((r) => r.path == '/dashboard/')
            .queryParameters['fecha_hasta'],
        '2026-10-24',
      );
      expect(
        find.text('Ventas: 01/10/2026 – 24/10/2026 · Inventario actual'),
        findsOneWidget,
      );
      await tester.enterText(field('dashboard-from'), '25/10/2026');
      await tester.pumpAndSettle();
      expect(
        find.text('La fecha desde debe ser anterior o igual a la fecha hasta.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Aplicar'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Limpiar fechas'));
      expect(
        requests.lastWhere((r) => r.path == '/dashboard/').queryParameters,
        isEmpty,
      );
    },
  );
  testWidgets(
    'calendario desplegable conserva estilo y se cierra al elegir día',
    (tester) async {
      await show(tester, service());
      await tap(tester, find.byTooltip('Elegir fecha desde'));
      expect(find.byKey(const Key('dashboard-date-popover')), findsOneWidget);
      await tap(tester, find.byType(InkWell).last);
      expect(find.byKey(const Key('dashboard-date-popover')), findsNothing);
      expect(
        tester.widget<TextField>(field('dashboard-from')).controller!.text,
        isNotEmpty,
      );
    },
  );
  testWidgets(
    'selección de día muestra su importe real, con un único día o importe cero',
    (tester) async {
      await show(tester, service());
      final dropdown = find.descendant(
        of: find.byType(SalesTrendChart),
        matching: find.byType(DropdownButtonFormField<int>),
      );
      await tap(tester, dropdown);
      await tap(tester, find.text('23/10/2026').last);
      expect(find.text('1 venta · \$ 100,00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final raw = dashboard();
      raw['evolucionVentas'] = [
        {'fecha': '2026-10-24', 'cantidadVentas': 1, 'totalFacturado': 0},
      ];
      await show(tester, service(data: raw));
      expect(find.text('1 venta · \$ 0,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('información insuficiente muestra las secciones disponibles', (
    tester,
  ) async {
    final raw = dashboard();
    raw['evolucionVentas'] = [];
    raw['resumenVentas'] = {'cantidadVentas': 0, 'totalFacturado': 0};
    raw['productosMasVendidos'] = [];
    raw['productosMenosVendidos'] = [];
    await show(tester, service(data: raw));
    expect(find.text('No hay ventas en este período.'), findsOneWidget);
    expect(find.text('Productos activos: 6'), findsOneWidget);
    expect(find.text('Cuaderno (#7)'), findsOneWidget);
  });
  testWidgets(
    'error de alertas mantiene los indicadores y error del resumen mantiene alertas',
    (tester) async {
      await show(tester, service(failAlerts: 500));
      expect(find.text('\$ 300,00'), findsOneWidget);
      expect(find.text('No se pudieron cargar las alertas.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await show(tester, service(failDashboard: 500));
      expect(find.text('\$ 300,00'), findsNothing);
      expect(find.text('Cuaderno (#7)'), findsOneWidget);
    },
  );
  testWidgets(
    'sección incompleta no se presenta como un cero ni elimina el resto',
    (tester) async {
      final raw = dashboard();
      raw.remove('resumenVentas');
      raw['evolucionVentas'] = 'inválido';
      await show(tester, service(data: raw));
      expect(find.text('No disponible'), findsNWidgets(2));
      expect(
        find.text('No se pudo cargar la evolución de ventas.'),
        findsOneWidget,
      );
      expect(find.text('Productos activos: 6'), findsOneWidget);
    },
  );
  testWidgets('una respuesta anterior no reemplaza el período vigente', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var first = true;
    final api = InventoryApi(
      client: MockClient((request) async {
        if (request.url.path == '/alertas/') return json(alerts());
        if (first) {
          first = false;
          return pending.future;
        }
        return json({
          ...dashboard(),
          'resumenVentas': {'cantidadVentas': 99, 'totalFacturado': 999},
        });
      }),
    );
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            api: api,
            onInventory: () {},
            onAlerts: () {},
            onSales: () {},
            onProduct: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Limpiar fechas'));
    await tester.pump();
    pending.complete(json(dashboard()));
    await tester.pumpAndSettle();
    expect(find.text('\$ 999,00'), findsOneWidget);
    expect(find.text('\$ 300,00'), findsNothing);
  });
  testWidgets(
    'inicio abre el dashboard y mantiene accesos a alertas e inventario',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = InventoryApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path == '/dashboard/') return json(dashboard());
          if (request.url.path == '/alertas/') return json(alerts());
          return json({'productos': []});
        }),
      );
      await tester.pumpWidget(StockiaApp(api: api, initialDashboard: true));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      await tap(tester, find.text('Ver alertas'));
      expect(find.byType(AlertsScreen), findsOneWidget);
      await tap(tester, find.byKey(const Key('nav-dashboard')));
      expect(find.byType(DashboardScreen), findsOneWidget);
      await tap(tester, find.byKey(const Key('nav-inventory')));
      expect(find.byType(DashboardScreen), findsNothing);
    },
  );
}
