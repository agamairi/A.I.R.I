library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/download_task.dart';
import 'package:local_ai_chat/features/models/services/model_catalog_service.dart';
import 'package:local_ai_chat/features/models/services/model_download_service.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:uuid/uuid.dart';

class ModelManagerViewModel extends ChangeNotifier {
  final ModelRuntimeService _runtimeService;
  final ModelCatalogService _catalogService;
  final ModelDownloadService _downloadService;
  final SettingsRepository _settingsRepository;

  ModelManagerViewModel(
    this._runtimeService,
    this._catalogService,
    this._downloadService,
    this._settingsRepository,
  );

  StreamSubscription<List<DownloadTask>>? _downloadSubscription;
  Timer? _searchDebounce;

  List<String> _localModels = <String>[];
  List<String> get localModels => List.unmodifiable(_localModels);

  List<Map<String, dynamic>> _availableModels = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get availableModels =>
      List.unmodifiable(_availableModels);

  List<DownloadTask> _tasks = <DownloadTask>[];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  final Map<String, int> modelSizes = {};

  bool _loadingLocal = false;
  bool get loadingLocal => _loadingLocal;

  bool _loadingCatalog = false;
  bool get loadingCatalog => _loadingCatalog;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get isModelLoaded => _runtimeService.isLoaded;
  String? get loadedModelPath => _runtimeService.currentModelPath;

  Future<void> initialize() async {
    _tasks = _downloadService.tasks;

    _downloadSubscription ??=
        _downloadService.downloadStateStream.listen((downloadTasks) {
      _tasks = downloadTasks;
      notifyListeners();
    });

    await Future.wait(<Future<void>>[
      refreshLocalModels(),
      loadCatalog(),
    ]);
  }

  Future<void> refreshLocalModels() async {
    _loadingLocal = true;
    notifyListeners();

    try {
      _localModels = await _runtimeService.listLocalModels();
    } catch (e) {
      _errorMessage = 'Failed to load local models: $e';
    } finally {
      _loadingLocal = false;
      notifyListeners();
    }
  }

  Future<void> loadCatalog() async {
    _loadingCatalog = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availableModels = await _catalogService.fetchAvailableModels();
      _fetchSizesForModels(_availableModels);
    } catch (e) {
      _errorMessage = 'Failed to fetch model catalog: $e';
      _availableModels = <Map<String, dynamic>>[];
    } finally {
      _loadingCatalog = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value.trim().toLowerCase();
    
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      _loadingCatalog = true;
      notifyListeners();

      try {
        if (_searchQuery.isEmpty) {
          _availableModels = await _catalogService.fetchAvailableModels();
        } else {
          _availableModels = await _catalogService.searchModels(_searchQuery);
        }
        _fetchSizesForModels(_availableModels);
      } catch (e) {
        _errorMessage = 'Failed to search models: $e';
        _availableModels = <Map<String, dynamic>>[];
      } finally {
        _loadingCatalog = false;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  Future<void> _fetchSizesForModels(List<Map<String, dynamic>> models) async {
    for (final model in models) {
      final id = model['id']?.toString() ?? '';
      if (id.isEmpty || modelSizes.containsKey(id)) continue;

      try {
        final size = await _catalogService.fetchModelSize(id);
        if (size != null) {
          modelSizes[id] = size;
          notifyListeners();
        }
      } catch (_) {
        // Ignore individual failures
      }

      // Throttle requests to avoid hitting HuggingFace rate limits.
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> enqueueDownload(String modelName) async {
    final trimmed = modelName.trim();
    if (trimmed.isEmpty) return;

    final task = DownloadTask(
      id: const Uuid().v4(),
      modelName: trimmed,
      downloadUrl: '',
      savePath: '',
      createdAt: DateTime.now(),
    );

    await _downloadService.enqueue(task);
  }

  Future<void> retryDownload(String taskId) async {
    await _downloadService.retry(taskId);
  }

  Future<void> cancelDownload(String taskId) async {
    await _downloadService.cancel(taskId);
  }

  Future<void> loadModel(String path) async {
    final settings = await _settingsRepository.loadAll();
    await _runtimeService.loadModel(
      path,
      nCtx: settings.model.nCtx,
      nBatch: settings.model.nBatch,
      nPredict: settings.model.nPredict,
      accelerator: settings.model.accelerator,
      threads: settings.model.threads,
      microBatchSize: settings.model.microBatchSize,
    );
    notifyListeners();
  }

  Future<void> deleteLocalModel(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await refreshLocalModels();
  }

  bool isQueuedOrActive(String repoId) {
    return _tasks.any(
      (task) =>
          task.modelName == repoId &&
          (task.status == DownloadStatus.active ||
              task.status == DownloadStatus.queued),
    );
  }

  double? progressForRepo(String repoId) {
    final task = _tasks.lastWhere(
      (entry) => entry.modelName == repoId,
      orElse: () => DownloadTask(
        id: '',
        modelName: '',
        downloadUrl: '',
        savePath: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    return task.id.isEmpty ? null : task.progress;
  }

  /// Called when the app resumes from background — checks for stalled
  /// downloads and restarts them.
  void handleAppResumed() {
    _downloadService.handleAppResumed();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
