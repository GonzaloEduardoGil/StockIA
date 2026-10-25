import '../helpers/tap_visible.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/stock_movement.dart';
import 'package:stockia/screens/movements_screen.dart';

Map<String, dynamic> movement(
  int id,
  String date,
  String type,
  int quantity,
  int product,
  String name,
  String? reason,
) => {
  'idMovimiento': id,
  'fecha': date,
  'tipoMovimiento': type,
  'cantidad': quantity,
  'idProducto': product,
  'nombreProducto': name,
  'motivo': reason,
};

class Fixture {
  bool fail = false;
  bool detailFail = false;
  bool malformed = false;
  int calls = 0;
  final rows = [
    movement(
      1,
      '2026-10-20',
      'Entrada',
      10,
      8,
      'Mouse',
      'Recepción de mercadería',
    ),
    movement(2, '2026-10-21', 'Ajuste', -3, 8, 'Mouse', 'Pérdida'),
    movement(3, '2026-10-22', 'Venta', 2, 9, 'Teclado', 'Venta #12'),
    movement(4, '2026-10-23', 'Ajuste', -1, 9, 'Teclado', 'perdida'),
    movement(5, '2026-10-24', 'Entrada', 5, 4, 'Producto inactivo', null),
    movement(6, '2026-10-24', 'Ajuste', 4, 8, 'Mouse', 'Corrección de conteo'),
  ];
  late final api = InventoryApi(
    baseUrl: 'http://test.local',
    client: MockClient((request) async {
      expect(request.method, 'GET');
      calls++;
      if (fail) return response({'detail': 'error privado'}, 500);
      if (request.url.path == '/movimientos/') {
        return response(
          malformed
              ? {'otro': []}
              : {'movimientos': rows, 'cantidad': rows.length},
        );
      }
      if (request.url.path.startsWith('/movimientos/')) {
        if (detailFail) return response({'detail': 'privado'}, 404);
        final id = int.parse(request.url.path.split('/').last);
        return response(rows.firstWhere((m) => m['idMovimiento'] == id));
      }
      if (request.url.path == '/stock/') return response({'productos': []});
      if (request.url.path == '/productos/') return response({'productos': []});
      return response({}, 404);
    }),
  );
}

