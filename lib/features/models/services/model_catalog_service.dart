/// Model catalog service — browses HuggingFace for GGUF models.
/// Includes automatic retry with exponential backoff for rate limits (429).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ModelCatalogService {
  late final Dio _dio;

  ModelCatalogService() {
    _dio = Dio();
    _dio.interceptors.add(_RateLimitInterceptor(_dio));
  }

  /// Fetches available GGUF models from HuggingFace.
  Future<List<Map<String, dynamic>>> fetchAvailableModels() async {
    const url =
        'https://huggingface.co/api/models?filter=gguf,conversational&full=true';
    final response = await _dio.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode}');
    }

    final models = (response.data as List<dynamic>).where((model) {
      final modelName = (model['id'] as String).toLowerCase();
      final quantKeywords = [
        'quantized',
        'q4',
        'q5',
        'q8',
        'int8',
        'int4',
        'ggml',
        'llama-q',
      ];
      final isQuantized = quantKeywords.any((kw) => modelName.contains(kw));
      final hasQuantTag = model['tags'] is List &&
          (model['tags'] as List)
              .any((t) => t.toString().toLowerCase().contains('quantized'));

      if (modelName.contains('llama') || modelName.contains('ggml')) {
        return isQuantized || hasQuantTag;
      }
      return false;
    }).toList();

    return models.cast<Map<String, dynamic>>();
  }

  /// Checks whether a model's GGUF file already exists locally.
  Future<bool> checkModelExists(String modelName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$modelName.gguf').exists();
  }

  /// Searches for GGUF models on HuggingFace matching a query.
  Future<List<Map<String, dynamic>>> searchModels(String query) async {
    final url =
        'https://huggingface.co/api/models?search=${Uri.encodeComponent(query)}&filter=gguf&full=true';
    final response = await _dio.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to search models: ${response.statusCode}');
    }

    final models = response.data as List<dynamic>;
    return models.cast<Map<String, dynamic>>();
  }

  /// Fetches the **total** byte size of all .gguf files for a model on
  /// HuggingFace. This gives the user a realistic picture of the repo's
  /// full download footprint.
  Future<int?> fetchModelSize(String modelName) async {
    try {
      final url = 'https://huggingface.co/api/models/$modelName/tree/main';
      final response = await _dio.get(url);
      if (response.statusCode != 200) return null;

      final files = response.data as List<dynamic>;
      final ggufFiles = files.where(
        (f) => f['path'].toString().toLowerCase().endsWith('.gguf'),
      );

      if (ggufFiles.isEmpty) return null;

      // Sum all GGUF file sizes to show the total repo download size.
      int totalSize = 0;
      for (final f in ggufFiles) {
        totalSize += (f['size'] as int?) ?? 0;
      }
      return totalSize > 0 ? totalSize : null;
    } catch (_) {}
    return null;
  }
}

/// Dio interceptor that automatically retries requests on HTTP 429
/// (Too Many Requests) with exponential backoff.
class _RateLimitInterceptor extends Interceptor {
  final Dio _dio;
  static const _maxRetries = 4;

  _RateLimitInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 429) {
      final retryCount = (err.requestOptions.extra['_retryCount'] as int?) ?? 0;

      if (retryCount < _maxRetries) {
        // Check for Retry-After header (seconds).
        final retryAfterHeader = err.response?.headers.value('retry-after');
        int delaySeconds;
        if (retryAfterHeader != null) {
          delaySeconds = int.tryParse(retryAfterHeader) ?? _backoffSeconds(retryCount);
        } else {
          delaySeconds = _backoffSeconds(retryCount);
        }

        await Future.delayed(Duration(seconds: delaySeconds));

        // Clone the request with incremented retry count.
        final opts = err.requestOptions;
        opts.extra['_retryCount'] = retryCount + 1;

        try {
          final response = await _dio.fetch(opts);
          return handler.resolve(response);
        } on DioException catch (e) {
          return handler.reject(e);
        }
      }
    }

    return handler.next(err);
  }

  /// Exponential backoff: 2s, 4s, 8s, 16s (capped).
  int _backoffSeconds(int retryCount) {
    return math.min(2 * math.pow(2, retryCount).toInt(), 30);
  }
}
