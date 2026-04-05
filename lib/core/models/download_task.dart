/// Download task model for the persistent download queue.
library;

enum DownloadStatus { queued, active, paused, completed, failed }

class DownloadTask {
  final String id;
  final String modelName;
  String downloadUrl;
  String savePath;
  DownloadStatus status;
  double progress;
  int? totalBytes;
  int? downloadedBytes;
  String? errorMessage;
  final DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.modelName,
    required this.downloadUrl,
    required this.savePath,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalBytes,
    this.downloadedBytes,
    this.errorMessage,
    required this.createdAt,
  });

  bool get isTerminal =>
      status == DownloadStatus.completed || status == DownloadStatus.failed;

  Map<String, dynamic> toMap() => {
        'id': id,
        'modelName': modelName,
        'downloadUrl': downloadUrl,
        'savePath': savePath,
        'status': status.name,
        'progress': progress,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadTask.fromMap(Map<String, dynamic> map) => DownloadTask(
        id: map['id'] as String,
        modelName: map['modelName'] as String,
        downloadUrl: map['downloadUrl'] as String,
        savePath: map['savePath'] as String,
        status: DownloadStatus.values.byName(map['status'] as String),
        progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
        totalBytes: map['totalBytes'] as int?,
        downloadedBytes: map['downloadedBytes'] as int?,
        errorMessage: map['errorMessage'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
