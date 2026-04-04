/// LAN server service — shelf-based local HTTP API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:uuid/uuid.dart';

class LanServerService {
  final ModelRuntimeService _runtime;

  HttpServer? _server;
  String _authToken = '';
  bool _isRunning = false;
  bool _chatInFlight = false;

  bool get isRunning => _isRunning;
  String get authToken => _authToken;
  String? get address =>
      _server != null ? '${_server!.address.address}:${_server!.port}' : null;

  LanServerService(this._runtime);

  /// Starts the LAN server on the given port.
  Future<void> start({
    int port = 8080,
    String? token,
    InternetAddress? bindAddress,
    bool exposeToLan = false,
  }) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(
          port, 'port', 'Port must be between 1 and 65535');
    }
    if (_isRunning) return;

    final resolvedToken = token?.trim();
    if (resolvedToken != null && resolvedToken.isNotEmpty) {
      _authToken = resolvedToken;
    } else if (_authToken.isEmpty) {
      _authToken = const Uuid().v4();
    }

    final router = Router()
      ..get('/health', _healthHandler)
      ..get('/model/info', _authMiddleware(_modelInfoHandler))
      ..post('/chat', _authMiddleware(_chatHandler));

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    final host = bindAddress ??
        (exposeToLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4);

    try {
      _server = await shelf_io.serve(handler, host, port);
      _isRunning = true;
    } catch (_) {
      _server = null;
      _isRunning = false;
      rethrow;
    }
  }

  /// Stops the LAN server.
  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } finally {
      _server = null;
      _isRunning = false;
      _chatInFlight = false;
    }
  }

  /// Regenerates the auth token.
  String regenerateToken() {
    _authToken = const Uuid().v4();
    return _authToken;
  }

  // ---------------------------------------------------------------------------
  // Middleware
  // ---------------------------------------------------------------------------

  Handler _authMiddleware(Handler inner) {
    return (Request request) {
      final authHeader = request.headers['authorization'];
      if (_authToken.isEmpty ||
          authHeader == null ||
          authHeader != 'Bearer $_authToken') {
        return Response.forbidden(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return inner(request);
    };
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Response _healthHandler(Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'modelLoaded': _runtime.isLoaded,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _modelInfoHandler(Request request) {
    return Response.ok(
      jsonEncode({
        'modelLoaded': _runtime.isLoaded,
        'modelPath': _runtime.currentModelPath,
        'capabilities': _runtime.capability.toMap(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _chatHandler(Request request) async {
    if (!_runtime.isLoaded) {
      return Response(503,
          body: jsonEncode({'error': 'No model loaded'}),
          headers: {'content-type': 'application/json'});
    }
    if (_chatInFlight) {
      return Response(
        429,
        body: jsonEncode({'error': 'Model is busy'}),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      _chatInFlight = true;
      final body = await request.readAsString();
      if (body.length > 256 * 1024) {
        return Response(
          413,
          body: jsonEncode({'error': 'Request body too large'}),
          headers: {'content-type': 'application/json'},
        );
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final prompt = (data['prompt'] as String?)?.trim();

      if (prompt == null || prompt.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing prompt field'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final buffer = StringBuffer();
      final stream = _runtime.generateStream(prompt);
      await for (final token in stream.timeout(const Duration(minutes: 2))) {
        buffer.write(token);
      }

      return Response.ok(
        jsonEncode({'response': buffer.toString()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    } finally {
      _chatInFlight = false;
    }
  }
}
