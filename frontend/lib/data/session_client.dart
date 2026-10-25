import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/auth_session.dart';

class SessionClient extends http.BaseClient {
  SessionClient(this.inner, this.session);
  final http.Client inner;
  final ValueNotifier<AuthSession?> session;
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = session.value?.token;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await inner.send(request);
    // Una respuesta vieja no invalida una sesión nueva que ya la reemplazó.
    if (!_closed &&
        response.statusCode == 401 &&
        token != null &&
        session.value?.token == token) {
      session.value = null;
    }
    return response;
  }

  @override
  void close() {
    _closed = true;
    inner.close();
  }
}
