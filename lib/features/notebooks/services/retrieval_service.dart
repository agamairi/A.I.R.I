/// Retrieval service — lexical, embedding, and hybrid retrieval.
library;

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:local_ai_chat/features/notebooks/services/chunk_store.dart';
import 'package:local_ai_chat/features/notebooks/services/embedding_provider.dart';

class RetrievalService {
  final ChunkStore _chunkStore;
  final EmbeddingProvider _embeddingProvider;
  final StorageService _storage;

  RetrievalService(this._chunkStore, this._embeddingProvider, this._storage);

  /// Retrieves relevant chunks for a query within a notebook.
  Future<List<RetrievalResult>> retrieve(
    String notebookId,
    RetrievalQuery query,
  ) async {
    final titleMap = await _loadDocumentTitles(notebookId);

    final mode = query.mode == RetrievalMode.auto
        ? (_embeddingProvider.isAvailable &&
                _embeddingProvider.supportsSemanticSearch
            ? RetrievalMode.hybrid
            : RetrievalMode.lexical)
        : query.mode;

    switch (mode) {
      case RetrievalMode.lexical:
        return _lexicalRetrieve(notebookId, query, titleMap);
      case RetrievalMode.embeddings:
        return _embeddingRetrieve(notebookId, query, titleMap);
      case RetrievalMode.hybrid:
        return _hybridRetrieve(notebookId, query, titleMap);
      case RetrievalMode.auto:
        return _lexicalRetrieve(notebookId, query, titleMap);
    }
  }

  /// Lexical retrieval — simple keyword matching.
  Future<List<RetrievalResult>> _lexicalRetrieve(
    String notebookId,
    RetrievalQuery query,
    Map<String, String> titleMap,
  ) async {
    final chunks = await _chunkStore.getChunksForNotebook(notebookId);
    final queryTerms = query.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList();
    if (queryTerms.isEmpty) return [];

    final scored = <RetrievalResult>[];
    for (final chunk in chunks) {
      final content = chunk.content.toLowerCase();
      int matchCount = 0;
      for (final term in queryTerms) {
        if (term.isNotEmpty && content.contains(term)) matchCount++;
      }
      if (matchCount > 0) {
        final score = matchCount / queryTerms.length;
        scored.add(_toResult(chunk, score, titleMap));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(query.topK).toList();
  }

  /// Embedding-based retrieval — cosine similarity.
  Future<List<RetrievalResult>> _embeddingRetrieve(
    String notebookId,
    RetrievalQuery query,
    Map<String, String> titleMap,
  ) async {
    if (!_embeddingProvider.isAvailable) return [];
    final queryEmbedding = await _embeddingProvider.embed(query.text);
    final chunks = await _chunkStore.getChunksForNotebook(notebookId);

    final scored = <RetrievalResult>[];
    for (final chunk in chunks) {
      if (chunk.embedding == null) continue;
      final score = cosineSimilarity(queryEmbedding, chunk.embedding!);
      if (score > 0) {
        scored.add(_toResult(chunk, score, titleMap));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(query.topK).toList();
  }

  /// Hybrid retrieval — weighted combination of lexical and embedding.
  Future<List<RetrievalResult>> _hybridRetrieve(
    String notebookId,
    RetrievalQuery query,
    Map<String, String> titleMap,
  ) async {
    final lexical = await _lexicalRetrieve(notebookId, query, titleMap);
    final embedding = await _embeddingRetrieve(notebookId, query, titleMap);
    if (embedding.isEmpty) {
      return lexical;
    }

    // Merge by chunk ID, weighted
    final scoreMap = <String, double>{};
    final chunkMap = <String, Chunk>{};

    for (final r in lexical) {
      scoreMap[r.chunk.id] = (scoreMap[r.chunk.id] ?? 0) + r.score * 0.4;
      chunkMap[r.chunk.id] = r.chunk;
    }
    for (final r in embedding) {
      scoreMap[r.chunk.id] = (scoreMap[r.chunk.id] ?? 0) + r.score * 0.6;
      chunkMap[r.chunk.id] = r.chunk;
    }

    final results = scoreMap.entries.map((e) {
      final chunk = chunkMap[e.key]!;
      return _toResult(chunk, e.value, titleMap);
    }).toList();

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(query.topK).toList();
  }

  RetrievalResult _toResult(
    Chunk chunk,
    double score,
    Map<String, String> titleMap,
  ) {
    return RetrievalResult(
      chunk: chunk,
      score: score,
      documentTitle: titleMap[chunk.documentId],
    );
  }

  Future<Map<String, String>> _loadDocumentTitles(String notebookId) async {
    final rows = await _storage.query(
      'documents',
      where: 'notebookId = ?',
      whereArgs: [notebookId],
    );

    final map = <String, String>{};
    for (final row in rows) {
      final id = row['id'] as String?;
      final fileName = row['fileName'] as String?;
      if (id != null && fileName != null) {
        map[id] = fileName;
      }
    }
    return map;
  }
}
