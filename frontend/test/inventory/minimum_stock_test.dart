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
import 'package:stockia/widgets/minimum_stock_dialog.dart';

class Fixture {
  int writes = 0;
  int status = 200;
  bool offline = false;
  bool malformed = false;
  Completer<void>? pending;
  final data = <String, dynamic>{
    'idProducto': 8,
    'nombre': 'Mouse de prueba',
    'categoria': 'Periféricos',
    'precio': 18000,
    'descripcion': 'Existente',
    'stockMinimo': 7,
    'cantidadDisponible': 33,
  };
  Product get product => Product.fromApi(data, data);
  late final api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      if (request.method != 'GET') {
        writes++;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/productos/8/stock-minimo');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['stockMinimo']);
        expect(body['stockMinimo'], isA<int>());
        if (pending != null) await pending!.future;
        if (offline) throw http.ClientException('sin conexión');
        if (status != 200) {
          return jsonResponse({'detail': 'detalle privado'}, status);
        }
        data['stockMinimo'] = body['stockMinimo'];
        if (malformed) return jsonResponse({});
        return jsonResponse({
          ...data,
          'estadoStock': data['cantidadDisponible'] <= data['stockMinimo']
              ? 'BAJO'
              : 'NORMAL',
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
  tester.view.physicalSize = Size(width, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(StockiaApp(api: f.api));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Mouse de prueba'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Configurar stock mínimo').last);
  await tapVisible(tester, find.text('Configurar stock mínimo').last);
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('minimum-stock-input')), value);
  await tapVisible(tester, find.text('Revisar cambio'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'valida enteros y cambios, permite corregir y cancelar sin escribir',
    (tester) async {
      size(tester, 1440);
      final f = Fixture();
      await open(tester, f);
      for (final text in ['', '-1', '1.5', 'abc', '2147483648', '7']) {
        await review(tester, text);
        expect(find.text('Revisar stock mínimo'), findsNothing);
        expect(f.writes, 0);
      }
      await review(tester, '40');
      expect(find.text('Nuevo mínimo: 40 unidades'), findsOneWidget);
      expect(f.writes, 0);
      await tapVisible(tester, find.text('Corregir'));
      await tester.pumpAndSettle();
      expect(find.text('40'), findsOneWidget);
      await review(tester, '0');
      expect(find.text('Nuevo mínimo: 0 unidades'), findsOneWidget);
      await tapVisible(tester, find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(f.writes, 0);
      expect(f.data['stockMinimo'], 7);
      expect(find.byType(MinimumStockDialog), findsNothing);
    },
  );
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'confirma y actualiza mínimo y estado a $width px sin cambiar cantidad',
      (tester) async {
        size(tester, width);
        final f = Fixture();
        await open(tester, f);
        await review(tester, '33');
        await tapVisible(tester, find.text('Confirmar cambio'));
        await tester.pumpAndSettle();
        expect(f.writes, 1);
        expect(f.data['stockMinimo'], 33);
        expect(f.data['cantidadDisponible'], 33);
        expect(
          find.text(
            'Stock mínimo actualizado. Se reevaluó el estado del stock.',
          ),
          findsOneWidget,
        );
        expect(find.text('Bajo'), findsWidgets);
        expect(find.byType(MinimumStockDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('bloquea envíos repetidos mientras se guarda', (tester) async {
    size(tester, 1440);
    final f = Fixture()..pending = Completer<void>();
    await open(tester, f);
    await review(tester, '0');
    await tapVisible(tester, find.text('Confirmar cambio'));
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
    expect(f.data['stockMinimo'], 0);
    expect(find.text('Normal'), findsWidgets);
  });
  for (final status in [404, 409, 500]) {
    testWidgets('error $status obliga a actualizar sin afirmar éxito', (
      tester,
    ) async {
      size(tester, 390);
      final f = Fixture()..status = status;
      await open(tester, f);
      await review(tester, '40');
      await tapVisible(tester, find.text('Confirmar cambio'));
      await tester.pumpAndSettle();
      expect(find.text('Actualizar inventario'), findsWidgets);
      expect(find.text('Confirmar cambio'), findsNothing);
      expect(find.textContaining('detalle privado'), findsNothing);
      await tapVisible(tester, find.text('Actualizar inventario').last);
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.data['stockMinimo'], 7);
    });
  }
  for (final malformed in [false, true]) {
    testWidgets(
      'respuesta incierta (malformada: $malformed) no permite reenvío',
      (tester) async {
        size(tester, 390);
        final f = Fixture()
          ..offline = !malformed
          ..malformed = malformed;
        await open(tester, f);
        await review(tester, '40');
        await tapVisible(tester, find.text('Confirmar cambio'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar cambio'), findsNothing);
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
  testWidgets('rechazo de validación conserva el valor para corregir', (
    tester,
  ) async {
    size(tester, 390);
    final f = Fixture()..status = 422;
    await open(tester, f);
    await review(tester, '40');
    await tapVisible(tester, find.text('Confirmar cambio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('El servicio rechazó el valor'), findsOneWidget);
    await tapVisible(tester, find.text('Corregir'));
    await tester.pumpAndSettle();
    expect(find.text('40'), findsOneWidget);
    expect(f.writes, 1);
    expect(f.data['stockMinimo'], 7);
  });
}
