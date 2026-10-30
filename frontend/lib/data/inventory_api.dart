import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/product.dart';
import '../models/stock_movement.dart';
import '../models/new_product.dart';
import '../models/sale.dart';
import '../models/sale_history.dart';
import '../models/stock_alert.dart';
import '../models/dashboard.dart';
import '../models/product_analysis.dart';
import '../models/recommendation.dart';
import '../models/auth_session.dart';
import '../models/managed_user.dart';
import 'session_client.dart';
import 'alert_updates.dart';

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
  InventoryApi({
    http.Client? client,
    String? baseUrl,
    bool enableAlertEvents = false,
    http.Client Function()? eventClientFactory,
  }) : _transport = client ?? http.Client(),
       baseUrl = (baseUrl ?? configuredUrl).replaceAll(RegExp(r'/+$'), '') {
    if (enableAlertEvents) {
      _alertUpdates = AlertUpdates(
        baseUrl: this.baseUrl,
        clientFactory: eventClientFactory,
        onUpdate: invalidateAlerts,
        onSessionExpired: (token) {
          if (!_closed && session.value?.token == token) session.value = null;
        },
      );
    }
    session.addListener(_sessionChanged);
  }
  static String get configuredUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  bool _closed = false;
  final http.Client _transport;
  final session = ValueNotifier<AuthSession?>(null);
  late final http.Client _client = SessionClient(_transport, session);
  final String baseUrl;
  final alerts = ValueNotifier<List<StockAlert>?>(null);
  AlertUpdates? _alertUpdates;
  Future<List<StockAlert>>? _alertsRequest;
  bool _alertsDirty = false;
  int _alertsEpoch = 0;

  void _sessionChanged() {
    ++_alertsEpoch;
    _alertsRequest = null;
    _alertsDirty = false;
    alerts.value = null;
    _alertUpdates?.stop();
    final user = session.value;
    if (user != null && user.stockRole) _alertUpdates?.start(user.token);
  }

  /// Una señal durante una consulta exige una lectura posterior: la primera
  /// puede haber tomado su snapshot antes del commit que originó el aviso.
  void invalidateAlerts() {
    if (_closed) return;
    _alertsDirty = true;
    unawaited(loadAlerts().then<void>((_) {}, onError: (Object _) {}));
  }

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

  Future<int> updateMinimumStock(Product product, int minimum) async {
    if (minimum < 0 || minimum > 2147483647) {
      throw const ApiFailure(
        'Ingresá una cantidad entera válida para el mínimo.',
      );
    }
    try {
      final response = await _client
          .patch(
            Uri.parse('$baseUrl/productos/${product.id}/stock-minimo'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'stockMinimo': minimum}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw const ApiFailure(
          'El producto no está disponible para cambiar su mínimo. Actualizá el inventario.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó el valor. Corregí el mínimo antes de confirmar.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudo confirmar el cambio de mínimo. Revisá el inventario antes de intentar otra vez.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> ||
          body['idProducto'] != product.id ||
          body['stockMinimo'] != minimum) {
        throw const FormatException();
      }
      return product.id;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Actualizá el inventario antes de volver a cambiar el mínimo.',
        mayHaveSaved: true,
      );
    }
  }

  Future<int> registerStockEntry(
    Product product,
    int quantity,
    String reason,
  ) async {
    if (quantity <= 0 ||
        quantity > 2147483647 - product.quantity ||
        reason.trim().length > 500) {
      throw const ApiFailure('Revisá la cantidad y el motivo de la entrada.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/stock/entradas/${product.id}'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'cantidad': quantity,
              'motivo': reason.trim().isEmpty ? null : reason.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw const ApiFailure(
          'El producto no está disponible para registrar una entrada. Actualizá el inventario y seleccioná otro producto.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó los datos. Revisá la cantidad y el motivo antes de confirmar.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudo confirmar la entrada. Revisá el inventario antes de volver a registrarla.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> ||
          body['idProducto'] != product.id ||
          body['cantidadIngresada'] != quantity ||
          body['cantidadAnterior'] is! int ||
          body['cantidadDisponible'] is! int ||
          body['cantidadDisponible'] != body['cantidadAnterior'] + quantity) {
        throw const FormatException();
      }
      return product.id;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Actualizá el inventario antes de intentar registrar la entrada otra vez, para evitar duplicarla.',
        mayHaveSaved: true,
      );
    }
  }

  Future<int> registerStockAdjustment(
    Product product,
    int quantity,
    String reason,
  ) async {
    if (quantity == 0 ||
        product.quantity + quantity < 0 ||
        product.quantity + quantity > 2147483647 ||
        reason.trim().isEmpty ||
        reason.trim().length > 500) {
      throw const ApiFailure('Revisá la cantidad y el motivo del ajuste.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/stock/ajustes/${product.id}'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'cantidad': quantity, 'motivo': reason.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw const ApiFailure(
          'No se puede aplicar el ajuste con el estado actual del producto. Actualizá el inventario.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó los datos. Revisá la cantidad y el motivo antes de confirmar.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudo confirmar el ajuste. Actualizá el inventario antes de repetirlo.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> ||
          body['idProducto'] != product.id ||
          body['cantidadAjuste'] != quantity ||
          body['cantidadAnterior'] is! int ||
          body['cantidadDisponible'] is! int ||
          body['cantidadDisponible'] < 0 ||
          body['cantidadDisponible'] != body['cantidadAnterior'] + quantity) {
        throw const FormatException();
      }
      return product.id;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Actualizá el inventario antes de repetir el ajuste.',
        mayHaveSaved: true,
      );
    }
  }

  Future<List<StockMovement>> loadMovements() async {
    final data = await _get('/movimientos/');
    try {
      final result = (data['movimientos'] as List<dynamic>)
          .map((row) => StockMovement.fromApi(row as Map<String, dynamic>))
          .toList();
      result.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate == 0 ? b.id.compareTo(a.id) : byDate;
      });
      return result;
    } catch (_) {
      throw const ApiFailure(
        'No se pudo interpretar el historial de movimientos.',
      );
    }
  }

  Future<StockMovement> loadMovement(int id) async {
    final data = await _get('/movimientos/$id');
    try {
      final movement = StockMovement.fromApi(data);
      if (movement.id != id) throw const FormatException();
      return movement;
    } catch (_) {
      throw const ApiFailure(
        'No se pudo interpretar el detalle del movimiento.',
      );
    }
  }

  Future<SaleReceipt> registerSale(int userId, List<SaleLine> lines) async {
    if (userId <= 0 ||
        lines.isEmpty ||
        lines.map((line) => line.product.id).toSet().length != lines.length ||
        lines.any(
          (line) => line.quantity <= 0 || line.quantity > line.product.quantity,
        )) {
      throw const ApiFailure('Revisá los datos de la venta.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/ventas/'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'idUsuario': userId,
              'productos': lines.map((line) => line.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 403) {
        throw const ApiFailure(
          'Tu usuario no tiene permiso para registrar ventas.',
        );
      }
      if (response.statusCode == 404 || response.statusCode == 409) {
        throw const ApiFailure(
          'El vendedor o algún producto no está disponible, o cambió el stock. Actualizá los productos y revisá la venta.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode == 422) {
        throw const ApiFailure(
          'El servicio rechazó los datos. Revisá los productos y cantidades.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          'No se pudo confirmar la venta. Revisá los movimientos antes de repetirla.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      return SaleReceipt.fromApi(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        lines,
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el resultado. Revisá los movimientos antes de repetir la venta.',
        mayHaveSaved: true,
      );
    }
  }

  Future<List<SaleSummary>> loadSales() async {
    final data = await _get('/ventas/');
    try {
      final sales = (data['ventas'] as List<dynamic>)
          .map((row) => SaleSummary.fromApi(row as Map<String, dynamic>))
          .toList();
      sales.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate == 0 ? b.id.compareTo(a.id) : byDate;
      });
      return sales;
    } catch (_) {
      throw const ApiFailure('No se pudo interpretar el historial de ventas.');
    }
  }

  Future<HistoricalSale> loadSale(int id) async {
    final data = await _get('/ventas/$id');
    try {
      final sale = HistoricalSale.fromApi(data);
      if (sale.summary.id != id) throw const FormatException();
      return sale;
    } catch (_) {
      throw const ApiFailure('No se pudo interpretar el detalle de la venta.');
    }
  }

  Future<List<StockAlert>> loadAlerts() {
    if (_alertsRequest != null) return _alertsRequest!;
    final epoch = _alertsEpoch;
    final completer = Completer<List<StockAlert>>();
    _alertsRequest = completer.future;
    Future<void> refresh() async {
      try {
        List<StockAlert> result;
        do {
          _alertsDirty = false;
          result = await _fetchAlerts();
        } while (!_closed && epoch == _alertsEpoch && _alertsDirty);
        if (!_closed && epoch == _alertsEpoch) alerts.value = result;
        completer.complete(result);
      } catch (error, stack) {
        // La última lista válida se conserva si falla una actualización.
        completer.completeError(error, stack);
      } finally {
        if (identical(_alertsRequest, completer.future)) _alertsRequest = null;
      }
    }

    unawaited(refresh());
    return completer.future;
  }

  Future<List<StockAlert>> _fetchAlerts() async {
    final data = await _get('/alertas/');
    try {
      final alerts = (data['alertas'] as List<dynamic>)
          .map((row) => StockAlert.fromApi(row as Map<String, dynamic>))
          .toList();
      alerts.sort((a, b) {
        if (a.outOfStock != b.outOfStock) return a.outOfStock ? -1 : 1;
        final deficit = (b.minimum - b.quantity).compareTo(
          a.minimum - a.quantity,
        );
        return deficit == 0
            ? searchable(a.name).compareTo(searchable(b.name))
            : deficit;
      });
      return alerts;
    } catch (_) {
      throw const ApiFailure(
        'No se pudo interpretar la información de alertas.',
      );
    }
  }

  Future<StockAlertDetail> loadAlert(int productId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/alertas/$productId'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 409 || response.statusCode == 404) {
        throw ApiFailure(
          response.statusCode == 409
              ? 'La alerta ya no está vigente para este producto. Volvé al listado para actualizar las alertas.'
              : 'El producto ya no está disponible. Volvé al listado para actualizar las alertas.',
          requiresRefresh: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ApiFailure(
          'No se pudo consultar el detalle de la alerta. Intentá nuevamente.',
        );
      }
      final detail = StockAlertDetail.fromApi(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (detail.product.id != productId) throw const FormatException();
      return detail;
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw const ApiFailure('No se pudo interpretar el detalle de la alerta.');
    } on TimeoutException {
      throw const ApiFailure(
        'La consulta está tardando demasiado. Volvé a intentarlo.',
      );
    } catch (_) {
      throw const ApiFailure(
        'No pudimos cargar el detalle de la alerta. Intentá nuevamente.',
      );
    }
  }

  Future<DashboardData> loadDashboard({DateTime? from, DateTime? to}) async {
    if (from != null && to != null && from.isAfter(to)) {
      throw const ApiFailure(
        'La fecha desde debe ser anterior o igual a la fecha hasta.',
      );
    }
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final path = Uri(
      path: '/dashboard/',
      queryParameters: {
        if (from != null) 'fecha_desde': date(from),
        if (to != null) 'fecha_hasta': date(to),
      },
    );
    return DashboardData.fromApi(await _get(path.toString()));
  }

  void _requireAdmin() {
    if (session.value?.role != 'Administrador') {
      throw const ApiFailure('Solo el administrador puede gestionar usuarios.');
    }
  }

  Future<List<ManagedUser>> loadUsers() async {
    _requireAdmin();
    final data = await _get('/usuarios/');
    try {
      return (data['usuarios'] as List<dynamic>)
          .map((row) => ManagedUser.fromApi(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiFailure('No se pudo interpretar el listado de usuarios.');
    }
  }

  Future<ManagedUser> createUser({
    required String name,
    required String email,
    required String role,
    required String password,
    required String confirmation,
  }) async {
    _requireAdmin();
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/usuarios/'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'nombre': name.trim(),
              'email': email.trim().toLowerCase(),
              'rol': role,
              'password': password,
              'confirmacion': confirmation,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 201) {
        final detail = data['detail'];
        throw ApiFailure(
          detail is String ? detail : 'No se pudo crear el usuario.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      return ManagedUser.fromApi(data['usuario'] as Map<String, dynamic>);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el alta. Actualizá el listado antes de volver a intentarlo.',
        mayHaveSaved: true,
      );
    }
  }

  Future<ManagedUser> editUser(
    int id, {
    required String name,
    required String email,
  }) async {
    _requireAdmin();
    try {
      final response = await _client
          .patch(
            Uri.parse('$baseUrl/usuarios/$id/'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'nombre': name.trim(),
              'email': email.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final detail = data['detail'];
        throw ApiFailure(
          detail is String ? detail : 'No se pudo editar el usuario.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final user = ManagedUser.fromApi(data['usuario'] as Map<String, dynamic>);
      if (user.id != id) throw const FormatException();
      return user;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar la edición. Actualizá el listado antes de volver a intentarlo.',
        mayHaveSaved: true,
      );
    }
  }

  Future<ManagedUser> changeUserStatus(int id, bool active) =>
      _changeUserAccess(id, 'estado', {'activo': active});

  Future<ManagedUser> changeUserRole(int id, String role) =>
      _changeUserAccess(id, 'rol', {'rol': role});

  Future<ManagedUser> resetUserPassword(
    int id,
    String password,
    String confirmation,
  ) => _changeUserAccess(id, 'password', {
    'password': password,
    'confirmacion': confirmation,
  }, post: true);

  Future<ManagedUser> _changeUserAccess(
    int id,
    String action,
    Map<String, dynamic> body, {
    bool post = false,
  }) async {
    _requireAdmin();
    try {
      final url = Uri.parse('$baseUrl/usuarios/$id/$action');
      const headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      };
      final response =
          await (post
                  ? _client.post(url, headers: headers, body: jsonEncode(body))
                  : _client.patch(
                      url,
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final detail = data['detail'];
        throw ApiFailure(
          detail is String ? detail : 'No se pudo completar la operación.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      final user = ManagedUser.fromApi(data['usuario'] as Map<String, dynamic>);
      if (user.id != id) throw const FormatException();
      return user;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar la operación. Actualizá el listado antes de volver a intentarlo.',
        mayHaveSaved: true,
      );
    }
  }

  Future<List<DemandPrediction>> loadPredictions() async {
    final data = await _get('/predicciones/');
    try {
      final rows = (data['predicciones'] as List<dynamic>)
          .map((row) => DemandPrediction.fromApi(row as Map<String, dynamic>))
          .toList();
      rows.sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date == 0 ? b.id.compareTo(a.id) : date;
      });
      return rows;
    } catch (_) {
      throw const ApiFailure(
        'No se pudieron interpretar las predicciones guardadas.',
      );
    }
  }

  Future<ProductAnalysis> loadProductAnalysis(int id) async {
    final data = await _get('/productos/$id/analisis');
    try {
      final analysis = ProductAnalysis.fromApi(data);
      if (analysis.id != id) throw const FormatException();
      return analysis;
    } catch (_) {
      throw const ApiFailure(
        'No se pudo interpretar el análisis del producto.',
      );
    }
  }

  Future<List<({int id, String name})>> loadAnalysisProducts() async {
    final data = await _get('/productos/');
    try {
      final rows = (data['productos'] as List<dynamic>)
          .map(
            (row) =>
                (id: row['idProducto'] as int, name: row['nombre'] as String),
          )
          .toList();
      rows.sort((a, b) => searchable(a.name).compareTo(searchable(b.name)));
      return rows;
    } catch (_) {
      throw const ApiFailure('No se pudo cargar la búsqueda de productos.');
    }
  }

  Future<List<Recommendation>> loadRecommendations() async {
    final data = await _get('/recomendaciones/');
    try {
      final rows = (data['recomendaciones'] as List<dynamic>)
          .map((row) => Recommendation.fromApi(row as Map<String, dynamic>))
          .toList();
      rows.sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date == 0 ? b.id.compareTo(a.id) : date;
      });
      return rows;
    } catch (_) {
      throw const ApiFailure(
        'No se pudo interpretar el historial de recomendaciones.',
      );
    }
  }

  Future<int> generateRecommendations(int userId) async {
    if (userId <= 0) {
      throw const ApiFailure('Iniciá sesión para generar recomendaciones.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/recomendaciones/generar'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'idUsuario': userId}),
          )
          .timeout(const Duration(seconds: 30));
      _checkRecommendationResponse(response.statusCode);
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rows = data['recomendaciones'] as List<dynamic>;
      if (data['cantidad'] is! int || data['cantidad'] != rows.length) {
        throw const FormatException();
      }
      final ids = <int>{};
      for (final row in rows) {
        final item = row as Map<String, dynamic>;
        final id = dashboardCount(item['idRecomendacion']);
        if (id == 0 ||
            !ids.add(id) ||
            dashboardCount(item['idProducto']) == 0 ||
            dashboardCount(item['cantidadSugerida']) == 0 ||
            item['estado'] != 'Pendiente' ||
            item['motivo'] is! String ||
            item['nombreProducto'] is! String) {
          throw const FormatException();
        }
      }
      return rows.length;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar la generación. Actualizá el historial antes de intentar generar otra vez.',
        mayHaveSaved: true,
      );
    }
  }

  Future<Recommendation> decideRecommendation(
    Recommendation current,
    int userId,
    String status,
  ) async {
    if (userId <= 0 ||
        !current.pending ||
        !['Aceptada', 'Rechazada'].contains(status)) {
      throw const ApiFailure(
        'Revisá el usuario y el estado de la recomendación.',
      );
    }
    try {
      final response = await _client
          .patch(
            Uri.parse('$baseUrl/recomendaciones/${current.id}/decision'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'idUsuario': userId, 'estado': status}),
          )
          .timeout(const Duration(seconds: 20));
      _checkRecommendationResponse(response.statusCode);
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final saved = data['recomendacion'] as Map<String, dynamic>;
      if (saved['idRecomendacion'] != current.id ||
          saved['idProducto'] != current.productId ||
          saved['cantidadSugerida'] != current.units ||
          saved['estado'] != status ||
          data['stockModificado'] != false) {
        throw const FormatException();
      }
      return current.withStatus(status);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar la decisión. Actualizá el historial y revisá el estado antes de repetirla.',
        mayHaveSaved: true,
      );
    }
  }

  void _checkRecommendationResponse(int status) {
    if (status == 403) {
      throw const ApiFailure(
        'Tu usuario no tiene permiso para realizar esta operación.',
      );
    }
    if (status == 404 || status == 409) {
      throw const ApiFailure(
        'El usuario o la recomendación ya no están disponibles para esta operación, o la decisión ya fue registrada. Se actualizará el historial.',
        requiresRefresh: true,
      );
    }
    if (status == 422) {
      throw const ApiFailure(
        'El servicio rechazó los datos de la recomendación. Revisá la sesión y el estado.',
      );
    }
    if (status < 200 || status >= 300) {
      throw ApiFailure(
        'El servicio no confirmó la operación. Actualizá el historial antes de repetirla.',
        mayHaveSaved: status >= 500,
      );
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ApiFailure('Email o contraseña incorrectos.');
      }
      if (response.statusCode == 429) {
        throw const ApiFailure(
          'Demasiados intentos. Esperá un minuto e intentá nuevamente.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ApiFailure(
          'No se pudo iniciar sesión. Intentá nuevamente.',
        );
      }
      if (_closed) return;
      session.value = AuthSession.fromApi(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos conectar para iniciar sesión. Intentá nuevamente.',
      );
    }
  }

  Future<void> changeOwnPassword(
    String current,
    String password,
    String confirmation,
  ) async {
    final token = session.value?.token;
    if (token == null) {
      throw const ApiFailure('Iniciá sesión para cambiar tu contraseña.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/auth/password'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'passwordActual': current,
              'password': password,
              'confirmacion': confirmation,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final detail = data['detail'];
        throw ApiFailure(
          detail is String ? detail : 'No se pudo cambiar la contraseña.',
          mayHaveSaved: response.statusCode >= 500,
        );
      }
      if (data['passwordActualizada'] != true ||
          data['sesionesCerradas'] != true) {
        throw const FormatException();
      }
      // Una respuesta tardía no debe cerrar un nuevo ingreso que la reemplazó.
      if (!_closed && session.value?.token == token) {
        session.value = null;
      }
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'No pudimos confirmar el cambio. Volvé a ingresar antes de reintentarlo.',
        mayHaveSaved: true,
      );
    }
  }

  Future<void> logout() async {
    if (_closed) return;
    final token = session.value?.token;
    session.value = null;
    if (token == null) return;
    try {
      await _transport
          .post(
            Uri.parse('$baseUrl/auth/logout'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      /* El token local ya se quitó; el remoto también tiene vencimiento. */
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _alertUpdates?.stop();
    session.removeListener(_sessionChanged);
    alerts.dispose();
    _client.close();
    session.dispose();
  }
}
