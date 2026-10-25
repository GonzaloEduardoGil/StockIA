import '../helpers/tap_visible.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/widgets/stock_adjustment_dialog.dart';

class Fixture {
  int writes = 0;
  int status = 200;
  bool offline = false;
  bool malformed = false;
  int concurrentQuantity = 0;
  Completer<void>? pending;
  final data = <String, dynamic>{
    'idProducto': 8,
    'nombre': 'Mouse de prueba',
    'categoria': 'Periféricos',
    'precio': 18000,
    'descripcion': 'Existente',
    'stockMinimo': 30,
    'cantidadDisponible': 33,
  };
  final movements = <Map<String, dynamic>>[];
  late final api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method != 'GET') {
        writes++;
        expect(request.method, 'POST');
        expect(request.url.path, '/stock/ajustes/8');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'cantidad', 'motivo'});
        expect(body['cantidad'], isA<int>());
        expect((body['motivo'] as String).trim(), isNotEmpty);
        if (pending != null) await pending!.future;
        if (offline) throw http.ClientException('sin conexión');
        if (status != 200) {
          return jsonResponse({'detail': 'detalle privado'}, status);
        }
        final previous = data['cantidadDisponible'] + concurrentQuantity;
        data['cantidadDisponible'] = previous + body['cantidad'];
        movements.add(body);
        if (malformed) return jsonResponse({});
        return jsonResponse({
          'idProducto': 8,
          'cantidadAnterior': previous,
          'cantidadAjuste': body['cantidad'],
          'cantidadDisponible': data['cantidadDisponible'],
        });
      }
      return switch (request.url.path) {
        '/stock/' => jsonResponse({
          'productos': [data],
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

http.Response jsonResponse(Object data, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
void size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(StockiaApp(api: f.api));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Mouse de prueba'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Registrar ajuste').last);
  await tapVisible(tester, find.text('Registrar ajuste').last);
  await tester.pumpAndSettle();
}

Future<void> chooseReason(WidgetTester tester, String reason) async {
  final selector = find.descendant(
    of: find.byType(StockAdjustmentDialog),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(selector);
  await tapVisible(tester, selector);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text(reason).last);
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester, String quantity) async {
  await tester.enterText(
    find.byKey(const Key('stock-adjustment-quantity')),
    quantity,
  );
  await tapVisible(tester, find.text('Revisar ajuste'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1440.0, 320.0]) {
    testWidgets(
      'muestra el stock resultante al escribir y cambiar la operación a $width px',
      (tester) async {
        size(tester, width);
        final f = Fixture();
        await open(tester, f);
        final quantity = find.byKey(const Key('stock-adjustment-quantity'));
        expect(find.text('Stock resultante: —'), findsOneWidget);
        await tester.enterText(quantity, '5');
        await tester.pump();
        expect(find.text('Stock resultante: 28 unidades'), findsOneWidget);
        await tapVisible(tester, find.text('Sumar'));
        await tester.pump();
        expect(find.text('Stock resultante: 38 unidades'), findsOneWidget);
        await tapVisible(tester, find.text('Restar'));
        await tester.enterText(quantity, '33');
        await tester.pump();
        expect(find.text('Stock resultante: 0 unidades'), findsOneWidget);
        await tester.enterText(quantity, '34');
        await tester.pump();
        expect(find.text('Stock insuficiente'), findsOneWidget);
        await tester.enterText(quantity, '');
        await tester.pump();
        expect(find.text('Stock resultante: —'), findsOneWidget);
        expect(f.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'exige cantidad positiva, motivo y stock suficiente antes de revisar',
    (tester) async {
      size(tester, 1440);
      final f = Fixture();
      await open(tester, f);
      for (final text in ['', '0', '-1', '1.5', 'abc', '34', '2147483648']) {
        await review(tester, text);
        expect(find.text('Confirmar ajuste'), findsNothing);
        expect(f.writes, 0);
      }
      await review(tester, '5');
      expect(find.text('Seleccioná un motivo.'), findsOneWidget);
      await chooseReason(tester, 'Pérdida');
      await review(tester, '5');
      expect(find.text('Ajuste: −5 unidades'), findsOneWidget);
      expect(find.text('Stock resultante: 28 unidades'), findsOneWidget);
      expect(f.writes, 0);
      await tapVisible(tester, find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(f.writes, 0);
      expect(f.movements, isEmpty);
      expect(f.data['cantidadDisponible'], 33);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('descuenta una pérdida y actualiza estado a $width px', (
      tester,
    ) async {
      size(tester, width);
      final f = Fixture();
      await open(tester, f);
      await chooseReason(tester, 'Pérdida');
      await review(tester, '5');
      await tapVisible(tester, find.text('Confirmar ajuste'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.data['cantidadDisponible'], 28);
      expect(f.data['stockMinimo'], 30);
      expect(f.movements, [
        {'cantidad': -5, 'motivo': 'Pérdida'},
      ]);
      expect(
        find.text('Ajuste registrado. Stock actualizado.'),
        findsOneWidget,
      );
      expect(find.text('Bajo'), findsWidgets);
      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('permite corregir y sumar, con motivo Otro obligatorio', (
    tester,
  ) async {
    size(tester, 390);
    final f = Fixture();
    await open(tester, f);
    await chooseReason(tester, 'Pérdida');
    await review(tester, '5');
    await tapVisible(tester, find.text('Corregir'));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    await tapVisible(tester, find.text('Sumar'));
    await tester.pumpAndSettle();
    await review(tester, '5');
    expect(find.text('Seleccioná un motivo.'), findsOneWidget);
    await chooseReason(tester, 'Otro');
    await review(tester, '5');
    expect(find.text('Ingresá el motivo.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('stock-adjustment-other')),
      '  Corrección de conteo  ',
    );
    await tapVisible(tester, find.text('Revisar ajuste'));
    await tester.pumpAndSettle();
    expect(find.text('Ajuste: +5 unidades'), findsOneWidget);
    expect(find.text('Motivo: Corrección de conteo'), findsOneWidget);
    await tapVisible(tester, find.text('Confirmar ajuste'));
    await tester.pumpAndSettle();
    expect(f.movements, [
      {'cantidad': 5, 'motivo': 'Corrección de conteo'},
    ]);
    expect(f.data['cantidadDisponible'], 38);
  });
  testWidgets('admite llegar a cero y evita reenvíos mientras guarda', (
    tester,
  ) async {
    size(tester, 1440);
    final f = Fixture()..pending = Completer<void>();
    await open(tester, f);
    await chooseReason(tester, 'Rotura');
    await review(tester, '33');
    await tapVisible(tester, find.text('Confirmar ajuste'));
    await tester.pump();
    expect(f.writes, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardando…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    f.pending!.complete();
    await tester.pumpAndSettle();
    expect(f.writes, 1);
    expect(f.data['cantidadDisponible'], 0);
  });
  testWidgets('tolera otro movimiento concurrente al confirmar el ajuste', (
    tester,
  ) async {
    size(tester, 1440);
    final f = Fixture()..concurrentQuantity = 5;
    await open(tester, f);
    await chooseReason(tester, 'Diferencia de inventario');
    await review(tester, '3');
    await tapVisible(tester, find.text('Confirmar ajuste'));
    await tester.pumpAndSettle();
    expect(f.data['cantidadDisponible'], 35);
    expect(find.text('Ajuste registrado. Stock actualizado.'), findsOneWidget);
  });
  for (final status in [404, 409, 500]) {
    testWidgets('error $status requiere actualizar sin afirmar éxito', (
      tester,
    ) async {
      size(tester, 390);
      final f = Fixture()..status = status;
      await open(tester, f);
      await chooseReason(tester, 'Vencimiento');
      await review(tester, '3');
      await tapVisible(tester, find.text('Confirmar ajuste'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar ajuste'), findsNothing);
      expect(find.textContaining('detalle privado'), findsNothing);
      await tapVisible(tester, find.text('Actualizar inventario').last);
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.movements, isEmpty);
      expect(f.data['cantidadDisponible'], 33);
    });
  }
  for (final malformed in [false, true]) {
    testWidgets(
      'respuesta incierta (malformada: $malformed) impide duplicar ajustes',
      (tester) async {
        size(tester, 390);
        final f = Fixture()
          ..offline = !malformed
          ..malformed = malformed;
        await open(tester, f);
        await chooseReason(tester, 'Pérdida');
        await review(tester, '3');
        await tapVisible(tester, find.text('Confirmar ajuste'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar ajuste'), findsNothing);
        await tapVisible(tester, find.text('Actualizar inventario').last);
        await tester.pumpAndSettle();
        expect(f.writes, 1);
        expect(
          find.text('Revisá los datos actuales del producto en el inventario.'),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets('rechazo 422 conserva cantidad y motivo para corregir', (
    tester,
  ) async {
    size(tester, 390);
    final f = Fixture()..status = 422;
    await open(tester, f);
    await chooseReason(tester, 'Rotura');
    await review(tester, '3');
    await tapVisible(tester, find.text('Confirmar ajuste'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Corregir'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Rotura'), findsOneWidget);
    expect(f.writes, 1);
    expect(f.data['cantidadDisponible'], 33);
  });
}
