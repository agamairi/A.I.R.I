/// Domain models for RAG notebooks, document sources, and chunks.
library;

// ---------------------------------------------------------------------------
// Notebook
// ---------------------------------------------------------------------------

class Notebook {
  final String id;
  String title;
  String? systemPrompt;
  final DateTime createdAt;
  DateTime updatedAt;

  // RAG settings
  int chunkSize;
  int chunkOverlap;
  int topK;
  bool strictGrounding;
  bool citationsEnabled;
  RetrievalMode retrievalMode;

  Notebook({
    required this.id,
    required this.title,
    this.systemPrompt,
    required this.createdAt,
    required this.updatedAt,
    this.chunkSize = 512,
    this.chunkOverlap = 64,
    this.topK = 5,
    this.strictGrounding = false,
    this.citationsEnabled = true,
    this.retrievalMode = RetrievalMode.auto,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'systemPrompt': systemPrompt,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'chunkSize': chunkSize,
        'chunkOverlap': chunkOverlap,
        'topK': topK,
        'strictGrounding': strictGrounding ? 1 : 0,
        'citationsEnabled': citationsEnabled ? 1 : 0,
        'retrievalMode': retrievalMode.name,
      };

  factory Notebook.fromMap(Map<String, dynamic> map) => Notebook(
        id: map['id'] as String,
        title: map['title'] as String,
        systemPrompt: map['systemPrompt'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        chunkSize: map['chunkSize'] as int? ?? 512,
        chunkOverlap: map['chunkOverlap'] as int? ?? 64,
        topK: map['topK'] as int? ?? 5,
        strictGrounding: (map['strictGrounding'] as int?) == 1,
        citationsEnabled: (map['citationsEnabled'] as int?) != 0,
        retrievalMode: RetrievalMode.values.byName(
          map['retrievalMode'] as String? ?? 'auto',
        ),
      );
}

enum RetrievalMode { auto, lexical, embeddings, hybrid }

// ---------------------------------------------------------------------------
// DocumentSource
// ---------------------------------------------------------------------------

enum DocumentType { pdf, txt, markdown, other }

enum DocumentStatus { pending, indexed, failed }

class DocumentSource {
  final String id;
  final String notebookId;
  final String fileName;
  final String filePath;
  final DocumentType type;
  final DateTime addedAt;
  DocumentStatus status;
  String? errorMessage;

  DocumentSource({
    required this.id,
    required this.notebookId,
    required this.fileName,
    required this.filePath,
    required this.type,
    required this.addedAt,
    this.status = DocumentStatus.pending,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'notebookId': notebookId,
        'fileName': fileName,
        'filePath': filePath,
        'type': type.name,
        'addedAt': addedAt.toIso8601String(),
        'status': status.name,
        'errorMessage': errorMessage,
      };

  factory DocumentSource.fromMap(Map<String, dynamic> map) => DocumentSource(
        id: map['id'] as String,
        notebookId: map['notebookId'] as String,
        fileName: map['fileName'] as String,
        filePath: map['filePath'] as String,
        type: DocumentType.values.byName(map['type'] as String),
        addedAt: DateTime.parse(map['addedAt'] as String),
        status: DocumentStatus.values.byName(
          map['status'] as String? ?? 'pending',
        ),
        errorMessage: map['errorMessage'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Chunk
// ---------------------------------------------------------------------------

class Chunk {
  final String id;
  final String documentId;
  final String content;
  final int index;
  List<double>? embedding;

  Chunk({
    required this.id,
    required this.documentId,
    required this.content,
    required this.index,
    this.embedding,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'documentId': documentId,
        'content': content,
        'chunkIndex': index,
        // Embeddings stored as comma-separated floats for simplicity
        'embedding': embedding?.join(','),
      };

  factory Chunk.fromMap(Map<String, dynamic> map) {
    final embStr = map['embedding'] as String?;
    return Chunk(
      id: map['id'] as String,
      documentId: map['documentId'] as String,
      content: map['content'] as String,
      index: map['chunkIndex'] as int,
      embedding: embStr != null && embStr.isNotEmpty
          ? embStr.split(',').map(double.parse).toList()
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Retrieval
// ---------------------------------------------------------------------------

class RetrievalQuery {
  final String text;
  final int topK;
  final RetrievalMode mode;

  const RetrievalQuery({
    required this.text,
    this.topK = 5,
    this.mode = RetrievalMode.auto,
  });
}

class RetrievalResult {
  final Chunk chunk;
  final double score;
  final String? documentTitle;

  const RetrievalResult({
    required this.chunk,
    required this.score,
    this.documentTitle,
  });
}
