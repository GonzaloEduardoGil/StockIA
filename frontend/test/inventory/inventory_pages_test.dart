import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockia/app.dart';
import 'package:stockia/models/inventory_action.dart';
import 'package:stockia/screens/inventory_operation_page.dart';
import 'package:stockia/widgets/product_details.dart';

import 'stock_adjustment_test.dart' as data;
import '../helpers/tap_visible.dart';

Future<void> navigate(
  WidgetTester tester,
  InventoryAction action,
  double width,
) async {
  if (width < 1000) {
    await tapVisible(tester, find.byTooltip('Menú de inventario'));
    await tester.pumpAndSettle();
  }
  await tapVisible(tester, find.byKey(ValueKey('nav-${action.name}')));
  await tester.pumpAndSettle();
}

Future<void> selectProduct(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const Key('operation-product-search')),
    query,
  );
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const ValueKey('select-product-8')));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1440.0, 390.0, 320.0]) {
    testWidgets(
      'todas las acciones del menú muestran buscador y formulario en página a $width px',
      (tester) async {
        data.size(tester, width);
        final fixture = data.Fixture();
        await tester.pumpWidget(StockiaApp(api: fixture.api));
        await tester.pumpAndSettle();
        for (final action in InventoryAction.values) {
          await navigate(tester, action, width);
          expect(find.byType(InventoryOperationPage), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.text('Seleccioná un producto para continuar.'),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const Key('operation-product-search')),
            'inexistente',
          );
          await tester.pumpAndSettle();
          expect(find.text('No se encontraron productos.'), findsOneWidget);
          await selectProduct(
            tester,
            action == InventoryAction.edit ? '8' : 'mouse',
          );
          expect(find.text('Código: 8'), findsOneWidget);
          expect(find.text('Stock: 33'), findsOneWidget);
          expect(find.text('Mínimo: 30'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          await tapVisible(tester, find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(find.byType(InventoryOperationPage), findsNothing);
          expect(fixture.writes, 0);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  for (final width in [1440.0, 320.0]) {
    testWidgets(
      'Ver detalle y botón de baja visible; acceso con producto seleccionado a $width px',
      (tester) async {
        data.size(tester, width);
        final fixture = data.Fixture();
        await tester.pumpWidget(StockiaApp(api: fixture.api));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Ver detalle'));
        await tester.pumpAndSettle();
        final button = find.descendant(
          of: find.byType(ProductDetails),
          matching: find.widgetWithText(OutlinedButton, 'Dar de baja'),
        );
        expect(button, findsOneWidget);
        final style = tester.widget<OutlinedButton>(button).style!;
        expect(style.side!.resolve({})!.color, const Color(0xFFB23C3C));
        await tapVisible(
          tester,
          find.descendant(
            of: find.byType(ProductDetails),
            matching: find.text('Registrar entrada'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('operation-product-search')),
          findsOneWidget,
        );
        expect(find.text('Stock: 33'), findsOneWidget);
        expect(find.byKey(const Key('stock-entry-quantity')), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'bloquea cambio de producto y menú al guardar; ofrece otra operación',
    (tester) async {
      data.size(tester, 1440);
      final fixture = data.Fixture()..pending = Completer<void>();
      await tester.pumpWidget(StockiaApp(api: fixture.api));
      await tester.pumpAndSettle();
      await navigate(tester, InventoryAction.adjustment, 1440);
      await selectProduct(tester, '8');
      await data.chooseReason(tester, 'Pérdida');
      await tester.enterText(
        find.byKey(const Key('stock-adjustment-quantity')),
        '5',
      );
      await tapVisible(tester, find.text('Revisar ajuste'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Confirmar ajuste'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('operation-product-search')),
            )
            .enabled,
        false,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('nav-entry')))
            .enabled,
        false,
      );
      expect(fixture.writes, 1);
      fixture.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InventoryOperationPage), findsNothing);
      expect(
        find.text('Ajuste registrado. Stock actualizado.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Otra operación'));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryOperationPage), findsOneWidget);
      expect(
        find.text('Seleccioná un producto para continuar.'),
        findsOneWidget,
      );
      expect(fixture.writes, 1);
    },
  );
}
