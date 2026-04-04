/// Model runtime service — wraps llamadart engine lifecycle for local inference.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:local_ai_chat/core/models/model_capability.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Abstracts local LLM model lifecycle: load, generate text, generate
/// multimodal text, and dispose.
class ModelRuntimeService {
  LlamaEngine? _engine;
  String? _currentModelPath;
  bool _isLoaded = false;
  ModelCapability _capability = ModelCapability.textOnly;
  bool _generationInProgress = false;
  int _maxPredictTokens = 512;
  bool _visionProjectorLoaded = false;

  bool get isLoaded => _isLoaded;
  String? get currentModelPath => _currentModelPath;
  ModelCapability get capability => _capability;

  /// Lists .gguf files in the app's documents directory.
  Future<List<String>> listLocalModels() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync();
    return files
        .where((f) => f is File && f.path.endsWith('.gguf'))
        .map((f) => f.path)
        .toList();
  }

  /// Loads a GGUF model using llamadart.
  Future<void> loadModel(
    String modelPath, {
    int nCtx = 2048,
    int nBatch = 512,
    int nPredict = 512,
    ModelCapability? capability,
  }) async {
    await dispose();

    _capability = capability ?? _inferCapability(modelPath);

    final safeNCtx = nCtx.clamp(256, 32768).toInt();
    final safeNBatch = nBatch.clamp(1, safeNCtx).toInt();
    final safeNPredict = nPredict.clamp(1, 8192).toInt();

    final file = File(modelPath);
    if (!file.existsSync()) {
      throw StateError('Model file does not exist at path: $modelPath');
    }

    final sizeBytes = file.lengthSync();
    final sizeMb = sizeBytes / (1024 * 1024);
    print('Loading model: $modelPath (Size: ${sizeMb.toStringAsFixed(2)} MB)');

    if (sizeMb < 10) {
      throw StateError(
        'Model file is suspiciously small (${sizeMb.toStringAsFixed(2)} MB). Download may be corrupted. Please delete and re-download.',
      );
    }

    final threads = Platform.isAndroid ? _recommendedThreadCount() : 0;
    final modelParams = ModelParams(
      contextSize: safeNCtx,
      batchSize: safeNBatch,
      microBatchSize: math.min(safeNBatch, Platform.isAndroid ? 64 : 256),
      numberOfThreads: threads,
      numberOfThreadsBatch: threads,
      gpuLayers: Platform.isAndroid ? 0 : ModelParams.maxGpuLayers,
      preferredBackend: Platform.isAndroid ? GpuBackend.cpu : GpuBackend.auto,
    );

    final engine = LlamaEngine(LlamaBackend());

    try {
      await engine.setLogLevel(LlamaLogLevel.none);
      await engine.loadModel(modelPath, modelParams: modelParams);

      _visionProjectorLoaded = false;
      if (_capability.supportsVision) {
        final mmprojPath = _findMultimodalProjectorPath(modelPath);
        if (mmprojPath != null) {
          await engine.loadMultimodalProjector(mmprojPath);
          _visionProjectorLoaded = await engine.supportsVision;
        }
      }

      _engine = engine;
      _currentModelPath = modelPath;
      _isLoaded = true;
      _maxPredictTokens = safeNPredict;
    } catch (error, stackTrace) {
      await _disposeEngineSilently(engine);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Generates text from a fully-formatted prompt.
  Stream<String> generateStream(String formattedPrompt) {
    final engine = _engine;
    if (!_isLoaded || engine == null) {
      throw StateError('Model not loaded');
    }

    return _streamFromEngine(engine, formattedPrompt);
  }

  /// Generates text from prompt + image inputs for multimodal models.
  Stream<String> generateVisionStream(
    String formattedPrompt, {
    required List<Uint8List> images,
  }) {
    final engine = _engine;
    if (!_isLoaded || engine == null) {
      throw StateError('Model not loaded');
    }
    if (!_capability.supportsVision) {
      throw StateError('Loaded model does not support vision');
    }
    if (!_visionProjectorLoaded) {
      throw StateError(
        'Vision projector is not loaded. Place the matching mmproj GGUF in the same folder as the model file.',
      );
    }

    final parts =
        images.map((bytes) => LlamaImageContent(bytes: bytes)).toList();
    return _streamFromEngine(engine, formattedPrompt, parts: parts);
  }

  Stream<String> _streamFromEngine(
    LlamaEngine engine,
    String prompt, {
    List<LlamaContentPart>? parts,
  }) {
    if (_generationInProgress) {
      throw StateError('Inference already in progress');
    }

    _generationInProgress = true;
    final controller = StreamController<String>();

    Future<void> run() async {
      try {
        final params = GenerationParams(maxTokens: _maxPredictTokens);
        await for (final token in engine.generate(
          prompt,
          params: params,
          parts: parts,
        )) {
          if (controller.isClosed) break;
          controller.add(token);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        _generationInProgress = false;
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    controller.onCancel = () async {
      try {
        engine.cancelGeneration();
      } catch (_) {}
      _generationInProgress = false;
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    unawaited(run());
    return controller.stream;
  }

  ModelCapability _inferCapability(String modelPath) {
    final normalized = modelPath.toLowerCase();
    if (normalized.contains('llava') ||
        normalized.contains('vision') ||
        normalized.contains('vlm')) {
      return ModelCapability.vision;
    }
    if (normalized.contains('embed')) {
      return ModelCapability.embedding;
    }
    return ModelCapability.textOnly;
  }

  String? _findMultimodalProjectorPath(String modelPath) {
    final modelFile = File(modelPath);
    final parent = modelFile.parent;
    if (!parent.existsSync()) {
      return null;
    }

    final candidates = parent.listSync().whereType<File>().where((file) {
      final name = p.basename(file.path).toLowerCase();
      return name.endsWith('.gguf') &&
          (name.contains('mmproj') || name.contains('projector'));
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }
    if (candidates.length == 1) {
      return candidates.first.path;
    }

    final modelBase = p.basenameWithoutExtension(modelPath).toLowerCase();
    for (final candidate in candidates) {
      final name = p.basename(candidate.path).toLowerCase();
      if (name.contains(modelBase)) {
        return candidate.path;
      }
    }

    return candidates.first.path;
  }

  /// Disposes the current model runtime.
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _isLoaded = false;
    _currentModelPath = null;
    _capability = ModelCapability.textOnly;
    _generationInProgress = false;
    _maxPredictTokens = 512;
    _visionProjectorLoaded = false;

    if (engine != null) {
      await _disposeEngineSilently(engine);
    }
  }

  int _recommendedThreadCount() {
    final cores = Platform.numberOfProcessors;
    return math.max(2, math.min(cores, 6));
  }

  Future<void> _disposeEngineSilently(LlamaEngine engine) async {
    await runZonedGuarded(
      () async => engine.dispose(),
      (_, __) {},
    );
  }
}
