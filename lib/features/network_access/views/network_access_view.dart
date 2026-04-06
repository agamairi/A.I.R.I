/// Network access view — shows server status, connection info, QR code,
/// and setup instructions for connecting tools (Cline, Continue, etc.).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/network_access/services/lan_server_service.dart';
import 'package:local_ai_chat/features/settings/viewmodels/settings_view_model.dart';

class NetworkAccessView extends StatefulWidget {
  final int drawerIndex;

  const NetworkAccessView({super.key, this.drawerIndex = 9});

  @override
  State<NetworkAccessView> createState() => _NetworkAccessViewState();
}

class _NetworkAccessViewState extends State<NetworkAccessView> {
  String? _localIp;
  bool _loadingIp = true;

  @override
  void initState() {
    super.initState();
    _fetchIp();
  }

  Future<void> _fetchIp() async {
    final ip = await LanServerService.getLocalIpAddress();
    if (mounted) {
      setState(() {
        _localIp = ip;
        _loadingIp = false;
      });
    }
  }

  String _serverUrl(LanServerService service) {
    final ip = _localIp ?? '0.0.0.0';
    final port = service.port ?? 11434;
    return 'http://$ip:$port';
  }

  Future<void> _toggleServer(BuildContext context, bool enable) async {
    final vm = context.read<SettingsViewModel>();
    final service = context.read<LanServerService>();
    final lan = vm.settings.lan;

    lan.enabled = enable;

    if (enable && lan.authToken.trim().isEmpty) {
      lan.authToken = service.regenerateToken();
    }

    await vm.saveLanSettings(lan);

    if (!enable) {
      await service.stop();
      return;
    }

    try {
      await service.stop();
      await service.start(
        port: lan.port,
        token: lan.authToken,
        requireAuth: lan.requireAuth,
        showWebUI: lan.showWebUI,
      );
    } catch (e) {
      lan.enabled = false;
      await vm.saveLanSettings(lan);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start server: $e')),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lanService = context.watch<LanServerService>();
    final vm = context.watch<SettingsViewModel>();
    final isRunning = lanService.isRunning;
    final url = _serverUrl(lanService);

    return Scaffold(
      drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
      appBar: AppBar(
        title: const Text('Network Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh IP',
            onPressed: () {
              setState(() => _loadingIp = true);
              _fetchIp();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Status Card ----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      isRunning ? Icons.cloud_done : Icons.cloud_off,
                      size: 48,
                      color: isRunning ? Colors.green : theme.colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isRunning ? 'Server Running' : 'Server Stopped',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isRunning) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _copyToClipboard(url),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withAlpha(80),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                url,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.copy, size: 18),
                            ],
                          ),
                        ),
                      ),
                      if (_loadingIp)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _toggleServer(context, !isRunning),
                      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(isRunning ? 'Stop Server' : 'Start Server'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isRunning ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ---- Quick Setup Instructions ----
            if (isRunning) ...[
              _SectionTitle(title: 'Quick Setup', theme: theme),

              _InstructionCard(
                icon: Icons.code,
                title: 'VS Code - Cline / Continue',
                instructions: [
                  'Set Ollama base URL to:',
                  url,
                  '',
                  'Model name will appear in the tool\'s model dropdown.',
                ],
                copyText: url,
                onCopy: _copyToClipboard,
                theme: theme,
              ),

              _InstructionCard(
                icon: Icons.web,
                title: 'Web Chat UI',
                instructions: [
                  'Open in any browser on your network:',
                  url,
                ],
                copyText: url,
                onCopy: _copyToClipboard,
                theme: theme,
              ),

              _InstructionCard(
                icon: Icons.terminal,
                title: 'curl / API',
                instructions: [
                  'List models:',
                  'curl $url/api/tags',
                  '',
                  'Chat:',
                  'curl $url/api/chat -d \'{"model":"<name>","messages":[{"role":"user","content":"Hello"}],"stream":false}\'',
                ],
                copyText: 'curl $url/api/tags',
                onCopy: _copyToClipboard,
                theme: theme,
              ),

              _InstructionCard(
                icon: Icons.api,
                title: 'OpenAI-Compatible',
                instructions: [
                  'Base URL: $url/v1',
                  'API Key: not required (or any string)',
                  '',
                  'Works with LangChain, LiteLLM, and other OpenAI-compatible tools.',
                ],
                copyText: '$url/v1',
                onCopy: _copyToClipboard,
                theme: theme,
              ),

              const SizedBox(height: 16),

              // ---- API Endpoints Reference ----
              _SectionTitle(title: 'Available Endpoints', theme: theme),

              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EndpointRow('GET', '/', 'Liveness check / Web UI'),
                      _EndpointRow('GET', '/api/tags', 'List models'),
                      _EndpointRow('GET', '/api/ps', 'Running models'),
                      _EndpointRow('GET', '/api/version', 'Server version'),
                      _EndpointRow('POST', '/api/show', 'Model details'),
                      _EndpointRow(
                          'POST', '/api/generate', 'Text completion'),
                      _EndpointRow(
                          'POST', '/api/chat', 'Chat completion'),
                      _EndpointRow('GET', '/api/health', 'Health + uptime'),
                      Divider(height: 24),
                      _EndpointRow(
                          'GET', '/v1/models', 'OpenAI model list'),
                      _EndpointRow('POST', '/v1/chat/completions',
                          'OpenAI chat'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---- Server Info ----
              _SectionTitle(title: 'Server Info', theme: theme),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.wifi),
                      title: const Text('IP Address'),
                      subtitle: Text(_localIp ?? 'Detecting...'),
                      trailing: _localIp != null
                          ? IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () =>
                                  _copyToClipboard(_localIp!),
                            )
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.numbers),
                      title: const Text('Port'),
                      subtitle: Text(
                          vm.settings.lan.port.toString()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Authentication'),
                      subtitle: Text(
                        vm.settings.lan.requireAuth
                            ? 'Required (Bearer token)'
                            : 'Open (Ollama-compatible)',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Recent clients'),
                      subtitle: Text(
                        '${lanService.ollamaHandler.recentClientCount} unique IPs',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionTitle({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> instructions;
  final String copyText;
  final void Function(String) onCopy;
  final ThemeData theme;

  const _InstructionCard({
    required this.icon,
    required this.title,
    required this.instructions,
    required this.copyText,
    required this.onCopy,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(icon, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        childrenPadding:
            const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: instructions.map((line) {
                if (line.isEmpty) return const SizedBox(height: 6);
                final isCode = line.startsWith('curl') ||
                    line.startsWith('http') ||
                    line.contains('://');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line,
                    style: isCode
                        ? TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          )
                        : const TextStyle(fontSize: 13),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => onCopy(copyText),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy URL'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  final String method;
  final String path;
  final String description;

  const _EndpointRow(this.method, this.path, this.description);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methodColor = method == 'POST'
        ? Colors.orange
        : Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: methodColor.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              method,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: methodColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            path,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
