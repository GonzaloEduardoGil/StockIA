import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/app.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/recommendation.dart';
import 'package:stockia/screens/recommendations_screen.dart';

Map<String, dynamic> row(
  int id, {
  String status = 'Pendiente',
  String date = '2026-10-24T23:59:00',
}) => {
  'idRecomendacion': id,
  'idProducto': id + 6,
  'nombreProducto': id == 1 ? 'Lápiz' : 'Mouse',
  'activo': true,
  'idUsuario': 73,
  'nombreUsuario': 'Encargado de prueba',
  'fecha': date,
  'tipo': 'Reposición',
  'cantidadSugerida': 40,
  'motivo': 'Stock actual: 0. Stock mínimo: 20. Demanda estimada: 30.',
  'estado': status,
};
http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  Fixture() {
    api = InventoryApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          if (request.url.path == '/recomendaciones/') {
            return json({'recomendaciones': rows});
          }
          return json({'productos': []});
        }
        if (request.method == 'POST') {
          if (pending != null) return pending!.future;
          if (postStatus != 200) return http.Response('', postStatus);
          if (!generateAny) return json({'cantidad': 0, 'recomendaciones': []});
          final generated = row(2);
          rows.add(generated);
          return json({
            'cantidad': 1,
            'recomendaciones': [generated],
          });
        }
        final id = int.parse(request.url.path.split('/')[2]);
        if (patchStatus == 409) {
          rows = rows
              .map(
                (r) => r['idRecomendacion'] == id
                    ? {...r, 'estado': 'Rechazada'}
                    : r,
              )
              .toList();
        }
        if (patchStatus != 200) return http.Response('', patchStatus);
        final status =
            (jsonDecode(request.body) as Map<String, dynamic>)['estado'];
        rows = rows
            .map(
              (r) => r['idRecomendacion'] == id ? {...r, 'estado': status} : r,
            )
            .toList();
        return json({
          'recomendacion': rows.firstWhere((r) => r['idRecomendacion'] == id),
          'stockModificado': stockModified,
        });
      }),
    );
  }
  late InventoryApi api;
  List<Map<String, dynamic>> rows = [row(1)];
  final requests = <http.Request>[];
  int postStatus = 200;
  int patchStatus = 200;
  bool generateAny = true;
  bool stockModified = false;
  Completer<http.Response>? pending;
  bool busy = false;
  List<http.Request> get writes =>
      requests.where((r) => r.method != 'GET').toList();
}

