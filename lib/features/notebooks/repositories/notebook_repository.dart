/// Notebook repository — notebook CRUD and document indexing orchestration.
library;

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:local_ai_chat/features/notebooks/services/chunk_store.dart';
import 'package:local_ai_chat/features/notebooks/services/document_parser_service.dart';
import 'package:local_ai_chat/features/notebooks/services/embedding_provider.dart';
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

  /// Imports a document into a notebook: parse, chunk, embed, store.
  Future<DocumentSource> importDocument({
    required String notebookId,
    required String filePath,
    required String fileName,
    int chunkSize = 512,
    int chunkOverlap = 64,
  }) async {
    final type = DocumentParserService.detectType(filePath);
    final doc = DocumentSource(
      id: const Uuid().v4(),
      notebookId: notebookId,
      fileName: fileName,
      filePath: filePath,
      type: type,
      addedAt: DateTime.now(),
      status: DocumentStatus.pending,
    );

    await _storage.insert('documents', doc.toMap());

    try {
      // Parse
      final text = await _parser.parse(filePath, type);

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

  /// Removes a document and its chunks.
  Future<void> deleteDocument(String documentId) async {
    await _chunkStore.deleteChunksForDocument(documentId);
    await _storage
        .delete('documents', where: 'id = ?', whereArgs: [documentId]);
  }
}
