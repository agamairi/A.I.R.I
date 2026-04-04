library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/models/widgets/model_init_sheet.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/speech/viewmodels/talk_view_model.dart';

class TalkView extends StatelessWidget {
  final int drawerIndex;

  const TalkView({super.key, this.drawerIndex = 1});

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

        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: drawerIndex),
          appBar: AppBar(
            title: const Text('Talk'),
            actions: [
              IconButton(
                onPressed: () => _openModelSheet(context),
                icon: const Icon(Icons.tune),
                tooltip: 'Model settings',
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (vm.spokenText.isNotEmpty)
                          _Bubble(
                            label: 'You',
                            text: vm.spokenText,
                            color: theme.colorScheme.primary,
                            textColor: theme.colorScheme.onPrimary,
                          ),
                        if (vm.response.isNotEmpty)
                          _Bubble(
                            label: 'A.I.R.I',
                            text: vm.response,
                            color: theme.colorScheme.surfaceContainerHighest,
                            textColor: theme.colorScheme.onSurface,
                          ),
                        if (vm.spokenText.isEmpty && vm.response.isEmpty)
                          Expanded(
                            child: Center(
                              child: Text(
                                vm.modelLoaded
                                    ? 'Tap Start Listening, then Generate.'
                                    : 'Load a model in settings first.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (vm.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        vm.errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              vm.isGenerating ? null : vm.toggleListening,
                          icon: Icon(vm.isListening ? Icons.stop : Icons.mic),
                          label: Text(
                            vm.isListening
                                ? 'Stop Listening'
                                : 'Start Listening',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: vm.isGenerating || !vm.modelLoaded
                              ? null
                              : vm.generateResponse,
                          icon: vm.isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_awesome),
                          label: Text(
                            vm.isGenerating ? 'Generating...' : 'Generate',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (vm.isSpeaking)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Speaking response...'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
