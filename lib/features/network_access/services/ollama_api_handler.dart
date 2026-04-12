/// Ollama-compatible API handler — implements the Ollama REST API so that
/// tools like VS Code Cline, Continue, Open WebUI, and LangChain can use
/// the on-device LLM as a drop-in replacement for `ollama serve`.
///
/// Also provides OpenAI-compatible endpoints (`/v1/chat/completions`,
/// `/v1/models`) for broader tool support.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/network_access/services/chat_template_formatter.dart';
import 'package:local_ai_chat/features/network_access/services/model_name_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

/// Version string reported by `/api/version`.
const String _serverVersion = '0.5.0';

class OllamaApiHandler {
  final ModelRuntimeService _runtime;
  final ModelNameResolver _nameResolver;

  /// Tracks whether a generation is currently in-flight (serialised inference).
  bool _inferenceInFlight = false;

  /// Queue of waiters for the inference lock. When inference finishes, the
  /// next waiter in line is completed so it can proceed.
  final Queue<Completer<void>> _inferenceQueue = Queue<Completer<void>>();

  /// Whether an external client request is currently generating tokens.
  bool get inferenceInFlight => _inferenceInFlight;

  /// Tracks server start time for uptime reporting.
  final DateTime _startedAt = DateTime.now();

  /// Track connected client IPs for monitoring.
  final Set<String> _recentClients = {};

  int get recentClientCount => _recentClients.length;
  Set<String> get recentClients => Set.unmodifiable(_recentClients);

  OllamaApiHandler(this._runtime, this._nameResolver);

  // ---------------------------------------------------------------------------
  // Inference lock helpers
  // ---------------------------------------------------------------------------

  /// Acquire the inference lock.  If the lock is free, returns immediately.
  /// If another generation is in-flight, waits up to [timeout] for it to
  /// finish.  Returns `true` if the lock was acquired, `false` on timeout.
  Future<bool> _acquireInference({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_inferenceInFlight) {
      _inferenceInFlight = true;
      return true;
    }

    // Already busy — enqueue ourselves and wait.
    final completer = Completer<void>();
    _inferenceQueue.add(completer);

    try {
      await completer.future.timeout(timeout);
      // When we're completed, _releaseInference already set us as the owner.
      return true;
    } on TimeoutException {
      // Remove ourselves from the queue if we timed out.
      _inferenceQueue.remove(completer);
      return false;
    }
  }

