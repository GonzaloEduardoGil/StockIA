import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/product.dart';
import 'package:stockia/models/sale.dart';
import 'package:stockia/screens/new_sale_screen.dart';

import 'tap_visible.dart';

class SaleFixture {
  int writes = 0;
  int stockReads = 0;
  int status = 200;
  int savedCallbacks = 0;
  int inventoryCallbacks = 0;
  int movementsCallbacks = 0;
  bool offline = false;
  bool malformed = false;
  bool failRead = false;
  bool busy = false;
  Completer<void>? pending;
  void Function()? onReview;
  Map<String, dynamic>? payload;
  final products = <Map<String, dynamic>>[
    {
      'idProducto': 8,
      'nombre': 'Mouse',
      'categoria': 'Periféricos',
      'precio': 19.99,
      'descripcion': 'Mouse',
      'stockMinimo': 2,
      'cantidadDisponible': 10,
    },
    {
      'idProducto': 9,
      'nombre': 'Teclado',
      'categoria': 'Periféricos',
      'precio': 7.50,
      'descripcion': null,
      'stockMinimo': 2,
      'cantidadDisponible': 5,
    },
    {
      'idProducto': 10,
      'nombre': 'Agotado',
      'categoria': null,
      'precio': 12.0,
      'descripcion': null,
      'stockMinimo': 0,
      'cantidadDisponible': 0,
    },
    {
      'idProducto': 11,
      'nombre': 'Sin precio',
      'categoria': null,
      'precio': null,
      'descripcion': null,
      'stockMinimo': 0,
      'cantidadDisponible': 5,
    },
  ];
  Product get mouse => Product.fromApi(products[0], products[0]);
  late final api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method != 'GET') {
        writes++;
        expect(request.method, 'POST');
        expect(request.url.path, '/ventas/');
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload!.keys.toSet(), {'idUsuario', 'productos'});
        for (final item in payload!['productos'] as List) {
          expect((item as Map).keys.toSet(), {'idProducto', 'cantidad'});
        }
        if (pending != null) await pending!.future;
        if (offline) throw http.ClientException('sin conexión');
        if (status != 200) {
          return response({'detail': 'detalle privado'}, status);
        }
        final lines = <Map<String, dynamic>>[];
        int totalCents = 0;
        for (final item in payload!['productos'] as List) {
          final p = products.firstWhere(
            (p) => p['idProducto'] == item['idProducto'],
          );
          final quantity = item['cantidad'] as int;
          final subtotal =
              ((p['precio'] as num).toDouble() * 100).round() * quantity;
          totalCents += subtotal;
          p['cantidadDisponible'] = (p['cantidadDisponible'] as int) - quantity;
          lines.add({
            'idProducto': p['idProducto'],
            'nombre': p['nombre'],
            'cantidad': quantity,
            'subtotal': subtotal / 100,
          });
        }
        return response(
          malformed
              ? {}
              : {'idVenta': 70, 'total': totalCents / 100, 'productos': lines},
        );
      }
      if (failRead) return response({'detail': 'privado'}, 500);
      if (request.url.path == '/stock/') {
        stockReads++;
        if (stockReads == 2) onReview?.call();
        return response({'productos': products});
      }
      if (request.url.path == '/productos/') {
        return response({'productos': products});
      }
      if (request.url.path == '/movimientos/') {
        return response({'movimientos': []});
      }
      return response({}, 404);
    }),
  );
}

