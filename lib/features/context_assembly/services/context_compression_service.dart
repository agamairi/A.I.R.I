/// Context compression service — summarizes long conversation history
/// to stay within context window limits.
library;

import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';

class ContextCompressionService {
  final ModelRuntimeService _runtime;

  ContextCompressionService(this._runtime);

  /// Default threshold: compress when message count exceeds this.
  static const int defaultMessageThreshold = 20;

  /// Checks if compression is needed given the current messages.
  bool shouldCompress(List<ChatMessage> messages, {int? threshold}) {
    final t = threshold ?? defaultMessageThreshold;
    // Count non-system messages
    final count = messages.where((m) => m.role != MessageRole.system).length;
    return count > t;
  }

  /// Compresses older messages into a structured summary.
  ///
  /// Returns the compressed summary string.
  /// [messagesToCompress] should be the older messages to summarize.
  /// [recentCount] is how many recent messages to keep raw (not compressed).
  Future<String> compress(
    List<ChatMessage> messagesToCompress,
  ) async {
    final filtered = messagesToCompress
        .where(
            (m) => m.role != MessageRole.system && m.content.trim().isNotEmpty)
        .toList();
    if (filtered.isEmpty) return '';

    if (!_runtime.isLoaded) {
      throw StateError('Model must be loaded to compress context');
    }

    // Build compression prompt
    final prompt = _buildCompressionPrompt(filtered);

    // Use the model to generate a structured summary
    final buffer = StringBuffer();
    final stream = _runtime.generateStream(prompt);
    await for (final token in stream) {
      buffer.write(token);
    }

    final summary = buffer.toString().trim();
    return summary.isEmpty ? _fallbackSummary(filtered) : summary;
  }

  /// Splits messages into [toCompress, toKeep] based on recentCount.
  (List<ChatMessage>, List<ChatMessage>) splitMessages(
    List<ChatMessage> messages, {
    int recentCount = 6,
  }) {
    final nonSystem =
        messages.where((m) => m.role != MessageRole.system).toList();

    if (nonSystem.length <= recentCount) {
      return (<ChatMessage>[], nonSystem);
    }

    final splitPoint = nonSystem.length - recentCount;
    return (
      nonSystem.sublist(0, splitPoint),
      nonSystem.sublist(splitPoint),
    );
  }

  String _buildCompressionPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('<|im_start|>system');
    buffer.writeln(
        'You are a conversation summarizer. Given the following conversation, '
        'produce a structured summary that preserves:');
    buffer.writeln('- Key facts and decisions');
    buffer.writeln('- Unresolved questions or tasks');
    buffer.writeln('- User preferences and instructions');
    buffer.writeln('- Important context that should be remembered');
    buffer.writeln();
    buffer.writeln('Be concise but comprehensive. Use bullet points. '
        'Do not invent information not present in the conversation.');
    buffer.writeln('<|im_end|>');

    buffer.writeln('<|im_start|>user');
    buffer.writeln('Summarize this conversation:');
    buffer.writeln();

    for (final msg in messages) {
      final role = msg.role == MessageRole.user ? 'User' : 'Assistant';
      buffer.writeln('$role: ${msg.content}');
    }

    buffer.writeln('<|im_end|>');
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  String _fallbackSummary(List<ChatMessage> messages) {
    final keyLines = messages
        .take(8)
        .map((m) =>
            '${m.role == MessageRole.user ? 'User' : 'Assistant'}: ${m.content.trim()}')
        .toList();
    return keyLines.join('\n');
  }
}
