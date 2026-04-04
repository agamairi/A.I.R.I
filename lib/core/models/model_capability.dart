/// Model capability metadata for feature gating (vision, embeddings, etc.).
library;

class ModelCapability {
  final bool supportsText;
  final bool supportsVision;
  final bool supportsEmbeddings;
  final bool ragFriendly;

  const ModelCapability({
    this.supportsText = true,
    this.supportsVision = false,
    this.supportsEmbeddings = false,
    this.ragFriendly = true,
  });

  /// Default text-only model.
  static const textOnly = ModelCapability();

  /// Vision-capable model (e.g. LLaVA).
  static const vision = ModelCapability(
    supportsVision: true,
  );

  /// Embedding model (e.g. nomic-embed).
  static const embedding = ModelCapability(
    supportsText: false,
    supportsEmbeddings: true,
    ragFriendly: false,
  );

  Map<String, dynamic> toMap() => {
        'supportsText': supportsText ? 1 : 0,
        'supportsVision': supportsVision ? 1 : 0,
        'supportsEmbeddings': supportsEmbeddings ? 1 : 0,
        'ragFriendly': ragFriendly ? 1 : 0,
      };

  factory ModelCapability.fromMap(Map<String, dynamic> map) => ModelCapability(
        supportsText: (map['supportsText'] as int?) != 0,
        supportsVision: (map['supportsVision'] as int?) == 1,
        supportsEmbeddings: (map['supportsEmbeddings'] as int?) == 1,
        ragFriendly: (map['ragFriendly'] as int?) != 0,
      );
}
