import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/data/alert_updates.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/auth_session.dart';
import 'package:stockia/screens/alerts_screen.dart';
import 'package:stockia/widgets/stock_notifications.dart';

http.Response rows(int quantity) => http.Response(
  jsonEncode({
    'alertas': [
      {
        'idProducto': 7,
        'nombreProducto': 'Cuaderno',
        'categoria': 'Librería',
        'cantidadDisponible': quantity,
        'stockMinimo': 10,
        'fechaCreacion': null,
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AuthSession user(String role, {String token = 'A'}) => AuthSession(
  token: token * 43,
  userId: 1,
  name: 'Prueba',
  email: 'prueba@example.test',
  role: role,
  expires: DateTime(2030),
);

class EventClient extends http.BaseClient {
  final controller = StreamController<List<int>>();
  http.BaseRequest? request;
  bool closed = false;
  int status = 200;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(
      controller.stream,
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void frame(String text) => controller.add(utf8.encode(text));

  @override
  void close() {
    closed = true;
    unawaited(controller.close());
  }
}

void main() {
  test(
    'manual y automática comparten consulta; señal tardía exige lectura nueva',
    () async {
      final pending = [Completer<http.Response>(), Completer<http.Response>()];
      var calls = 0;
      final api = InventoryApi(
        client: MockClient((_) => pending[calls++].future),
      );
      addTearDown(api.close);
      final first = api.loadAlerts();
      final manual = api.loadAlerts();
      expect(identical(first, manual), isTrue);
      api.invalidateAlerts();
      api.invalidateAlerts();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      pending[0].complete(rows(8));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(api.alerts.value, isNull);
      pending[1].complete(rows(3));
      expect((await first).single.quantity, 3);
      expect(api.alerts.value!.single.quantity, 3);
      expect(calls, 2);
    },
  );

  test('error de actualización conserva la última lista válida', () async {
    var fail = false;
    final api = InventoryApi(
      client: MockClient((_) async => fail ? http.Response('', 503) : rows(4)),
    );
    addTearDown(api.close);
    await api.loadAlerts();
    fail = true;
    await expectLater(api.loadAlerts(), throwsA(isA<ApiFailure>()));
    expect(api.alerts.value!.single.quantity, 4);
  });

  test(
    'una respuesta de la sesión anterior no reemplaza alertas de la nueva',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = InventoryApi(
        client: MockClient(
          (_) async => calls++ == 0 ? pending.future : rows(2),
        ),
      );
      addTearDown(api.close);
      api.session.value = user('Administrador');
      final old = api.loadAlerts();
      api.session.value = user('Encargado de stock', token: 'B');
      await api.loadAlerts();
      pending.complete(rows(9));
      await old;
      expect(api.alerts.value!.single.quantity, 2);
    },
  );

  test(
    'SSE autentica, agrupa frames completos y reconecta; stop cancela',
    () async {
      Future<void> pump([Duration duration = Duration.zero]) =>
          Future<void>.delayed(duration);
      final clients = <EventClient>[];
      var updates = 0;
      final observer = AlertUpdates(
        baseUrl: 'http://example.test',
        onUpdate: () => ++updates,
        onSessionExpired: (_) => fail('No debe expirar'),
        coalesceDelay: const Duration(milliseconds: 10),
        retryDelay: const Duration(milliseconds: 20),
        clientFactory: () {
          final client = EventClient();
          clients.add(client);
          return client;
        },
      );
      observer.start('A' * 43);
      await pump();
      expect(
        clients.single.request!.headers['Authorization'],
        'Bearer ${'A' * 43}',
      );
      expect(clients.single.request!.url.query, isEmpty);
      clients.first.frame('event: actual');
      await pump(const Duration(milliseconds: 20));
      expect(updates, 0);
      clients.first.frame('izar\ndata: {}\n\nevent: actualizar\ndata: {}\n\n');
      await pump();
      await pump(const Duration(milliseconds: 20));
      expect(updates, 1);
      await clients.first.controller.close();
      await pump();
      await pump(const Duration(milliseconds: 50));
      expect(clients, hasLength(2));
      clients.last.frame('event: actualizar\ndata: {}\n\n');
      await pump();
      await pump(const Duration(milliseconds: 20));
      expect(updates, 2);
      observer.stop();
      await pump(const Duration(milliseconds: 50));
      expect(clients, hasLength(2));
      expect(clients.last.closed, isTrue);
    },
  );

  testWidgets('sesión expirada por SSE cierra conexión y no reintenta', (
    tester,
  ) async {
    final client = EventClient();
    String? expired;
    final observer = AlertUpdates(
      baseUrl: 'http://example.test',
      onUpdate: () {},
      onSessionExpired: (token) => expired = token,
      clientFactory: () => client,
    );
    observer.start('A' * 43);
    await tester.pump();
    client.frame('event: sesion_expirada\ndata: {}\n\n');
    await tester.pump();
    expect(expired, 'A' * 43);
    expect(client.closed, isTrue);
    observer.stop();
  });

  testWidgets('Vendedor no se suscribe; encargado sí; salir desconecta', (
    tester,
  ) async {
    final clients = <EventClient>[];
    final api = InventoryApi(
      client: MockClient((_) async => rows(4)),
      enableAlertEvents: true,
      eventClientFactory: () {
        final client = EventClient();
        clients.add(client);
        return client;
      },
    );
    api.session.value = user('Vendedor');
    await tester.pump();
    expect(clients, isEmpty);
    api.session.value = user('Encargado de stock');
    await tester.pump();
    expect(clients, hasLength(1));
    clients.single.frame('event: actualizar\ndata: {}\n\n');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(api.alerts.value!.single.quantity, 4);
    api.session.value = null;
    await tester.pump();
    expect(clients.single.closed, isTrue);
    expect(api.alerts.value, isNull);
    api.close();
  });

  testWidgets('lista abierta se actualiza sin perder el filtro escrito', (
    tester,
  ) async {
    var quantity = 8;
    final api = InventoryApi(client: MockClient((_) async => rows(quantity)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertsScreen(api: api, onEntry: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('alert-search')), 'Cuaderno');
    quantity = 2;
    api.invalidateAlerts();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('alert-search')))
          .controller!
          .text,
      'Cuaderno',
    );
    expect(find.text('Cuaderno (#7)'), findsOneWidget);
    expect(find.text('Stock: 2 · Mínimo: 10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'campanita y menú abierto observan la actualización sin navegar',
    (tester) async {
      var quantity = 8;
      var count = 0;
      final api = InventoryApi(client: MockClient((_) async => rows(quantity)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockNotifications(
              api: api,
              count: 0,
              onAlert: (_) {},
              onAllAlerts: () {},
              onCountChanged: (value) => count = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('stock-alert-notification')));
      await tester.pumpAndSettle();
      expect(find.text('Stock: 8 · Mínimo: 10'), findsOneWidget);
      quantity = 1;
      api.invalidateAlerts();
      await tester.pumpAndSettle();
      expect(find.text('Stock: 1 · Mínimo: 10'), findsOneWidget);
      expect(count, 1);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
