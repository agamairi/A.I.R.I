/// Embedding provider — abstract interface for generating embeddings,
/// with a lexical TF-IDF fallback.
library;

import 'dart:math';

/// Abstract interface for embedding generation.
abstract class EmbeddingProvider {
  /// Generates an embedding vector for the given text.
  Future<List<double>> embed(String text);

  /// Whether this provider is available (model loaded, etc).
  bool get isAvailable;

  /// Whether this provider offers semantic embeddings (not lexical fallback).
  bool get supportsSemanticSearch;
}

/// Lexical fallback embedding using simple term-frequency hashing.
/// This provides a basic "embedding" for cosine similarity without
/// requiring a real embedding model.
class LexicalEmbeddingProvider implements EmbeddingProvider {
  static const int _vectorSize = 256;

  @override
  bool get isAvailable => true;

  @override
  bool get supportsSemanticSearch => false;

  @override
  Future<List<double>> embed(String text) async {
    final vector = List<double>.filled(_vectorSize, 0.0);
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final wordCount = words.length;

    for (final word in words) {
      if (word.isEmpty) continue;
      // Hash to a bucket
      final bucket = word.hashCode.abs() % _vectorSize;
      vector[bucket] += 1.0 / wordCount;
    }

    // L2 normalize
    final norm = sqrt(vector.fold<double>(0, (sum, v) => sum + v * v));
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }
}

/// Cosine similarity between two vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = sqrt(normA) * sqrt(normB);
  return denom > 0 ? dot / denom : 0.0;
}
