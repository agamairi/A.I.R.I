/// Chunk store — stores and retrieves document chunks from sqflite.
library;

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';

class ChunkStore {
  final StorageService _storage;

  ChunkStore(this._storage);

  /// Stores a chunk.
  Future<void> addChunk(Chunk chunk) async {
    await _storage.insert('chunks', chunk.toMap());
  }

  /// Stores multiple chunks.
  Future<void> addChunks(List<Chunk> chunks) async {
    for (final chunk in chunks) {
      await _storage.insert('chunks', chunk.toMap());
    }
  }

  /// Gets all chunks for a document.
  Future<List<Chunk>> getChunksForDocument(String documentId) async {
    final rows = await _storage.query(
      'chunks',
      where: 'documentId = ?',
      whereArgs: [documentId],
      orderBy: 'chunkIndex ASC',
    );
    return rows.map(Chunk.fromMap).toList();
  }

  /// Gets all chunks for a notebook (across all its documents).
  Future<List<Chunk>> getChunksForNotebook(String notebookId) async {
    // Get all document IDs for this notebook
    final docRows = await _storage.query(
      'documents',
      where: 'notebookId = ?',
      whereArgs: [notebookId],
    );
    final docIds = docRows.map((r) => r['id'] as String).toList();

    if (docIds.isEmpty) return [];

    final placeholders = List<String>.filled(docIds.length, '?').join(',');
    final rows = await _storage.query(
      'chunks',
      where: 'documentId IN ($placeholders)',
      whereArgs: docIds,
      orderBy: 'chunkIndex ASC',
    );
    return rows.map(Chunk.fromMap).toList();
  }

  /// Deletes all chunks for a document.
  Future<void> deleteChunksForDocument(String documentId) async {
    await _storage.delete(
      'chunks',
      where: 'documentId = ?',
      whereArgs: [documentId],
    );
  }
}
