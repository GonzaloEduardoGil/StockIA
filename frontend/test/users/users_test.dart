import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/auth_session.dart';
import 'package:stockia/screens/users_screen.dart';
import 'package:stockia/screens/inventory_screen.dart';

const password = 'Only-Test-Password-998';
Map<String, dynamic> user({String name = 'Ana', String role = 'Vendedor'}) => {
  'idUsuario': 7,
  'nombre': name,
  'email': 'ana@example.com',
  'rol': role,
};
http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

InventoryApi apiFor(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'Administrador',
}) {
  final api = InventoryApi(client: MockClient(handler));
  api.session.value = AuthSession(
    token: 'A' * 43,
    userId: 1,
    name: 'Admin',
    email: 'admin@example.com',
    role: role,
    expires: DateTime(2030),
  );
  return api;
}

Future<void> show(
  WidgetTester tester,
  InventoryApi api, {
  double width = 1200,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UsersScreen(api: api)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tap(tester, find.text('Nuevo usuario'));
  await tester.enterText(find.byKey(const Key('user-name')), 'Ana');
  await tester.enterText(
    find.byKey(const Key('user-email')),
    ' ANA@EXAMPLE.COM ',
  );
  await tester.enterText(find.byKey(const Key('user-password')), password);
  await tester.enterText(find.byKey(const Key('user-confirmation')), password);
}

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets('edita solo nombre y email a $width px', (tester) async {
      final requests = <http.Request>[];
      final api = apiFor((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? json({
                'usuarios': [user()],
              })
            : json({
                'usuario': {
                  ...user(name: 'Ana editada'),
                  'email': 'editada@example.com',
                },
              });
      });
      addTearDown(api.close);
      await show(tester, api, width: width);
      await tap(tester, find.byKey(const ValueKey('edit-user-7')));
      expect(find.text('Editar usuario'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('user-name')))
            .controller!
            .text,
        'Ana',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('user-email')))
            .controller!
            .text,
        'ana@example.com',
      );
      expect(find.byKey(const Key('user-role')), findsNothing);
      expect(find.byKey(const Key('user-password')), findsNothing);
      expect(find.byKey(const Key('user-confirmation')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('user-name')),
        ' Ana editada ',
      );
      await tester.enterText(
        find.byKey(const Key('user-email')),
        ' EDITADA@EXAMPLE.COM ',
      );
      await tap(tester, find.text('Guardar cambios'));
      final patch = requests.singleWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, '/usuarios/7/');
      expect(jsonDecode(patch.body), {
        'nombre': 'Ana editada',
        'email': 'editada@example.com',
      });
      expect(
        find.textContaining('Usuario actualizado: Ana editada'),
        findsOneWidget,
      );
      expect(find.text('editada@example.com'), findsOneWidget);
      expect(find.text('ana@example.com'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('permite conservar el email propio y cancelar no envía cambios', (
    tester,
  ) async {
    var updates = 0;
    final api = apiFor((request) async {
      if (request.method == 'GET') {
        return json({
          'usuarios': [user()],
        });
      }
      updates++;
      return json({'usuario': user()});
    });
    addTearDown(api.close);
    await show(tester, api);
    await tap(tester, find.byKey(const ValueKey('edit-user-7')));
    await tester.enterText(find.byKey(const Key('user-name')), 'No guardar');
    await tap(tester, find.text('Cancelar'));
    expect(updates, 0);
    expect(find.text('ana@example.com'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('edit-user-7')));
    await tap(tester, find.text('Guardar cambios'));
    expect(updates, 1);
  });

  testWidgets('un GET lento no restaura los datos anteriores a la edición', (
    tester,
  ) async {
    var gets = 0;
    final old = Completer<http.Response>();
    final api = apiFor((request) async {
      if (request.method == 'PATCH') {
        return json({
          'usuario': {...user(name: 'Editada'), 'email': 'editada@example.com'},
        });
      }
      return ++gets == 1
          ? json({
              'usuarios': [user()],
            })
          : old.future;
    });
    addTearDown(api.close);
    await show(tester, api);
    await tap(tester, find.byKey(const ValueKey('edit-user-7')));
    await tester.enterText(find.byKey(const Key('user-name')), 'Editada');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'editada@example.com',
    );
    await tester.ensureVisible(find.text('Actualizar listado'));
    await tester.tap(find.text('Actualizar listado'));
    await tester.pump();
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    old.complete(
      json({
        'usuarios': [user()],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('editada@example.com'), findsOneWidget);
    expect(find.text('ana@example.com'), findsNothing);
    expect(find.textContaining('Usuario actualizado: Editada'), findsOneWidget);
  });

  testWidgets(
    'conflicto permite corregir y guardado incierto exige actualizar',
    (tester) async {
      var updates = 0;
      final api = apiFor((request) async {
        if (request.method == 'GET') {
          return json({
            'usuarios': [user()],
          });
        }
        if (++updates == 1) {
          return json({'detail': 'Ya existe un usuario con ese email.'}, 409);
        }
        return http.Response('respuesta perdida', 200);
      });
      addTearDown(api.close);
      await show(tester, api);
      await tap(tester, find.byKey(const ValueKey('edit-user-7')));
      await tap(tester, find.text('Guardar cambios'));
      expect(find.text('Ya existe un usuario con ese email.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNotNull,
      );
      await tap(tester, find.text('Guardar cambios'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Actualizar listado'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar cambios'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('GET anterior no habilita reintentar un alta incierta', (
    tester,
  ) async {
    final initial = Completer<http.Response>();
    var gets = 0;
    final api = apiFor((request) async {
      if (request.method == 'POST') {
        return http.Response('respuesta perdida', 201);
      }
      return ++gets == 1 ? initial.future : json({'usuarios': []});
    });
    addTearDown(api.close);
    await show(tester, api, settle: false);
    await tester.tap(find.text('Nuevo usuario'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('user-name')), 'Ana');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'ana@example.com',
    );
    await tester.enterText(find.byKey(const Key('user-password')), password);
    await tester.enterText(
      find.byKey(const Key('user-confirmation')),
      password,
    );
    await tester.ensureVisible(find.text('Crear usuario'));
    await tester.tap(find.text('Crear usuario'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    initial.complete(json({'usuarios': []}));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear usuario'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('Actualizar listado'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear usuario'),
          )
          .onPressed,
      isNotNull,
    );
  });

  for (final oldGetFails in [false, true]) {
    testWidgets(
      'alta confirmada sobrevive a GET anterior (error: $oldGetFails)',
      (tester) async {
        final initial = Completer<http.Response>();
        final api = apiFor(
          (request) async => request.method == 'GET'
              ? initial.future
              : json({'usuario': user()}, 201),
        );
        addTearDown(api.close);
        await show(tester, api, settle: false);
        await tester.tap(find.text('Nuevo usuario'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('user-name')), 'Ana');
        await tester.enterText(
          find.byKey(const Key('user-email')),
          'ana@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('user-password')),
          password,
        );
        await tester.enterText(
          find.byKey(const Key('user-confirmation')),
          password,
        );
        await tester.ensureVisible(find.text('Crear usuario'));
        await tester.tap(find.text('Crear usuario'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.textContaining('Usuario creado: Ana'), findsOneWidget);
        initial.complete(
          oldGetFails
              ? http.Response('', 503)
              : json({
                  'usuarios': [
                    {
                      ...user(name: 'Cuenta anterior'),
                      'idUsuario': 8,
                      'email': 'anterior@example.com',
                    },
                  ],
                }),
        );
        await tester.pumpAndSettle();
        expect(find.text('ana@example.com'), findsOneWidget);
        expect(find.textContaining('Usuario creado: Ana'), findsOneWidget);
        if (!oldGetFails) {
          expect(find.text('anterior@example.com'), findsOneWidget);
        }
        expect(
          find.text('Todavía no hay encargados ni vendedores registrados.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'un GET anterior no reemplaza una actualización posterior al alta',
    (tester) async {
      final initial = Completer<http.Response>();
      var gets = 0;
      final api = apiFor((request) async {
        if (request.method == 'POST') return json({'usuario': user()}, 201);
        if (++gets == 1) return initial.future;
        return json({
          'usuarios': [
            user(),
            {
              ...user(name: 'Otra cuenta'),
              'idUsuario': 8,
              'email': 'otra@example.com',
            },
          ],
        });
      });
      addTearDown(api.close);
      await show(tester, api, settle: false);
      await tester.tap(find.text('Nuevo usuario'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('user-name')), 'Ana');
      await tester.enterText(
        find.byKey(const Key('user-email')),
        'ana@example.com',
      );
      await tester.enterText(find.byKey(const Key('user-password')), password);
      await tester.enterText(
        find.byKey(const Key('user-confirmation')),
        password,
      );
      await tester.ensureVisible(find.text('Crear usuario'));
      await tester.tap(find.text('Crear usuario'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('Actualizar listado'));
      await tester.tap(find.text('Actualizar listado'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      initial.complete(json({'usuarios': []}));
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(find.text('ana@example.com'), findsOneWidget);
      expect(find.text('otra@example.com'), findsOneWidget);
    },
  );

  testWidgets('alta autenticada, rol limitado y listado sin contraseñas', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = apiFor((request) async {
      requests.add(request);
      return request.method == 'GET'
          ? json({'usuarios': []})
          : json({'usuario': user()}, 201);
    });
    addTearDown(api.close);
    await show(tester, api);
    await fill(tester);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('user-role')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(dropdown.items!.map((item) => item.value), [
      'Encargado de stock',
      'Vendedor',
    ]);
    await tap(tester, find.text('Crear usuario'));
    final post = requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/usuarios/');
    expect(post.headers['Authorization'], startsWith('Bearer '));
    expect((jsonDecode(post.body) as Map)['email'], 'ana@example.com');
    expect(find.textContaining('Usuario creado: Ana'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text(password), findsNothing);
    expect(find.byKey(const Key('user-password')), findsNothing);
  });

  testWidgets('validación de confirmación evita enviar y se ve a 320 px', (
    tester,
  ) async {
    var posts = 0;
    final api = apiFor((r) async {
      if (r.method == 'POST') posts++;
      return json({'usuarios': []});
    });
    addTearDown(api.close);
    await show(tester, api, width: 320);
    await fill(tester);
    await tester.enterText(
      find.byKey(const Key('user-confirmation')),
      'Different-password',
    );
    await tap(tester, find.text('Crear usuario'));
    expect(posts, 0);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doble clic no duplica el alta y el conflicto permite corregir', (
    tester,
  ) async {
    var count = 0;
    final pending = Completer<http.Response>();
    final api = apiFor((r) async {
      if (r.method == 'GET') return json({'usuarios': []});
      count++;
      return pending.future;
    });
    addTearDown(api.close);
    await show(tester, api);
    await fill(tester);
    await tester.ensureVisible(find.text('Crear usuario'));
    await tester.tap(find.text('Crear usuario'));
    await tester.pump();
    expect(find.text('Creando…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Creando…'))
          .onPressed,
      isNull,
    );
    expect(count, 1);
    pending.complete(
      json({'detail': 'Ya existe un usuario con ese email.'}, 409),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ya existe un usuario con ese email.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear usuario'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('resultado incierto exige actualizar antes de volver a crear', (
    tester,
  ) async {
    final api = apiFor(
      (r) async => r.method == 'GET'
          ? json({'usuarios': []})
          : http.Response('respuesta perdida', 201),
    );
    addTearDown(api.close);
    await show(tester, api);
    await fill(tester);
    await tap(tester, find.text('Crear usuario'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear usuario'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('Actualizar listado'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crear usuario'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('solo el administrador tiene acceso en la navegación', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final role in ['Administrador', 'Encargado de stock', 'Vendedor']) {
      final api = apiFor(
        (r) async => json(
          r.url.path == '/usuarios/'
              ? {
                  'usuarios': [user()],
                }
              : {'productos': [], 'alertas': []},
        ),
        role: role,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryScreen(
            key: ValueKey(role),
            api: api,
            currentUserRole: role,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (role == 'Administrador') {
        await tap(tester, find.byKey(const Key('nav-users')));
        expect(find.text('ana@example.com'), findsOneWidget);
        await tap(tester, find.byKey(const Key('nav-inventory')));
        expect(find.text('ana@example.com'), findsNothing);
      } else {
        expect(find.byKey(const Key('nav-users')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      api.close();
    }
  });

  test('sin rol administrador el cliente no envía solicitudes', () async {
    final api = apiFor(
      (_) async => throw StateError('No debe enviar'),
      role: 'Vendedor',
    );
    addTearDown(api.close);
    await expectLater(api.loadUsers(), throwsA(isA<ApiFailure>()));
    await expectLater(
      api.createUser(
        name: 'Ana',
        email: 'ana@example.com',
        role: 'Vendedor',
        password: password,
        confirmation: password,
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
}
