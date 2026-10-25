import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockia/widgets/compact_calendar.dart';

import 'movements_test.dart' as data;
import 'tap_visible.dart';

Future<void> chooseDate(WidgetTester tester, String date) async {
  expect(find.byType(CompactCalendar), findsOneWidget);
  final parts = date.split('/').map(int.parse).toList();
  await tapVisible(
    tester,
    find.byKey(ValueKey('calendar-day-${parts[2]}-${parts[1]}-${parts[0]}')),
  );
  await tester.pumpAndSettle();
  expect(find.byType(CompactCalendar), findsNothing);
}

void main() {
  testWidgets(
    'permite elegir mes y año sin cerrar y contempla febrero bisiesto',
    (tester) async {
      data.size(tester, 1440);
      final f = data.Fixture();
      await data.open(tester, f);
      final field = find.byKey(const Key('movement-date-from'));
      await tester.enterText(field, '20/10/2026');
      await tapVisible(tester, find.byTooltip('Elegir fecha desde'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('calendar-year')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('2024').last);
      await tester.pumpAndSettle();
      expect(find.byType(CompactCalendar), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('calendar-month')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Febrero').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-day-2024-2-29')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-day-2024-2-30')),
        findsNothing,
      );
      await chooseDate(tester, '29/02/2024');
      expect(tester.widget<TextField>(field).controller!.text, '29/02/2024');
      f.api.close();
    },
  );
  for (final width in [1440.0, 320.0]) {
    testWidgets('calendarios en español filtran desde y hasta a $width px', (
      tester,
    ) async {
      data.size(tester, width);
      final f = data.Fixture();
      await data.open(tester, f);
      await tester.enterText(
        find.byKey(const Key('movement-date-from')),
        '20/10/2026',
      );
      await tapVisible(tester, find.byTooltip('Elegir fecha desde'));
      await tester.pumpAndSettle();
      final popup = tester.getRect(
        find.byKey(const Key('movement-date-popover')),
      );
      final field = tester.getRect(find.byKey(const Key('movement-date-from')));
      expect(popup.top, greaterThanOrEqualTo(field.bottom));
      expect(popup.right, lessThanOrEqualTo(width));
      expect(find.byType(AlertDialog), findsNothing);
      await chooseDate(tester, '21/10/2026');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('movement-date-from')))
            .controller!
            .text,
        '21/10/2026',
      );
      await tester.enterText(
        find.byKey(const Key('movement-date-to')),
        '24/10/2026',
      );
      await tapVisible(tester, find.byKey(const Key('movement-date-to')));
      await tester.pumpAndSettle();
      await chooseDate(tester, '23/10/2026');
      expect(find.text('3 de 6 movimientos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.calls, 1);
      f.api.close();
    });
  }
  testWidgets(
    'cancelar el calendario conserva la fecha; limpiar filtros la borra',
    (tester) async {
      data.size(tester, 1440);
      final f = data.Fixture();
      await data.open(tester, f);
      final field = find.byKey(const Key('movement-date-from'));
      await tester.enterText(field, '20/10/2026');
      await tapVisible(tester, find.byTooltip('Elegir fecha desde'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CompactCalendar>(find.byType(CompactCalendar))
            .initialDate,
        DateTime(2026, 10, 20),
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '20/10/2026');
      await tapVisible(tester, find.text('Limpiar filtros'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      f.api.close();
    },
  );
}
