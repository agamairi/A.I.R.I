/// Benchmark service — runs standardized inference benchmarks using llamadart.
///
/// Captures TTFT, prefill tok/s, decode tok/s, init times, and runtime
/// diagnostics. Uses LlamaEngine's getPerformanceContext() for accurate
/// timing data from the native layer.
library;

import 'dart:async';
import 'dart:io';
import 'package:llamadart/llamadart.dart';
import 'package:local_ai_chat/features/performance/models/benchmark_models.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class BenchmarkService {
  /// Generates a prompt string of approximately [tokenCount] tokens.
  ///
  /// Uses a repeating pattern of common English words to approximate
  /// token counts (roughly 1.3 tokens per word for most tokenizers).
  String generatePromptForTokenCount(int tokenCount) {
    const words = [
      'The', 'quick', 'brown', 'fox', 'jumps', 'over', 'the', 'lazy', 'dog.',
      'A', 'large', 'language', 'model', 'processes', 'text', 'efficiently.',
      'Machine', 'learning', 'algorithms', 'optimize', 'neural', 'network',
      'performance.', 'Data', 'flows', 'through', 'transformer', 'layers',
      'computing', 'attention', 'weights.', 'Tokens', 'are', 'embedded',
      'into', 'high', 'dimensional', 'vector', 'spaces.', 'The', 'system',
      'generates', 'coherent', 'responses', 'from', 'context', 'windows.',
    ];

    // ~1.3 tokens per word on average for English text
    final wordCount = (tokenCount / 1.3).ceil();
    final buffer = StringBuffer();
    for (var i = 0; i < wordCount; i++) {
      if (i > 0) buffer.write(' ');
      buffer.write(words[i % words.length]);
    }
    return buffer.toString();
  }

  /// Collects device info for benchmark metadata.
  DeviceInfo collectDeviceInfo() {
    return DeviceInfo(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      deviceModel: Platform.localHostname,
      coreCount: Platform.numberOfProcessors,
    );
  }

  /// Runs a single benchmark iteration against a loaded engine.
  ///
  /// Returns [IterationMetrics] with TTFT, prefill speed, and decode speed
  /// derived from llamadart's native performance counters.
  Future<IterationMetrics> runIteration(
    LlamaEngine engine,
    String prompt,
    int maxDecodeTokens,
  ) async {
    final stopwatch = Stopwatch()..start();
    double? ttftMs;
    int tokenCount = 0;

    final params = GenerationParams(
      maxTokens: maxDecodeTokens,
      reusePromptPrefix: false, // Don't reuse prefix during benchmarks
    );

    await for (final _ in engine.generate(prompt, params: params)) {
      ttftMs ??= stopwatch.elapsedMicroseconds / 1000.0;
      tokenCount++;
    }
    stopwatch.stop();

    // Get native performance counters
    final perfCtx = await engine.getPerformanceContext();

    final double prefillMs;
    final int promptTokens;
    final double decodeMs;
    final int completionTokens;

    if (perfCtx != null) {
      prefillMs = perfCtx.promptEvalMs;
      promptTokens = perfCtx.promptEvalTokens;
      decodeMs = perfCtx.evalMs;
      completionTokens = perfCtx.evalTokens;
    } else {
      // Fallback: estimate from wall clock
      prefillMs = ttftMs ?? 0;
      promptTokens = 0; // Unknown without native data
      decodeMs = (stopwatch.elapsedMicroseconds / 1000.0) - (ttftMs ?? 0);
      completionTokens = tokenCount;
    }

    final prefillTokPerSec =
        prefillMs > 0 ? (promptTokens / prefillMs * 1000) : 0.0;
    final decodeTokPerSec =
        decodeMs > 0 ? (completionTokens / decodeMs * 1000) : 0.0;

    return IterationMetrics(
      ttftMs: ttftMs ?? 0,
      prefillTokensPerSec: prefillTokPerSec,
      decodeTokensPerSec: decodeTokPerSec,
      prefillMs: prefillMs,
      decodeMs: decodeMs,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  /// Runs a full benchmark profile against a loaded engine.
  ///
  /// Executes [profile.iterations] runs and collects aggregated metrics.
  /// [onProgress] is called after each iteration with (completed, total).
  Future<BenchmarkRun> runProfile({
    required LlamaEngine engine,
    required BenchmarkProfile profile,
    required String modelPath,
    required RuntimeInfo runtimeInfo,
    void Function(int completed, int total)? onProgress,
  }) async {
    final prompt = generatePromptForTokenCount(profile.prefillTokens);
    final iterations = <IterationMetrics>[];

    for (var i = 0; i < profile.iterations; i++) {
      final metrics = await runIteration(
        engine,
        prompt,
        profile.decodeTokens,
      );
      iterations.add(metrics);
      onProgress?.call(i + 1, profile.iterations);
    }

    return BenchmarkRun(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      profile: profile,
      modelPath: modelPath,
      modelName: p.basenameWithoutExtension(modelPath),
      deviceInfo: collectDeviceInfo(),
      runtimeInfo: runtimeInfo,
      iterations: iterations,
    );
  }

  /// Measures cold model init time (load from scratch).
  Future<double> measureInitTime(
    String modelPath,
    ModelParams modelParams,
  ) async {
    final engine = LlamaEngine(LlamaBackend());
    final stopwatch = Stopwatch()..start();
    try {
      await engine.setLogLevel(LlamaLogLevel.none);
      await engine.loadModel(modelPath, modelParams: modelParams);
      stopwatch.stop();
      return stopwatch.elapsedMicroseconds / 1000.0;
    } finally {
      await _disposeEngineSilently(engine);
    }
  }

  /// Measures warm model init time (reload after previous dispose).
  Future<double> measureWarmInitTime(
    String modelPath,
    ModelParams modelParams,
  ) async {
    // First load + dispose to warm OS file cache
    final warmup = LlamaEngine(LlamaBackend());
    try {
      await warmup.setLogLevel(LlamaLogLevel.none);
      await warmup.loadModel(modelPath, modelParams: modelParams);
    } finally {
      await _disposeEngineSilently(warmup);
    }

    // Measure second load
    return measureInitTime(modelPath, modelParams);
  }

  /// Collects runtime diagnostics from a loaded engine.
  Future<RuntimeInfo> collectRuntimeInfo(
    LlamaEngine engine, {
    required String requestedBackend,
    required int threads,
    required int batchSize,
    required int microBatchSize,
    required int contextSize,
  }) async {
    String? resolvedBackend;
    String? availableBackends;
    int? resolvedGpuLayers;

    try {
      resolvedBackend = await engine.getBackendName();
    } catch (_) {}
    try {
      availableBackends = await engine.getAvailableBackends();
    } catch (_) {}
    try {
      resolvedGpuLayers = await engine.getResolvedGpuLayers();
    } catch (_) {}

    return RuntimeInfo(
      requestedBackend: requestedBackend,
      resolvedBackend: resolvedBackend,
      availableBackends: availableBackends,
      resolvedGpuLayers: resolvedGpuLayers,
      threads: threads,
      batchSize: batchSize,
      microBatchSize: microBatchSize,
      contextSize: contextSize,
    );
  }

  Future<void> _disposeEngineSilently(LlamaEngine engine) async {
    await runZonedGuarded(
      () async => engine.dispose(),
      (_, __) {},
    );
  }
}
