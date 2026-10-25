import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Observa señales SSE; no transporta datos ni modifica el inventario.
class AlertUpdates {
  AlertUpdates({
    required this.baseUrl,
    required this.onUpdate,
    required this.onSessionExpired,
    http.Client Function()? clientFactory,
    this.retryDelay = const Duration(seconds: 1),
    this.coalesceDelay = const Duration(milliseconds: 180),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String baseUrl;
  final void Function() onUpdate;
  final void Function(String token) onSessionExpired;
  final http.Client Function() _clientFactory;
  final Duration retryDelay;
  final Duration coalesceDelay;
  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Completer<void>? _abort;
  Timer? _retry;
  Timer? _signal;
  String? _token;
  String? _event;
  int _generation = 0;
  int _attempts = 0;

  void start(String token) {
    stop();
    _token = token;
    _connect(_generation);
  }

  void stop() {
    ++_generation;
    _token = null;
    _retry?.cancel();
    _signal?.cancel();
    _retry = null;
    _signal = null;
    _attempts = 0;
    _disconnect();
  }

  void _disconnect() {
    _event = null;
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    _client?.close();
    _client = null;
  }

  Future<void> _connect(int generation) async {
    final token = _token;
    if (token == null || generation != _generation) return;
    final client = _clientFactory();
    _client = client;
    final abort = Completer<void>();
    _abort = abort;
    try {
      final request =
          http.AbortableRequest(
              'GET',
              Uri.parse('$baseUrl/eventos/alertas'),
              abortTrigger: abort.future,
            )
            ..headers.addAll({
              'Accept': 'text/event-stream',
              'Authorization': 'Bearer $token',
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (generation != _generation) {
        unawaited(response.stream.listen((_) {}).cancel());
        return;
      }
      if (response.statusCode == 401) {
        stop();
        onSessionExpired(token);
        return;
      }
      if (response.statusCode == 403) {
        stop();
        return;
      }
      if (response.statusCode != 200 ||
          !response.headers['content-type'].toString().contains(
            'text/event-stream',
          )) {
        throw const FormatException('El flujo de alertas no está disponible.');
      }
      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45))
          .listen(
            (line) => _line(line, generation),
            onError: (Object _) => _reconnect(generation),
            onDone: () => _reconnect(generation),
            cancelOnError: true,
          );
    } catch (_) {
      _reconnect(generation);
    }
  }

  void _line(String line, int generation) {
    if (generation != _generation) return;
    if (line.startsWith('event:')) {
      _event = line.substring(6).trim();
    } else if (line.isEmpty) {
      final event = _event;
      _event = null;
      if (event == 'actualizar') {
        _attempts = 0;
        // Agrupar sin posponer indefinidamente una ráfaga de señales.
        _signal ??= Timer(coalesceDelay, () {
          _signal = null;
          if (generation == _generation) onUpdate();
        });
      } else if (event == 'sesion_expirada') {
        final token = _token!;
        stop();
        onSessionExpired(token);
      } else if (event == 'reconectar') {
        _reconnect(generation);
      }
    }
  }

  void _reconnect(int generation) {
    if (generation != _generation || _token == null || _retry != null) return;
    _disconnect();
    final factor = 1 << _attempts.clamp(0, 5);
    ++_attempts;
    _retry = Timer(retryDelay * factor, () {
      _retry = null;
      _connect(generation);
    });
  }
}
