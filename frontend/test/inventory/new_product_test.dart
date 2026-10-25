import '../helpers/tap_visible.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/new_product.dart';
import 'package:stockia/screens/new_product_form.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('product-name')),
    '  Producto nuevo  ',
  );
  await tester.ensureVisible(find.byKey(const Key('product-price')));
  await tester.enterText(find.byKey(const Key('product-price')), '18.500,50');
  await tester.ensureVisible(find.byKey(const Key('product-minimum')));
  await tester.enterText(find.byKey(const Key('product-minimum')), '5');
  await tester.ensureVisible(find.byKey(const Key('product-initial')));
  await tester.enterText(find.byKey(const Key('product-initial')), '12');
  await tapVisible(tester, find.text('Revisar datos'));
  await tester.pumpAndSettle();
}

void size(WidgetTester tester, double width, {double height = 1000}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'interpreta precio argentino, rechaza importes inválidos y stock negativo',
    () {
      expect(parsePrice('18.500,50'), 18500.5);
      expect(parsePrice('18500.50'), 18500.5);
      for (final invalid in ['0', '-1', 'NaN', '1,2,3', '12.34,50', '1e400']) {
        expect(parsePrice(invalid), isNull);
      }
      expect(parseStock('0'), 0);
      expect(parseStock('-2'), isNull);
      expect(parseStock('2.5'), isNull);
    },
  );
  test('envía el contrato del backend sin código manual ni textos opcionales vacíos', () async {
    final client = InventoryApi(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/productos/');
        expect(request.headers['content-type'], contains('application/json'));
        expect(jsonDecode(request.body), {
          'nombre': 'Producto nuevo',
          'precio': 10.5,
          'stockMinimo': 0,
          'stockInicial': 0,
          'descripcion': null,
          'categoria': null,
        });
        return jsonResponse({'idProducto': 99});
      }),
    );
    addTearDown(client.close);
    expect(
      await client.createProduct(
        const NewProduct(
          name: ' Producto nuevo ',
          price: 10.5,
          minimum: 0,
          initial: 0,
          category: ' ',
        ),
      ),
      99,
    );
  });
  testWidgets('valida antes de revisar y no envía al cancelar', (tester) async {
    size(tester, 1100);
    var posts = 0;
    final client = InventoryApi(
      client: MockClient((request) async {
        if (request.method == 'POST') posts++;
        return jsonResponse({'productos': []});
      }),
    );
    await tester.pumpWidget(StockiaApp(api: client));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Nuevo producto'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Revisar datos'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar registro'), findsNothing);
    expect(posts, 0);
    await tapVisible(tester, find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(NewProductForm), findsNothing);
    expect(posts, 0);
  });
  testWidgets(
    'revisa, edita y confirma una sola vez; vuelve al inventario actualizado',
    (tester) async {
      size(tester, 1440);
      var posts = 0;
      var saved = false;
      final save = Completer<http.Response>();
      final client = InventoryApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            final result = await save.future;
            saved = true;
            return result;
          }
          final row = {
            'idProducto': 99,
            'nombre': 'Producto nuevo',
            'categoria': null,
            'descripcion': null,
            'precio': 18500.5,
            'stockMinimo': 5,
            'cantidadDisponible': 12,
          };
          return jsonResponse({
            'productos': saved ? [row] : [],
          });
        }),
      );
      await tester.pumpWidget(StockiaApp(api: client));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Nuevo producto'));
      await tester.pumpAndSettle();
      await fill(tester);
      expect(posts, 0);
      expect(find.text(r'$ 18.500,50'), findsOneWidget);
      await tapVisible(tester, find.text('Editar datos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-name')))
            .controller!
            .text,
        '  Producto nuevo  ',
      );
      await tapVisible(tester, find.text('Revisar datos'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Confirmar registro'));
      await tester.pump();
      expect(posts, 1);
      expect(find.text('Guardando…'), findsOneWidget);
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(cancel.onPressed, isNull);
      save.complete(jsonResponse({'idProducto': 99}));
      await tester.pumpAndSettle();
      expect(find.byType(NewProductForm), findsNothing);
      expect(find.text('Producto nuevo'), findsOneWidget);
      expect(find.text('Producto registrado con código 99.'), findsOneWidget);
      expect(posts, 1);
    },
  );
  testWidgets(
    'mantiene datos al rechazar el servidor y oculta sus errores internos',
    (tester) async {
      size(tester, 1100);
      final client = InventoryApi(
        client: MockClient(
          (request) async => request.method == 'POST'
              ? jsonResponse({'detail': 'SQL password secreto'}, 422)
              : jsonResponse({'productos': []}),
        ),
      );
      await tester.pumpWidget(StockiaApp(api: client));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Nuevo producto'));
      await tester.pumpAndSettle();
      await fill(tester);
      await tapVisible(tester, find.text('Confirmar registro'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SQL password'), findsNothing);
      expect(find.text('Producto nuevo'), findsOneWidget);
      expect(find.text('Confirmar registro'), findsOneWidget);
      await tapVisible(tester, find.text('Editar datos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-price')))
            .controller!
            .text,
        '18.500,50',
      );
    },
  );
  testWidgets(
    'ante una respuesta incierta obliga a revisar el inventario antes de repetir',
    (tester) async {
      size(tester, 1100);
      var posts = 0;
      final client = InventoryApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            throw http.ClientException('sin conexión');
          }
          return jsonResponse({'productos': []});
        }),
      );
      await tester.pumpWidget(StockiaApp(api: client));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Nuevo producto'));
      await tester.pumpAndSettle();
      await fill(tester);
      await tapVisible(tester, find.text('Confirmar registro'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar registro'), findsNothing);
      await tapVisible(tester, find.text('Volver al inventario'));
      await tester.pumpAndSettle();
      expect(find.byType(NewProductForm), findsNothing);
      expect(posts, 1);
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets('formulario y revisión en celular a $width px', (tester) async {
      size(tester, width, height: 844);
      final client = InventoryApi(
        client: MockClient((_) async => jsonResponse({'productos': []})),
      );
      await tester.pumpWidget(StockiaApp(api: client));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Nuevo producto'));
      await tester.pumpAndSettle();
      await fill(tester);
      expect(find.text('Revisar producto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
