/// LAN server service — Ollama-compatible HTTP API server.
///
/// Exposes the on-device LLM via the standard Ollama REST API so that any
/// tool on the local network (VS Code Cline, Continue, Open WebUI, curl, etc.)
/// can use the phone as a drop-in replacement for `ollama serve`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/network_access/services/model_name_resolver.dart';
import 'package:local_ai_chat/features/network_access/services/ollama_api_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LanServerService {
  final ModelRuntimeService _runtime;
  final ModelNameResolver _nameResolver;
  late final OllamaApiHandler _ollamaHandler;

  HttpServer? _server;
  String _authToken = '';
  bool _isRunning = false;
  bool _requireAuth = false;
  bool _showWebUI = true;
  bool _keepScreenOn = false;
  String? _cachedWebUI;

  bool get isRunning => _isRunning;
  String get authToken => _authToken;
  bool get requireAuth => _requireAuth;

  String? get address =>
      _server != null ? '${_server!.address.address}:${_server!.port}' : null;

  int? get port => _server?.port;

  /// Exposes the Ollama handler for monitoring (e.g. client count).
  OllamaApiHandler get ollamaHandler => _ollamaHandler;

  LanServerService(this._runtime, this._nameResolver) {
    _ollamaHandler = OllamaApiHandler(_runtime, _nameResolver);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts the Ollama-compatible LAN server on the given port.
  ///
  /// Default port is 11434 (same as Ollama) so tools work with zero config.
  Future<void> start({
    int port = 11434,
    String? token,
    bool requireAuth = false,
    bool showWebUI = true,
    bool keepScreenOn = false,
  }) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(
          port, 'port', 'Port must be between 1 and 65535');
    }
    if (_isRunning) return;

    _requireAuth = requireAuth;
    _showWebUI = showWebUI;
    _keepScreenOn = keepScreenOn;

    final resolvedToken = token?.trim();
    if (resolvedToken != null && resolvedToken.isNotEmpty) {
      _authToken = resolvedToken;
    } else if (_authToken.isEmpty) {
      _authToken = const Uuid().v4();
    }

    // Build the handler using Pipeline — no double-routing.
    // The OllamaApiHandler router handles all API path matching directly.
    // We only add CORS and auth as middleware layers on top.
    final apiHandler = _ollamaHandler.router.call;

    // Compose: CORS → log → auth → (webUI catch or API handler)
    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests())
        .addMiddleware(_authMiddleware())
        .addHandler(_showWebUI ? _withWebUI(apiHandler) : apiHandler);

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
      );
      _isRunning = true;
      if (_keepScreenOn) {
        WakelockPlus.enable();
      }
      print('Ollama-compatible server running on 0.0.0.0:$port');
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
      WakelockPlus.disable();
    }
  }

  /// Regenerates the auth token.
  String regenerateToken() {
    _authToken = const Uuid().v4();
    return _authToken;
  }

  // ---------------------------------------------------------------------------
  // CORS Middleware
  // ---------------------------------------------------------------------------

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS, HEAD',
    'Access-Control-Allow-Headers':
        'Content-Type, Authorization, Accept, X-Requested-With',
    'Access-Control-Max-Age': '86400',
  };

  Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        // Handle preflight
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  // ---------------------------------------------------------------------------
  // Auth Middleware
  // ---------------------------------------------------------------------------

  /// Middleware that enforces Bearer token auth when [_requireAuth] is true.
  ///
  /// When auth is disabled (default, Ollama-compatible) all requests pass.
  /// Web UI (`/`) and liveness checks are always exempt from auth so the
  /// browser can load the page without a token.
  Middleware _authMiddleware() {
    return (Handler inner) {
      return (Request request) {
        if (!_requireAuth) return inner(request);

        // Exempt web UI root and OPTIONS (preflight already handled above)
        final path = request.requestedUri.path;
        if (path == '/' || path.isEmpty) return inner(request);

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
    };
  }

  // ---------------------------------------------------------------------------
  // Web UI Handler
  // ---------------------------------------------------------------------------

  /// Wraps the API handler so that `GET /` serves the web UI HTML instead
  /// of the Ollama liveness text. All other paths fall through to the API.
  Handler _withWebUI(Handler apiHandler) {
    return (Request request) async {
      // Serve web UI for the root path (GET only)
      if (request.method == 'GET' && request.requestedUri.path == '/') {
        return _serveWebUI(request);
      }
      // Everything else goes to the Ollama API handler
      return apiHandler(request);
    };
  }

  Future<Response> _serveWebUI(Request request) async {
    try {
      _cachedWebUI ??=
          await rootBundle.loadString('assets/web_ui/index.html');
      return Response.ok(
        _cachedWebUI,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    } catch (e) {
      // Fallback: if asset not found, return liveness text
      return Response.ok(
        'Ollama is running (A.I.R.I). Web UI not available: $e',
        headers: {'content-type': 'text/plain'},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Network utilities
  // ---------------------------------------------------------------------------

  /// Returns the device's LAN IPv4 address, or null if unavailable.
  static Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
