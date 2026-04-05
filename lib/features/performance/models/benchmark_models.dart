/// Benchmark data models — mirrors Gallery's LlmBenchmarkStats approach.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Benchmark profile — defines a standardized test workload
// ---------------------------------------------------------------------------

class BenchmarkProfile {
  final String name;
  final int prefillTokens;
  final int decodeTokens;
  final int iterations;

  const BenchmarkProfile({
    required this.name,
    required this.prefillTokens,
    required this.decodeTokens,
    this.iterations = 5,
  });

  static const short = BenchmarkProfile(
    name: 'short',
    prefillTokens: 128,
    decodeTokens: 128,
  );

  static const medium = BenchmarkProfile(
    name: 'medium',
    prefillTokens: 512,
    decodeTokens: 256,
  );

  static const long = BenchmarkProfile(
    name: 'long',
    prefillTokens: 2048,
    decodeTokens: 256,
  );

  static const List<BenchmarkProfile> all = [short, medium, long];

  Map<String, dynamic> toJson() => {
        'name': name,
        'prefillTokens': prefillTokens,
        'decodeTokens': decodeTokens,
        'iterations': iterations,
      };

  factory BenchmarkProfile.fromJson(Map<String, dynamic> json) {
    return BenchmarkProfile(
      name: json['name'] as String,
      prefillTokens: json['prefillTokens'] as int,
      decodeTokens: json['decodeTokens'] as int,
      iterations: json['iterations'] as int? ?? 5,
    );
  }
}

// ---------------------------------------------------------------------------
// Value series — statistical aggregation over N measurements
// ---------------------------------------------------------------------------

class ValueSeries {
  final List<double> values;

  const ValueSeries(this.values);

  bool get isEmpty => values.isEmpty;
  int get count => values.length;

  double get min => values.isEmpty ? 0 : values.reduce(math.min);
  double get max => values.isEmpty ? 0 : values.reduce(math.max);

  double get avg =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  double get median => _percentile(50);
  double get p25 => _percentile(25);
  double get p75 => _percentile(75);

  double _percentile(int p) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final index = (p / 100 * (sorted.length - 1));
    final lower = index.floor();
    final upper = index.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
  }

  Map<String, dynamic> toJson() => {
        'values': values,
        'min': min,
        'max': max,
        'avg': avg,
        'median': median,
        'p25': p25,
        'p75': p75,
      };

  factory ValueSeries.fromJson(Map<String, dynamic> json) {
    final values = (json['values'] as List).cast<num>().map((n) => n.toDouble()).toList();
    return ValueSeries(values);
  }
}

// ---------------------------------------------------------------------------
// Single iteration metrics — captured per benchmark run iteration
// ---------------------------------------------------------------------------

class IterationMetrics {
  final double ttftMs;
  final double prefillTokensPerSec;
  final double decodeTokensPerSec;
  final double prefillMs;
  final double decodeMs;
  final int promptTokens;
  final int completionTokens;

  const IterationMetrics({
    required this.ttftMs,
    required this.prefillTokensPerSec,
    required this.decodeTokensPerSec,
    required this.prefillMs,
    required this.decodeMs,
    required this.promptTokens,
    required this.completionTokens,
  });

  Map<String, dynamic> toJson() => {
        'ttftMs': ttftMs,
        'prefillTokensPerSec': prefillTokensPerSec,
        'decodeTokensPerSec': decodeTokensPerSec,
        'prefillMs': prefillMs,
        'decodeMs': decodeMs,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
      };

