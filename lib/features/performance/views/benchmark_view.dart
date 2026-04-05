/// Benchmark view — minimal UI for running and viewing benchmark results.
library;

import 'package:flutter/material.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/models/widgets/model_init_sheet.dart';
import 'package:local_ai_chat/features/performance/models/benchmark_models.dart';
import 'package:local_ai_chat/features/performance/viewmodels/benchmark_view_model.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:provider/provider.dart';

class BenchmarkView extends StatefulWidget {
  final int drawerIndex;

  const BenchmarkView({super.key, this.drawerIndex = 7});

  @override
  State<BenchmarkView> createState() => _BenchmarkViewState();
}

class _BenchmarkViewState extends State<BenchmarkView> {
  @override
  void initState() {
    super.initState();
    context.read<BenchmarkViewModel>().loadHistory();
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BenchmarkViewModel>();
    final runtime = context.read<ModelRuntimeService>();
    final theme = Theme.of(context);

    return Scaffold(
      drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
      appBar: AppBar(
        title: const Text('Performance Benchmark'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Model settings',
            onPressed: _openModelSheet,
          ),
          if (vm.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: vm.state == BenchmarkState.running
                  ? null
                  : () => vm.clearHistory(),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Measures inference speed of the loaded model: '
            'time-to-first-token (TTFT), prefill throughput, and '
            'decode throughput. Each profile runs multiple iterations '
            'and reports min/max/avg/median statistics.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildProfileSelector(vm, runtime, theme),
          const SizedBox(height: 16),
          if (vm.state == BenchmarkState.running) _buildProgress(vm, theme),
          if (vm.state == BenchmarkState.error) _buildError(vm, theme),
          if (vm.lastRun != null) ...[
            const SizedBox(height: 16),
            _buildRunResult(vm.lastRun!, theme, isLatest: true),
          ],
          if (vm.history.length > 1) ...[
            const SizedBox(height: 24),
            Text('History', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...vm.history.reversed
                .skip(vm.lastRun != null ? 1 : 0)
                .take(20)
                .map((run) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildRunResult(run, theme),
                    )),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSelector(
    BenchmarkViewModel vm,
    ModelRuntimeService runtime,
    ThemeData theme,
  ) {
    final isRunning = vm.state == BenchmarkState.running;
    final modelLoaded = runtime.isLoaded;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run Benchmark', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!modelLoaded)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No model loaded.'),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openModelSheet,
                    icon: const Icon(Icons.tune),
                    label: const Text('Load model'),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BenchmarkProfile.all.map((profile) {
                  return FilledButton.tonal(
                    onPressed:
                        isRunning ? null : () => vm.runBenchmark(profile),
                    child: Text(
                      '${profile.name} (${profile.prefillTokens}/${profile.decodeTokens})',
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BenchmarkViewModel vm, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Running ${vm.currentProfile?.name ?? ""} profile...',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: vm.totalIterations > 0
                  ? vm.currentIteration / vm.totalIterations
                  : null,
            ),
            const SizedBox(height: 8),
            Text('Iteration ${vm.currentIteration} / ${vm.totalIterations}'),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BenchmarkViewModel vm, ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          vm.errorMessage ?? 'Unknown error',
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }

  Widget _buildRunResult(
    BenchmarkRun run,
    ThemeData theme, {
    bool isLatest = false,
  }) {
    return Card(
      elevation: isLatest ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${run.modelName} — ${run.profile.name}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (isLatest)
                  Chip(
                    label: const Text('Latest'),
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${run.timestamp.toLocal().toString().substring(0, 19)} '
              '| ${run.iterations.length} iterations',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 16),
            _metricRow('TTFT', run.ttft, 'ms'),
            _metricRow('Prefill', run.prefillSpeed, 'tok/s'),
            _metricRow('Decode', run.decodeSpeed, 'tok/s'),
            if (run.initTimeMs != null)
              _singleMetricRow(
                  'Cold init', run.initTimeMs!.toStringAsFixed(0), 'ms'),
            if (run.warmInitTimeMs != null)
              _singleMetricRow(
                  'Warm init', run.warmInitTimeMs!.toStringAsFixed(0), 'ms'),
            const Divider(height: 16),
            Text(
              'Backend: ${run.runtimeInfo.resolvedBackend ?? run.runtimeInfo.requestedBackend} '
              '| GPU layers: ${run.runtimeInfo.resolvedGpuLayers ?? "N/A"} '
              '| Threads: ${run.runtimeInfo.threads}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String label, ValueSeries series, String unit) {
    if (series.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: Text(
              'med: ${series.median.toStringAsFixed(1)} $unit  '
              'avg: ${series.avg.toStringAsFixed(1)}  '
              'p25: ${series.p25.toStringAsFixed(1)}  '
              'p75: ${series.p75.toStringAsFixed(1)}  '
              'min: ${series.min.toStringAsFixed(1)}  '
              'max: ${series.max.toStringAsFixed(1)}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleMetricRow(String label, String value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Text('$value $unit',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
