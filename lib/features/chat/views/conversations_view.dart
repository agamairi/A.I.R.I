library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/chat/viewmodels/conversations_view_model.dart';

class ConversationsView extends StatefulWidget {
  final void Function(String conversationId)? onConversationSelected;
  final int drawerIndex;

  const ConversationsView({
    super.key,
    this.onConversationSelected,
    this.drawerIndex = 2,
  });

  @override
  State<ConversationsView> createState() => _ConversationsViewState();
}

class _ConversationsViewState extends State<ConversationsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConversationsViewModel>().load(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationsViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            title: const Text('Chat History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh history',
                onPressed: () => vm.load(force: true),
              ),
            ],
          ),
          body: vm.isLoading
              ? const Center(child: CircularProgressIndicator())
              : vm.conversations.isEmpty
                  ? const Center(child: Text('No conversations yet.'))
                  : ListView.builder(
                      itemCount: vm.conversations.length,
                      itemBuilder: (context, index) {
                        final convo = vm.conversations[index];
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(convo.title),
                          subtitle: Text(_formatDate(convo.updatedAt)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => vm.deleteConversation(convo.id),
                          ),
                          onTap: () =>
                              widget.onConversationSelected?.call(convo.id),
                        );
                      },
                    ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
