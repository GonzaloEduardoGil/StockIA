import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockia/data/inventory_api.dart';
import 'package:stockia/models/auth_session.dart';
import 'package:stockia/screens/dashboard_screen.dart';

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets('consulta automáticas sin generación manual a $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final api = InventoryApi(
        client: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          final Object data = switch (request.url.path) {
            '/predicciones/' => {
              'predicciones': [
                {
                  'idPrediccion': 91,
                  'idProducto': 7,
                  'nombreProducto': 'Cuaderno',
                  'activo': true,
                  'fechaPrediccion': '2026-10-26',
                  'periodoPrediccion': 'Semanal: 2026-10-26 a 2026-11-01',
                  'cantidadEstimada': 28,
                },
              ],
            },
            '/productos/' => {
              'productos': [
                {'idProducto': 7, 'nombre': 'Cuaderno'},
              ],
            },
            '/alertas/' => {'alertas': []},
            _ => {},
          };
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      api.session.value = AuthSession(
        token: 'A' * 43,
        userId: 1,
        name: 'QA',
        email: 'qa@example.test',
        role: 'Administrador',
        expires: DateTime(2030),
      );
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              api: api,
              onInventory: () {},
              onAlerts: () {},
              onSales: () {},
              onProduct: (id) => selected = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Actualización automática semanal'), findsOneWidget);
      expect(find.text('PREDICCIÓN SEMANAL'), findsOneWidget);
      expect(find.text('Generar predicción'), findsNothing);
      expect(find.text('Cantidad de días'), findsNothing);
      expect(find.text('Consultar producto'), findsNothing);
      await tester.ensureVisible(find.text('Ver análisis'));
      await tester.tap(find.text('Ver análisis'));
      expect(selected, 7);
      expect(requests.any((r) => r.method != 'GET'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
