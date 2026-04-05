library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/features/app_shell/viewmodels/theme_view_model.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/network_access/services/lan_server_service.dart';
import 'package:local_ai_chat/features/settings/viewmodels/settings_view_model.dart';
import 'package:local_ai_chat/features/web_access/services/web_access_service.dart';

class SettingsView extends StatelessWidget {
  final int drawerIndex;

  const SettingsView({super.key, this.drawerIndex = 8});

  Future<void> _toggleLan(
    BuildContext context,
    SettingsViewModel vm,
    bool enabled,
  ) async {
    final lan = vm.settings.lan;
    final service = context.read<LanServerService>();

    lan.enabled = enabled;

    if (enabled && lan.authToken.trim().isEmpty) {
      lan.authToken = service.regenerateToken();
    }

    await vm.saveLanSettings(lan);

    if (!enabled) {
      await service.stop();
      return;
    }

    try {
      await service.stop();
      await service.start(
        port: lan.port,
        token: lan.authToken,
        exposeToLan: true,
      );
    } catch (e) {
      lan.enabled = false;
      await vm.saveLanSettings(lan);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start LAN server: $e')),
        );
      }
    }
  }

  Future<void> _editInt(
    BuildContext context,
    String title,
    int current,
    Future<void> Function(int value) onSave, {
    int min = 1,
    int max = 65535,
  }) async {
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null) return;
                Navigator.of(dialogContext).pop(parsed.clamp(min, max));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await onSave(result);
    }
  }

  Future<void> _editDouble(
    BuildContext context,
    String title,
    double current,
    Future<void> Function(double value) onSave, {
    double min = 0,
    double max = 1,
  }) async {
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) return;
                Navigator.of(dialogContext).pop(parsed.clamp(min, max));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await onSave(result);
    }
  }

  Future<void> _pickColor(BuildContext context, ThemeViewModel themeVm) async {
    var selected = themeVm.theme.primaryColor;

    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Pick Theme Color'),
          content: BlockPicker(
            pickerColor: selected,
            onColorChanged: (color) {
              selected = color;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await themeVm.setPrimaryColor(selected);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editOptionalInt(
    BuildContext context,
    String title,
    int? current,
    Future<void> Function(int? value) onSave,
  ) async {
    final controller =
        TextEditingController(text: current?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Leave empty for default',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  Navigator.of(dialogContext).pop(null);
                  return;
                }
                final parsed = int.tryParse(text);
                if (parsed != null) {
                  Navigator.of(dialogContext).pop(parsed);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    // Dialog returns null for cancel AND for empty — disambiguate via
    // controller text: if it was dismissed via Cancel the result is null
    // and text is unchanged; if cleared and saved, result is also null.
    // We call onSave whenever the dialog wasn't cancelled.
    if (result != null || controller.text.trim().isEmpty) {
      await onSave(result);
    }
  }

  Future<void> _pickAccelerator(
    BuildContext context,
    SettingsViewModel vm,
    AppSettings settings,
  ) async {
    const options = ['auto', 'cpu', 'vulkan', 'metal', 'cuda'];
    final current = settings.model.accelerator;

    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Accelerator'),
          children: options.map((option) {
            return ListTile(
              title: Text(option),
              leading: Icon(
                option == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => Navigator.of(dialogContext).pop(option),
            );
          }).toList(),
        );
      },
    );

    if (picked != null && picked != current) {
      settings.model.accelerator = picked;
      await vm.saveModelSettings(settings.model);
    }
  }

  void _syncWebPolicy(WebAccessService service, WebAccessSettings settings) {
    service.policy = WebToolPolicy(
      enabled: settings.allowInternetAccess,
      askBeforeSearch: settings.askBeforeSearch,
      requestTimeout: service.policy.requestTimeout,
      allowedHosts: service.policy.allowedHosts,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsViewModel, ThemeViewModel>(
      builder: (context, vm, themeVm, _) {
        if (vm.loading) {
          return Scaffold(
            drawer: AppShellDrawer(selectedIndex: drawerIndex),
            appBar: AppBar(title: const Text('Settings')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final settings = vm.settings;
        final lanService = context.watch<LanServerService>();
        final webService = context.read<WebAccessService>();

        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: drawerIndex),
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsSection(
                  title: 'Appearance',
                  children: [
                    SwitchListTile(
                      value: themeVm.theme.isDarkMode,
                      onChanged: themeVm.setDarkMode,
                      title: const Text('Dark mode'),
                      subtitle:
                          const Text('Applies instantly without app restart.'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.color_lens_outlined),
                      title: const Text('Theme color'),
                      subtitle: const Text('Choose app accent color'),
                      trailing: CircleAvatar(
                        radius: 12,
                        backgroundColor: themeVm.theme.primaryColor,
                      ),
                      onTap: () => _pickColor(context, themeVm),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Model Defaults',
                  children: [
                    _ValueTile(
                      title: 'n_ctx',
                      value: settings.model.nCtx.toString(),
                      onTap: () => _editInt(
                        context,
                        'n_ctx',
                        settings.model.nCtx,
                        (value) async {
                          settings.model.nCtx = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 256,
                        max: 32768,
                      ),
                    ),
                    _ValueTile(
                      title: 'n_batch',
                      value: settings.model.nBatch.toString(),
                      onTap: () => _editInt(
                        context,
                        'n_batch',
                        settings.model.nBatch,
                        (value) async {
                          settings.model.nBatch = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 1,
                        max: 4096,
                      ),
                    ),
                    _ValueTile(
                      title: 'n_predict',
                      value: settings.model.nPredict.toString(),
                      onTap: () => _editInt(
                        context,
                        'n_predict',
                        settings.model.nPredict,
                        (value) async {
                          settings.model.nPredict = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 1,
                        max: 8192,
                      ),
                    ),
                    _ValueTile(
                      title: 'temperature',
                      value: settings.model.temperature.toStringAsFixed(2),
                      onTap: () => _editDouble(
                        context,
                        'temperature',
                        settings.model.temperature,
                        (value) async {
                          settings.model.temperature = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 0,
                        max: 2,
                      ),
                    ),
                    _ValueTile(
                      title: 'top_k',
                      value: settings.model.topK.toString(),
                      onTap: () => _editInt(
                        context,
                        'top_k',
                        settings.model.topK,
                        (value) async {
                          settings.model.topK = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 1,
                        max: 200,
                      ),
                    ),
                    _ValueTile(
                      title: 'top_p',
                      value: settings.model.topP.toStringAsFixed(2),
                      onTap: () => _editDouble(
                        context,
                        'top_p',
                        settings.model.topP,
                        (value) async {
                          settings.model.topP = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 0.1,
                        max: 1.0,
                      ),
                    ),
                    _ValueTile(
                      title: 'repeat_penalty',
                      value: settings.model.repeatPenalty.toStringAsFixed(2),
                      onTap: () => _editDouble(
                        context,
                        'repeat_penalty',
                        settings.model.repeatPenalty,
                        (value) async {
                          settings.model.repeatPenalty = value;
                          await vm.saveModelSettings(settings.model);
                        },
                        min: 0.0,
                        max: 2.0,
                      ),
                    ),
                    _ValueTile(
                      title: 'seed',
                      value: settings.model.seed?.toString() ?? 'random',
                      onTap: () => _editOptionalInt(
                        context,
                        'Seed (leave empty for random)',
                        settings.model.seed,
                        (value) async {
                          settings.model.seed = value;
                          await vm.saveModelSettings(settings.model);
                        },
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Runtime / Acceleration',
                  children: [
                    ListTile(
                      title: const Text('Accelerator'),
                      subtitle: Text(settings.model.accelerator),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _pickAccelerator(context, vm, settings),
                    ),
                    _ValueTile(
                      title: 'Threads',
                      value: settings.model.threads == 0
                          ? 'auto'
                          : settings.model.threads.toString(),
                      onTap: () => _editOptionalInt(
                        context,
                        'Threads (0 = auto)',
                        settings.model.threads == 0
                            ? null
                            : settings.model.threads,
                        (value) async {
                          settings.model.threads = value ?? 0;
                          await vm.saveModelSettings(settings.model);
                        },
                      ),
                    ),
                    _ValueTile(
                      title: 'Micro-batch size',
                      value: settings.model.microBatchSize == 0
                          ? 'auto'
                          : settings.model.microBatchSize.toString(),
                      onTap: () => _editOptionalInt(
                        context,
                        'Micro-batch size (0 = auto)',
                        settings.model.microBatchSize == 0
                            ? null
                            : settings.model.microBatchSize,
                        (value) async {
                          settings.model.microBatchSize = value ?? 0;
                          await vm.saveModelSettings(settings.model);
                        },
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Vision',
                  children: [
                    SwitchListTile(
                      value: settings.vision.performanceMode,
                      onChanged: (value) async {
                        settings.vision.performanceMode = value;
                        await vm.saveVisionSettings(settings.vision);
                      },
                      title: const Text('Performance mode'),
                      subtitle:
                          const Text('Lower frame rate and processing cost'),
                    ),
                    _ValueTile(
                      title: 'Frame interval (ms)',
                      value: settings.vision.frameSamplingIntervalMs.toString(),
                      onTap: () => _editInt(
                        context,
                        'Frame interval (ms)',
                        settings.vision.frameSamplingIntervalMs,
                        (value) async {
                          settings.vision.frameSamplingIntervalMs = value;
                          await vm.saveVisionSettings(settings.vision);
                        },
                        min: 500,
                        max: 60000,
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Web Access',
                  children: [
                    SwitchListTile(
                      value: settings.web.allowInternetAccess,
                      onChanged: (value) async {
                        settings.web.allowInternetAccess = value;
                        await vm.saveWebSettings(settings.web);
                        _syncWebPolicy(webService, settings.web);
                      },
                      title: const Text('Allow optional web access'),
                    ),
                    SwitchListTile(
                      value: settings.web.askBeforeSearch,
                      onChanged: (value) async {
                        settings.web.askBeforeSearch = value;
                        await vm.saveWebSettings(settings.web);
                        _syncWebPolicy(webService, settings.web);
                      },
                      title: const Text('Ask before web search'),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'LAN Serving',
                  children: [
                    SwitchListTile(
                      value: settings.lan.enabled,
                      onChanged: (value) => _toggleLan(context, vm, value),
                      title: const Text('Enable LAN server'),
                      subtitle: const Text(
                        'Requires auth token for protected endpoints.',
                      ),
                    ),
                    _ValueTile(
                      title: 'Port',
                      value: settings.lan.port.toString(),
                      onTap: () => _editInt(
                        context,
                        'LAN Port',
                        settings.lan.port,
                        (value) async {
                          settings.lan.port = value;
                          await vm.saveLanSettings(settings.lan);
                          if (settings.lan.enabled) {
                            if (!context.mounted) return;
                            await _toggleLan(context, vm, true);
                          }
                        },
                        min: 1,
                        max: 65535,
                      ),
                    ),
                    ListTile(
                      title: const Text('Auth token'),
                      subtitle: Text(
                        settings.lan.authToken.isEmpty
                            ? '(not generated yet)'
                            : settings.lan.authToken,
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Regenerate',
                            onPressed: () async {
                              settings.lan.authToken = context
                                  .read<LanServerService>()
                                  .regenerateToken();
                              await vm.saveLanSettings(settings.lan);
                              if (settings.lan.enabled) {
                                if (!context.mounted) return;
                                await _toggleLan(context, vm, true);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy',
                            onPressed: settings.lan.authToken.isEmpty
                                ? null
                                : () => Clipboard.setData(
                                      ClipboardData(
                                          text: settings.lan.authToken),
                                    ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      title: const Text('Server status'),
                      subtitle: Text(
                        lanService.isRunning
                            ? 'Running on ${lanService.address}'
                            : 'Stopped',
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Speech',
                  children: [
                    _ValueTile(
                      title: 'Language',
                      value: settings.speech.language,
                      onTap: () async {
                        final controller = TextEditingController(
                            text: settings.speech.language);
                        final value = await showDialog<String>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Speech language'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'e.g. en-US',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                    context, controller.text.trim()),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (value != null && value.isNotEmpty) {
                          settings.speech.language = value;
                          await vm.saveSpeechSettings(settings.speech);
                        }
                      },
                    ),
                    _ValueTile(
                      title: 'Speech rate',
                      value: settings.speech.speechRate.toStringAsFixed(2),
                      onTap: () => _editDouble(
                        context,
                        'Speech rate',
                        settings.speech.speechRate,
                        (value) async {
                          settings.speech.speechRate = value;
                          await vm.saveSpeechSettings(settings.speech);
                        },
                        min: 0.1,
                        max: 1,
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Context Compression',
                  children: [
                    SwitchListTile(
                      value: settings.performance.autoCompress,
                      onChanged: (value) async {
                        settings.performance.autoCompress = value;
                        await vm.savePerformanceSettings(settings.performance);
                      },
                      title: const Text('Auto compression'),
                    ),
                    _ValueTile(
                      title: 'Compression threshold',
                      value: settings.performance.contextCompressionThreshold
                          .toString(),
                      onTap: () => _editInt(
                        context,
                        'Compression threshold (messages)',
                        settings.performance.contextCompressionThreshold,
                        (value) async {
                          settings.performance.contextCompressionThreshold =
                              value;
                          await vm
                              .savePerformanceSettings(settings.performance);
                        },
                        min: 6,
                        max: 200,
                      ),
                    ),
                  ],
                ),
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      vm.errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
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

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _ValueTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.edit_outlined),
      onTap: onTap,
    );
  }
}
