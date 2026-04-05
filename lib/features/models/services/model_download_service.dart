/// Persistent download service with queue management.
/// Downloads survive screen navigation and restore state on reopen.
/// Supports resumable downloads via HTTP Range headers.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:local_ai_chat/core/models/download_task.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';

class ModelDownloadService {
  final StorageService _storage;
  late final Dio _dio;

  final Map<String, CancelToken> _cancelTokens = {};
  bool _queuePumpRunning = false;

  /// Tracks when the last progress update was received for active downloads.
  /// Used by [handleAppResumed] to detect stalled downloads.
  DateTime? _lastProgressTime;

  /// Stream controller that broadcasts download state changes.
  final _stateController = StreamController<List<DownloadTask>>.broadcast();
  Stream<List<DownloadTask>> get downloadStateStream => _stateController.stream;

  List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  ModelDownloadService(this._storage) {
    _dio = Dio();
    _dio.interceptors.add(_RateLimitInterceptor(_dio));
  }

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
        // Don't reset progress/downloadedBytes — we'll resume from the
        // partial file on disk using Range headers.
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

  /// Called when the app resumes from background. Detects stalled active
  /// downloads whose HTTP connection may have been broken by the OS and
  /// re-queues them so they resume from the partial file.
  void handleAppResumed() {
    final now = DateTime.now();
    bool changed = false;

    for (final t in _tasks) {
      if (t.status == DownloadStatus.active) {
        // If no progress was received in the last 10 seconds, assume the
        // connection died while the app was backgrounded.
        final stalled = _lastProgressTime == null ||
            now.difference(_lastProgressTime!).inSeconds > 10;

        if (stalled) {
          // Cancel the old HTTP request if it's still lingering
          _cancelTokens[t.id]?.cancel();
          _cancelTokens.remove(t.id);

          t.status = DownloadStatus.queued;
          _persist(t);
          changed = true;
        }
      }
    }

    if (changed) {
      _broadcastState();
      unawaited(_processQueue());
    }
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

  /// Retries a failed download. Preserves downloaded bytes so it can resume
  /// from the partial file via HTTP Range headers.
  Future<void> retry(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.status = DownloadStatus.queued;
    // Don't reset downloadedBytes or progress — _startDownload will check the
    // partial file on disk and resume from there.
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

      // Persist the resolved URL/path back to the task so retries don't need
      // to re-resolve from the HuggingFace API.
      if (task.downloadUrl.isEmpty || task.savePath.isEmpty) {
        task.downloadUrl = resolved.downloadUrl;
        task.savePath = resolved.savePath;
        await _persist(task);
      }

      final saveFile = File(resolved.savePath);
      await saveFile.parent.create(recursive: true);

      // Check for an existing partial file to enable resume.
      int existingBytes = 0;
      if (await saveFile.exists()) {
        existingBytes = await saveFile.length();
      }

      // If we already know the total and the file is complete, skip download.
      if (task.totalBytes != null &&
          task.totalBytes! > 0 &&
          existingBytes >= task.totalBytes!) {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.downloadedBytes = existingBytes;
        await _persist(task);
        _broadcastState();
        return;
      }

      int lastProgressPersistMs = 0;
      _lastProgressTime = DateTime.now();

      // Use streaming download with Range header for resume support.
      final response = await _dio.get<ResponseBody>(
        resolved.downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: existingBytes > 0
              ? {'Range': 'bytes=$existingBytes-'}
              : null,
        ),
      );

      // Determine total size from Content-Range or Content-Length.
      final contentRange =
          response.headers.value('content-range'); // e.g. "bytes 1024-9999/10000"
      int totalBytes;
      if (contentRange != null) {
        // Content-Range: bytes <start>-<end>/<total>
        final total = contentRange.split('/').last;
        totalBytes = int.tryParse(total) ?? -1;
      } else {
        final contentLength =
            int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
        totalBytes = contentLength > 0 ? contentLength + existingBytes : -1;
      }

      if (totalBytes > 0) {
        task.totalBytes = totalBytes;
      }

      // Write the stream to file in append mode.
      final sink = saveFile.openWrite(mode: FileMode.append);
      int received = existingBytes;

      try {
        await for (final chunk in response.data!.stream) {
          if (cancelToken.isCancelled) break;

          sink.add(chunk);
          received += chunk.length;
          _lastProgressTime = DateTime.now();

          if (totalBytes > 0) {
            task.progress = received / totalBytes;
            task.totalBytes = totalBytes;
            task.downloadedBytes = received;
            _broadcastState();

            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (nowMs - lastProgressPersistMs > 1500) {
              lastProgressPersistMs = nowMs;
              unawaited(_persist(task));
            }
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!cancelToken.isCancelled) {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.downloadedBytes = received;
      }
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
    final totalSize = ggufFile['size'] as int?;
    resolvedUrl =
        'https://huggingface.co/${task.modelName}/resolve/main/${ggufFile['path']}';
    resolvedPath = '${dir.path}/$fileName';

    // Store total size from the tree API so progress is accurate from the start.
    if (totalSize != null && totalSize > 0) {
      task.totalBytes = totalSize;
    }

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
        final retryAfterHeader = err.response?.headers.value('retry-after');
        int delaySeconds;
        if (retryAfterHeader != null) {
          delaySeconds =
              int.tryParse(retryAfterHeader) ?? _backoffSeconds(retryCount);
        } else {
          delaySeconds = _backoffSeconds(retryCount);
        }

        await Future.delayed(Duration(seconds: delaySeconds));

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

  int _backoffSeconds(int retryCount) {
    return math.min(2 * math.pow(2, retryCount).toInt(), 30);
  }
}
