library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/chat/viewmodels/chat_view_model.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/models/widgets/model_init_sheet.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';

class ChatView extends StatefulWidget {
  final String? conversationId;
  final String? notebookId;
  final int drawerIndex;

  const ChatView({
    super.key,
    this.conversationId,
    this.notebookId,
    this.drawerIndex = 0,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final ChatViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<ChatViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.conversationId;
      if (id != null) {
        _vm.loadConversation(id);
      } else if (widget.notebookId != null) {
        _vm.createConversation(
          title: 'Notebook Chat',
          notebookId: widget.notebookId,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId &&
        widget.conversationId != null) {
      _vm.loadConversation(widget.conversationId!);
    }
  }

  @override
  void dispose() {
    _vm.cancelGeneration();
    super.dispose();
  }

  Future<void> _openModelSheet() async {
    final runtime = context.read<ModelRuntimeService>();
    final settings = context.read<SettingsRepository>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ModelInitSheet(
        runtimeService: runtime,
        settingsRepository: settings,
        onApplied: () {
          if (mounted) {
            context.read<ChatViewModel>().clearError();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatViewModel>(
      builder: (context, vm, _) {
        final theme = Theme.of(context);

        return Scaffold(
          drawer: widget.drawerIndex >= 0 ? AppShellDrawer(selectedIndex: widget.drawerIndex) : null,
          appBar: AppBar(
            leading: widget.drawerIndex < 0 ? const BackButton() : null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vm.conversation?.title ?? 'Chat'),
                if (vm.notebookTitle != null)
                  Text(
                    'Grounded in: ${vm.notebookTitle}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.green,
                        ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Model settings',
                onPressed: _openModelSheet,
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New Chat',
                onPressed: () => vm.createConversation(),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (vm.isLoadingConversation)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: vm.messages.isEmpty
                      ? _EmptyState(modelLoaded: vm.modelLoaded)
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          itemCount: vm.messages.length,
                          itemBuilder: (context, index) {
                            final msg = vm.messages[index];
                            return _MessageBubble(message: msg);
                          },
                        ),
                ),
                if (vm.errorMessage != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(
                      vm.errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _ChatInputBar(
                    isGenerating: vm.isGenerating,
                    enabled: vm.modelLoaded,
                    onSend: vm.sendMessage,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool modelLoaded;

  const _EmptyState({required this.modelLoaded});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        modelLoaded
            ? 'Start chatting with A.I.R.I.'
            : 'No model loaded. Open model settings to initialize one.',
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.content.isEmpty ? '...' : message.content,
          style: TextStyle(
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatefulWidget {
  final bool isGenerating;
  final bool enabled;
  final Future<void> Function(String value) onSend;

  const _ChatInputBar({
    required this.isGenerating,
    required this.enabled,
    required this.onSend,
  });

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || !widget.enabled || widget.isGenerating) return;
    _controller.clear();
    await widget.onSend(input);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: widget.enabled && !widget.isGenerating,
            decoration: InputDecoration(
              hintText: 'Type a message...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        widget.isGenerating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.send),
                onPressed: widget.enabled ? _submit : null,
              ),
      ],
    );
  }
}
