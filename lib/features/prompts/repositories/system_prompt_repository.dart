/// System prompt repository — manages global, per-chat, per-notebook prompts.
library;

import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:uuid/uuid.dart';

class SystemPromptRepository {
  final StorageService _storage;

  SystemPromptRepository(this._storage);

  /// Gets a system prompt by type and optional target ID.
  ///
  /// [type] is one of: 'global', 'chat', 'notebook'.
  /// [targetId] is the conversationId or notebookId (null for global).
  Future<String?> getPrompt(String type, String? targetId) async {
    final rows = await _storage.query(
      'system_prompts',
      where: targetId != null
          ? 'type = ? AND targetId = ?'
          : 'type = ? AND targetId IS NULL',
      whereArgs: targetId != null ? [type, targetId] : [type],
      orderBy: 'updatedAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  /// Sets or updates a system prompt.
  Future<void> setPrompt(String type, String? targetId, String content) async {
    final existingRows = await _storage.query(
      'system_prompts',
      where: targetId != null
          ? 'type = ? AND targetId = ?'
          : 'type = ? AND targetId IS NULL',
      whereArgs: targetId != null ? [type, targetId] : [type],
      orderBy: 'updatedAt DESC',
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();

    if (existingRows.isNotEmpty) {
      final rowId = existingRows.first['id'];
      await _storage.update(
        'system_prompts',
        {'content': content, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [rowId],
      );
    } else {
      await _storage.insert('system_prompts', {
        'id': const Uuid().v4(),
        'type': type,
        'targetId': targetId,
        'content': content,
        'updatedAt': now,
      });
    }
  }

  /// Deletes a system prompt.
  Future<void> deletePrompt(String type, String? targetId) async {
    if (targetId != null) {
      await _storage.delete(
        'system_prompts',
        where: 'type = ? AND targetId = ?',
        whereArgs: [type, targetId],
      );
    } else {
      await _storage.delete(
        'system_prompts',
        where: 'type = ? AND targetId IS NULL',
        whereArgs: [type],
      );
    }
  }

  /// Lists all prompts of a given type.
  Future<List<Map<String, dynamic>>> listPrompts({String? type}) async {
    return _storage.query(
      'system_prompts',
      where: type != null ? 'type = ?' : null,
      whereArgs: type != null ? [type] : null,
      orderBy: 'updatedAt DESC',
    );
  }
}
