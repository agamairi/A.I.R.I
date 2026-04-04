/// Conversation repository — CRUD for conversations + messages.
library;

import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';

class ConversationRepository {
  final StorageService _storage;

  ConversationRepository(this._storage);

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  Future<void> createConversation(Conversation convo) async {
    await _storage.insert('conversations', convo.toMap());
  }

  Future<List<Conversation>> listConversations() async {
    final rows =
        await _storage.query('conversations', orderBy: 'updatedAt DESC');
    return rows.map(Conversation.fromMap).toList();
  }

  Future<Conversation?> getConversation(String id) async {
    final rows = await _storage.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  Future<void> updateConversation(Conversation convo) async {
    await _storage.update(
      'conversations',
      convo.toMap(),
      where: 'id = ?',
      whereArgs: [convo.id],
    );
  }

  Future<void> deleteConversation(String id) async {
    await _storage
        .delete('messages', where: 'conversationId = ?', whereArgs: [id]);
    await _storage.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Future<void> addMessage(ChatMessage message) async {
    await _storage.insert('messages', message.toMap());
  }

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final rows = await _storage.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> updateMessage(ChatMessage message) async {
    await _storage.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteMessage(String id) async {
    await _storage.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
