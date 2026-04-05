/// Context assembler — assembles the full prompt from layered context sources.
///
/// Precedence:
/// 1. Base system prompt
/// 2. Chat/notebook custom system prompt
/// 3. User profile context
/// 4. Notebook/RAG retrieved context
/// 5. Compressed long-term chat memory
/// 6. Recent raw messages
/// 7. Current user input (included in messages)
library;

import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/prompts/repositories/system_prompt_repository.dart';
import 'package:local_ai_chat/features/profile/repositories/user_profile_repository.dart';

class ContextAssembler {
  final SystemPromptRepository _promptRepo;
  final UserProfileRepository _profileRepo;

  ContextAssembler(this._promptRepo, this._profileRepo);

  static const String _defaultSystemPrompt = '''
You are A.I.R.I (AI, Real-Time, In-App). You are a highly capable and versatile AI assistant designed to assist users in a wide range of tasks. Your main objective is to provide clear, accurate, and helpful information in a friendly and approachable manner.

Your strengths include:
1. Information retrieval and clear explanations
2. Task automation and troubleshooting
3. Conversational interaction
4. Personalized assistance

Be accurate, stay neutral, be concise but informative, and use a positive, friendly tone.
''';

  /// Assembles the full context string for LLM inference.
  ///
  /// [messages] — all messages in the conversation (user + assistant).
  /// [conversationId] — for loading custom prompts.
  /// [notebookId] — if this is a notebook-grounded chat.
  /// [customSystemPrompt] — inline override attached to conversation/notebook.
  /// [ragContext] — retrieved document context from RAG pipeline.
  /// [compressedMemory] — compressed summary of earlier conversation.
  /// [strictGrounding] — if true, instructs the LLM to answer only from documents.
  Future<String> assemble({
    required List<ChatMessage> messages,
    String? conversationId,
    String? notebookId,
    String? customSystemPrompt,
    String? ragContext,
    String? compressedMemory,
    bool strictGrounding = false,
  }) async {
    final buffer = StringBuffer();

    // Layer 1: Base system prompt
    buffer.writeln('<|im_start|>system');
    buffer.writeln(_defaultSystemPrompt.trim());

    // Layer 2: Custom system prompt (inline > notebook > chat > global)
    String? customPrompt = customSystemPrompt?.trim();
    if (customPrompt == null || customPrompt.isEmpty) {
      if (notebookId != null) {
        customPrompt = await _promptRepo.getPrompt('notebook', notebookId);
      }
      customPrompt ??= conversationId != null
          ? await _promptRepo.getPrompt('chat', conversationId)
          : null;
      customPrompt ??= await _promptRepo.getPrompt('global', null);
    }

    if (customPrompt != null && customPrompt.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(customPrompt.trim());
    }

    // Layer 3: User profile context
    final profile = await _profileRepo.getProfile();
    if (profile != null && profile.hasContent) {
      final shouldInject = profile.injectInAllChats ||
          (notebookId != null && profile.injectInNotebookMode);
      if (shouldInject) {
        buffer.writeln();
        buffer.writeln('User Profile:');
        buffer.writeln(profile.toContextString());
      }
    }

    // Layer 4: RAG retrieved context
    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.writeln();
      if (strictGrounding) {
        buffer.writeln(
          'IMPORTANT: You must answer ONLY using the provided document context below. '
          'If the answer cannot be found in the documents, clearly state that the '
          'information is not available in the uploaded documents. Do not use '
          'outside knowledge.',
        );
        buffer.writeln();
      }
      buffer.writeln('Relevant document context:');
      buffer.writeln(ragContext);
    }

    // Layer 5: Compressed long-term memory
    if (compressedMemory != null && compressedMemory.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Previous conversation summary:');
      buffer.writeln(compressedMemory);
    }

    buffer.writeln('<|im_end|>');

    // Layer 6 + 7: Recent raw messages (including current user input)
    for (final msg in messages) {
      if (msg.role == MessageRole.system) continue;
      final content = msg.content.trim();
      if (content.isEmpty) continue;

      final role = msg.role == MessageRole.user ? 'user' : 'assistant';
      buffer.writeln('<|im_start|>$role');
      buffer.writeln(content);
      buffer.writeln('<|im_end|>');
    }

    // Prompt the model to respond
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }
}
