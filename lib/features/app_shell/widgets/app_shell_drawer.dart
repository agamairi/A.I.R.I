library;

import 'package:flutter/material.dart';
import 'package:local_ai_chat/features/app_shell/views/app_shell_view.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/network_access/services/lan_server_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class AppShellDrawer extends StatelessWidget {
  final int selectedIndex;

  const AppShellDrawer({
    super.key,
    required this.selectedIndex,
  });

  static const _destinations = <_DrawerDestination>[
    _DrawerDestination(icon: Icons.chat_outlined, label: 'Chat'),
    _DrawerDestination(icon: Icons.mic_none_outlined, label: 'Talk'),
    _DrawerDestination(icon: Icons.history, label: 'History'),
    _DrawerDestination(icon: Icons.camera_alt_outlined, label: 'Vision'),
    _DrawerDestination(icon: Icons.book_outlined, label: 'Notebooks'),
    _DrawerDestination(icon: Icons.download_outlined, label: 'Models'),
    _DrawerDestination(icon: Icons.person_outline, label: 'Profile'),
    _DrawerDestination(icon: Icons.speed_outlined, label: 'Benchmark'),
    _DrawerDestination(icon: Icons.dns_outlined, label: 'Server'),
    _DrawerDestination(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  /// Server page index constant.
  static const _serverIndex = 8;

  void _navigateTo(BuildContext context, int index) {
    // Block navigation away from server page while inference is active
    if (selectedIndex == _serverIndex && index != _serverIndex) {
      final lanService = context.read<LanServerService>();
      if (lanService.isRunning &&
          lanService.ollamaHandler.inferenceInFlight) {
        Navigator.of(context).pop(); // close drawer
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Server is processing a client request. '
              'Stop the server or wait for it to finish.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    Navigator.of(context).pop();
    if (index == selectedIndex) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppShellView(initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runtime = context.read<ModelRuntimeService>();
    final modelPath = runtime.currentModelPath;
    final modelName = modelPath != null
        ? p.basenameWithoutExtension(modelPath)
        : null;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A.I.R.I',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'AI, Real-Time, In-App',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Model status chip
            if (modelName != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.memory, size: 14,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        modelName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.memory, size: 14,
                        color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      'No model loaded',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _destinations.length,
                itemBuilder: (context, index) {
                  final item = _destinations[index];
                  return ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    selected: index == selectedIndex,
                    onTap: () => _navigateTo(context, index),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // App version
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.hasData
                    ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                    : '';
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Text(
                    'A.I.R.I $version',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerDestination {
  final IconData icon;
  final String label;

  const _DrawerDestination({
    required this.icon,
    required this.label,
  });
}
