import '../helpers/tap_visible.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/new_product.dart';
import 'package:stockia/models/product.dart';
import 'package:stockia/screens/new_product_form.dart';

class EditFixture {
  String name = 'Mouse original';
  String? category;
  double price = 18000;
  int writes = 0;
  int status = 200;
  Map<String, dynamic>? payload;
  Map<String, dynamic> get detail => {
    'idProducto': 8,
    'nombre': name,
    'categoria': category,
    'precio': price,
    'descripcion': null,
    'stockMinimo': 7,
  };
  Map<String, dynamic> get stock => {...detail, 'cantidadDisponible': 33};
  Product get product => Product.fromApi(stock, detail).withDetails(detail);
  late final InventoryApi api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method == 'PUT') {
        writes++;
        expect(request.url.path, '/productos/8');
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload!.keys.toSet(), {
          'nombre',
          'descripcion',
          'categoria',
          'precio',
        });
        if (status != 200) {
          return response({'detail': 'error interno no visible'}, status);
        }
        name = payload!['nombre'] as String;
        category = payload!['categoria'] as String?;
        price = (payload!['precio'] as num).toDouble();
        return response({'producto': detail});
      }
      return switch (request.url.path) {
        '/stock/' => response({
          'productos': [stock],
        }),
        '/productos/' => response({
          'productos': [detail],
        }),
        '/productos/8' => response(detail),
        _ => response({}, 404),
      };
    }),
  );
}

http.Response response(Object value, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void screen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openEdit(WidgetTester tester, EditFixture fixture) async {
  await tester.pumpWidget(StockiaApp(api: fixture.api));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Mouse original'));
  await tapVisible(tester, find.text('Mouse original'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Editar producto').last);
  await tapVisible(tester, find.text('Editar producto').last);
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('product-name')),
    'Mouse actualizado',
  );
  await tester.ensureVisible(find.byKey(const Key('product-price')));
  await tester.enterText(find.byKey(const Key('product-price')), '18.500,50');
  await tapVisible(tester, find.text('Revisar datos'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'solo actualiza los cuatro campos permitidos y conserva categoría nula',
    () async {
      final fixture = EditFixture();
      addTearDown(fixture.api.close);
      expect(fixture.product.category, 'Sin categoría');
      expect(fixture.product.rawCategory, isNull);
      expect(
        await fixture.api.updateProduct(
          fixture.product,
          const NewProduct(
            name: 'Mouse actualizado',
            price: 18500.5,
            minimum: 999,
            initial: 999,
          ),
        ),
        8,
      );
      expect(fixture.payload!['categoria'], isNull);
      expect(fixture.payload!.containsKey('stockMinimo'), false);
      expect(fixture.payload!.containsKey('stockInicial'), false);
      expect(fixture.payload!.containsKey('idProducto'), false);
    },
  );
  testWidgets(
    'carga datos actuales sin convertir Sin categoría en un dato real; cancelar no escribe',
    (tester) async {
      screen(tester, 1440);
      final fixture = EditFixture();
      await openEdit(tester, fixture);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-name')))
            .controller!
            .text,
        'Mouse original',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-category')))
            .controller!
            .text,
        '',
      );
      expect(find.byKey(const Key('product-minimum')), findsNothing);
      expect(find.byKey(const Key('product-initial')), findsNothing);
      await tapVisible(tester, find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fixture.writes, 0);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('edición completa a $width px, conservando código y stock', (
      tester,
    ) async {
      screen(tester, width);
      final fixture = EditFixture();
      await openEdit(tester, fixture);
      await review(tester);
      expect(fixture.writes, 0);
      expect(find.text('Revisar cambios'), findsOneWidget);
      expect(find.text('Stock actual (sin cambios)'), findsOneWidget);
      await tapVisible(tester, find.text('Confirmar cambios'));
      await tester.pumpAndSettle();
      expect(fixture.writes, 1);
      expect(fixture.name, 'Mouse actualizado');
      expect(find.byType(NewProductForm), findsNothing);
      expect(find.text('Producto actualizado con código 8.'), findsOneWidget);
      expect(find.text('Mouse actualizado'), findsWidgets);
      expect(tester.takeException(), isNull);
      if (width >= 1280) {
        expect(find.text('33 unidades'), findsOneWidget);
        expect(find.text('7 unidades'), findsOneWidget);
        expect(find.text('Código: 8'), findsOneWidget);
      }
    });
  }
  for (final status in [404, 409]) {
    testWidgets(
      'si el producto desaparece o está inactivo ($status), pide actualizar',
      (tester) async {
        screen(tester, 1440);
        final fixture = EditFixture()..status = status;
        await openEdit(tester, fixture);
        await review(tester);
        await tapVisible(tester, find.text('Confirmar cambios'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ya no está disponible'), findsOneWidget);
        expect(find.text('Confirmar cambios'), findsNothing);
        await tapVisible(tester, find.text('Volver al inventario'));
        await tester.pumpAndSettle();
        expect(fixture.writes, 1);
        expect(find.byType(NewProductForm), findsNothing);
      },
    );
  }
  testWidgets('un rechazo de validación conserva los datos para corregir', (
    tester,
  ) async {
    screen(tester, 1440);
    final fixture = EditFixture()..status = 422;
    await openEdit(tester, fixture);
    await review(tester);
    await tapVisible(tester, find.text('Confirmar cambios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('error interno'), findsNothing);
    await tapVisible(tester, find.text('Editar datos'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('product-name')))
          .controller!
          .text,
      'Mouse actualizado',
    );
  });
}
