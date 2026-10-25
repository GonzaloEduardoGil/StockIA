import '../helpers/tap_visible.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/widgets/stock_entry_dialog.dart';

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
    'stockMinimo': 35,
    'cantidadDisponible': 33,
  };
  final movements = <Map<String, dynamic>>[];
  late final api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method != 'GET') {
        writes++;
        expect(request.method, 'POST');
        expect(request.url.path, '/stock/entradas/8');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'cantidad', 'motivo'});
        expect(body['cantidad'], isA<int>());
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
          'cantidadIngresada': body['cantidad'],
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
  await tester.ensureVisible(find.text('Registrar entrada').last);
  await tapVisible(tester, find.text('Registrar entrada').last);
  await tester.pumpAndSettle();
}

Future<void> review(
  WidgetTester tester,
  String quantity, {
  String reason = '',
}) async {
  await tester.enterText(
    find.byKey(const Key('stock-entry-quantity')),
    quantity,
  );
  await tester.enterText(find.byKey(const Key('stock-entry-reason')), reason);
  await tapVisible(tester, find.text('Revisar entrada'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'valida cantidades y permite revisar, corregir y cancelar sin escribir',
    (tester) async {
      size(tester, 1440);
      final f = Fixture();
      await open(tester, f);
      for (final text in ['', '0', '-1', '1.5', 'abc', '2147483647']) {
        await review(tester, text);
        expect(find.text('Revisar entrada de stock'), findsNothing);
        expect(f.writes, 0);
      }
      await review(tester, '10', reason: 'Entrega de proveedor');
      expect(find.text('Stock estimado: 43 unidades'), findsOneWidget);
      expect(find.text('Motivo: Entrega de proveedor'), findsOneWidget);
      expect(f.writes, 0);
      await tapVisible(tester, find.text('Corregir'));
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Entrega de proveedor'), findsOneWidget);
      await tapVisible(tester, find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(f.writes, 0);
      expect(f.data['cantidadDisponible'], 33);
      expect(f.movements, isEmpty);
      expect(find.byType(StockEntryDialog), findsNothing);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('entrada confirmada actualiza cantidad y estado a $width px', (
      tester,
    ) async {
      size(tester, width);
      final f = Fixture();
      await open(tester, f);
      await review(tester, '10', reason: '  Entrega de proveedor  ');
      await tapVisible(tester, find.text('Confirmar entrada'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.data['cantidadDisponible'], 43);
      expect(f.data['stockMinimo'], 35);
      expect(f.movements, [
        {'cantidad': 10, 'motivo': 'Entrega de proveedor'},
      ]);
      expect(
        find.text('Entrada registrada: 10 unidades. Stock actualizado.'),
        findsOneWidget,
      );
      expect(find.text('Normal'), findsWidgets);
      expect(find.byType(StockEntryDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'acepta motivo vacío y cambios concurrentes, evita envíos repetidos',
    (tester) async {
      size(tester, 1440);
      final f = Fixture()
        ..pending = Completer<void>()
        ..concurrentQuantity = 5;
      await open(tester, f);
      await review(tester, '2');
      await tapVisible(tester, find.text('Confirmar entrada'));
      await tester.pump();
      expect(f.writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardando…'),
            )
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
      expect(f.data['cantidadDisponible'], 40);
      expect(f.movements, [
        {'cantidad': 2, 'motivo': null},
      ]);
      expect(
        find.text('Entrada registrada: 2 unidades. Stock actualizado.'),
        findsOneWidget,
      );
    },
  );
  for (final status in [404, 409, 500]) {
    testWidgets('error $status exige actualizar antes de repetir', (
      tester,
    ) async {
      size(tester, 390);
      final f = Fixture()..status = status;
      await open(tester, f);
      await review(tester, '10');
      await tapVisible(tester, find.text('Confirmar entrada'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar entrada'), findsNothing);
      expect(find.textContaining('detalle privado'), findsNothing);
      await tapVisible(tester, find.text('Actualizar inventario').last);
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.data['cantidadDisponible'], 33);
      expect(f.movements, isEmpty);
    });
  }
  for (final malformed in [false, true]) {
    testWidgets(
      'resultado incierto (respuesta malformada: $malformed) evita duplicar entradas',
      (tester) async {
        size(tester, 390);
        final f = Fixture()
          ..offline = !malformed
          ..malformed = malformed;
        await open(tester, f);
        await review(tester, '10');
        await tapVisible(tester, find.text('Confirmar entrada'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar entrada'), findsNothing);
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
    await review(tester, '10', reason: 'Entrega');
    await tapVisible(tester, find.text('Confirmar entrada'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El servicio rechazó los datos'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Corregir'));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Entrega'), findsOneWidget);
    expect(f.writes, 1);
    expect(f.data['cantidadDisponible'], 33);
  });
}
