/// Model name resolver — maps between Ollama-style model names (e.g.
/// `llama3.2:3b-q4_K_M`) and local GGUF file paths, and extracts metadata
/// from filenames.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

/// Metadata for a single locally available GGUF model.
class LocalModelInfo {
  final String filePath;
  final String ollamaName;
  final String family;
  final String parameterSize;
  final String quantizationLevel;
  final int sizeBytes;
  final DateTime modifiedAt;

  /// A stable digest derived from the file path + size (fast, no full-file hash).
  String get digest {
    final input = '$filePath:$sizeBytes';
    return 'sha256:${sha256.convert(utf8.encode(input)).toString()}';
  }

  const LocalModelInfo({
    required this.filePath,
    required this.ollamaName,
    required this.family,
    required this.parameterSize,
    required this.quantizationLevel,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  /// Converts to the Ollama `/api/tags` response model entry format.
  Map<String, dynamic> toOllamaTagEntry() => {
        'name': ollamaName,
        'model': ollamaName,
        'modified_at': modifiedAt.toUtc().toIso8601String(),
        'size': sizeBytes,
        'digest': digest,
        'details': {
          'parent_model': '',
          'format': 'gguf',
          'family': family,
          'parameter_size': parameterSize,
          'quantization_level': quantizationLevel,
        },
      };

  /// Converts to the OpenAI `/v1/models` response entry format.
  Map<String, dynamic> toOpenAIModelEntry() => {
        'id': ollamaName,
        'object': 'model',
        'created': modifiedAt.millisecondsSinceEpoch ~/ 1000,
        'owned_by': 'local',
      };
}

/// Resolves local GGUF models and provides name mapping.
class ModelNameResolver {
  /// Scans a directory for `.gguf` files and returns their metadata.
  ///
  /// Excludes files that contain `mmproj` or `projector` (multimodal projectors).
  List<LocalModelInfo> scanModels(String directoryPath) {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return [];

    final results = <LocalModelInfo>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.gguf')) continue;
      if (name.contains('mmproj') || name.contains('projector')) continue;

      results.add(_infoFromFile(entity));
    }

    // Sort by modification time (newest first).
    results.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return results;
  }

  /// Finds a model by its Ollama-style name from a list of scanned models.
  LocalModelInfo? findByName(List<LocalModelInfo> models, String ollamaName) {
    final lower = ollamaName.toLowerCase();
    for (final m in models) {
      if (m.ollamaName.toLowerCase() == lower) return m;
    }
    return null;
  }

  /// Builds model info from a single GGUF file.
  LocalModelInfo _infoFromFile(File file) {
    final stat = file.statSync();
    final baseName = p.basenameWithoutExtension(file.path);
    final parsed = _parseModelFilename(baseName);

    return LocalModelInfo(
      filePath: file.path,
      ollamaName: parsed.ollamaName,
      family: parsed.family,
      parameterSize: parsed.parameterSize,
      quantizationLevel: parsed.quantizationLevel,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }
}

// ---------------------------------------------------------------------------
// Filename parsing helpers
// ---------------------------------------------------------------------------

class _ParsedName {
  final String ollamaName;
  final String family;
  final String parameterSize;
  final String quantizationLevel;

  const _ParsedName({
    required this.ollamaName,
    required this.family,
    required this.parameterSize,
    required this.quantizationLevel,
  });
}

/// Parses a GGUF filename (without extension) into Ollama-style metadata.
///
/// Examples:
///   `Llama-3.2-3B-Instruct-Q4_K_M`  -> `llama-3.2:3b-instruct-q4_K_M`
///   `Phi-3-mini-4k-instruct-q4`      -> `phi-3:mini-4k-instruct-q4`
///   `mistral-7b-instruct-v0.3.Q5_K_M` -> `mistral:7b-instruct-v0.3-Q5_K_M`
_ParsedName _parseModelFilename(String baseName) {
  // Common quantization patterns
  final quantRegex = RegExp(
    r'[_.-]?((?:IQ[1-4]_(?:XS|XXS|S|M|NL)|Q[0-9]_[A-Z0-9_]+|[Qq][0-9]+(?:_[A-Za-z0-9]+)?))',
  );

  String quantLevel = 'unknown';
  String nameWithoutQuant = baseName;

  final quantMatch = quantRegex.firstMatch(baseName);
  if (quantMatch != null) {
    quantLevel = quantMatch.group(1)!;
    nameWithoutQuant =
        baseName.substring(0, quantMatch.start) +
        baseName.substring(quantMatch.end);
  }

  // Parameter size patterns (e.g. 3B, 7B, 70B, 0.5B)
  final paramRegex = RegExp(r'[_.-]?(\d+(?:\.\d+)?[Bb])\b');
  String paramSize = 'unknown';
  String remaining = nameWithoutQuant;

  final paramMatch = paramRegex.firstMatch(nameWithoutQuant);
  if (paramMatch != null) {
    paramSize = paramMatch.group(1)!.toUpperCase();
    remaining =
        nameWithoutQuant.substring(0, paramMatch.start) +
        nameWithoutQuant.substring(paramMatch.end);
  }

  // Clean up remaining name: replace separators, remove trailing dashes
  remaining = remaining
      .replaceAll(RegExp(r'[-_]+$'), '')
      .replaceAll(RegExp(r'^[-_]+'), '')
      .trim();

  // Build Ollama-style name: family:variant-quant
  // First segment before a dash/dot is typically the family
  final parts = remaining.split(RegExp(r'[-_.]'));
  String family = parts.isNotEmpty ? parts.first.toLowerCase() : 'unknown';

  // Build the tag portion (everything after family)
  final tagParts = <String>[];
  if (paramSize != 'unknown') tagParts.add(paramSize.toLowerCase());
  if (parts.length > 1) {
    tagParts.addAll(parts.skip(1).map((s) => s.toLowerCase()));
  }
  if (quantLevel != 'unknown') tagParts.add(quantLevel);

  final tag = tagParts.isNotEmpty ? tagParts.join('-') : 'latest';
  final ollamaName = '$family:$tag';

  return _ParsedName(
    ollamaName: ollamaName,
    family: family,
    parameterSize: paramSize,
    quantizationLevel: quantLevel,
  );
}
