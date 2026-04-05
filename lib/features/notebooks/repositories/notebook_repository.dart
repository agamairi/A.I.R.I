/// Notebook repository — notebook CRUD and document indexing orchestration.
library;

import 'dart:io';

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:local_ai_chat/features/notebooks/services/chunk_store.dart';
import 'package:local_ai_chat/features/notebooks/services/document_parser_service.dart';
import 'package:local_ai_chat/features/notebooks/services/embedding_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class NotebookRepository {
  final StorageService _storage;
  final DocumentParserService _parser;
  final ChunkStore _chunkStore;
  final EmbeddingProvider _embedding;

  NotebookRepository(
    this._storage,
    this._parser,
    this._chunkStore,
    this._embedding,
  );

  // ---------------------------------------------------------------------------
  // Notebook CRUD
  // ---------------------------------------------------------------------------

  Future<void> createNotebook(Notebook notebook) async {
    await _storage.insert('notebooks', notebook.toMap());
  }

  Future<List<Notebook>> listNotebooks() async {
    final rows = await _storage.query('notebooks', orderBy: 'updatedAt DESC');
    return rows.map(Notebook.fromMap).toList();
  }

  Future<Notebook?> getNotebook(String id) async {
    final rows = await _storage.query(
      'notebooks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Notebook.fromMap(rows.first);
  }

  Future<void> updateNotebook(Notebook notebook) async {
    await _storage.update(
      'notebooks',
      notebook.toMap(),
      where: 'id = ?',
      whereArgs: [notebook.id],
    );
  }

  Future<void> deleteNotebook(String id) async {
    // Delete chunks for all documents in this notebook
    final docs = await listDocuments(id);
    for (final doc in docs) {
      await _chunkStore.deleteChunksForDocument(doc.id);
    }
    // Delete the stored document files
    for (final doc in docs) {
      try {
        final file = File(doc.filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _storage
        .delete('documents', where: 'notebookId = ?', whereArgs: [id]);
    await _storage.delete('notebooks', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Document management
  // ---------------------------------------------------------------------------

  Future<List<DocumentSource>> listDocuments(String notebookId) async {
    final rows = await _storage.query(
      'documents',
      where: 'notebookId = ?',
      whereArgs: [notebookId],
      orderBy: 'addedAt DESC',
    );
    return rows.map(DocumentSource.fromMap).toList();
  }

  /// Returns the count of documents for a notebook.
  Future<int> documentCount(String notebookId) async {
    final rows = await _storage.query(
      'documents',
      where: 'notebookId = ?',
      whereArgs: [notebookId],
    );
    return rows.length;
  }

  /// Copies a picked file to the app's permanent notebook storage directory.
  ///
  /// Picked files may reside in a temporary cache that gets cleaned up by the
  /// OS (especially on Android). Copying ensures the file survives cache purges.
  Future<String> _copyToPermanentStorage(
    String sourcePath,
    String notebookId,
    String fileName,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final notebookDir =
        Directory(p.join(appDir.path, 'notebooks', notebookId));
    if (!await notebookDir.exists()) {
      await notebookDir.create(recursive: true);
    }

    // Avoid name collisions by prefixing with a short UUID segment
    final uniqueName = '${const Uuid().v4().substring(0, 8)}_$fileName';
    final destPath = p.join(notebookDir.path, uniqueName);
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Imports a document into a notebook: copy, parse, chunk, embed, store.
  Future<DocumentSource> importDocument({
    required String notebookId,
    required String filePath,
    required String fileName,
    int chunkSize = 512,
    int chunkOverlap = 64,
  }) async {
    // Copy to permanent storage first
    final permanentPath =
        await _copyToPermanentStorage(filePath, notebookId, fileName);

    final type = DocumentParserService.detectType(permanentPath);
    final doc = DocumentSource(
      id: const Uuid().v4(),
      notebookId: notebookId,
      fileName: fileName,
      filePath: permanentPath,
      type: type,
      addedAt: DateTime.now(),
      status: DocumentStatus.pending,
    );

    await _storage.insert('documents', doc.toMap());

    try {
      // Parse
      final text = await _parser.parse(permanentPath, type);

      // Chunk
      final chunkTexts = _parser.chunkText(
        text,
        chunkSize: chunkSize,
        overlap: chunkOverlap,
      );
      if (chunkTexts.isEmpty) {
        throw const FormatException('No indexable text chunks were produced');
      }

      // Embed and store each chunk
      final chunks = <Chunk>[];
      for (int i = 0; i < chunkTexts.length; i++) {
        List<double>? embedding;
        if (_embedding.isAvailable) {
          try {
            embedding = await _embedding.embed(chunkTexts[i]);
          } catch (_) {
            // Embedding failed; continue without
          }
        }

        chunks.add(Chunk(
          id: const Uuid().v4(),
          documentId: doc.id,
          content: chunkTexts[i],
          index: i,
          embedding: embedding,
        ));
      }

      await _chunkStore.addChunks(chunks);

      doc.status = DocumentStatus.indexed;
    } catch (e) {
      await _chunkStore.deleteChunksForDocument(doc.id);
      doc.status = DocumentStatus.failed;
      doc.errorMessage = e.toString();
    }

    await _storage
        .update('documents', doc.toMap(), where: 'id = ?', whereArgs: [doc.id]);
    return doc;
  }

  /// Removes a document, its chunks, and its stored file.
  Future<void> deleteDocument(String documentId) async {
    // Find the document to get its file path
    final rows = await _storage.query(
      'documents',
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final filePath = rows.first['filePath'] as String?;
      if (filePath != null) {
        try {
          final file = File(filePath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    await _chunkStore.deleteChunksForDocument(documentId);
    await _storage
        .delete('documents', where: 'id = ?', whereArgs: [documentId]);
  }
}
