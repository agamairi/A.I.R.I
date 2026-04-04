library;

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/chat/repositories/conversation_repository.dart';

class ConversationsViewModel extends ChangeNotifier {
  final ConversationRepository _conversationRepository;

  ConversationsViewModel(this._conversationRepository);

  List<Conversation> _conversations = <Conversation>[];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _loadedOnce = false;

  Future<void> load({bool force = false}) async {
    if (_isLoading || (_loadedOnce && !force)) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _conversations = await _conversationRepository.listConversations();
      _loadedOnce = true;
    } catch (e) {
      _errorMessage = 'Failed to load conversations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String id) async {
    try {
      await _conversationRepository.deleteConversation(id);
      _conversations.removeWhere((conversation) => conversation.id == id);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete conversation: $e';
      notifyListeners();
    }
  }
}
