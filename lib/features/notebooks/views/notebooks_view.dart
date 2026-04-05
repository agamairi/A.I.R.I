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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotebooksViewModel>().load();
    });
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

  Future<void> _confirmDeleteNotebook(
      NotebooksViewModel vm, Notebook notebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Notebook'),
          content: Text(
            'Are you sure you want to delete "${notebook.title}"? '
            'This will permanently remove all imported documents and their data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await vm.deleteNotebook(notebook.id);
    }
  }

  Future<void> _confirmDeleteDocument(
      NotebooksViewModel vm, DocumentSource doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Document'),
          content: Text(
            'Remove "${doc.fileName}" from this notebook? '
            'The indexed data will be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await vm.deleteDocument(doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotebooksViewModel>(
      builder: (context, vm, _) {
        final theme = Theme.of(context);

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
                      // ---------- Notebook selector ----------
                      if (vm.notebooks.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(Icons.library_books_outlined,
                                    size: 48,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                  'No notebooks yet',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Create a notebook to start importing PDF documents for AI-grounded Q&A.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
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
                                  child: Text(
                                    '${notebook.title} (${vm.documentCountFor(notebook.id)} docs)',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              vm.selectNotebook(value);
                            }
                          },
                        ),
                        if (vm.selectedNotebook != null) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _confirmDeleteNotebook(
                                  vm, vm.selectedNotebook!),
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: theme.colorScheme.error),
                              label: Text(
                                'Delete notebook',
                                style:
                                    TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 12),

                      // ---------- Action buttons ----------
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: vm.selectedNotebook == null ||
                                      vm.importing
                                  ? null
                                  : vm.importDocuments,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Import documents'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: vm.selectedNotebook == null ||
                                      vm.documents.isEmpty
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatView(
                                            notebookId:
                                                vm.selectedNotebook!.id,
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

                      // ---------- Import progress ----------
                      if (vm.importing) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    vm.importStatus,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ---------- Documents list ----------
                      Text(
                        'Documents',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (vm.selectedNotebook == null)
                        Text(
                          'Select or create a notebook to see documents.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (vm.documents.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 36,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(height: 8),
                                Text(
                                  'No documents imported yet.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap "Import documents" to add PDF, TXT, or Markdown files.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...vm.documents.map(
                          (doc) => Card(
                            child: ListTile(
                              leading: Icon(
                                _iconForDocType(doc.type),
                                color: _colorForStatus(doc.status, theme),
                              ),
                              title: Text(doc.fileName),
                              subtitle: Text(
                                _statusLabel(doc),
                                style: TextStyle(
                                  color: _colorForStatus(doc.status, theme),
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: theme.colorScheme.error),
                                tooltip: 'Remove document',
                                onPressed: () =>
                                    _confirmDeleteDocument(vm, doc),
                              ),
                            ),
                          ),
                        ),

                      // ---------- Error ----------
                      if (vm.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            vm.errorMessage!,
                            style:
                                TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  IconData _iconForDocType(DocumentType type) {
    switch (type) {
      case DocumentType.pdf:
        return Icons.picture_as_pdf;
      case DocumentType.txt:
        return Icons.text_snippet;
      case DocumentType.markdown:
        return Icons.code;
      case DocumentType.other:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForStatus(DocumentStatus status, ThemeData theme) {
    switch (status) {
      case DocumentStatus.indexed:
        return Colors.green;
      case DocumentStatus.pending:
        return theme.colorScheme.onSurfaceVariant;
      case DocumentStatus.failed:
        return theme.colorScheme.error;
    }
  }

  String _statusLabel(DocumentSource doc) {
    switch (doc.status) {
      case DocumentStatus.indexed:
        return 'Indexed ✓';
      case DocumentStatus.pending:
        return 'Pending…';
      case DocumentStatus.failed:
        return 'Failed${doc.errorMessage != null ? ' • ${doc.errorMessage}' : ''}';
    }
  }
}
