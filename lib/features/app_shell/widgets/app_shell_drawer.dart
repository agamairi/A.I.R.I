library;

import 'package:flutter/material.dart';
import 'package:local_ai_chat/features/app_shell/views/app_shell_view.dart';

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

  void _navigateTo(BuildContext context, int index) {
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
