import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/auth_session.dart';
import 'package:stockia/screens/login_screen.dart';
import 'package:stockia/widgets/change_password_dialog.dart';

import 'login_test.dart' as h;

const oldPassword = 'QA-only-old-password';
const newPassword = 'QA-only-new-password';
http.Response success() =>
    h.json({'passwordActualizada': true, 'sesionesCerradas': true});

InventoryApi apiFor(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'Vendedor',
}) {
  final api = InventoryApi(
    client: MockClient((r) async {
      if (r.url.path == '/auth/password') return handler(r);
      return h.json({
        'productos': [],
        'alertas': [],
        'predicciones': [],
        'resumenVentas': {'cantidadVentas': 0, 'totalFacturado': 0},
        'inventario': {
          'productosActivos': 0,
          'unidadesDisponibles': 0,
          'productosStockBajo': 0,
          'productosStockNormal': 0,
        },
        'evolucionVentas': [],
        'productosMasVendidos': [],
        'productosMenosVendidos': [],
      });
    }),
  );
  api.session.value = AuthSession.fromApi(h.loginData(role));
  return api;
}

Future<void> open(
  WidgetTester tester,
  InventoryApi api, {
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(StockiaApp(api: api, requireLogin: true));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('session-account')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cambiar mi contraseña'));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('own-current-password')),
    oldPassword,
  );
  await tester.enterText(
    find.byKey(const Key('own-new-password')),
    newPassword,
  );
  await tester.enterText(
    find.byKey(const Key('own-confirmation')),
    newPassword,
  );
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Cambiar contraseña'));
  await tester.tap(find.text('Cambiar contraseña'));
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['Administrador', 'Encargado de stock', 'Vendedor']) {
    testWidgets('cambia clave propia y vuelve al login: $role', (tester) async {
      final requests = <http.Request>[];
      final api = apiFor((r) async {
        requests.add(r);
        return success();
      }, role: role);
      await open(tester, api, width: role == 'Vendedor' ? 360 : 1280);
      await fill(tester);
      for (final key in [
        'own-current-password',
        'own-new-password',
        'own-confirmation',
      ]) {
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(TextField),
                ),
              )
              .obscureText,
          isTrue,
        );
      }
      await submit(tester);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/auth/password');
      expect(requests.single.headers['Authorization'], 'Bearer ${'A' * 43}');
      expect(jsonDecode(requests.single.body), {
        'passwordActual': oldPassword,
        'password': newPassword,
        'confirmacion': newPassword,
      });
      expect(api.session.value, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ChangePasswordDialog), findsNothing);
      expect(find.textContaining('Contraseña actualizada.'), findsOneWidget);
      expect(find.text(newPassword), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clave actual incorrecta conserva sesión y permite corregir', (
    tester,
  ) async {
    final api = apiFor(
      (_) async => http.Response(
        jsonEncode({'detail': 'La contraseña actual no es correcta.'}),
        400,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await open(tester, api);
    await fill(tester);
    await submit(tester);
    expect(find.text('La contraseña actual no es correcta.'), findsOneWidget);
    expect(api.session.value, isNotNull);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cambiar contraseña'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.session.value, isNotNull);
  });

  testWidgets(
    'valida confirmación y exige una clave distinta antes de enviar',
    (tester) async {
      var sent = 0;
      final api = apiFor((_) async {
        sent++;
        return success();
      });
      await open(tester, api);
      await fill(tester);
      await tester.enterText(
        find.byKey(const Key('own-confirmation')),
        'different',
      );
      await submit(tester);
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('own-new-password')),
        oldPassword,
      );
      await tester.enterText(
        find.byKey(const Key('own-confirmation')),
        oldPassword,
      );
      await submit(tester);
      expect(
        find.text('La nueva contraseña debe ser distinta.'),
        findsOneWidget,
      );
      expect(sent, 0);
    },
  );

  testWidgets('bloquea doble envío mientras guarda', (tester) async {
    final pending = Completer<http.Response>();
    var sent = 0;
    final api = apiFor((_) {
      sent++;
      return pending.future;
    });
    await open(tester, api);
    await fill(tester);
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
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
    expect(sent, 1);
    pending.complete(success());
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
    'resultado incierto no permite repetir y ofrece volver a ingresar',
    (tester) async {
      var sent = 0;
      final api = apiFor((_) async {
        sent++;
        return http.Response('respuesta perdida', 200);
      });
      await open(tester, api);
      await fill(tester);
      await submit(tester);
      expect(find.textContaining('No pudimos confirmar'), findsOneWidget);
      expect(find.text('Cambiar contraseña'), findsNothing);
      await tester.tap(find.text('Volver a ingresar'));
      await tester.pumpAndSettle();
      expect(api.session.value, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(sent, 1);
    },
  );

  test('una respuesta tardía no cierra una sesión que la reemplazó', () async {
    final pending = Completer<http.Response>();
    final api = apiFor((_) => pending.future);
    addTearDown(api.close);
    final saving = api.changeOwnPassword(oldPassword, newPassword, newPassword);
    await Future<void>.delayed(Duration.zero);
    api.session.value = AuthSession.fromApi({
      ...h.loginData('Vendedor'),
      'token': 'B' * 43,
    });
    pending.complete(success());
    await saving;
    expect(api.session.value?.token, 'B' * 43);
  });

  testWidgets(
    'formulario de una sesión anterior no cambia ni cierra la nueva',
    (tester) async {
      var sent = 0;
      final api = apiFor((_) async {
        sent++;
        return success();
      });
      await open(tester, api);
      await fill(tester);
      api.session.value = AuthSession.fromApi({
        ...h.loginData('Vendedor'),
        'token': 'B' * 43,
      });
      await tester.pumpAndSettle();
      await submit(tester);
      expect(sent, 0);
      expect(find.textContaining('La sesión cambió.'), findsOneWidget);
      await tester.tap(find.text('Volver a ingresar'));
      await tester.pumpAndSettle();
      expect(api.session.value?.token, 'B' * 43);
      expect(find.byType(LoginScreen), findsNothing);
    },
  );

  test('sin sesión no se envía el cambio', () async {
    final api = InventoryApi(
      client: MockClient((_) async => throw StateError('No enviar')),
    );
    addTearDown(api.close);
    await expectLater(
      api.changeOwnPassword(oldPassword, newPassword, newPassword),
      throwsA(isA<ApiFailure>()),
    );
  });
}
