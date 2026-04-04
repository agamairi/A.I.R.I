library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/notebooks/viewmodels/notebooks_view_model.dart';
import 'package:local_ai_chat/features/chat/views/chat_view.dart';

class NotebooksView extends StatefulWidget {
  final int drawerIndex;

  const NotebooksView({super.key, this.drawerIndex = 4});

  @override
  State<NotebooksView> createState() => _NotebooksViewState();
}

class _NotebooksViewState extends State<NotebooksView> {
  final _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotebooksViewModel>().load();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _promptCreateNotebook(NotebooksViewModel vm) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New Notebook'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Notebook title',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (title != null && title.isNotEmpty) {
      await vm.createNotebook(title);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotebooksViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            title: const Text('Notebooks'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Create notebook',
                onPressed: () => _promptCreateNotebook(vm),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: vm.load,
              ),
            ],
          ),
          body: vm.loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (vm.notebooks.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                                'No notebooks yet. Create one to start importing documents.'),
                          ),
                        )
                      else
                        DropdownButtonFormField<Notebook>(
                          initialValue: vm.selectedNotebook,
                          decoration: const InputDecoration(
                            labelText: 'Active notebook',
                            border: OutlineInputBorder(),
                          ),
                          items: vm.notebooks
                              .map(
                                (notebook) => DropdownMenuItem<Notebook>(
                                  value: notebook,
                                  child: Text(notebook.title),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              vm.selectNotebook(value);
                            }
                          },
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: vm.selectedNotebook == null
                                  ? null
                                  : vm.importDocument,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Import document'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: vm.selectedNotebook == null
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatView(
                                            notebookId: vm.selectedNotebook!.id,
                                            drawerIndex: -1,
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.chat),
                              label: const Text('Chat'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Documents',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (vm.documents.isEmpty)
                        const Text('No imported documents in this notebook.')
                      else
                        ...vm.documents.map(
                          (doc) => Card(
                            child: ListTile(
                              title: Text(doc.fileName),
                              subtitle: Text(
                                '${doc.status.name}${doc.errorMessage == null ? '' : ' • ${doc.errorMessage}'}',
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Ask notebook',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _queryController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Ask a question about your documents',
                              ),
                              minLines: 1,
                              maxLines: 3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: vm.selectedNotebook == null
                                ? null
                                : () =>
                                    vm.retrieveContext(_queryController.text),
                            child: const Text('Retrieve'),
                          ),
                        ],
                      ),
                      if (vm.ragContext.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(vm.ragContext),
                          ),
                        ),
                      ],
                      if (vm.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            vm.errorMessage!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
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
