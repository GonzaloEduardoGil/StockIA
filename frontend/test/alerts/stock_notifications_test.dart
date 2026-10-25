import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/screens/alerts_screen.dart';
import 'package:stockia/widgets/product_details.dart';

http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> alert(int id) => {
  'idProducto': id,
  'nombreProducto': 'Lápiz $id',
  'categoria': 'Librería',
  'cantidadDisponible': 0,
  'stockMinimo': 10,
  'fechaCreacion': null,
};

class Fixture {
  Fixture({
    this.empty = false,
    this.fail = false,
    this.many = false,
    this.pending,
  }) {
    api = InventoryApi(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        requests.add(request.url.path);
        switch (request.url.path) {
          case '/stock/':
            return json({
              'productos': [
                {
                  'idProducto': 7,
                  'nombre': 'Lápiz 7',
                  'categoria': 'Librería',
                  'cantidadDisponible': empty ? 20 : 0,
                  'stockMinimo': 10,
                },
              ],
            });
          case '/productos/':
            return json({
              'productos': [
                {'idProducto': 7, 'nombre': 'Lápiz 7', 'precio': 250},
              ],
            });
          case '/alertas/':
            if (pending != null) return pending!.future;
            if (fail) return http.Response('', 500);
            return json({
              'alertas': empty
                  ? []
                  : [for (var id = 7; id < (many ? 27 : 8); id++) alert(id)],
            });
          default:
            final id = int.parse(request.url.path.split('/').last);
            return json({
              'producto': {
                'idProducto': id,
                'nombre': 'Lápiz $id',
                'categoria': 'Librería',
                'precio': 250,
                'cantidadDisponible': 0,
                'stockMinimo': 10,
              },
              'ultimaAlerta': null,
            });
        }
      }),
    );
  }
  late InventoryApi api;
  bool empty;
  bool fail;
  bool many;
  final Completer<http.Response>? pending;
  final requests = <String>[];
}

Future<void> show(
  WidgetTester tester,
  Fixture f, {
  double width = 1280,
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(StockiaApp(api: f.api));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get bell => find.byKey(const Key('stock-alert-notification'));
Finder get menu => find.byKey(const Key('stock-notifications-menu'));

void main() {
  testWidgets(
    'abrir notificaciones conserva el detalle seleccionado en inventario',
    (tester) async {
      await show(tester, Fixture());
      await tap(tester, find.text('Ver detalle').first);
      expect(find.byType(ProductDetails), findsOneWidget);
      await tap(tester, bell);
      expect(find.byType(ProductDetails), findsOneWidget);
      await tap(tester, find.byTooltip('Cerrar alertas'));
      expect(find.byType(ProductDetails), findsOneWidget);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('campana abre desplegable sin navegar a $width px', (
      tester,
    ) async {
      final f = Fixture();
      await show(tester, f, width: width);
      await tap(tester, bell);
      expect(menu, findsOneWidget);
      expect(find.byType(AlertsScreen), findsNothing);
      expect(
        find.descendant(of: menu, matching: find.text('Lápiz 7 (#7)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('Stock: 0 · Mínimo: 10')),
        findsOneWidget,
      );
      final rect = tester.getRect(menu);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
      await tap(tester, find.byKey(const ValueKey('notification-open-7')));
      expect(menu, findsNothing);
      expect(find.byType(AlertsScreen), findsOneWidget);
      expect(find.text('Detalle de alerta'), findsOneWidget);
      expect(find.text('Stock actual: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('cierra al volver a tocar campana, con Escape y al tocar fuera', (
    tester,
  ) async {
    await show(tester, Fixture());
    await tap(tester, bell);
    await tap(tester, bell);
    expect(menu, findsNothing);
    await tap(tester, bell);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    await tap(tester, bell);
    await tester.tapAt(const Offset(450, 150));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(find.byType(AlertsScreen), findsNothing);
  });
  testWidgets('permite consultar el listado completo', (tester) async {
    await show(tester, Fixture());
    await tap(tester, bell);
    await tap(tester, find.byKey(const Key('notification-all-alerts')));
    expect(menu, findsNothing);
    expect(find.byType(AlertsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('alert-detail-7')), findsOneWidget);
    expect(find.text('Detalle de alerta'), findsNothing);
  });
  testWidgets('sin alertas y error recuperable no cambian de pantalla', (
    tester,
  ) async {
    final f = Fixture(empty: true);
    await show(tester, f);
    await tap(tester, bell);
    expect(find.text('No hay alertas de stock bajo.'), findsOneWidget);
    await tap(tester, bell);
    f.empty = false;
    f.fail = true;
    await tap(tester, bell);
    expect(
      find.descendant(of: menu, matching: find.text('Reintentar')),
      findsOneWidget,
    );
    f.fail = false;
    await tap(
      tester,
      find.descendant(of: menu, matching: find.text('Reintentar')),
    );
    expect(find.byKey(const ValueKey('notification-open-7')), findsOneWidget);
    expect(find.byType(AlertsScreen), findsNothing);
  });
  testWidgets(
    'muchas alertas se desplazan dentro del menú en pantalla pequeña',
    (tester) async {
      await show(tester, Fixture(many: true), width: 320, height: 500);
      await tap(tester, bell);
      final rect = tester.getRect(menu);
      expect(rect.bottom, lessThanOrEqualTo(500));
      await tester.drag(
        find.descendant(of: menu, matching: find.byType(SingleChildScrollView)),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-all-alerts')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('una respuesta tardía no reabre el menú que se cerró', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    await show(tester, Fixture(pending: pending));
    await tester.tap(bell);
    await tester.pump();
    await tester.tap(find.byTooltip('Cerrar alertas'));
    await tester.pump();
    pending.complete(
      json({
        'alertas': [alert(7)],
      }),
    );
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(find.byType(AlertsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'la misma alerta se puede volver a abrir después de regresar al listado',
    (tester) async {
      await show(tester, Fixture());
      await tap(tester, bell);
      await tap(tester, find.byKey(const ValueKey('notification-open-7')));
      await tap(tester, find.text('Volver a alertas'));
      expect(find.text('Detalle de alerta'), findsNothing);
      await tap(tester, bell);
      await tap(tester, find.byKey(const ValueKey('notification-open-7')));
      expect(find.text('Detalle de alerta'), findsOneWidget);
    },
  );
}
