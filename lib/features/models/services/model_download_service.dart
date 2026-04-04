/// Persistent download service with queue management.
/// Downloads survive screen navigation and restore state on reopen.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:local_ai_chat/core/models/download_task.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';

class ModelDownloadService {
  final StorageService _storage;
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  bool _queuePumpRunning = false;

  /// Stream controller that broadcasts download state changes.
  final _stateController = StreamController<List<DownloadTask>>.broadcast();
  Stream<List<DownloadTask>> get downloadStateStream => _stateController.stream;

  List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  ModelDownloadService(this._storage);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Restores persisted download tasks and resumes queued/active ones.
  Future<void> initialize() async {
    final rows = await _storage.query('download_tasks', orderBy: 'createdAt');
    _tasks = rows.map(DownloadTask.fromMap).toList();

    // Mark previously-active downloads as queued (app was killed)
    for (final t in _tasks) {
      if (t.status == DownloadStatus.active) {
        t.status = DownloadStatus.queued;
        t.progress = 0.0;
        t.downloadedBytes = 0;
        await _storage.update(
          'download_tasks',
          t.toMap(),
          where: 'id = ?',
          whereArgs: [t.id],
        );
      }
    }

    _broadcastState();
    unawaited(_processQueue());
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  /// Enqueues a new download.
  Future<void> enqueue(DownloadTask task) async {
    final existingIndex = _tasks.indexWhere((t) => t.id == task.id);
    if (existingIndex >= 0) {
      _tasks[existingIndex] = task;
    } else {
      _tasks.add(task);
    }
    await _storage.insert('download_tasks', task.toMap());
    _broadcastState();
    unawaited(_processQueue());
  }

  /// Cancels and removes a download.
  Future<void> cancel(String taskId) async {
    _cancelTokens[taskId]?.cancel();
    _cancelTokens.remove(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    await _storage
        .delete('download_tasks', where: 'id = ?', whereArgs: [taskId]);
    _broadcastState();
  }

  /// Retries a failed download.
  Future<void> retry(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.status = DownloadStatus.queued;
    task.progress = 0.0;
    task.downloadedBytes = 0;
    task.errorMessage = null;
    await _persist(task);
    _broadcastState();
    unawaited(_processQueue());
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  bool get _hasActiveDownload =>
      _tasks.any((t) => t.status == DownloadStatus.active);

  Future<void> _processQueue() async {
    if (_queuePumpRunning) return;
    _queuePumpRunning = true;
    try {
      while (true) {
        if (_hasActiveDownload) return;
        final next =
            _tasks.where((t) => t.status == DownloadStatus.queued).firstOrNull;
        if (next == null) return;
        await _startDownload(next);
      }
    } finally {
      _queuePumpRunning = false;
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.active;
    await _persist(task);
    _broadcastState();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final resolved = await _resolveDownload(task);
      final saveFile = File(resolved.savePath);
      await saveFile.parent.create(recursive: true);
      int lastProgressPersistMs = 0;

      await _dio.download(
        resolved.downloadUrl,
        resolved.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            task.progress = received / total;
            task.totalBytes = total;
            task.downloadedBytes = received;
            _broadcastState();

            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (nowMs - lastProgressPersistMs > 1500) {
              lastProgressPersistMs = nowMs;
              unawaited(_persist(task));
            }
          }
        },
      );

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return; // Already removed from task list
      }
      task.status = DownloadStatus.failed;
      task.errorMessage = e.message ?? 'Download failed';
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
    } finally {
      _cancelTokens.remove(task.id);
      if (_tasks.any((t) => t.id == task.id)) {
        await _persist(task);
      }
      _broadcastState();
    }
  }

  Future<({String downloadUrl, String savePath})> _resolveDownload(
    DownloadTask task,
  ) async {
    var resolvedUrl = task.downloadUrl.trim();
    var resolvedPath = task.savePath.trim();

    if (resolvedUrl.isNotEmpty && resolvedPath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = Uri.tryParse(resolvedUrl)?.pathSegments.last;
      if (fileName != null && fileName.isNotEmpty) {
        resolvedPath = '${dir.path}/$fileName';
      }
    }

    if (resolvedUrl.isNotEmpty && resolvedPath.isNotEmpty) {
      return (downloadUrl: resolvedUrl, savePath: resolvedPath);
    }

    final dir = await getApplicationDocumentsDirectory();
    final filesUrl =
        'https://huggingface.co/api/models/${task.modelName}/tree/main';
    final filesResp = await _dio.get(filesUrl);
    final filesData = filesResp.data as List<dynamic>;
    final ggufFiles = filesData
        .where((f) => f['path'].toString().toLowerCase().endsWith('.gguf'))
        .toList();

    if (ggufFiles.isEmpty) {
      throw Exception('No .gguf file found for ${task.modelName}');
    }

    ggufFiles.sort((a, b) {
      final aSize = a['size'] as int? ?? 0;
      final bSize = b['size'] as int? ?? 0;
      return bSize.compareTo(aSize);
    });
    final ggufFile = ggufFiles.first;
    final fileName = (ggufFile['path'] as String).split('/').last;
    resolvedUrl =
        'https://huggingface.co/${task.modelName}/resolve/main/${ggufFile['path']}';
    resolvedPath = '${dir.path}/$fileName';

    return (downloadUrl: resolvedUrl, savePath: resolvedPath);
  }

  Future<void> _persist(DownloadTask task) async {
    await _storage.update(
      'download_tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  void _broadcastState() {
    if (_stateController.isClosed) return;
    _stateController.add(List.unmodifiable(_tasks));
  }

  Future<void> dispose() async {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    await _stateController.close();
  }
}
