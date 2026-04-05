/// Benchmark view model — orchestrates benchmark execution and results display.
library;

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/performance/models/benchmark_models.dart';
import 'package:local_ai_chat/features/performance/services/benchmark_service.dart';
import 'package:local_ai_chat/features/performance/services/benchmark_storage_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';

enum BenchmarkState { idle, running, completed, error }

class BenchmarkViewModel extends ChangeNotifier {
  final ModelRuntimeService _runtimeService;
  final BenchmarkService _benchmarkService;
  final BenchmarkStorageService _storageService;
  final SettingsRepository _settingsRepository;

  BenchmarkViewModel(
    this._runtimeService,
    this._benchmarkService,
    this._storageService,
    this._settingsRepository,
  );

  BenchmarkState _state = BenchmarkState.idle;
  BenchmarkState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  BenchmarkProfile? _currentProfile;
  BenchmarkProfile? get currentProfile => _currentProfile;

  int _currentIteration = 0;
  int get currentIteration => _currentIteration;

  int _totalIterations = 0;
  int get totalIterations => _totalIterations;

  BenchmarkRun? _lastRun;
  BenchmarkRun? get lastRun => _lastRun;

  List<BenchmarkRun> _history = [];
  List<BenchmarkRun> get history => List.unmodifiable(_history);

  /// Loads benchmark history from storage.
  Future<void> loadHistory() async {
    _history = await _storageService.loadAllRuns();
    notifyListeners();
  }

  /// Runs a benchmark profile against the currently loaded model.
  Future<void> runBenchmark(BenchmarkProfile profile) async {
    if (!_runtimeService.isLoaded) {
      _errorMessage = 'No model loaded. Load a model first.';
      _state = BenchmarkState.error;
      notifyListeners();
      return;
    }

    _state = BenchmarkState.running;
    _currentProfile = profile;
    _currentIteration = 0;
    _totalIterations = profile.iterations;
    _errorMessage = null;
    notifyListeners();

    try {
      final engine = _runtimeService.engine;
      if (engine == null) throw StateError('Engine not available');

      final settings = await _settingsRepository.loadAll();
      final runtimeInfo = await _benchmarkService.collectRuntimeInfo(
        engine,
        requestedBackend: settings.model.accelerator,
        threads: settings.model.threads,
        batchSize: settings.model.nBatch,
        microBatchSize: settings.model.microBatchSize,
        contextSize: settings.model.nCtx,
      );

      final run = await _benchmarkService.runProfile(
        engine: engine,
        profile: profile,
        modelPath: _runtimeService.currentModelPath!,
        runtimeInfo: runtimeInfo,
        onProgress: (completed, total) {
          _currentIteration = completed;
          notifyListeners();
        },
      );

      await _storageService.saveRun(run);
      _lastRun = run;
      _history = await _storageService.loadAllRuns();
      _state = BenchmarkState.completed;
    } catch (e) {
      _errorMessage = 'Benchmark failed: $e';
      _state = BenchmarkState.error;
    }

    notifyListeners();
  }

  /// Clears all stored benchmark data.
  Future<void> clearHistory() async {
    await _storageService.clearAll();
    _history = [];
    _lastRun = null;
    notifyListeners();
  }
}
