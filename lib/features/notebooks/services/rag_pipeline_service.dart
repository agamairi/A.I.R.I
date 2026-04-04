/// RAG pipeline service — orchestrates retrieval + context injection.
library;

import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/features/notebooks/services/retrieval_service.dart';

class RagPipelineService {
  final RetrievalService _retrieval;

  RagPipelineService(this._retrieval);

  /// Retrieves relevant context for a query and formats it for injection.
  ///
  /// Returns formatted context string with optional citations.
  Future<String> retrieveContext({
    required String notebookId,
    required String query,
    int topK = 5,
    RetrievalMode mode = RetrievalMode.auto,
    bool includeCitations = true,
  }) async {
    final results = await _retrieval.retrieve(
      notebookId,
      RetrievalQuery(text: query, topK: topK, mode: mode),
    );

    if (results.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();

    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      if (includeCitations) {
        buffer.writeln(
            '[Source ${i + 1}${r.documentTitle != null ? ' - ${r.documentTitle}' : ''}]:');
      }
      buffer.writeln(r.chunk.content.trim());
      buffer.writeln();
    }

    return buffer.toString().trim();
  }
}