http.Response response(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void screen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester, SaleFixture f, {int? userId}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NewSaleScreen(
          api: f.api,
          currentUserId: userId,
          onBusyChanged: (busy) => f.busy = busy,
          onSaved: () async {
            f.savedCallbacks++;
          },
          onInventory: () => f.inventoryCallbacks++,
          onMovements: () => f.movementsCallbacks++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> add(WidgetTester tester, int id) async {
  final search = find.byKey(const Key('sale-product-search'));
  await tester.ensureVisible(search);
  await tester.pumpAndSettle();
  await tester.enterText(search, '$id');
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(ValueKey('sale-add-$id')));
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester) async {
  await tapVisible(tester, find.text('Revisar venta'));
  await tester.pumpAndSettle();
}

void main() {
  test('centavos y payload sin precios ni cantidades de stock', () async {
    final f = SaleFixture();
    final line = SaleLine(product: f.mouse, quantity: 3);
    expect(line.subtotalCents, 5997);
    final receipt = await f.api.registerSale(42, [line]);
    expect(f.payload, {
      'idUsuario': 42,
      'productos': [
        {'idProducto': 8, 'cantidad': 3},
      ],
    });
    expect(receipt.id, 70);
    expect(receipt.total, 59.97);
    f.api.close();
  });
  test('rechaza ventas vacías, cantidades inválidas, usuario inválido y duplicados sin POST', () async {
    final f = SaleFixture();
    for (final lines in <List<SaleLine>>[
      [],
      [SaleLine(product: f.mouse, quantity: 0)],
      [SaleLine(product: f.mouse, quantity: 11)],
      [
        SaleLine(product: f.mouse, quantity: 1),
        SaleLine(product: f.mouse, quantity: 1),
      ],
    ]) {
      await expectLater(
        f.api.registerSale(42, lines),
        throwsA(isA<ApiFailure>()),
      );
    }
    await expectLater(
      f.api.registerSale(0, [SaleLine(product: f.mouse, quantity: 1)]),
      throwsA(isA<ApiFailure>()),
    );
    expect(f.writes, 0);
    f.api.close();
  });
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'arma y revisa una venta visual sin sesión a $width px sin guardar',
      (tester) async {
        screen(tester, width);
        final f = SaleFixture();
        await open(tester, f);
        await review(tester);
        expect(find.text('Agregá al menos un producto.'), findsOneWidget);
        await add(tester, 8);
        await add(tester, 9);
        await tester.enterText(
          find.byKey(const ValueKey('sale-quantity-8')),
          '2',
        );
        await review(tester);
        expect(find.text('Revisar venta'), findsOneWidget);
        expect(find.text(r'$ 47,48'), findsOneWidget);
        expect(
          find.text('Necesitás iniciar sesión para confirmar.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmar venta'),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Código del vendedor'), findsNothing);
        expect(f.writes, 0);
        await tapVisible(tester, find.text('Corregir'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('sale-quantity-8')),
              )
              .controller!
              .text,
          '2',
        );
        await tapVisible(tester, find.text('Volver al inventario'));
        expect(f.inventoryCallbacks, 1);
        expect(f.writes, 0);
        expect(tester.takeException(), isNull);
        f.api.close();
      },
    );
  }
  testWidgets(
    'sin stock o precio no permite agregar; repetir no duplica el renglón y quitar no escribe',
    (tester) async {
      screen(tester, 390);
      final f = SaleFixture();
      await open(tester, f);
      await add(tester, 8);
      await add(tester, 8);
      expect(find.byKey(const ValueKey('sale-line-8')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sale-quantity-8')),
            )
            .controller!
            .text,
        '2',
      );
      for (final id in [10, 11]) {
        await tester.enterText(
          find.byKey(const Key('sale-product-search')),
          '$id',
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.byKey(ValueKey('sale-add-$id')))
              .onPressed,
          isNull,
        );
      }
      await tapVisible(tester, find.byTooltip('Quitar Mouse'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-line-8')), findsNothing);
      expect(f.writes, 0);
      f.api.close();
    },
  );
  testWidgets('valida enteros y stock antes de revisar', (tester) async {
    screen(tester, 390);
    final f = SaleFixture();
    await open(tester, f);
    await add(tester, 8);
    for (final text in ['0', '-1', '1.5', 'abc', '11']) {
      await tester.enterText(
        find.byKey(const ValueKey('sale-quantity-8')),
        text,
      );
      await review(tester);
      expect(find.text('Confirmar venta'), findsNothing);
    }
    expect(f.writes, 0);
    f.api.close();
  });
  testWidgets('revalida disponibilidad y precio al entrar al resumen', (
    tester,
  ) async {
    screen(tester, 1440);
    final f = SaleFixture()..onReview = () {};
    f.onReview = () => f.products[0]['precio'] = 20.49;
    await open(tester, f);
    await add(tester, 8);
    await review(tester);
    expect(find.text(r'$ 20,49'), findsWidgets);
    expect(f.writes, 0);
    f.api.close();
  });
  testWidgets('si bajó el stock conserva el carrito y pide corregir', (
    tester,
  ) async {
    screen(tester, 390);
    final f = SaleFixture();
    f.onReview = () => f.products[0]['cantidadDisponible'] = 1;
    await open(tester, f);
    await add(tester, 8);
    await tester.enterText(find.byKey(const ValueKey('sale-quantity-8')), '2');
    await review(tester);
    expect(find.text('Stock disponible: 1.'), findsOneWidget);
    expect(find.text('Confirmar venta'), findsNothing);
    expect(f.writes, 0);
    f.api.close();
  });
  testWidgets(
    'usa el usuario actual al confirmar y el total devuelto por el servicio',
    (tester) async {
      screen(tester, 1440);
      final f = SaleFixture();
      await open(tester, f, userId: 42);
      await add(tester, 8);
      await review(tester);
      f.products[0]['precio'] = 21.49;
      await open(tester, f, userId: 77);
      await tapVisible(tester, find.text('Confirmar venta'));
      await tester.pumpAndSettle();
      expect(f.payload!['idUsuario'], 77);
      expect(f.writes, 1);
      expect(f.savedCallbacks, 1);
      expect(find.text('Venta #70 registrada'), findsOneWidget);
      expect(find.text(r'Total: $ 21,49'), findsOneWidget);
      expect(f.products[0]['cantidadDisponible'], 9);
      f.api.close();
    },
  );
  testWidgets(
    'durante el envío bloquea cambios y después permite otra venta vacía',
    (tester) async {
      screen(tester, 390);
      final f = SaleFixture()..pending = Completer<void>();
      await open(tester, f, userId: 42);
      await add(tester, 8);
      await review(tester);
      await tapVisible(tester, find.text('Confirmar venta'));
      await tester.pump();
      expect(f.busy, true);
      expect(f.writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardando…'),
            )
            .onPressed,
        isNull,
      );
      f.pending!.complete();
      await tester.pumpAndSettle();
      expect(f.busy, false);
      await tapVisible(tester, find.text('Registrar otra venta'));
      await tester.pumpAndSettle();
      expect(find.text('Todavía no agregaste productos.'), findsOneWidget);
      expect(f.writes, 1);
      f.api.close();
    },
  );
  for (final status in [403, 422, 404, 409]) {
    testWidgets('error $status conserva el borrador y no afirma éxito', (
      tester,
    ) async {
      screen(tester, 390);
      final f = SaleFixture()..status = status;
      await open(tester, f, userId: 42);
      await add(tester, 8);
      await review(tester);
      await tapVisible(tester, find.text('Confirmar venta'));
      await tester.pumpAndSettle();
      expect(find.textContaining('detalle privado'), findsNothing);
      expect(find.text('Venta #70 registrada'), findsNothing);
      await tapVisible(
        tester,
        find.text(
          status == 403 || status == 422 ? 'Corregir' : 'Actualizar productos',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sale-line-8')), findsOneWidget);
      expect(f.writes, 1);
      expect(f.products[0]['cantidadDisponible'], 10);
      f.api.close();
    });
  }
  for (final mode in ['network', '500', 'malformed']) {
    testWidgets(
      'respuesta incierta $mode impide reenviar y ofrece consultar movimientos',
      (tester) async {
        screen(tester, 390);
        final f = SaleFixture()
          ..offline = mode == 'network'
          ..malformed = mode == 'malformed'
          ..status = mode == '500' ? 500 : 200;
        await open(tester, f, userId: 42);
        await add(tester, 8);
        await review(tester);
        await tapVisible(tester, find.text('Confirmar venta'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar venta'), findsNothing);
        expect(find.text('Corregir'), findsNothing);
        await tapVisible(tester, find.text('Ver movimientos'));
        expect(f.movementsCallbacks, 1);
        expect(f.writes, 1);
        f.api.close();
      },
    );
  }
  for (final width in [1440.0, 320.0]) {
    testWidgets('Ventas se abre con la navegación de la app a $width px', (
      tester,
    ) async {
      screen(tester, width);
      final f = SaleFixture();
      await tester.pumpWidget(StockiaApp(api: f.api));
      await tester.pumpAndSettle();
      if (width < 1000) {
        await tapVisible(tester, find.byTooltip('Menú de inventario'));
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.byKey(const Key('nav-new-sale')));
      await tester.pumpAndSettle();
      expect(find.byType(NewSaleScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.writes, 0);
      if (width >= 1000) {
        expect(find.byKey(const Key('nav-inventory')), findsOneWidget);
      }
    });
  }
}
