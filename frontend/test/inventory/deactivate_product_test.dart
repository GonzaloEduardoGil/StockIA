import '../helpers/tap_visible.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/product.dart';
import 'package:stockia/widgets/deactivate_product_dialog.dart';

class Fixture {
  bool active = true;
  bool offline = false;
  int writes = 0;
  int status = 200;
  Completer<void>? pending;
  final Map<String, dynamic> data = {
    'idProducto': 8,
    'nombre': 'Mouse de prueba',
    'categoria': 'Periféricos',
    'precio': 18000,
    'descripcion': 'Producto existente',
    'stockMinimo': 7,
    'cantidadDisponible': 33,
  };
  Product get product => Product.fromApi(data, data);
  late final InventoryApi api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method != 'GET') {
        writes++;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/productos/8/baja');
        expect(request.body, isEmpty);
        if (pending != null) await pending!.future;
        if (offline) throw http.ClientException('sin conexión');
        if (status != 200) {
          return jsonResponse({
            'detail': 'detalle privado del servidor',
          }, status);
        }
        active = false;
        return jsonResponse({
          'idProducto': 8,
          'nombre': data['nombre'],
          'activo': false,
        });
      }
      return switch (request.url.path) {
        '/stock/' => jsonResponse({
          'productos': active ? [data] : [],
        }),
        '/productos/' => jsonResponse({
          'productos': [data],
        }),
        '/productos/8' => jsonResponse(data),
        _ => jsonResponse({}, 404),
      };
    }),
  );
}

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
void size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openConfirmation(WidgetTester tester, Fixture fixture) async {
  await tester.pumpWidget(StockiaApp(api: fixture.api));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Mouse de prueba'));
  await tapVisible(tester, find.text('Mouse de prueba'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Dar de baja').last);
  await tapVisible(tester, find.text('Dar de baja').last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'utiliza PATCH de baja lógica sin borrar ni enviar cambios de stock',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.api.close);
      expect(await fixture.api.deactivateProduct(fixture.product), 8);
      expect(fixture.writes, 1);
      expect(fixture.data['cantidadDisponible'], 33);
      expect(fixture.data['idProducto'], 8);
    },
  );
  testWidgets('no cambia nada antes de confirmar ni al cancelar', (
    tester,
  ) async {
    size(tester, 1440);
    final fixture = Fixture();
    await openConfirmation(tester, fixture);
    expect(
      find.textContaining('Se conservarán sus datos e historial.'),
      findsOneWidget,
    );
    expect(fixture.writes, 0);
    await tapVisible(tester, find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(fixture.writes, 0);
    expect(find.byType(DeactivateProductDialog), findsNothing);
    expect(find.text('Detalle del producto'), findsOneWidget);
  });
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'confirmar quita el producto del inventario activo a $width px',
      (tester) async {
        size(tester, width);
        final fixture = Fixture();
        await openConfirmation(tester, fixture);
        await tapVisible(tester, find.text('Confirmar baja'));
        await tester.pumpAndSettle();
        expect(fixture.writes, 1);
        expect(find.byType(DeactivateProductDialog), findsNothing);
        expect(find.text('Detalle del producto'), findsNothing);
        expect(find.text('Todavía no hay productos activos'), findsOneWidget);
        expect(
          find.text('Producto dado de baja. Se conservó su historial.'),
          findsOneWidget,
        );
        expect(fixture.data['cantidadDisponible'], 33);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('impide reenvíos y cancelación mientras se procesa', (
    tester,
  ) async {
    size(tester, 1440);
    final fixture = Fixture()..pending = Completer<void>();
    await openConfirmation(tester, fixture);
    await tapVisible(tester, find.text('Confirmar baja'));
    await tester.pump();
    expect(fixture.writes, 1);
    expect(find.text('Procesando…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Procesando…'),
          )
          .onPressed,
      isNull,
    );
    fixture.pending!.complete();
    await tester.pumpAndSettle();
    expect(fixture.writes, 1);
  });
  for (final status in [404, 409]) {
    testWidgets(
      'si no existe o ya está inactivo ($status), actualiza sin afirmar una nueva baja',
      (tester) async {
        size(tester, 1440);
        final fixture = Fixture()..status = status;
        await openConfirmation(tester, fixture);
        await tapVisible(tester, find.text('Confirmar baja'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar baja'), findsNothing);
        expect(find.textContaining('detalle privado'), findsNothing);
        await tapVisible(tester, find.text('Actualizar inventario'));
        await tester.pumpAndSettle();
        expect(find.byType(DeactivateProductDialog), findsNothing);
        expect(
          find.text('Producto dado de baja. Se conservó su historial.'),
          findsNothing,
        );
        expect(fixture.writes, 1);
      },
    );
  }
  testWidgets(
    'si se pierde la respuesta pide consultar el inventario antes de repetir',
    (tester) async {
      size(tester, 1440);
      final fixture = Fixture()..offline = true;
      await openConfirmation(tester, fixture);
      await tapVisible(tester, find.text('Confirmar baja'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar baja'), findsNothing);
      expect(
        find.textContaining('No pudimos confirmar el resultado'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Actualizar inventario'));
      await tester.pumpAndSettle();
      expect(fixture.writes, 1);
    },
  );
}
