import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/screens/inventory_screen.dart';
import 'package:stockia/screens/sales_screen.dart';

Map<String, dynamic> summary(int id, String date) => {
  'idVenta': id,
  'fecha': date,
  'total': 25000.0,
  'idUsuario': 1,
  'vendedor': 'Ana',
};
Map<String, dynamic> detail(int id) => {
  'idVenta': id,
  'fecha': '2026-10-24T23:59:00',
  'total': 25000,
  'vendedor': {'idUsuario': 1, 'nombre': 'Ana'},
  'detalles': [
    {
      'idDetalle': 1,
      'idProducto': 7,
      'nombreProducto': 'Cuaderno A4',
      'cantidad': 2,
      'precioUnitario': 3500,
      'subtotal': 7000,
    },
    {
      'idDetalle': 2,
      'idProducto': 8,
      'nombreProducto': 'Mouse inalámbrico',
      'cantidad': 1,
      'precioUnitario': 18000,
      'subtotal': 18000,
    },
  ],
};
http.Response response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
InventoryApi api({List<dynamic>? sales}) => InventoryApi(
  client: MockClient((request) async {
    expect(request.method, 'GET');
    if (request.url.path == '/ventas/') {
      return response({
        'ventas':
            sales ??
            [
              summary(12, '2026-10-24T23:59:00'),
              summary(2, '2026-10-23T10:00:00'),
            ],
      });
    }
    return response(detail(int.parse(request.url.path.split('/').last)));
  }),
);
Future<void> show(
  WidgetTester tester,
  InventoryApi service, {
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SalesScreen(api: service)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('consulta ventas ordenadas y detalle con precios históricos usando solo GET', () async {
    final service = api(
      sales: [
        summary(2, '2026-10-24'),
        summary(12, '2026-10-24'),
        summary(20, '2026-10-23'),
      ],
    );
    final sales = await service.loadSales();
    expect(sales.map((s) => s.id), [12, 2, 20]);
    final sale = await service.loadSale(12);
    expect(sale.lines.first.unitPrice, 3500);
    expect(sale.lines.first.quantity, 2);
    expect(sale.lines.first.subtotal, 7000);
  });
  test('rechaza respuestas incompletas o detalle de otra venta', () async {
    final malformed = InventoryApi(
      client: MockClient(
        (_) async => response({
          'ventas': [
            {'idVenta': 2},
          ],
        }),
      ),
    );
    await expectLater(malformed.loadSales(), throwsA(isA<ApiFailure>()));
    final wrong = InventoryApi(
      client: MockClient((_) async => response(detail(4))),
    );
    await expectLater(wrong.loadSale(12), throwsA(isA<ApiFailure>()));
  });
  for (final width in [390.0, 1000.0, 1280.0]) {
    testWidgets('listado, filtro exacto y detalle adaptable a $width px', (
      tester,
    ) async {
      await show(tester, api(), width: width);
      expect(find.byKey(const ValueKey('sale-detail-12')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('sale-number')), '2');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-detail-12')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('sale-detail-2')));
      expect(find.text('Venta #2'), findsOneWidget);
      expect(find.text('Cuaderno A4 (#7)'), findsOneWidget);
      expect(find.text('2 × \$ 3.500,00'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      await tap(tester, find.text('Volver a ventas'));
      expect(find.byKey(const ValueKey('sale-detail-12')), findsNothing);
      await tap(tester, find.text('Limpiar filtros'));
      expect(find.byKey(const ValueKey('sale-detail-12')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('fecha hasta incluye la última hora del día y valida el rango', (
    tester,
  ) async {
    await show(tester, api());
    await tester.enterText(
      find.byKey(const Key('sale-date-from')),
      '24/10/2026',
    );
    await tester.enterText(find.byKey(const Key('sale-date-to')), '24/10/2026');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sale-detail-12')), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-detail-2')), findsNothing);
    await tester.enterText(find.byKey(const Key('sale-date-to')), '23/10/2026');
    await tester.pumpAndSettle();
    expect(
      find.text('La fecha desde debe ser anterior o igual a la fecha hasta.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('sale-date-to')), '31/02/2026');
    await tester.pumpAndSettle();
    expect(find.text('Usá fechas válidas: dd/mm/aaaa.'), findsOneWidget);
  });
  testWidgets('abre calendario anclado y aplica una fecha', (tester) async {
    await show(tester, api());
    await tap(tester, find.byTooltip('Elegir fecha desde'));
    expect(find.byKey(const Key('sale-date-popover')), findsOneWidget);
    expect(find.byKey(const Key('calendar-month')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale-date-popover')), findsNothing);
  });
  testWidgets('estados vacíos y sin coincidencias', (tester) async {
    await show(tester, api(sales: []));
    expect(find.text('Todavía no hay ventas registradas.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(tester, api());
    await tester.enterText(find.byKey(const Key('sale-number')), '999');
    await tester.pumpAndSettle();
    expect(
      find.text('No encontramos ventas con estos filtros.'),
      findsOneWidget,
    );
  });
  testWidgets('reintenta listado y detalle sin mostrar información vieja', (
    tester,
  ) async {
    var failList = true;
    var failDetail = true;
    final service = InventoryApi(
      client: MockClient((request) async {
        if (request.url.path == '/ventas/') {
          if (failList) {
            failList = false;
            return http.Response('', 500);
          }
          return response({
            'ventas': [summary(12, '2026-10-24')],
          });
        }
        if (failDetail) {
          failDetail = false;
          return http.Response('', 404);
        }
        return response(detail(12));
      }),
    );
    await show(tester, service);
    await tap(tester, find.text('Reintentar'));
    await tap(tester, find.byKey(const ValueKey('sale-detail-12')));
    expect(find.text('Cuaderno A4 (#7)'), findsNothing);
    await tap(tester, find.text('Reintentar'));
    expect(find.text('Cuaderno A4 (#7)'), findsOneWidget);
  });
  testWidgets(
    'volver durante la carga no reabre el detalle al recibir la respuesta',
    (tester) async {
      final pending = Completer<http.Response>();
      final service = InventoryApi(
        client: MockClient((request) async {
          if (request.url.path == '/ventas/') {
            return response({
              'ventas': [summary(12, '2026-10-24')],
            });
          }
          return pending.future;
        }),
      );
      await show(tester, service);
      await tester.tap(find.byKey(const ValueKey('sale-detail-12')));
      await tester.pump();
      await tester.tap(find.text('Volver a ventas'));
      await tester.pump();
      pending.complete(response(detail(12)));
      await tester.pumpAndSettle();
      expect(find.text('Cuaderno A4 (#7)'), findsNothing);
      expect(find.byKey(const ValueKey('sale-detail-12')), findsOneWidget);
    },
  );
  testWidgets('navegación conserva barra lateral y vuelve al inventario', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = InventoryApi(
      client: MockClient((request) async {
        if (request.url.path == '/ventas/') {
          return response({
            'ventas': [summary(12, '2026-10-24')],
          });
        }
        return response({'productos': []});
      }),
    );
    await tester.pumpWidget(StockiaApp(api: service));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('nav-sales-history')));
    expect(find.byType(SalesScreen), findsOneWidget);
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(find.byKey(const Key('nav-new-sale')), findsOneWidget);
    await tap(tester, find.byKey(const Key('nav-inventory')));
    expect(find.byType(SalesScreen), findsNothing);
  });
}