http.Response response(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(MaterialApp(home: MovementsScreen(api: f.api)));
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String label, String option) async {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is InputDecorator && widget.decoration.labelText == label,
  );
  await tester.ensureVisible(field);
  await tapVisible(tester, field);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  test('consulta ordenada y ventas con descuento aunque el backend guarde cantidad positiva', () async {
    final f = Fixture();
    final data = await f.api.loadMovements();
    expect(data.map((m) => m.id), [6, 5, 4, 3, 2, 1]);
    expect(data.singleWhere((m) => m.id == 3).quantityLabel, '−2 unidades');
    expect(data.singleWhere((m) => m.id == 5).reasonLabel, 'Sin motivo');
    expect((await f.api.loadMovement(2)).reason, 'Pérdida');
    f.api.close();
  });
  test('fechas estrictas e inclusivas con formato local', () {
    expect(parseMovementDate('31/02/2026'), isNull);
    expect(parseMovementDate('2026-10-24'), isNull);
    expect(parseMovementDate('24/10/2026'), DateTime(2026, 10, 24));
  });
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets('listado y detalle se adaptan a $width px', (tester) async {
      size(tester, width);
      final f = Fixture();
      await open(tester, f);
      expect(find.text('6 de 6 movimientos'), findsOneWidget);
      final row = find.byKey(const ValueKey('movement-2'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tapVisible(tester, row);
      await tester.pumpAndSettle();
      expect(find.text('Movimiento #2'), findsOneWidget);
      expect(find.text('Motivo: Pérdida'), findsOneWidget);
      expect(find.text('Cantidad: −3 unidades'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      f.api.close();
    });
  }
  testWidgets(
    'combina motivo normalizado, producto, tipo y fecha sin escribir ni consultar de nuevo',
    (tester) async {
      size(tester, 1440);
      final f = Fixture();
      await open(tester, f);
      await select(tester, 'Motivo', 'Pérdida');
      expect(find.text('2 de 6 movimientos'), findsOneWidget);
      await select(tester, 'Producto', 'Mouse (#8)');
      await select(tester, 'Tipo de movimiento', 'Ajuste');
      await tester.enterText(
        find.byKey(const Key('movement-date-from')),
        '21/10/2026',
      );
      await tester.enterText(
        find.byKey(const Key('movement-date-to')),
        '21/10/2026',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 de 6 movimientos'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-4')), findsNothing);
      expect(f.calls, 1);
      await tapVisible(tester, find.text('Limpiar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('6 de 6 movimientos'), findsOneWidget);
      f.api.close();
    },
  );
  testWidgets('filtra Sin motivo y busca motivos libres sin tildes', (
    tester,
  ) async {
    size(tester, 390);
    final f = Fixture();
    await open(tester, f);
    await select(tester, 'Motivo', 'Sin motivo');
    expect(find.text('1 de 6 movimientos'), findsOneWidget);
    expect(find.byKey(const ValueKey('movement-5')), findsOneWidget);
    await tester.ensureVisible(find.text('Limpiar filtros'));
    await tapVisible(tester, find.text('Limpiar filtros'));
    await tester.enterText(
      find.byKey(const Key('movement-reason-search')),
      'correccion',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 6 movimientos'), findsOneWidget);
    expect(find.byKey(const ValueKey('movement-6')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('movement-reason-search')),
      'inexistente',
    );
    await tester.pumpAndSettle();
    expect(find.text('No hay movimientos con estos filtros.'), findsOneWidget);
    f.api.close();
  });
  testWidgets(
    'rechaza fechas inválidas o invertidas sin mostrar resultados engañosos',
    (tester) async {
      size(tester, 1440);
      final f = Fixture();
      await open(tester, f);
      await tester.enterText(
        find.byKey(const Key('movement-date-from')),
        '31/02/2026',
      );
      await tester.pumpAndSettle();
      expect(find.text('Usá fechas válidas: dd/mm/aaaa.'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-1')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('movement-date-from')),
        '24/10/2026',
      );
      await tester.enterText(
        find.byKey(const Key('movement-date-to')),
        '20/10/2026',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('La fecha desde'), findsOneWidget);
      f.api.close();
    },
  );
  testWidgets(
    'error del listado y reintento sin exponer detalles del servidor',
    (tester) async {
      size(tester, 390);
      final f = Fixture()..fail = true;
      await open(tester, f);
      expect(find.textContaining('error privado'), findsNothing);
      await tester.ensureVisible(find.text('Reintentar'));
      f.fail = false;
      await tapVisible(tester, find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('6 de 6 movimientos'), findsOneWidget);
      f.api.close();
    },
  );
  testWidgets('detalle fallido permite reintentar y conserva los filtros', (
    tester,
  ) async {
    size(tester, 1440);
    final f = Fixture()..detailFail = true;
    await open(tester, f);
    await select(tester, 'Tipo de movimiento', 'Venta');
    await tapVisible(tester, find.byKey(const ValueKey('movement-3')));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar detalle'), findsOneWidget);
    f.detailFail = false;
    await tapVisible(tester, find.text('Reintentar detalle'));
    await tester.pumpAndSettle();
    expect(find.text('Cantidad: −2 unidades'), findsOneWidget);
    await tapVisible(tester, find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 6 movimientos'), findsOneWidget);
    f.api.close();
  });
  testWidgets('historial vacío y respuestas inválidas se distinguen', (
    tester,
  ) async {
    size(tester, 1440);
    final f = Fixture()..rows.clear();
    await open(tester, f);
    expect(find.text('Todavía no hay movimientos.'), findsOneWidget);
    f.malformed = true;
    await tapVisible(tester, find.byTooltip('Actualizar movimientos'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo interpretar el historial de movimientos.'),
      findsOneWidget,
    );
    f.api.close();
  });
  for (final width in [1440.0, 320.0]) {
    testWidgets('acceso desde inventario y regreso a $width px', (
      tester,
    ) async {
      size(tester, width);
      final f = Fixture();
      await tester.pumpWidget(StockiaApp(api: f.api));
      await tester.pumpAndSettle();
      if (width >= 1000) {
        await tapVisible(tester, find.text('Movimientos'));
      } else {
        await tapVisible(tester, find.byTooltip('Menú de inventario'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Movimientos'));
        await tapVisible(tester, find.text('Movimientos'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MovementsScreen), findsOneWidget);
      if (width >= 1000) {
        expect(find.byKey(const ValueKey('nav-entry')), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Movimientos'))
              .selected,
          true,
        );
        await tapVisible(tester, find.byKey(const Key('nav-inventory')));
      } else {
        await tapVisible(tester, find.byTooltip('Menú de inventario'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(const Key('nav-inventory')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MovementsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