Future<void> show(
  WidgetTester tester,
  Fixture f, {
  double width = 1280,
  int? user = 73,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecommendationsScreen(
          api: f.api,
          currentUserId: user,
          onBusyChanged: (value) => f.busy = value,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, int id) =>
    tap(tester, find.byKey(ValueKey('recommendation-detail-$id')));
Finder field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));
void main() {
  test(
    'generación y decisión envían exclusivamente usuario de sesión y estado',
    () async {
      final f = Fixture();
      expect(await f.api.generateRecommendations(73), 1);
      expect(jsonDecode(f.writes.first.body), {'idUsuario': 73});
      final current = Recommendation.fromApi(row(1));
      final saved = await f.api.decideRecommendation(current, 73, 'Aceptada');
      expect(saved.status, 'Aceptada');
      expect(jsonDecode(f.writes.last.body), {
        'idUsuario': 73,
        'estado': 'Aceptada',
      });
      expect(f.writes.last.url.path, '/recomendaciones/1/decision');
      expect(f.writes.length, 2);
    },
  );
  test(
    'no envía solicitudes sin usuario o con una decisión inválida',
    () async {
      final f = Fixture();
      await expectLater(
        f.api.generateRecommendations(0),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        f.api.decideRecommendation(
          Recommendation.fromApi(row(1)),
          73,
          'Pendiente',
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.writes, isEmpty);
    },
  );
  test(
    'respuesta que no confirma stock intacto se trata como incierta',
    () async {
      final f = Fixture()..stockModified = true;
      await expectLater(
        f.api.decideRecommendation(
          Recommendation.fromApi(row(1)),
          73,
          'Aceptada',
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.mayHaveSaved, 'incierto', true),
        ),
      );
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('historial y detalle visual sin sesión a $width px', (
      tester,
    ) async {
      final f = Fixture();
      await show(tester, f, width: width, user: null);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('generate-recommendations')),
            )
            .onPressed,
        isNull,
      );
      await open(tester, 1);
      expect(find.text('40 unidades sugeridas'), findsOneWidget);
      expect(find.text('Motivo'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('accept-recommendation')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('reject-recommendation')),
            )
            .onPressed,
        isNull,
      );
      expect(f.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('filtra por producto, estado y fecha hasta inclusiva', (
    tester,
  ) async {
    final f = Fixture()
      ..rows = [row(1), row(2, status: 'Aceptada', date: '2026-10-23')];
    await show(tester, f);
    await tester.enterText(
      find.byKey(const Key('recommendation-search')),
      'lapiz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-detail-2')), findsNothing);
    await tester.enterText(field('recommendation-to'), '24/10/2026');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recommendation-detail-1')),
      findsOneWidget,
    );
    await tap(tester, find.text('Limpiar filtros'));
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('Aceptada').last);
    expect(find.byKey(const ValueKey('recommendation-detail-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('recommendation-detail-2')),
      findsOneWidget,
    );
  });
  for (final accept in [true, false]) {
    testWidgets(
      'registra decisión ${accept ? 'aceptada' : 'rechazada'} luego de confirmar',
      (tester) async {
        final f = Fixture();
        await show(tester, f);
        await open(tester, 1);
        await tap(
          tester,
          find.byKey(
            Key(accept ? 'accept-recommendation' : 'reject-recommendation'),
          ),
        );
        expect(f.writes, isEmpty);
        await tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(accept ? 'Aceptar' : 'Rechazar'),
          ),
        );
        expect(f.writes.single.method, 'PATCH');
        expect(find.text(accept ? 'Aceptada' : 'Rechazada'), findsOneWidget);
        expect(find.byKey(const Key('accept-recommendation')), findsNothing);
        expect(f.busy, isFalse);
      },
    );
  }
  testWidgets('cancelar conserva la recomendación pendiente sin escribir', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await open(tester, 1);
    await tap(tester, find.byKey(const Key('accept-recommendation')));
    await tap(tester, find.text('Cancelar'));
    expect(f.writes, isEmpty);
    expect(find.text('Pendiente'), findsOneWidget);
  });
  testWidgets('genera y carga el historial sin asignar un usuario fijo', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await tap(tester, find.byKey(const Key('generate-recommendations')));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Generar'),
      ),
    );
    expect(find.text('Se generó 1 recomendación.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-detail-2')),
      findsOneWidget,
    );
    expect(jsonDecode(f.writes.single.body), {'idUsuario': 73});
  });
  testWidgets('cero nuevas no afirma que todo el stock sea normal', (
    tester,
  ) async {
    final f = Fixture()..generateAny = false;
    await show(tester, f);
    await tap(tester, find.byKey(const Key('generate-recommendations')));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Generar'),
      ),
    );
    expect(
      find.text(
        'No se generaron recomendaciones nuevas. Revisá las pendientes.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-detail-1')),
      findsOneWidget,
    );
  });
  testWidgets('409 actualiza el estado sin repetir la decisión', (
    tester,
  ) async {
    final f = Fixture()..patchStatus = 409;
    await show(tester, f);
    await open(tester, 1);
    await tap(tester, find.byKey(const Key('accept-recommendation')));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Aceptar'),
      ),
    );
    expect(find.text('Rechazada'), findsOneWidget);
    expect(f.writes.length, 1);
  });
  testWidgets('403 no muestra éxito ni cambia la recomendación', (
    tester,
  ) async {
    final f = Fixture()..patchStatus = 403;
    await show(tester, f);
    await open(tester, 1);
    await tap(tester, find.byKey(const Key('accept-recommendation')));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Aceptar'),
      ),
    );
    expect(
      find.text('Tu usuario no tiene permiso para realizar esta operación.'),
      findsOneWidget,
    );
    expect(find.text('Pendiente'), findsOneWidget);
  });
  testWidgets(
    'error incierto bloquea generación incluso después de consultar el historial',
    (tester) async {
      final f = Fixture()..postStatus = 500;
      await show(tester, f);
      await tap(tester, find.byKey(const Key('generate-recommendations')));
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Generar'),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('generate-recommendations')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Actualizar'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('generate-recommendations')),
            )
            .onPressed,
        isNull,
      );
      expect(f.writes.length, 1);
    },
  );
  testWidgets('evita envíos repetidos mientras se está generando', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = Fixture()..pending = pending;
    await show(tester, f);
    await tap(tester, find.byKey(const Key('generate-recommendations')));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Generar'),
      ),
    );
    await tester.pump();
    expect(f.busy, isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('generate-recommendations')),
          )
          .onPressed,
      isNull,
    );
    pending.complete(json({'cantidad': 0, 'recomendaciones': []}));
    await tester.pumpAndSettle();
    expect(f.writes.length, 1);
    expect(f.busy, isFalse);
  });
  testWidgets('vacío y error de consulta tienen estados distintos', (
    tester,
  ) async {
    final f = Fixture()..rows = [];
    await show(tester, f);
    expect(
      find.text('Todavía no hay recomendaciones guardadas.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    final api = InventoryApi(
      client: MockClient((_) async => http.Response('', 500)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationsScreen(
            api: api,
            currentUserId: 73,
            onBusyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(
      find.text('Todavía no hay recomendaciones guardadas.'),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('generate-recommendations')),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('navegación conserva sidebar y permite volver al inventario', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(StockiaApp(api: f.api));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('nav-recommendations')));
    expect(find.byType(RecommendationsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, find.byKey(const Key('nav-inventory')));
    expect(find.byType(RecommendationsScreen), findsNothing);
  });
}
