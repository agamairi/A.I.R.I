library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/models/widgets/model_init_sheet.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/speech/viewmodels/talk_view_model.dart';

class TalkView extends StatefulWidget {
  final int drawerIndex;
  final String? conversationId;

  const TalkView({super.key, this.drawerIndex = 1, this.conversationId});

  @override
  State<TalkView> createState() => _TalkViewState();
}

class _TalkViewState extends State<TalkView> {
  final ScrollController _scrollController = ScrollController();
  late final TalkViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<TalkViewModel>();
    if (widget.conversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _vm.loadFromConversation(widget.conversationId!);
      });
    }
  }

  @override
  void dispose() {
    _vm.stopConversation();
    _vm.resetSession();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openModelSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ModelInitSheet(
        runtimeService: context.read<ModelRuntimeService>(),
        settingsRepository: context.read<SettingsRepository>(),
        onApplied: () {
          context.read<TalkViewModel>().clearError();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TalkViewModel>(
      builder: (context, vm, _) {
        final theme = Theme.of(context);

        // Auto-scroll when messages change or streaming content updates.
        _scrollToBottom();

        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            title: Text(vm.readOnly ? 'Talk History' : 'Talk'),
            actions: [
              if (!vm.readOnly)
                IconButton(
                  onPressed: () => _openModelSheet(context),
                  icon: const Icon(Icons.tune),
                  tooltip: 'Model settings',
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // ── Message list ──
                Expanded(
                  child: _buildMessageList(vm, theme),
                ),

                // ── Error message ──
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Text(
                      vm.errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Don't show controls in read-only mode
                if (!vm.readOnly) ...[
                  // ── Status text ──
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _statusText(vm),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // ── Central conversation orb ──
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: _ConversationOrb(
                        state: vm.state,
                        conversationActive: vm.conversationActive,
                        modelLoaded: vm.modelLoaded,
                        onTap: () => _handleOrbTap(vm),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageList(TalkViewModel vm, ThemeData theme) {
    final finalized = vm.messages;
    final hasLiveUser = vm.currentSpokenText.isNotEmpty;
    final hasLiveResponse = vm.currentResponse.isNotEmpty;
    final totalItems = finalized.length +
        (hasLiveUser ? 1 : 0) +
        (hasLiveResponse ? 1 : 0);

    if (totalItems == 0 && !vm.conversationActive) {
      return Center(
        child: Text(
          vm.readOnly
              ? 'No messages in this session.'
              : (vm.modelLoaded
                  ? 'Tap the button below to start talking.'
                  : 'Load a model in settings first.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Finalized messages first
        if (index < finalized.length) {
          final msg = finalized[index];
          final isUser = msg.role == MessageRole.user;
          return _Bubble(
            label: isUser ? 'You' : 'A.I.R.I',
            text: msg.content,
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            textColor: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          );
        }

        // Live user transcription
        final liveIndex = index - finalized.length;
        if (liveIndex == 0 && hasLiveUser) {
          return _Bubble(
            label: 'You',
            text: vm.currentSpokenText,
            color: theme.colorScheme.primary,
            textColor: theme.colorScheme.onPrimary,
          );
        }

        // Live streaming response
        return _Bubble(
          label: 'A.I.R.I',
          text: vm.currentResponse,
          color: theme.colorScheme.surfaceContainerHighest,
          textColor: theme.colorScheme.onSurface,
        );
      },
    );
  }

  void _handleOrbTap(TalkViewModel vm) {
    if (!vm.modelLoaded) return;

    if (!vm.conversationActive) {
      vm.startConversation();
    } else if (vm.state == TalkState.generating ||
        vm.state == TalkState.speaking) {
      vm.interrupt();
    } else {
      vm.stopConversation();
    }
  }

  String _statusText(TalkViewModel vm) {
    if (!vm.modelLoaded) return '';
    switch (vm.state) {
      case TalkState.idle:
        return vm.conversationActive ? 'Starting...' : '';
      case TalkState.listening:
        return 'Listening...';
      case TalkState.generating:
        return 'Thinking...';
      case TalkState.speaking:
        return 'Speaking... (tap to interrupt)';
    }
  }
}

// ── Animated conversation orb ────────────────────────────────────────────────

class _ConversationOrb extends StatefulWidget {
  final TalkState state;
  final bool conversationActive;
  final bool modelLoaded;
  final VoidCallback onTap;

  const _ConversationOrb({
    required this.state,
    required this.conversationActive,
    required this.modelLoaded,
    required this.onTap,
  });

  @override
  State<_ConversationOrb> createState() => _ConversationOrbState();
}

class _ConversationOrbState extends State<_ConversationOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_ConversationOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.conversationActive != widget.conversationActive) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.state == TalkState.listening ||
        widget.state == TalkState.speaking) {
      _controller.repeat(reverse: true);
    } else if (widget.state == TalkState.generating) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const baseSize = 120.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          double scale = 1.0;
          double pulseOpacity = 0.0;

          switch (widget.state) {
            case TalkState.listening:
              scale = 1.0 + (_controller.value * 0.15);
              pulseOpacity = 0.3 * (1 - _controller.value);
              break;
            case TalkState.generating:
              scale = 1.0 + (sin(_controller.value * 2 * pi) * 0.05);
              break;
            case TalkState.speaking:
              scale = 1.0 + (sin(_controller.value * 4 * pi) * 0.08);
              pulseOpacity = 0.2 * (1 - _controller.value);
              break;
            case TalkState.idle:
              break;
          }

          final orbColor = _orbColor(theme);

          return SizedBox(
            width: baseSize * 1.5,
            height: baseSize * 1.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring
                if (pulseOpacity > 0)
                  Container(
                    width: baseSize * scale * 1.3,
                    height: baseSize * scale * 1.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: orbColor.withValues(alpha: pulseOpacity),
                    ),
                  ),
                // Main orb
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: baseSize * scale,
                  height: baseSize * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: orbColor,
                    boxShadow: widget.conversationActive
                        ? [
                            BoxShadow(
                              color: orbColor.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _orbIcon(theme),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _orbColor(ThemeData theme) {
    if (!widget.modelLoaded) {
      return theme.colorScheme.surfaceContainerHighest;
    }
    switch (widget.state) {
      case TalkState.idle:
        return theme.colorScheme.primary;
      case TalkState.listening:
        return theme.colorScheme.primary;
      case TalkState.generating:
        return theme.colorScheme.tertiary;
      case TalkState.speaking:
        return theme.colorScheme.secondary;
    }
  }

  Widget _orbIcon(ThemeData theme) {
    if (!widget.modelLoaded) {
      return Icon(Icons.mic_off,
          color: theme.colorScheme.onSurfaceVariant, size: 40);
    }

    if (widget.state == TalkState.generating) {
      return SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: theme.colorScheme.onTertiary,
        ),
      );
    }

    final IconData icon;
    final Color color;

    switch (widget.state) {
      case TalkState.idle:
        icon = widget.conversationActive ? Icons.mic : Icons.mic_none;
        color = theme.colorScheme.onPrimary;
        break;
      case TalkState.listening:
        icon = Icons.mic;
        color = theme.colorScheme.onPrimary;
        break;
      case TalkState.generating:
        icon = Icons.auto_awesome;
        color = theme.colorScheme.onTertiary;
        break;
      case TalkState.speaking:
        icon = Icons.volume_up;
        color = theme.colorScheme.onSecondary;
        break;
    }

    return Icon(icon, color: color, size: 40);
  }
}

// ── Chat bubble ──────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final Color textColor;

  const _Bubble({
    required this.label,
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: textColor)),
        ],
      ),
    );
  }
}
