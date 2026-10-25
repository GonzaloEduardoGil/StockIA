import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/screens/login_screen.dart';
import 'package:stockia/screens/inventory_screen.dart';

http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> loginData(String role) => {
  'token': 'A' * 43,
  'usuario': {
    'idUsuario': 73,
    'nombre': 'Cuenta de prueba',
    'email': 'test@example.test',
    'rol': role,
  },
  'expira': '2027-01-01T00:00:00Z',
};

class TrackingClient extends http.BaseClient {
  TrackingClient(this.inner);
  final http.Client inner;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) throw StateError('Client closed');
    return inner.send(request);
  }

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

class Fixture {
  Fixture({this.role = 'Vendedor'}) {
    transport = TrackingClient(
      MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/login') {
          if (pending != null) return pending!.future;
          return status == 200
              ? json(loginData(role))
              : http.Response('', status);
        }
        expect(request.headers['Authorization'], 'Bearer ${'A' * 43}');
        if (expire) return http.Response('', 401);
        if (request.url.path == '/auth/logout') {
          return json({'sesionCerrada': true});
        }
        if (request.url.path == '/dashboard/') {
          return json({
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
        }
        if (request.url.path == '/alertas/') return json({'alertas': []});
        if (request.url.path == '/predicciones/') {
          return json({'predicciones': []});
        }
        if (request.url.path == '/ventas/') return json({'ventas': []});
        return json({'productos': []});
      }),
    );
    api = InventoryApi(client: transport);
  }
  late InventoryApi api;
  late TrackingClient transport;
  String role;
  int status = 200;
  bool expire = false;
  Completer<http.Response>? pending;
  final requests = <http.Request>[];
}

Future<void> show(WidgetTester tester, Fixture f, {double width = 1280}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(StockiaApp(api: f.api, requireLogin: true));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'test@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'test-password-not-for-real-db',
  );
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'login adaptable y sin consultar datos antes de entrar a $width px',
      (tester) async {
        final f = Fixture();
        await show(tester, f, width: width);
        expect(find.text('Iniciar sesión'), findsOneWidget);
        expect(f.requests, isEmpty);
        await submit(tester);
        expect(find.text('Ingresá un email válido.'), findsOneWidget);
        expect(f.requests, isEmpty);
        await fill(tester);
        await submit(tester);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(InventoryScreen), findsOneWidget);
        expect(f.api.session.value?.userId, 73);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'credenciales incorrectas y límite de intentos muestran errores claros',
    (tester) async {
      final f = Fixture()..status = 401;
      await show(tester, f);
      await fill(tester);
      await submit(tester);
      expect(find.text('Email o contraseña incorrectos.'), findsOneWidget);
      expect(f.api.session.value, isNull);
      f.status = 429;
      await submit(tester);
      expect(
        find.text(
          'Demasiados intentos. Esperá un minuto e intentá nuevamente.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('contraseña oculta por defecto y visible a pedido', (
    tester,
  ) async {
    await show(tester, Fixture());
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('login-password'))),
      isNotNull,
    );
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });
  testWidgets('no repite solicitudes de acceso mientras espera', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = Fixture()..pending = pending;
    await show(tester, f);
    await fill(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNull,
    );
    pending.complete(json(loginData('Vendedor')));
    await tester.pumpAndSettle();
    expect(f.requests.where((r) => r.url.path == '/auth/login').length, 1);
  });
  for (final role in ['Vendedor', 'Encargado de stock', 'Administrador']) {
    testWidgets('menú respeta el rol $role', (tester) async {
      final f = Fixture(role: role);
      await show(tester, f);
      await fill(tester);
      await submit(tester);
      expect(
        find.byKey(const Key('nav-dashboard')),
        role == 'Vendedor' ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const Key('nav-new-sale')),
        role == 'Vendedor' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Nuevo producto'),
        role == 'Administrador' ? findsNothing : findsNothing,
      );
      await tester.tap(find.byKey(const Key('nav-inventory')));
      await tester.pumpAndSettle();
      expect(
        find.text('Nuevo producto'),
        role == 'Administrador' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('nav-edit')),
        role == 'Administrador' ? findsOneWidget : findsNothing,
      );
    });
  }
  testWidgets(
    'logout revoca token y permite volver a entrar sin cerrar el cliente',
    (tester) async {
      final f = Fixture();
      await show(tester, f);
      await fill(tester);
      await submit(tester);
      await tester.tap(find.byKey(const Key('session-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(f.transport.closed, isFalse);
      expect(f.requests.where((r) => r.url.path == '/auth/logout').length, 1);
      await fill(tester);
      await submit(tester);
      expect(find.byType(InventoryScreen), findsOneWidget);
    },
  );
  testWidgets('401 devuelve al login sin conservar acceso a las pantallas', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await fill(tester);
    await submit(tester);
    f.expire = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Actualizar'));
    await tester.pumpAndSettle();
    expect(f.api.session.value, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(InventoryScreen), findsNothing);
  });
}
