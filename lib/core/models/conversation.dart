/// Domain models for chat conversations and messages.
library;

class Conversation {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String? modelId;
  String? notebookId;
  String? customSystemPrompt;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelId,
    this.notebookId,
    this.customSystemPrompt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'modelId': modelId,
        'notebookId': notebookId,
        'customSystemPrompt': customSystemPrompt,
      };

  factory Conversation.fromMap(Map<String, dynamic> map) => Conversation(
        id: map['id'] as String,
        title: map['title'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        modelId: map['modelId'] as String?,
        notebookId: map['notebookId'] as String?,
        customSystemPrompt: map['customSystemPrompt'] as String?,
      );
}

enum MessageRole { system, user, assistant }

class ChatMessage {
  final String id;
  final String conversationId;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  String? imageAttachmentPath;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.imageAttachmentPath,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'imageAttachmentPath': imageAttachmentPath,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        conversationId: map['conversationId'] as String,
        role: MessageRole.values.byName(map['role'] as String),
        content: map['content'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        imageAttachmentPath: map['imageAttachmentPath'] as String?,
      );
}
