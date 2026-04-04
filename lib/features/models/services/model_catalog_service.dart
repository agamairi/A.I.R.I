/// Model catalog service — browses HuggingFace for GGUF models.
/// Migrated from the original download_api.dart browsing logic.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ModelCatalogService {
  final Dio _dio = Dio();

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

  /// Fetches byte size of the first .gguf file for a model on HuggingFace.
  Future<int?> fetchModelSize(String modelName) async {
    try {
      final url = 'https://huggingface.co/api/models/$modelName/tree/main';
      final response = await _dio.get(url);
      if (response.statusCode != 200) return null;

      final files = response.data as List<dynamic>;
      final gguf = files.where(
        (f) => f['path'].toString().toLowerCase().endsWith('.gguf'),
      );
      if (gguf.isNotEmpty) return gguf.first['size'] as int?;
    } catch (_) {}
    return null;
  }
}
