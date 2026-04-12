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

        return DefaultTabController(
          initialIndex: 2, // Always open Saved tab first
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

    final progress = viewModel.progressForRepo(rawId);

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
                FilledButton.tonalIcon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (bottomSheetContext) => _ModelFilesBottomSheet(
                        repoId: rawId,
                        repoName: id,
                        viewModel: viewModel,
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('View Files'),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('No models found.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // Switch to Browse tab (index 0)
                DefaultTabController.of(context).animateTo(0);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Models'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => viewModel.importModelFromFile(),
              icon: const Icon(Icons.file_open),
              label: const Text('Import from Files'),
            ),
          ],
        ),
      );
    }

    final isExternal = viewModel.externalModelPaths.toSet();

    return Column(
      children: [
        // Import button at top
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => viewModel.importModelFromFile(),
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('Import Model from Files'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: viewModel.localModels.length,
            itemBuilder: (context, index) {
              final path = viewModel.localModels[index];
              final file = File(path);
              final name = file.uri.pathSegments.last;
              final isCurrent = viewModel.loadedModelPath == path;
              final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
              final isExt = isExternal.contains(path);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${_humanReadableBytes(sizeBytes)}'
                        '${isCurrent ? '  •  Currently loaded' : ''}'
                        '${isExt ? '  •  External' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isCurrent) ...[
                            FilledButton.tonal(
                              onPressed: () => viewModel.offloadModel(),
                              child: const Text('Offload'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () => viewModel.loadModel(path),
                              child: const Text('Reload'),
                            ),
                          ] else
                            FilledButton.tonal(
                              onPressed: () => viewModel.loadModel(path),
                              child: const Text('Load'),
                            ),
                          const Spacer(),
                          if (isExt)
                            IconButton(
                              icon: const Icon(Icons.link_off, size: 20),
                              tooltip: 'Remove external link',
                              onPressed: () =>
                                  viewModel.removeExternalPath(path),
                            ),
                          if (!isExt)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () =>
                                  viewModel.deleteLocalModel(path),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

class _ModelFilesBottomSheet extends StatefulWidget {
  final String repoId;
  final String repoName;
  final ModelManagerViewModel viewModel;

  const _ModelFilesBottomSheet({
    required this.repoId,
    required this.repoName,
    required this.viewModel,
  });

  @override
  State<_ModelFilesBottomSheet> createState() => _ModelFilesBottomSheetState();
}

class _ModelFilesBottomSheetState extends State<_ModelFilesBottomSheet> {
  List<Map<String, dynamic>>? _files;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    try {
      final files = await widget.viewModel.fetchFilesForRepo(widget.repoId);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load files.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.repoName} Files',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildBody(scrollController),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (_files == null || _files!.isEmpty) {
      return const Center(
        child: Text('No .gguf files found in this repository.'),
      );
    }

    return ListView.separated(
      controller: scrollController,
      itemCount: _files!.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = _files![index];
        final filename = (file['path'] as String).split('/').last;
        final sizeBytes = file['size'] as int? ?? 0;
        final downloadUrl =
            'https://huggingface.co/${widget.repoId}/resolve/main/${file['path']}';

        // Actually look to see if this specific file is queued or downloading.
        // The service checks `modelName == repoId`, but now `modelName` is set 
        // to `repoId` initially. The true check for *exact* file would be checking URL or savePath.
        // We'll rely on the global repo-level progress for simplicity, but if the download
        // has a non-empty downloadUrl matching ours, it's this file.
        final tasks = widget.viewModel.tasks;
        final isActive = tasks.any((t) =>
            t.modelName == widget.repoId &&
            t.downloadUrl == downloadUrl &&
            (t.status == DownloadStatus.active ||
                t.status == DownloadStatus.queued));

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(filename, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(_humanReadableBytes(sizeBytes)),
          trailing: FilledButton.icon(
            onPressed: isActive
                ? null
                : () {
                    widget.viewModel.enqueueDownload(
                      widget.repoId,
                      downloadUrl: downloadUrl,
                      totalBytes: sizeBytes,
                    );
                    Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.download, size: 18),
            label: Text(isActive ? 'Queued' : 'Download'),
          ),
        );
      },
    );
  }
}
