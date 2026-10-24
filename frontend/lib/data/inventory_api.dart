import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/product.dart';
import '../models/new_product.dart';

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.mayHaveSaved = false,
    this.requiresRefresh = false,
  });
  final String message;
  final bool mayHaveSaved;
  final bool requiresRefresh;
}

class InventoryApi {
  InventoryApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = (baseUrl ?? configuredUrl).replaceAll(RegExp(r'/+$'), '');
  static String get configuredUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ApiFailure(
          'El servicio no pudo completar la consulta. Intentá nuevamente.',
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException();
      return body;
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(
        'La consulta está tardando demasiado. Volvé a intentarlo.',
      );
    } on FormatException {
      throw const ApiFailure('No se pudo interpretar la información recibida.');
    } catch (_) {
      throw const ApiFailure(
        'No pudimos conectar con el servicio. Comprobá la conexión e intentá nuevamente.',
      );
    }
  }

  Future<List<Product>> loadInventory() async {
    final responses = await Future.wait([_get('/stock/'), _get('/productos/')]);
    try {
      final stock = responses[0]['productos'] as List<dynamic>;
      final products = responses[1]['productos'] as List<dynamic>;
      final byId = {
        for (final row in products)
          (row as Map<String, dynamic>)['idProducto']: row,
      };
      final result = stock.map((row) {
        final item = row as Map<String, dynamic>;
        return Product.fromApi(item, byId[item['idProducto']]);
      }).toList();
      result.sort((a, b) => searchable(a.name).compareTo(searchable(b.name)));
      return result;
    } catch (_) {
      throw const ApiFailure(
        'La información de inventario recibida está incompleta.',
      );
    }
  }

  Future<Product> loadDetail(Product current) async {
    final data = await _get('/productos/${current.id}');
    try {
      return current.withDetails(data);
    } catch (_) {
      throw const ApiFailure('No se pudo interpretar el detalle del producto.');
    }
  }

  Future<int> createProduct(NewProduct product) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/productos/'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(product.toJson()),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó los datos. Revisá los campos antes de confirmar.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode >= 500) {
          throw const ApiFailure(
            'El servicio no confirmó el registro. Volvé al inventario y comprobá el resultado antes de intentar otra vez.',
            mayHaveSaved: true,
          );
        }
        throw const ApiFailure(
          'No se pudo registrar el producto. Los datos del formulario se conservaron.',
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final id = body is Map<String, dynamic> ? body['idProducto'] : null;
      if (id is! num || !id.isFinite || id <= 0 || id != id.roundToDouble()) {
        throw const FormatException();
      }
      return id.toInt();
    } on ApiFailure {
      rethrow;
    } catch (_) {
      // Una pérdida de conexión no prueba que el servidor haya deshecho el alta.
      // No repetir automáticamente una operación de escritura sin idempotencia.
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Volvé al inventario y comprobá si el producto se registró antes de intentar otra vez.',
        mayHaveSaved: true,
      );
    }
  }

  Future<int> updateProduct(Product current, NewProduct changes) async {
    try {
      final values = changes.toJson();
      final response = await _client
          .put(
            Uri.parse('$baseUrl/productos/${current.id}'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              for (final key in [
                'nombre',
                'descripcion',
                'categoria',
                'precio',
              ])
                key: values[key],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw const ApiFailure(
          'El producto ya no está disponible para modificar. Volvé al inventario para actualizar la información.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó los datos. Revisá los campos antes de confirmar.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudieron confirmar los cambios. Los datos del formulario se conservaron.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final saved = body is Map<String, dynamic> ? body['producto'] : null;
      if (saved is! Map<String, dynamic> || saved['idProducto'] != current.id) {
        throw const FormatException();
      }
      return current.id;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Volvé al inventario y revisá los datos actuales antes de intentar otra vez.',
        mayHaveSaved: true,
      );
    }
  }

  Future<int> deactivateProduct(Product product) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('$baseUrl/productos/${product.id}/baja'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw ApiFailure(
          response.statusCode == 409
              ? 'El producto ya está inactivo. Actualizá el inventario para ver su estado actual.'
              : 'El producto ya no está disponible. Actualizá el inventario.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudo confirmar la baja. Actualizá el inventario para comprobar el estado del producto.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> ||
          body['idProducto'] != product.id ||
          body['activo'] != false) {
        throw const FormatException();
      }
      return product.id;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado de la baja. Actualizá el inventario antes de intentar otra vez.',
        mayHaveSaved: true,
      );
    }
  }

  void close() => _client.close();
}
