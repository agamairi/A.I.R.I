library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/download_task.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/models/viewmodels/model_manager_view_model.dart';

class ModelManagerView extends StatefulWidget {
  final int drawerIndex;

  const ModelManagerView({super.key, this.drawerIndex = 5});

  @override
  State<ModelManagerView> createState() => _ModelManagerViewState();
}

class _ModelManagerViewState extends State<ModelManagerView>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ModelManagerViewModel>().initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ModelManagerViewModel>().handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelManagerViewModel>(
      builder: (context, vm, _) {
        final downloading = vm.tasks.where((task) {
          return task.status == DownloadStatus.active ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.failed;
        }).toList();

        final browseModels = vm.availableModels;

        // Default to Saved tab if local models exist, Browse otherwise.
        final initialTab = vm.localModels.isNotEmpty ? 2 : 0;

        return DefaultTabController(
          initialIndex: initialTab,
          length: 3,
          child: Scaffold(
            drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
            appBar: AppBar(
              title: const Text('Model Downloads'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () {
                    vm.refreshLocalModels();
                    vm.loadCatalog();
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(118),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: _searchController,
                        onChanged: vm.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Search models or tags',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: vm.searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    vm.setSearchQuery('');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Browse'),
                        Tab(text: 'Downloading'),
                        Tab(text: 'Saved'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              children: [
                _BrowseModelsTab(
                  viewModel: vm,
                  browseModels: browseModels,
                ),
                _DownloadingTab(viewModel: vm, tasks: downloading),
                _SavedModelsTab(viewModel: vm),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BrowseModelsTab extends StatelessWidget {
  final ModelManagerViewModel viewModel;
  final List<Map<String, dynamic>> browseModels;

  const _BrowseModelsTab({
    required this.viewModel,
    required this.browseModels,
  });

  @override
  Widget build(BuildContext context) {
    if (viewModel.loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (browseModels.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No models match your current filter.'),
          )
        else
          ...browseModels.map(
            (model) => _BrowseModelCard(model: model, viewModel: viewModel),
          ),
      ],
    );
  }
}

class _BrowseModelCard extends StatelessWidget {
  final Map<String, dynamic> model;
  final ModelManagerViewModel viewModel;

  const _BrowseModelCard({required this.model, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawId = model['id']?.toString() ?? 'Unknown model';
    final id = rawId.split('/').last;
    final description = model['cardData']?['description']?.toString();
    final downloads = model['downloads'] as int? ?? 0;
    final likes = model['likes'] as int? ?? 0;
    // Filter tags: remove machine-readable metadata (contains ':'),
    // known noise tags, and overly long tags.
    const noiseTags = <String>{
      'endpoints_compatible',
      'region:us',
      'region:eu',
      'imatrix',
      'conversational',
      'has_space',
      'autotrain_compatible',
    };
    final tags = (model['tags'] as List<dynamic>? ?? <dynamic>[])
        .map((t) => t.toString())
        .where((tag) {
          if (tag.contains(':')) return false;
          if (noiseTags.contains(tag)) return false;
          if (tag.length > 20) return false;
          return true;
        })
        .take(8)
        .toList();

    final queuedOrActive = viewModel.isQueuedOrActive(rawId);
    final progress = viewModel.progressForRepo(rawId);
    final sizeBytes = viewModel.modelSizes[rawId];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(id, style: theme.textTheme.titleMedium),
                      if (description != null && description.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: queuedOrActive
                      ? null
                      : () => viewModel.enqueueDownload(rawId),
                  icon: const Icon(Icons.download),
                  label: Text(queuedOrActive ? 'Queued' : 'Download'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: -8,
              children: tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.download,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('$downloads'),
                const SizedBox(width: 14),
                Icon(Icons.thumb_up,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('$likes'),
                if (sizeBytes != null) ...[
                  const SizedBox(width: 14),
                  Icon(Icons.sd_storage_outlined,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(_humanReadableBytes(sizeBytes)),
                ],
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(1)}%'),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadingTab extends StatelessWidget {
  final ModelManagerViewModel viewModel;
  final List<DownloadTask> tasks;

  const _DownloadingTab({required this.viewModel, required this.tasks});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(child: Text('No active or failed downloads.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final progress = task.progress.clamp(0.0, 1.0);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: progress,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.modelName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (task.status == DownloadStatus.failed)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Retry',
                            onPressed: () => viewModel.retryDownload(task.id),
                          ),
                        if (task.status == DownloadStatus.active ||
                            task.status == DownloadStatus.queued)
                          IconButton(
                            icon: const Icon(Icons.cancel),
                            tooltip: 'Cancel',
                            onPressed: () => viewModel.cancelDownload(task.id),
                          ),
                      ],
                    ),
                    Text(
                      '${task.status.name} • ${(progress * 100).toStringAsFixed(1)}%',
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                    if (task.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        task.errorMessage!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedModelsTab extends StatelessWidget {
  final ModelManagerViewModel viewModel;

  const _SavedModelsTab({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.loadingLocal) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.localModels.isEmpty) {
      return const Center(child: Text('No local GGUF models found yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: viewModel.localModels.length,
      itemBuilder: (context, index) {
        final path = viewModel.localModels[index];
        final file = File(path);
        final name = file.uri.pathSegments.last;
        final isCurrent = viewModel.loadedModelPath == path;
        final sizeBytes = file.existsSync() ? file.lengthSync() : 0;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            title: Text(name),
            subtitle: Text(
              '${_humanReadableBytes(sizeBytes)}${isCurrent ? ' • Currently loaded' : ''}',
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => viewModel.loadModel(path),
                  child: Text(isCurrent ? 'Reload' : 'Load'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => viewModel.deleteLocalModel(path),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}

String _humanReadableBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var idx = 0;
  while (size >= 1024 && idx < units.length - 1) {
    size /= 1024;
    idx++;
  }
  return '${size.toStringAsFixed(1)} ${units[idx]}';
}
