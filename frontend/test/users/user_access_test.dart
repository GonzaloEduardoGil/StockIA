import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stockia/data/inventory_api.dart';

import 'users_test.dart' as h;

Future<void> menu(WidgetTester tester, String action) async {
  await h.tap(tester, find.byKey(const ValueKey('user-access-7')));
  await h.tap(tester, find.text(action));
}

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets('desactiva y reactiva con confirmación a $width px', (
      tester,
    ) async {
      var active = true;
      final requests = <http.Request>[];
      final api = h.apiFor((r) async {
        requests.add(r);
        if (r.method == 'GET') {
          return h.json({
            'usuarios': [
              {...h.user(), 'activo': active},
            ],
          });
        }
        active = (jsonDecode(r.body) as Map)['activo'] as bool;
        return h.json({
          'usuario': {...h.user(), 'activo': active},
        });
      });
      addTearDown(api.close);
      await h.show(tester, api, width: width);
      await menu(tester, 'Desactivar');
      await h.tap(tester, find.text('Cancelar'));
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await menu(tester, 'Desactivar');
      await h.tap(tester, find.text('Desactivar'));
      expect(find.text('Inactivo'), findsOneWidget);
      expect(find.text('Usuario desactivado.'), findsOneWidget);
      expect(find.text('ana@example.com'), findsOneWidget);
      await menu(tester, 'Reactivar');
      await h.tap(tester, find.text('Reactivar'));
      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('Usuario reactivado.'), findsOneWidget);
      final changes = requests.where((r) => r.method == 'PATCH').toList();
      expect(changes.length, 2);
      expect(changes.first.url.path, '/usuarios/7/estado');
      expect(jsonDecode(changes.first.body), {'activo': false});
      expect(jsonDecode(changes.last.body), {'activo': true});
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'restablece contraseña con confirmación y sin mostrarla en listado',
    (tester) async {
      final requests = <http.Request>[];
      final api = h.apiFor((r) async {
        requests.add(r);
        return r.method == 'GET'
            ? h.json({
                'usuarios': [h.user()],
              })
            : h.json({'usuario': h.user()});
      });
      addTearDown(api.close);
      await h.show(tester, api);
      await menu(tester, 'Restablecer contraseña');
      await tester.enterText(
        find.byKey(const Key('reset-password')),
        h.password,
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirmation')),
        'different-password',
      );
      await h.tap(tester, find.text('Restablecer'));
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('reset-confirmation')),
        h.password,
      );
      await h.tap(tester, find.text('Restablecer'));
      final post = requests.singleWhere((r) => r.method == 'POST');
      expect(post.url.path, '/usuarios/7/password');
      expect(jsonDecode(post.body), {
        'password': h.password,
        'confirmacion': h.password,
      });
      expect(find.text('Contraseña restablecida.'), findsOneWidget);
      expect(find.byKey(const Key('reset-password')), findsNothing);
      expect(find.text(h.password), findsNothing);
    },
  );

  testWidgets(
    'rol solo permite encargado o vendedor y exige cambiar el valor',
    (tester) async {
      final requests = <http.Request>[];
      final api = h.apiFor((r) async {
        requests.add(r);
        return r.method == 'GET'
            ? h.json({
                'usuarios': [h.user()],
              })
            : h.json({'usuario': h.user(role: 'Encargado de stock')});
      });
      addTearDown(api.close);
      await h.show(tester, api);
      await menu(tester, 'Cambiar rol');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar rol'),
            )
            .onPressed,
        isNull,
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('change-user-role')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value), [
        'Encargado de stock',
        'Vendedor',
      ]);
      await h.tap(tester, find.byKey(const Key('change-user-role')));
      await h.tap(tester, find.text('Encargado de stock').last);
      await h.tap(tester, find.text('Guardar rol'));
      final patch = requests.singleWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, '/usuarios/7/rol');
      expect(jsonDecode(patch.body), {'rol': 'Encargado de stock'});
      expect(find.text('Encargado de stock'), findsOneWidget);
      expect(find.text('Rol actualizado.'), findsOneWidget);
    },
  );

  testWidgets(
    'bloquea doble envío y exige actualizar si no confirma el cambio',
    (tester) async {
      final pending = Completer<http.Response>();
      var changes = 0;
      final api = h.apiFor((r) async {
        if (r.method == 'GET') {
          return h.json({
            'usuarios': [
              {...h.user(), 'activo': changes == 0},
            ],
          });
        }
        changes++;
        return pending.future;
      });
      addTearDown(api.close);
      await h.show(tester, api);
      await menu(tester, 'Desactivar');
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('user-access-7')),
            )
            .enabled,
        isFalse,
      );
      pending.complete(http.Response('respuesta perdida', 200));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos confirmar'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('user-access-7')),
            )
            .enabled,
        isFalse,
      );
      await h.tap(tester, find.text('Actualizar listado'));
      expect(find.text('Inactivo'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('user-access-7')),
            )
            .enabled,
        isTrue,
      );
      expect(changes, 1);
    },
  );

  test('los otros roles no pueden enviar cambios de acceso', () async {
    final api = h.apiFor(
      (_) async => throw StateError('No debe enviar'),
      role: 'Vendedor',
    );
    addTearDown(api.close);
    await expectLater(
      api.changeUserStatus(7, false),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      api.changeUserRole(7, 'Encargado de stock'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      api.resetUserPassword(7, h.password, h.password),
      throwsA(isA<ApiFailure>()),
    );
  });
}