  /// Release the inference lock and hand it to the next waiter, if any.
  void _releaseInference() {
    if (_inferenceQueue.isNotEmpty) {
      // Hand the lock directly to the next waiter — keep _inferenceInFlight
      // true so no one else can sneak in.
      final next = _inferenceQueue.removeFirst();
      // Complete on the next microtask so the caller's finally block finishes
      // before the next request starts generating.
      scheduleMicrotask(() => next.complete());
    } else {
      _inferenceInFlight = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Router
  // ---------------------------------------------------------------------------

  Router get router {
    final r = Router();

    // Root — Ollama liveness check
    r.get('/', _rootHandler);
    r.head('/', _rootHandler);

    // Ollama API
    r.get('/api/tags', _tagsHandler);
    r.get('/api/ps', _psHandler);
    r.get('/api/version', _versionHandler);
    r.post('/api/show', _showHandler);
    r.post('/api/generate', _generateHandler);
    r.post('/api/chat', _chatHandler);

    // Model management (custom — lets the web UI load/unload models)
    r.post('/api/load', _loadHandler);
    r.post('/api/unload', _unloadHandler);

    // Custom health endpoint
    r.get('/api/health', _healthHandler);

    // OpenAI-compatible endpoints
    r.get('/v1/models', _openaiModelsHandler);
    r.post('/v1/chat/completions', _openaiChatCompletionsHandler);

    return r;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<List<LocalModelInfo>> _listModels() async {
    final dir = await getApplicationDocumentsDirectory();
    return _nameResolver.scanModels(dir.path);
  }

  String _currentModelOllamaName() {
    final path = _runtime.currentModelPath;
    if (path == null) return 'unknown';
    final baseName = p.basenameWithoutExtension(path);
    // Quick re-derive name; for loaded model we just do a lightweight parse
    final models = _nameResolver.scanModels(p.dirname(path));
    for (final m in models) {
      if (m.filePath == path) return m.ollamaName;
    }
    return baseName.toLowerCase();
  }

  GenerationParams _paramsFromOptions(Map<String, dynamic>? options) {
    if (options == null) return const GenerationParams(maxTokens: 512);
    return GenerationParams(
      maxTokens: (options['num_predict'] as int?) ?? 512,
      temp: (options['temperature'] as num?)?.toDouble() ?? 0.8,
      topK: (options['top_k'] as int?) ?? 40,
      topP: (options['top_p'] as num?)?.toDouble() ?? 0.9,
      penalty: (options['repeat_penalty'] as num?)?.toDouble() ?? 1.1,
      seed: options['seed'] as int?,
    );
  }

  GenerationParams _paramsFromOpenAI(Map<String, dynamic> body) {
    return GenerationParams(
      maxTokens: (body['max_tokens'] as int?) ?? 512,
      temp: (body['temperature'] as num?)?.toDouble() ?? 0.8,
      topK: (body['top_k'] as int?) ?? 40,
      topP: (body['top_p'] as num?)?.toDouble() ?? 0.9,
      seed: body['seed'] as int?,
    );
  }

  void _trackClient(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    final ip = forwarded ?? request.headers['host'] ?? 'unknown';
    _recentClients.add(ip.split(':').first);
  }

  Response _jsonResponse(Object body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _errorResponse(int statusCode, String message) {
    return _jsonResponse({'error': message}, statusCode: statusCode);
  }

  /// Logs detailed request info for debugging ghost/unexpected requests.
  void _logRequestDetails(Request request, String endpoint) {
    final ip = request.headers['x-forwarded-for'] ??
        request.headers['x-real-ip'] ??
        '(direct)';
    final ua = request.headers['user-agent'] ?? '(no user-agent)';
    final cl = request.headers['content-length'] ?? '?';
    print('[$endpoint] client=$ip  ua=$ua  content-length=$cl');
  }

  // ---------------------------------------------------------------------------
  // Root / Liveness
  // ---------------------------------------------------------------------------

  Response _rootHandler(Request request) {
    _trackClient(request);
    return Response.ok('Ollama is running');
  }

  // ---------------------------------------------------------------------------
  // GET /api/tags
  // ---------------------------------------------------------------------------

  Future<Response> _tagsHandler(Request request) async {
    _trackClient(request);
    final models = await _listModels();
    return _jsonResponse({
      'models': models.map((m) => m.toOllamaTagEntry()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // GET /api/ps
  // ---------------------------------------------------------------------------

  Future<Response> _psHandler(Request request) async {
    _trackClient(request);
    if (!_runtime.isLoaded) {
      return _jsonResponse({'models': []});
    }

    final models = await _listModels();
    final loaded = models.where(
      (m) => m.filePath == _runtime.currentModelPath,
    );

    return _jsonResponse({
      'models': loaded.map((m) {
        final entry = m.toOllamaTagEntry();
        entry['expires_at'] =
            DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();
        entry['size_vram'] = m.sizeBytes;
        return entry;
      }).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // GET /api/version
  // ---------------------------------------------------------------------------

  Response _versionHandler(Request request) {
    _trackClient(request);
    return _jsonResponse({'version': _serverVersion});
  }

  // ---------------------------------------------------------------------------
  // GET /api/health (custom)
  // ---------------------------------------------------------------------------

  Response _healthHandler(Request request) {
    _trackClient(request);
    final uptime = DateTime.now().difference(_startedAt);
    return _jsonResponse({
      'status': 'ok',
      'model_loaded': _runtime.isLoaded,
      'inference_active': _inferenceInFlight,
      'uptime_seconds': uptime.inSeconds,
      'connected_clients': _recentClients.length,
    });
  }

  // ---------------------------------------------------------------------------
  // POST /api/load
  // ---------------------------------------------------------------------------

  Future<Response> _loadHandler(Request request) async {
    _trackClient(request);
    if (_inferenceInFlight) {
      return _errorResponse(429, 'Model is busy processing a request. Try again shortly.');
    }

    final rawBody = await request.readAsString();
    final body = jsonDecode(rawBody) as Map<String, dynamic>;
    final modelName = (body['model'] as String?)?.trim() ?? '';
    if (modelName.isEmpty) return _errorResponse(400, 'Missing model field');

    final models = await _listModels();
    final found = _nameResolver.findByName(models, modelName);
    if (found == null) return _errorResponse(404, 'model "$modelName" not found');

    // Already loaded?
    if (_runtime.isLoaded && _runtime.currentModelPath == found.filePath) {
      return _jsonResponse({
        'status': 'ok',
        'message': 'Model already loaded',
        'model': modelName,
      });
    }

    // Extract optional parameters
    final nCtx = (body['n_ctx'] as int?) ?? 2048;
    final nBatch = (body['n_batch'] as int?) ?? 512;
    final nPredict = (body['n_predict'] as int?) ?? 512;

    try {
      await _runtime.loadModel(
        found.filePath,
        nCtx: nCtx,
        nBatch: nBatch,
        nPredict: nPredict,
      );
      return _jsonResponse({
        'status': 'ok',
        'message': 'Model loaded successfully',
        'model': modelName,
      });
    } catch (e) {
      return _errorResponse(500, 'Failed to load model: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // POST /api/unload
  // ---------------------------------------------------------------------------

  Future<Response> _unloadHandler(Request request) async {
    _trackClient(request);
    if (_inferenceInFlight) {
      return _errorResponse(429, 'Model is busy processing a request. Try again shortly.');
    }

    try {
      await _runtime.dispose();
      return _jsonResponse({
        'status': 'ok',
        'message': 'Model unloaded',
      });
    } catch (e) {
      return _errorResponse(500, 'Failed to unload model: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // POST /api/show
  // ---------------------------------------------------------------------------

  Future<Response> _showHandler(Request request) async {
    _trackClient(request);
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final modelName = (body['model'] as String?)?.trim() ?? '';
    if (modelName.isEmpty) return _errorResponse(400, 'Missing model field');

    final models = await _listModels();
    final found = _nameResolver.findByName(models, modelName);
    if (found == null) return _errorResponse(404, 'model "$modelName" not found');

    return _jsonResponse({
      'modelfile': 'FROM ${found.filePath}',
      'parameters': 'num_ctx ${_runtime.resolvedContextSize}',
      'template': '<|im_start|>system\n{{ .System }}<|im_end|>\n<|im_start|>user\n{{ .Prompt }}<|im_end|>\n<|im_start|>assistant',
      'details': {
        'parent_model': '',
        'format': 'gguf',
        'family': found.family,
        'parameter_size': found.parameterSize,
        'quantization_level': found.quantizationLevel,
      },
      'model_info': {
        'general.file_type': found.quantizationLevel,
        'general.parameter_count': found.parameterSize,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // POST /api/generate
  // ---------------------------------------------------------------------------

  Future<Response> _generateHandler(Request request) async {
    _trackClient(request);
    _logRequestDetails(request, '/api/generate');
    if (!_runtime.isLoaded) {
      return _errorResponse(503, 'No model loaded. Load a model in the A.I.R.I app first.');
    }

    // Wait for the inference lock (queues behind any in-flight generation).
    final acquired = await _acquireInference();
    if (!acquired) {
      return _errorResponse(429, 'Model is busy and the request timed out. Try again shortly.');
    }

    try {
      final rawBody = await request.readAsString();
      if (rawBody.length > 512 * 1024) {
        _releaseInference();
        return _errorResponse(413, 'Request body too large');
      }

      final body = jsonDecode(rawBody) as Map<String, dynamic>;
      final prompt = (body['prompt'] as String?)?.trim();
      final system = (body['system'] as String?)?.trim();
      final stream = body['stream'] as bool? ?? true;
      final options = body['options'] as Map<String, dynamic>?;

      if (prompt == null || prompt.isEmpty) {
        _releaseInference();
        return _errorResponse(400, 'Missing prompt field');
      }

      final formattedPrompt = formatRawPrompt(prompt, system: system);
      final params = _paramsFromOptions(options);
      final modelName = _currentModelOllamaName();

      if (!stream) {
        return _generateNonStreaming(formattedPrompt, params, modelName);
      }

      return _generateStreaming(formattedPrompt, params, modelName);
    } catch (e) {
      _releaseInference();
      return _errorResponse(500, 'Internal error: $e');
    }
  }

  Future<Response> _generateNonStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
  ) async {
    // _inferenceInFlight already set by _generateHandler
    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    int tokenCount = 0;

    try {
      final tokenStream = _runtime.generateStream(prompt, generationParams: params);
      await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
        buffer.write(token);
        tokenCount++;
      }
      stopwatch.stop();

      return _jsonResponse({
        'model': modelName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'response': buffer.toString(),
        'done': true,
        'done_reason': 'stop',
        'total_duration': stopwatch.elapsedMicroseconds * 1000, // ns
        'eval_count': tokenCount,
        'eval_duration': stopwatch.elapsedMicroseconds * 1000,
      });
    } catch (e) {
      return _errorResponse(500, e.toString());
    } finally {
      _releaseInference();
    }
  }

  Response _generateStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
  ) {
    // _inferenceInFlight already set by _generateHandler
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    final streamController = StreamController<List<int>>();

    /// Safe emit — silently drops writes if the stream is already closed.
    void emitJson(Map<String, dynamic> obj) {
      if (streamController.isClosed) return;
      try {
        streamController.add(utf8.encode('${jsonEncode(obj)}\n'));
      } catch (_) {
        // Client disconnected — ignore.
      }
    }

    () async {
      try {
        final tokenStream = _runtime.generateStream(prompt, generationParams: params);
        await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
          tokenCount++;
          emitJson({
            'model': modelName,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'response': token,
            'done': false,
          });
        }
      } catch (e) {
        emitJson({
          'model': modelName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'response': '',
          'done': true,
          'error': e.toString(),
        });
      } finally {
        stopwatch.stop();
        emitJson({
          'model': modelName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'response': '',
          'done': true,
          'done_reason': 'stop',
          'total_duration': stopwatch.elapsedMicroseconds * 1000,
          'eval_count': tokenCount,
          'eval_duration': stopwatch.elapsedMicroseconds * 1000,
        });
        // Always release the lock before closing the stream.
        _releaseInference();
        try {
          await streamController.close();
        } catch (_) {}
      }
    }();

    return Response.ok(
      streamController.stream,
      headers: {'content-type': 'application/x-ndjson'},
      context: {'shelf.io.buffer_output': false},
    );
  }

  // ---------------------------------------------------------------------------
  // POST /api/chat
  // ---------------------------------------------------------------------------

  Future<Response> _chatHandler(Request request) async {
    _trackClient(request);
    _logRequestDetails(request, '/api/chat');
    if (!_runtime.isLoaded) {
      return _errorResponse(503, 'No model loaded. Load a model in the A.I.R.I app first.');
    }

    // Wait for the inference lock (queues behind any in-flight generation).
    final acquired = await _acquireInference();
    if (!acquired) {
      return _errorResponse(429, 'Model is busy and the request timed out. Try again shortly.');
    }

    try {
      final rawBody = await request.readAsString();
      if (rawBody.length > 512 * 1024) {
        _releaseInference();
        return _errorResponse(413, 'Request body too large');
      }

      final body = jsonDecode(rawBody) as Map<String, dynamic>;
      final messages = (body['messages'] as List<dynamic>?)
          ?.map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final stream = body['stream'] as bool? ?? true;
      final options = body['options'] as Map<String, dynamic>?;

      if (messages == null || messages.isEmpty) {
        _releaseInference();
        return _errorResponse(400, 'Missing or empty messages array');
      }

      final formattedPrompt = formatChatMessages(messages);
      final params = _paramsFromOptions(options);
      final modelName = _currentModelOllamaName();

      if (!stream) {
        return _chatNonStreaming(formattedPrompt, params, modelName);
      }

      return _chatStreaming(formattedPrompt, params, modelName);
    } catch (e) {
      _releaseInference();
      return _errorResponse(500, 'Internal error: $e');
    }
  }

  Future<Response> _chatNonStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
  ) async {
    // _inferenceInFlight already set by _chatHandler
    final stopwatch = Stopwatch()..start();
    final buffer = StringBuffer();
    int tokenCount = 0;

    try {
      final tokenStream = _runtime.generateStream(prompt, generationParams: params);
      await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
        buffer.write(token);
        tokenCount++;
      }
      stopwatch.stop();

      return _jsonResponse({
        'model': modelName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'message': {
          'role': 'assistant',
          'content': buffer.toString(),
        },
        'done': true,
        'done_reason': 'stop',
        'total_duration': stopwatch.elapsedMicroseconds * 1000,
        'eval_count': tokenCount,
        'eval_duration': stopwatch.elapsedMicroseconds * 1000,
      });
    } catch (e) {
      return _errorResponse(500, e.toString());
    } finally {
      _releaseInference();
    }
  }

  Response _chatStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
  ) {
    // _inferenceInFlight already set by _chatHandler
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    final streamController = StreamController<List<int>>();

    /// Safe emit — silently drops writes if the stream is already closed.
    void emitJson(Map<String, dynamic> obj) {
      if (streamController.isClosed) return;
      try {
        streamController.add(utf8.encode('${jsonEncode(obj)}\n'));
      } catch (_) {
        // Client disconnected — ignore.
      }
    }

    () async {
      try {
        final tokenStream = _runtime.generateStream(prompt, generationParams: params);
        await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
          tokenCount++;
          emitJson({
            'model': modelName,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'message': {'role': 'assistant', 'content': token},
            'done': false,
          });
        }
      } catch (e) {
        emitJson({
          'model': modelName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'error': e.toString(),
        });
      } finally {
        stopwatch.stop();
        emitJson({
          'model': modelName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'done_reason': 'stop',
          'total_duration': stopwatch.elapsedMicroseconds * 1000,
          'eval_count': tokenCount,
          'eval_duration': stopwatch.elapsedMicroseconds * 1000,
        });
        // Always release the lock before closing the stream.
        _releaseInference();
        try {
          await streamController.close();
        } catch (_) {}
      }
    }();

    return Response.ok(
      streamController.stream,
      headers: {'content-type': 'application/x-ndjson'},
      context: {'shelf.io.buffer_output': false},
    );
  }

  // ---------------------------------------------------------------------------
  // GET /v1/models  (OpenAI-compatible)
  // ---------------------------------------------------------------------------

  Future<Response> _openaiModelsHandler(Request request) async {
    _trackClient(request);
    final models = await _listModels();
    return _jsonResponse({
      'object': 'list',
      'data': models.map((m) => m.toOpenAIModelEntry()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // POST /v1/chat/completions  (OpenAI-compatible)
  // ---------------------------------------------------------------------------

  Future<Response> _openaiChatCompletionsHandler(Request request) async {
    _trackClient(request);
    _logRequestDetails(request, '/v1/chat/completions');
    if (!_runtime.isLoaded) {
      return _errorResponse(503, 'No model loaded. Load a model in the A.I.R.I app first.');
    }

    // Wait for the inference lock (queues behind any in-flight generation).
    final acquired = await _acquireInference();
    if (!acquired) {
      return _errorResponse(429, 'Model is busy and the request timed out. Try again shortly.');
    }

    try {
      final rawBody = await request.readAsString();
      if (rawBody.length > 512 * 1024) {
        _releaseInference();
        return _errorResponse(413, 'Request body too large');
      }

      final body = jsonDecode(rawBody) as Map<String, dynamic>;
      final messages = (body['messages'] as List<dynamic>?)
          ?.map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final stream = body['stream'] as bool? ?? false;

      if (messages == null || messages.isEmpty) {
        _releaseInference();
        return _errorResponse(400, 'Missing or empty messages array');
      }

      final formattedPrompt = formatChatMessages(messages);
      final params = _paramsFromOpenAI(body);
      final modelName = _currentModelOllamaName();
      final requestId = 'chatcmpl-${const Uuid().v4().substring(0, 12)}';
      final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (!stream) {
        return _openaiChatNonStreaming(
          formattedPrompt, params, modelName, requestId, created,
        );
      }

      return _openaiChatStreaming(
        formattedPrompt, params, modelName, requestId, created,
      );
    } catch (e) {
      _releaseInference();
      return _errorResponse(500, 'Internal error: $e');
    }
  }

  Future<Response> _openaiChatNonStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
    String requestId,
    int created,
  ) async {
    // _inferenceInFlight already set by _openaiChatCompletionsHandler
    final buffer = StringBuffer();
    int tokenCount = 0;

    try {
      final tokenStream = _runtime.generateStream(prompt, generationParams: params);
      await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
        buffer.write(token);
        tokenCount++;
      }

      return _jsonResponse({
        'id': requestId,
        'object': 'chat.completion',
        'created': created,
        'model': modelName,
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': buffer.toString(),
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 0,
          'completion_tokens': tokenCount,
          'total_tokens': tokenCount,
        },
      });
    } catch (e) {
      return _errorResponse(500, e.toString());
    } finally {
      _releaseInference();
    }
  }

  Response _openaiChatStreaming(
    String prompt,
    GenerationParams params,
    String modelName,
    String requestId,
    int created,
  ) {
    // _inferenceInFlight already set by _openaiChatCompletionsHandler
    bool isFirst = true;

    final streamController = StreamController<List<int>>();

    /// Safe emit — silently drops writes if the stream is already closed.
    void emitSSE(Map<String, dynamic> obj) {
      if (streamController.isClosed) return;
      try {
        streamController.add(utf8.encode('data: ${jsonEncode(obj)}\n\n'));
      } catch (_) {
        // Client disconnected — ignore.
      }
    }

    () async {
      try {
        final tokenStream = _runtime.generateStream(prompt, generationParams: params);
        await for (final token in tokenStream.timeout(const Duration(minutes: 5))) {
          final delta = <String, dynamic>{'content': token};
          if (isFirst) {
            delta['role'] = 'assistant';
            isFirst = false;
          }

          emitSSE({
            'id': requestId,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': modelName,
            'choices': [
              {
                'index': 0,
                'delta': delta,
                'finish_reason': null,
              }
            ],
          });
        }
      } catch (_) {
        // Best-effort — emit stop chunk
      } finally {
        // Final stop chunk
        emitSSE({
          'id': requestId,
          'object': 'chat.completion.chunk',
          'created': created,
          'model': modelName,
          'choices': [
            {
              'index': 0,
              'delta': <String, dynamic>{},
              'finish_reason': 'stop',
            }
          ],
        });
        if (!streamController.isClosed) {
          try {
            streamController.add(utf8.encode('data: [DONE]\n\n'));
          } catch (_) {}
        }
        // Always release the lock before closing the stream.
        _releaseInference();
        try {
          await streamController.close();
        } catch (_) {}
      }
    }();

    return Response.ok(
      streamController.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }
}
