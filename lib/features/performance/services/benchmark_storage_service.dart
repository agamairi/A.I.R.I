/// Benchmark storage service — persists benchmark runs as structured JSON.
library;

import 'dart:convert';
import 'dart:io';

import 'package:local_ai_chat/features/performance/models/benchmark_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class BenchmarkStorageService {
  static const _fileName = 'benchmark_results.json';

  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _fileName);
  }

  /// Saves a benchmark run, appending to existing results.
  Future<void> saveRun(BenchmarkRun run) async {
    final runs = await loadAllRuns();
    runs.add(run);
    await _writeRuns(runs);
  }

  /// Loads all stored benchmark runs.
  Future<List<BenchmarkRun>> loadAllRuns() async {
    final path = await _filePath;
    final file = File(path);
    if (!file.existsSync()) return [];

    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      return list
          .map((e) => BenchmarkRun.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Loads runs filtered by model name.
  Future<List<BenchmarkRun>> loadRunsForModel(String modelName) async {
    final all = await loadAllRuns();
    return all.where((r) => r.modelName == modelName).toList();
  }

  /// Loads the most recent run for a given profile and model.
  Future<BenchmarkRun?> loadLatestRun(
    String modelName,
    String profileName,
  ) async {
    final runs = await loadAllRuns();
    final matching = runs
        .where(
            (r) => r.modelName == modelName && r.profile.name == profileName)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return matching.isEmpty ? null : matching.first;
  }

  /// Deletes all stored benchmark data.
  Future<void> clearAll() async {
    final path = await _filePath;
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _writeRuns(List<BenchmarkRun> runs) async {
    final path = await _filePath;
    final file = File(path);
    final json = jsonEncode(runs.map((r) => r.toJson()).toList());
    await file.writeAsString(json);
  }
}
