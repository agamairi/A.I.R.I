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
  String _requestedBackend = 'auto';
  int _resolvedThreads = 0;
  int _resolvedBatchSize = 0;
  int _resolvedMicroBatchSize = 0;
  int _resolvedContextSize = 0;
  double? _lastLoadTimeMs;

  bool get isLoaded => _isLoaded;
  String? get currentModelPath => _currentModelPath;
  ModelCapability get capability => _capability;

  /// Exposes the underlying engine for benchmarking and diagnostics.
  LlamaEngine? get engine => _engine;

  String get requestedBackend => _requestedBackend;
  int get resolvedThreads => _resolvedThreads;
  int get resolvedBatchSize => _resolvedBatchSize;
  int get resolvedMicroBatchSize => _resolvedMicroBatchSize;
  int get resolvedContextSize => _resolvedContextSize;
  double? get lastLoadTimeMs => _lastLoadTimeMs;

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
  ///
  /// [accelerator] controls GPU backend: 'auto', 'cpu', 'vulkan', 'metal',
  /// 'cuda', or 'npu'. Defaults to 'auto' which lets llamadart pick.
  /// [threads] overrides thread count (0 = auto-detect).
  /// [microBatchSize] overrides micro-batch size (0 = default).
  Future<void> loadModel(
    String modelPath, {
    int nCtx = 2048,
    int nBatch = 512,
    int nPredict = 512,
    String accelerator = 'auto',
    int threads = 0,
    int microBatchSize = 0,
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

    // Resolve accelerator → GpuBackend + gpuLayers
    final (backend, gpuLayers) = _resolveAccelerator(accelerator);

    // Resolve thread count — scale with device cores and backend
    final resolvedThreads = threads > 0
        ? threads
        : _recommendedThreadCount(gpuActive: gpuLayers > 0);

    // Resolve micro-batch size
    final resolvedMicroBatch = microBatchSize > 0
        ? math.min(microBatchSize, safeNBatch)
        : math.min(safeNBatch, Platform.isAndroid ? 128 : 256);

    _requestedBackend = accelerator;
    _resolvedThreads = resolvedThreads;
    _resolvedBatchSize = safeNBatch;
    _resolvedMicroBatchSize = resolvedMicroBatch;
    _resolvedContextSize = safeNCtx;

    final modelParams = ModelParams(
      contextSize: safeNCtx,
      batchSize: safeNBatch,
      microBatchSize: resolvedMicroBatch,
      numberOfThreads: resolvedThreads,
      numberOfThreadsBatch: resolvedThreads,
      gpuLayers: gpuLayers,
      preferredBackend: backend,
    );

    final engine = LlamaEngine(LlamaBackend());
    final loadStopwatch = Stopwatch()..start();

    try {
      await engine.setLogLevel(LlamaLogLevel.none);
      await engine.loadModel(modelPath, modelParams: modelParams);
      loadStopwatch.stop();
      _lastLoadTimeMs = loadStopwatch.elapsedMicroseconds / 1000.0;

      _visionProjectorLoaded = false;
      if (_capability.supportsVision) {
        final mmprojPath = _findMultimodalProjectorPath(modelPath);
        if (mmprojPath != null) {
          await engine.loadMultimodalProjector(mmprojPath);
          _visionProjectorLoaded = await engine.supportsVision;
        }
      }

      // Log runtime diagnostics
      _logRuntimeDiagnostics(engine, accelerator, resolvedThreads, gpuLayers);

      _engine = engine;
      _currentModelPath = modelPath;
      _isLoaded = true;
      _maxPredictTokens = safeNPredict;
    } catch (error, stackTrace) {
      loadStopwatch.stop();

      // GPU fallback: if non-CPU backend failed, retry with CPU
      if (accelerator != 'cpu') {
        print('GPU init failed ($error), falling back to CPU...');
        await _disposeEngineSilently(engine);
        return loadModel(
          modelPath,
          nCtx: nCtx,
          nBatch: nBatch,
          nPredict: nPredict,
          accelerator: 'cpu',
          threads: threads,
          microBatchSize: microBatchSize,
          capability: _capability,
        );
      }

      await _disposeEngineSilently(engine);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Resolves accelerator string to GpuBackend + gpuLayers.
  ///
  /// `auto` picks the best GPU backend per platform:
  /// - Android → Vulkan (llama.cpp's `auto` doesn't probe Vulkan on Android)
  /// - iOS/macOS → Metal
  /// - Other → delegates to llama.cpp's auto detection
  ///
  /// If GPU init fails, [loadModel] catches the error and retries with CPU.
  (GpuBackend, int) _resolveAccelerator(String accelerator) {
    switch (accelerator.toLowerCase()) {
      case 'cpu':
        return (GpuBackend.cpu, 0);
      case 'vulkan':
        return (GpuBackend.vulkan, ModelParams.maxGpuLayers);
      case 'metal':
        return (GpuBackend.metal, ModelParams.maxGpuLayers);
      case 'cuda':
        return (GpuBackend.cuda, ModelParams.maxGpuLayers);
      case 'auto':
      default:
        if (Platform.isAndroid) {
          return (GpuBackend.vulkan, ModelParams.maxGpuLayers);
        }
        if (Platform.isIOS || Platform.isMacOS) {
          return (GpuBackend.metal, ModelParams.maxGpuLayers);
        }
        return (GpuBackend.auto, ModelParams.maxGpuLayers);
    }
  }

  void _logRuntimeDiagnostics(
    LlamaEngine engine,
    String requested,
    int threads,
    int gpuLayers,
  ) {
    Future<void> log() async {
      try {
        final resolved = await engine.getBackendName();
        final available = await engine.getAvailableBackends();
        final layers = await engine.getResolvedGpuLayers();
        print('Runtime diagnostics:');
        print('  Requested backend: $requested');
        print('  Resolved backend: $resolved');
        print('  Available backends: $available');
        print('  GPU layers: $layers');
        print('  Threads: $threads');
        print('  Load time: ${_lastLoadTimeMs?.toStringAsFixed(0)} ms');
      } catch (_) {}
    }

    log(); // Fire-and-forget diagnostics logging
  }

  /// Generates text from a fully-formatted prompt.
  ///
  /// [generationParams] allows passing full sampling parameters (temperature,
  /// topK, topP, etc.). If null, uses defaults with maxTokens from model load.
  Stream<String> generateStream(
    String formattedPrompt, {
    GenerationParams? generationParams,
  }) {
    final engine = _engine;
    if (!_isLoaded || engine == null) {
      throw StateError('Model not loaded');
    }

    return _streamFromEngine(
      engine,
      formattedPrompt,
      generationParams: generationParams,
    );
  }

  /// Generates text from prompt + image inputs for multimodal models.
  Stream<String> generateVisionStream(
    String formattedPrompt, {
    required List<Uint8List> images,
    GenerationParams? generationParams,
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
    return _streamFromEngine(
      engine,
      formattedPrompt,
      parts: parts,
      generationParams: generationParams,
    );
  }

  Stream<String> _streamFromEngine(
    LlamaEngine engine,
    String prompt, {
    List<LlamaContentPart>? parts,
    GenerationParams? generationParams,
  }) {
    if (_generationInProgress) {
      throw StateError('Inference already in progress');
    }

    _generationInProgress = true;
    final controller = StreamController<String>();

    Future<void> run() async {
      try {
        final params = generationParams ??
            GenerationParams(maxTokens: _maxPredictTokens);
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
    _lastLoadTimeMs = null;

    if (engine != null) {
      await _disposeEngineSilently(engine);
    }
  }

  /// Recommends thread count based on device cores and whether GPU is active.
  ///
  /// When GPU is active, fewer CPU threads are needed since compute shifts
  /// to the GPU. Scales up to cores-2 for CPU-only, cores/2 for GPU.
  int _recommendedThreadCount({bool gpuActive = false}) {
    final cores = Platform.numberOfProcessors;
    if (gpuActive) {
      // GPU handles most compute; use fewer CPU threads
      return math.max(2, cores ~/ 2);
    }
    // CPU-only: use most available cores, leave 2 for OS/UI
    return math.max(2, cores - 2);
  }

  Future<void> _disposeEngineSilently(LlamaEngine engine) async {
    await runZonedGuarded(
      () async => engine.dispose(),
      (_, __) {},
    );
  }
}
