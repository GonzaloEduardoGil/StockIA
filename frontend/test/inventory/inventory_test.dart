import '../helpers/tap_visible.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';

final stock = [
  {
    'idProducto': 1,
    'nombre': 'Mouse inalámbrico',
    'categoria': 'Periféricos',
    'cantidadDisponible': 10,
    'stockMinimo': 10,
  },
  {
    'idProducto': 2,
    'nombre': 'Teclado mecánico',
    'categoria': 'Periféricos',
    'cantidadDisponible': 25,
    'stockMinimo': 12,
  },
  {
    'idProducto': 3,
    'nombre': 'Cable USB-C',
    'categoria': null,
    'cantidadDisponible': 0,
    'stockMinimo': 0,
  },
];
final products = [
  {
    'idProducto': 1,
    'nombre': 'Mouse inalámbrico',
    'categoria': 'Periféricos',
    'precio': 18500,
    'descripcion': 'Mouse de prueba',
    'stockMinimo': 10,
  },
  {
    'idProducto': 2,
    'nombre': 'Teclado mecánico',
    'categoria': 'Periféricos',
    'precio': 45000,
    'descripcion': null,
    'stockMinimo': 12,
  },
  {
    'idProducto': 3,
    'nombre': 'Cable USB-C',
    'categoria': null,
    'precio': 8500,
    'descripcion': null,
    'stockMinimo': 0,
  },
  {
    'idProducto': 4,
    'nombre': 'Producto sin stock activo',
    'categoria': null,
    'precio': 1,
    'stockMinimo': 0,
  },
];
http.Response response(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
InventoryApi api({bool Function()? failing}) => InventoryApi(
  baseUrl: 'http://test.local',
  client: MockClient((request) async {
    if (failing?.call() == true) {
      return response({'detail': 'error privado del servidor'}, 500);
    }
    return switch (request.url.path) {
      '/stock/' => response({'productos': stock}),
      '/productos/' => response({'productos': products}),
      '/productos/1' => response(products[0]),
      _ => response({}, 404),
    };
  }),
);

void main() {
  test(
    'combina stock activo con datos del producto y contempla el mínimo exacto',
    () async {
      final client = api();
      addTearDown(client.close);
      final list = await client.loadInventory();
      expect(list.length, 3);
      expect(list.any((p) => p.id == 4), false);
      expect(list.singleWhere((p) => p.id == 1).isLow, true);
      expect(list.singleWhere((p) => p.id == 1).price, 18500);
      expect(list.singleWhere((p) => p.id == 3).category, 'Sin categoría');
    },
  );
  test(
    'rechaza respuestas incompletas en lugar de mostrar datos de ejemplo',
    () async {
      final client = InventoryApi(
        client: MockClient((_) async => response({'otro': []})),
      );
      addTearDown(client.close);
      await expectLater(client.loadInventory(), throwsA(isA<ApiFailure>()));
    },
  );
  testWidgets('busca sin tildes, filtra stock bajo y abre detalle real', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(StockiaApp(api: api()));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Stock bajo'));
    await tester.pumpAndSettle();
    expect(find.text('Teclado mecánico'), findsNothing);
    await tester.enterText(find.byType(TextField), 'inalambrico');
    await tester.pumpAndSettle();
    expect(find.text('Cable USB-C'), findsNothing);
    await tapVisible(tester, find.text('Mouse inalámbrico'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del producto'), findsOneWidget);
    expect(find.text('Mouse de prueba'), findsOneWidget);
    expect(find.text(r'$ 18.500,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'permite reintentar una consulta fallida sin mostrar errores privados',
    (tester) async {
      var failing = true;
      await tester.pumpWidget(StockiaApp(api: api(failing: () => failing)));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos cargar el inventario'), findsOneWidget);
      expect(find.textContaining('error privado'), findsNothing);
      failing = false;
      await tester.ensureVisible(find.text('Reintentar'));
      await tapVisible(tester, find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Mouse inalámbrico'), findsOneWidget);
    },
  );
  for (final width in [320.0, 390.0, 760.0, 1000.0]) {
    testWidgets('listado y detalle sin desbordes a $width px', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(StockiaApp(api: api()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Mouse inalámbrico'));
      await tapVisible(tester, find.text('Mouse inalámbrico'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del producto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