  factory IterationMetrics.fromJson(Map<String, dynamic> json) {
    return IterationMetrics(
      ttftMs: (json['ttftMs'] as num).toDouble(),
      prefillTokensPerSec: (json['prefillTokensPerSec'] as num).toDouble(),
      decodeTokensPerSec: (json['decodeTokensPerSec'] as num).toDouble(),
      prefillMs: (json['prefillMs'] as num).toDouble(),
      decodeMs: (json['decodeMs'] as num).toDouble(),
      promptTokens: json['promptTokens'] as int,
      completionTokens: json['completionTokens'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// Benchmark run — aggregated results for one profile execution
// ---------------------------------------------------------------------------

class BenchmarkRun {
  final String id;
  final DateTime timestamp;
  final BenchmarkProfile profile;
  final String modelPath;
  final String modelName;
  final DeviceInfo deviceInfo;
  final RuntimeInfo runtimeInfo;
  final List<IterationMetrics> iterations;
  final double? initTimeMs;
  final double? warmInitTimeMs;

  const BenchmarkRun({
    required this.id,
    required this.timestamp,
    required this.profile,
    required this.modelPath,
    required this.modelName,
    required this.deviceInfo,
    required this.runtimeInfo,
    required this.iterations,
    this.initTimeMs,
    this.warmInitTimeMs,
  });

  ValueSeries get ttft => ValueSeries(iterations.map((i) => i.ttftMs).toList());
  ValueSeries get prefillSpeed =>
      ValueSeries(iterations.map((i) => i.prefillTokensPerSec).toList());
  ValueSeries get decodeSpeed =>
      ValueSeries(iterations.map((i) => i.decodeTokensPerSec).toList());

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'profile': profile.toJson(),
        'modelPath': modelPath,
        'modelName': modelName,
        'deviceInfo': deviceInfo.toJson(),
        'runtimeInfo': runtimeInfo.toJson(),
        'iterations': iterations.map((i) => i.toJson()).toList(),
        'initTimeMs': initTimeMs,
        'warmInitTimeMs': warmInitTimeMs,
        'stats': {
          'ttft': ttft.toJson(),
          'prefillSpeed': prefillSpeed.toJson(),
          'decodeSpeed': decodeSpeed.toJson(),
        },
      };

  factory BenchmarkRun.fromJson(Map<String, dynamic> json) {
    return BenchmarkRun(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      profile: BenchmarkProfile.fromJson(json['profile'] as Map<String, dynamic>),
      modelPath: json['modelPath'] as String,
      modelName: json['modelName'] as String,
      deviceInfo: DeviceInfo.fromJson(json['deviceInfo'] as Map<String, dynamic>),
      runtimeInfo: RuntimeInfo.fromJson(json['runtimeInfo'] as Map<String, dynamic>),
      iterations: (json['iterations'] as List)
          .map((i) => IterationMetrics.fromJson(i as Map<String, dynamic>))
          .toList(),
      initTimeMs: (json['initTimeMs'] as num?)?.toDouble(),
      warmInitTimeMs: (json['warmInitTimeMs'] as num?)?.toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Device & runtime metadata
// ---------------------------------------------------------------------------

class DeviceInfo {
  final String os;
  final String osVersion;
  final String deviceModel;
  final int coreCount;
  final String? ramInfo;

  const DeviceInfo({
    required this.os,
    required this.osVersion,
    required this.deviceModel,
    required this.coreCount,
    this.ramInfo,
  });

  Map<String, dynamic> toJson() => {
        'os': os,
        'osVersion': osVersion,
        'deviceModel': deviceModel,
        'coreCount': coreCount,
        'ramInfo': ramInfo,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      os: json['os'] as String,
      osVersion: json['osVersion'] as String,
      deviceModel: json['deviceModel'] as String,
      coreCount: json['coreCount'] as int,
      ramInfo: json['ramInfo'] as String?,
    );
  }
}

class RuntimeInfo {
  final String requestedBackend;
  final String? resolvedBackend;
  final String? availableBackends;
  final int? resolvedGpuLayers;
  final int threads;
  final int batchSize;
  final int microBatchSize;
  final int contextSize;

  const RuntimeInfo({
    required this.requestedBackend,
    this.resolvedBackend,
    this.availableBackends,
    this.resolvedGpuLayers,
    required this.threads,
    required this.batchSize,
    required this.microBatchSize,
    required this.contextSize,
  });

  Map<String, dynamic> toJson() => {
        'requestedBackend': requestedBackend,
        'resolvedBackend': resolvedBackend,
        'availableBackends': availableBackends,
        'resolvedGpuLayers': resolvedGpuLayers,
        'threads': threads,
        'batchSize': batchSize,
        'microBatchSize': microBatchSize,
        'contextSize': contextSize,
      };

  factory RuntimeInfo.fromJson(Map<String, dynamic> json) {
    return RuntimeInfo(
      requestedBackend: json['requestedBackend'] as String,
      resolvedBackend: json['resolvedBackend'] as String?,
      availableBackends: json['availableBackends'] as String?,
      resolvedGpuLayers: json['resolvedGpuLayers'] as int?,
      threads: json['threads'] as int,
      batchSize: json['batchSize'] as int,
      microBatchSize: json['microBatchSize'] as int,
      contextSize: json['contextSize'] as int,
    );
  }
}
