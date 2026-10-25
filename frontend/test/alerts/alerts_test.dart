import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/product.dart';
import 'package:stockia/screens/alerts_screen.dart';
import 'package:stockia/screens/inventory_operation_page.dart';

Map<String, dynamic> alert(
  int id,
  String name,
  int quantity, {
  int minimum = 10,
  String? category = 'Librería',
}) => {
  'idAlerta': null,
  'fechaCreacion': null,
  'mensaje': null,
  'idProducto': id,
  'nombreProducto': name,
  'categoria': category,
  'cantidadDisponible': quantity,
  'stockMinimo': minimum,
  'estadoStock': 'BAJO',
};
Map<String, dynamic> detail(int id) => {
  'producto': {
    'idProducto': id,
    'nombre': 'Lápiz',
    'descripcion': 'Grafito',
    'categoria': 'Librería',
    'precio': 250,
    'cantidadDisponible': 0,
    'stockMinimo': 10,
  },
  'ultimaAlerta': null,
};
http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
InventoryApi service({List<dynamic>? alerts}) => InventoryApi(
  client: MockClient((request) async {
    expect(request.method, 'GET');
    if (request.url.path == '/alertas/') {
      return json({
        'alertas':
            alerts ??
            [
              alert(7, 'Lápiz', 0),
              alert(8, 'Mouse', 10, category: 'Tecnología'),
            ],
      });
    }
    return json(detail(int.parse(request.url.path.split('/').last)));
  }),
);
Future<void> show(
  WidgetTester tester,
  InventoryApi api, {
  double width = 1280,
  ValueChanged<Product>? onEntry,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AlertsScreen(api: api, onEntry: onEntry ?? (_) {}),
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

void main() {
  test(
    'GET ordena sin stock primero, admite mínimos iguales y avisos nulos',
    () async {
      final api = service(
        alerts: [
          alert(8, 'Mouse', 10),
          alert(9, 'Teclado', 2),
          alert(7, 'Lápiz', 0, minimum: 0, category: null),
        ],
      );
      final result = await api.loadAlerts();
      expect(result.map((a) => a.productId), [7, 9, 8]);
      expect(result.first.category, 'Sin categoría');
      expect(result.first.date, isNull);
      final d = await api.loadAlert(7);
      expect(d.product.quantity, 0);
      expect(d.lastAlertDate, isNull);
    },
  );
  test('rechaza datos incompletos y detalles de otro producto', () async {
    final malformed = InventoryApi(
      client: MockClient(
        (_) async => json({
          'alertas': [alert(1, 'Error', 20)],
        }),
      ),
    );
    await expectLater(malformed.loadAlerts(), throwsA(isA<ApiFailure>()));
    final wrong = InventoryApi(
      client: MockClient((_) async => json(detail(8))),
    );
    await expectLater(wrong.loadAlert(7), throwsA(isA<ApiFailure>()));
  });
  for (final status in [404, 409]) {
    test(
      'detalle $status indica actualizar sin mostrar una alerta vigente',
      () async {
        final api = InventoryApi(
          client: MockClient((_) async => http.Response('', status)),
        );
        await expectLater(
          api.loadAlert(7),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.requiresRefresh,
              'requiresRefresh',
              true,
            ),
          ),
        );
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('busca código, nombre sin acentos y categoría a $width px', (
      tester,
    ) async {
      await show(tester, service(), width: width);
      expect(find.text('Sin stock'), findsOneWidget);
      final search = find.byKey(const Key('alert-search'));
      for (final query in ['7', 'lapiz', 'libreria']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('alert-detail-7')), findsOneWidget);
        expect(find.byKey(const ValueKey('alert-detail-8')), findsNothing);
      }
      await tester.enterText(search, 'inexistente');
      await tester.pumpAndSettle();
      expect(
        find.text('No encontramos alertas con estos filtros.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Limpiar filtros'));
      expect(find.byKey(const ValueKey('alert-detail-8')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('detalle y entrada con el producto elegido a $width px', (
      tester,
    ) async {
      Product? selected;
      await show(tester, service(), width: width, onEntry: (p) => selected = p);
      await tap(tester, find.byKey(const ValueKey('alert-detail-7')));
      expect(find.text('Stock actual: 0'), findsOneWidget);
      expect(find.text('Stock mínimo: 10'), findsOneWidget);
      expect(find.textContaining('Último aviso:'), findsNothing);
      await tap(tester, find.byKey(const Key('alert-register-entry')));
      expect(selected?.id, 7);
      expect(selected?.quantity, 0);
      expect(selected?.price, 250);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('filtra por categoría y limpia los filtros', (tester) async {
    await show(tester, service());
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('Tecnología').last);
    expect(find.byKey(const ValueKey('alert-detail-7')), findsNothing);
    expect(find.byKey(const ValueKey('alert-detail-8')), findsOneWidget);
    await tap(tester, find.text('Limpiar filtros'));
    expect(find.byKey(const ValueKey('alert-detail-7')), findsOneWidget);
  });
  testWidgets(
    'alerta ya repuesta vuelve a consultar y desaparece del listado',
    (tester) async {
      var resolved = false;
      final api = InventoryApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path == '/alertas/') {
            return json({
              'alertas': resolved ? [] : [alert(7, 'Lápiz', 0)],
            });
          }
          resolved = true;
          return http.Response('', 409);
        }),
      );
      await show(tester, api);
      await tap(tester, find.byKey(const ValueKey('alert-detail-7')));
      expect(
        find.textContaining('La alerta ya no está vigente'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('alert-register-entry')), findsNothing);
      await tap(tester, find.text('Volver a alertas'));
      expect(find.text('No hay productos con stock bajo.'), findsOneWidget);
    },
  );
  testWidgets('error de consulta permite reintentar sin inventar alertas', (
    tester,
  ) async {
    var failed = false;
    final api = InventoryApi(
      client: MockClient((_) async {
        if (!failed) {
          failed = true;
          return http.Response('', 500);
        }
        return json({'alertas': []});
      }),
    );
    await show(tester, api);
    expect(find.byKey(const ValueKey('alert-detail-7')), findsNothing);
    await tap(tester, find.text('Reintentar'));
    expect(find.text('No hay productos con stock bajo.'), findsOneWidget);
  });
  testWidgets('volver mientras carga no reabre un detalle viejo', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final api = InventoryApi(
      client: MockClient((request) async {
        if (request.url.path == '/alertas/') {
          return json({
            'alertas': [alert(7, 'Lápiz', 0)],
          });
        }
        return pending.future;
      }),
    );
    await show(tester, api);
    await tester.tap(find.byKey(const ValueKey('alert-detail-7')));
    await tester.pump();
    await tester.tap(find.text('Volver a alertas'));
    await tester.pump();
    pending.complete(json(detail(7)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('alert-register-entry')), findsNothing);
    expect(find.byKey(const ValueKey('alert-detail-7')), findsOneWidget);
  });
  testWidgets(
    'aviso identifica producto, abre alertas y reutiliza entrada con sidebar',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = InventoryApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          switch (request.url.path) {
            case '/stock/':
              return json({
                'productos': [
                  {
                    'idProducto': 7,
                    'nombre': 'Lápiz',
                    'categoria': 'Librería',
                    'cantidadDisponible': 0,
                    'stockMinimo': 10,
                  },
                ],
              });
            case '/productos/':
              return json({
                'productos': [
                  {'idProducto': 7, 'nombre': 'Lápiz', 'precio': 250},
                ],
              });
            case '/productos/7':
              return json({
                'idProducto': 7,
                'nombre': 'Lápiz',
                'descripcion': 'Grafito',
                'categoria': 'Librería',
                'precio': 250,
                'stockMinimo': 10,
              });
            case '/alertas/':
              return json({
                'alertas': [alert(7, 'Lápiz', 0)],
              });
            default:
              return json(detail(7));
          }
        }),
      );
      await tester.pumpWidget(StockiaApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Stock bajo: Lápiz (#7).'), findsOneWidget);
      await tap(tester, find.text('Ver alertas'));
      expect(find.byType(AlertsScreen), findsOneWidget);
      expect(find.byKey(const Key('nav-inventory')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('alert-detail-7')));
      await tap(tester, find.byKey(const Key('alert-register-entry')));
      expect(find.byType(InventoryOperationPage), findsOneWidget);
      expect(find.textContaining('Lápiz'), findsWidgets);
      expect(find.byKey(const Key('nav-alerts')), findsOneWidget);
    },
  );
  testWidgets('el aviso se retira al actualizar un inventario ya repuesto', (
    tester,
  ) async {
    var quantity = 0;
    final api = InventoryApi(
      client: MockClient((request) async {
        return json({
          'productos': [
            {
              'idProducto': 7,
              'nombre': 'Lápiz',
              'categoria': 'Librería',
              'cantidadDisponible': quantity,
              'stockMinimo': 10,
              'precio': 250,
            },
          ],
        });
      }),
    );
    await tester.pumpWidget(StockiaApp(api: api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stock-low-notice')), findsOneWidget);
    quantity = 20;
    await tap(tester, find.widgetWithText(OutlinedButton, 'Actualizar'));
    expect(find.byKey(const Key('stock-low-notice')), findsNothing);
  });
}
