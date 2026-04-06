/// Chat template formatter — converts Ollama/OpenAI message arrays into
/// a fully formatted prompt string using ChatML (`<|im_start|>` / `<|im_end|>`)
/// markers that the local LLM expects.
library;

/// Formats a list of chat messages into a ChatML prompt string.
///
/// Each message must have `role` (system | user | assistant) and `content`.
/// The returned string ends with `<|im_start|>assistant\n` to prompt the model.
String formatChatMessages(List<Map<String, dynamic>> messages) {
  final buffer = StringBuffer();

  for (final msg in messages) {
    final role = (msg['role'] as String?)?.trim() ?? 'user';
    final content = (msg['content'] as String?)?.trim() ?? '';
    if (content.isEmpty && role != 'assistant') continue;

    buffer.writeln('<|im_start|>$role');
    buffer.writeln(content);
    buffer.writeln('<|im_end|>');
  }

  // Prompt the model to respond
  buffer.write('<|im_start|>assistant\n');
  return buffer.toString();
}

/// Wraps a raw prompt string into ChatML format with an optional system prompt.
String formatRawPrompt(String prompt, {String? system}) {
  final buffer = StringBuffer();

  if (system != null && system.trim().isNotEmpty) {
    buffer.writeln('<|im_start|>system');
    buffer.writeln(system.trim());
    buffer.writeln('<|im_end|>');
  }

  buffer.writeln('<|im_start|>user');
  buffer.writeln(prompt.trim());
  buffer.writeln('<|im_end|>');
  buffer.write('<|im_start|>assistant\n');

  return buffer.toString();
}
