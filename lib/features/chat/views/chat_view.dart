library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
                    onSendWithAttachments: vm.sendMessageWithAttachments,
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

    // Thinking bubbles get a distinct style
    if (message.isThinking) {
      return _ThinkingBubble(message: message);
    }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show attachment thumbnails if present
            if (message.attachmentPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: message.attachmentPaths.map((path) {
                    final isImage = _isImageFile(path);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isImage
                          ? Image.file(
                              File(path),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _AttachmentChip(path: path, isUser: isUser),
                            )
                          : _AttachmentChip(path: path, isUser: isUser),
                    );
                  }).toList(),
                ),
              ),
            Text(
              message.content.isEmpty ? '...' : message.content,
              style: TextStyle(
                color: isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp');
  }
}

class _AttachmentChip extends StatelessWidget {
  final String path;
  final bool isUser;

  const _AttachmentChip({required this.path, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = path.split('/').last;
    final isPdf = path.toLowerCase().endsWith('.pdf');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.primary)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
            size: 16,
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thinking/reasoning bubble — visually distinct from regular messages.
class _ThinkingBubble extends StatelessWidget {
  final ChatMessage message;

  const _ThinkingBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology,
                  size: 16,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Thinking',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message.content.isEmpty ? '...' : message.content,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatefulWidget {
  final bool isGenerating;
  final bool enabled;
  final Future<void> Function(String value) onSend;
  final Future<void> Function(String value, List<String> attachments) onSendWithAttachments;

  const _ChatInputBar({
    required this.isGenerating,
    required this.enabled,
    required this.onSend,
    required this.onSendWithAttachments,
  });

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _pendingAttachments = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || !widget.enabled || widget.isGenerating) return;
    _controller.clear();

    if (_pendingAttachments.isNotEmpty) {
      final paths = List<String>.from(_pendingAttachments);
      setState(() => _pendingAttachments.clear());
      await widget.onSendWithAttachments(input, paths);
    } else {
      await widget.onSend(input);
    }
  }

  Future<void> _pickFiles() async {
    // Request photo/storage permission
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        for (final file in result.files) {
          if (file.path != null) {
            _pendingAttachments.add(file.path!);
          }
        }
      });
    }
  }

  void _removeAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attachment preview strip
        if (_pendingAttachments.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
              itemCount: _pendingAttachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final path = _pendingAttachments[index];
                final isImage = _isImagePath(path);

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: isImage
                          ? Image.file(
                              File(path),
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _fileThumbnail(path, theme),
                            )
                          : _fileThumbnail(path, theme),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: GestureDetector(
                        onTap: () => _removeAttachment(index),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        // Input row
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_circle_outline,
                color: widget.enabled
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              tooltip: 'Attach files',
              onPressed: widget.enabled && !widget.isGenerating
                  ? _pickFiles
                  : null,
            ),
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
        ),
      ],
    );
  }

  Widget _fileThumbnail(String path, ThemeData theme) {
    final fileName = path.split('/').last;
    final isPdf = path.toLowerCase().endsWith('.pdf');

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
            size: 24,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isImagePath(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp');
  }
}
