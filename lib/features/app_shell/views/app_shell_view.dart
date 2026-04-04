library;

import 'package:flutter/material.dart';
import 'package:local_ai_chat/features/chat/views/chat_view.dart';
import 'package:local_ai_chat/features/chat/views/conversations_view.dart';
import 'package:local_ai_chat/features/models/views/model_manager_view.dart';
import 'package:local_ai_chat/features/notebooks/views/notebooks_view.dart';
import 'package:local_ai_chat/features/profile/views/profile_view.dart';
import 'package:local_ai_chat/features/settings/views/settings_view.dart';
import 'package:local_ai_chat/features/speech/views/talk_view.dart';
import 'package:local_ai_chat/features/vision/views/vision_view.dart';

class AppShellView extends StatefulWidget {
  final int initialIndex;

  const AppShellView({super.key, this.initialIndex = 0});

  @override
  State<AppShellView> createState() => _AppShellViewState();
}

class _AppShellViewState extends State<AppShellView> {
  late int _selectedIndex;
  String? _selectedConversationId;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return ChatView(
          key: ValueKey('chat:${_selectedConversationId ?? 'new'}'),
          conversationId: _selectedConversationId,
          drawerIndex: 0,
        );
      case 1:
        return const TalkView(drawerIndex: 1);
      case 2:
        return ConversationsView(
          drawerIndex: 2,
          onConversationSelected: (id) {
            setState(() {
              _selectedConversationId = id;
              _selectedIndex = 0;
            });
          },
        );
      case 3:
        return const VisionView(drawerIndex: 3);
      case 4:
        return const NotebooksView(drawerIndex: 4);
      case 5:
        return const ModelManagerView(drawerIndex: 5);
      case 6:
        return const ProfileView(drawerIndex: 6);
      case 7:
        return const SettingsView(drawerIndex: 7);
      default:
        return const ChatView(drawerIndex: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }
}
