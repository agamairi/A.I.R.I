library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/features/notebooks/repositories/notebook_repository.dart';
import 'package:uuid/uuid.dart';

class NotebooksViewModel extends ChangeNotifier {
  final NotebookRepository _notebookRepository;

  NotebooksViewModel(this._notebookRepository);

  List<Notebook> _notebooks = <Notebook>[];
  List<Notebook> get notebooks => List.unmodifiable(_notebooks);

  Notebook? _selectedNotebook;
  Notebook? get selectedNotebook => _selectedNotebook;

  List<DocumentSource> _documents = <DocumentSource>[];
  List<DocumentSource> get documents => List.unmodifiable(_documents);

  // Document counts per notebook id
  Map<String, int> _documentCounts = <String, int>{};
  int documentCountFor(String notebookId) => _documentCounts[notebookId] ?? 0;

  bool _loading = false;
  bool get loading => _loading;

  bool _importing = false;
  bool get importing => _importing;

  String _importStatus = '';
  String get importStatus => _importStatus;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notebooks = await _notebookRepository.listNotebooks();
      if (_selectedNotebook == null && _notebooks.isNotEmpty) {
        _selectedNotebook = _notebooks.first;
      }
      // Refresh selected notebook reference in case list was reloaded
      if (_selectedNotebook != null) {
        final match = _notebooks.where((n) => n.id == _selectedNotebook!.id);
        if (match.isNotEmpty) {
          _selectedNotebook = match.first;
        } else {
          _selectedNotebook = _notebooks.isNotEmpty ? _notebooks.first : null;
        }
      }
      await _loadDocumentCounts();
      await _loadDocuments();
    } catch (e) {
      _errorMessage = 'Failed to load notebooks: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> createNotebook(String title) async {
    if (title.trim().isEmpty) return;

    final now = DateTime.now();
    final notebook = Notebook(
      id: const Uuid().v4(),
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
    );

    await _notebookRepository.createNotebook(notebook);
    await load();
    // Auto-select the newly created notebook
    _selectedNotebook = _notebooks.firstWhere((n) => n.id == notebook.id);
    await _loadDocuments();
    notifyListeners();
  }

  Future<void> selectNotebook(Notebook notebook) async {
    _selectedNotebook = notebook;
    await _loadDocuments();
    notifyListeners();
  }

  /// Opens a multi-file picker and imports each selected file sequentially.
  Future<void> importDocuments() async {
    if (_selectedNotebook == null) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
    );

    if (result == null || result.files.isEmpty) return;

    _importing = true;
    _errorMessage = null;
    notifyListeners();

    final files = result.files.where((f) => f.path != null).toList();
    int completed = 0;

    for (final file in files) {
      _importStatus = 'Importing ${completed + 1} of ${files.length}: ${file.name}';
      notifyListeners();

      try {
        await _notebookRepository.importDocument(
          notebookId: _selectedNotebook!.id,
          filePath: file.path!,
          fileName: file.name,
          chunkSize: _selectedNotebook!.chunkSize,
          chunkOverlap: _selectedNotebook!.chunkOverlap,
        );
      } catch (e) {
        _errorMessage = 'Failed to import ${file.name}: $e';
      }

      completed++;
    }

    _importing = false;
    _importStatus = '';
    await _loadDocumentCounts();
    await _loadDocuments();
    notifyListeners();
  }

  /// Deletes a notebook after confirmation (caller handles the dialog).
  Future<void> deleteNotebook(String id) async {
    await _notebookRepository.deleteNotebook(id);

    if (_selectedNotebook?.id == id) {
      _selectedNotebook = null;
      _documents = <DocumentSource>[];
    }

    await load();
  }

  /// Deletes a single document and refreshes the list.
  Future<void> deleteDocument(String documentId) async {
    await _notebookRepository.deleteDocument(documentId);
    await _loadDocumentCounts();
    await _loadDocuments();
    notifyListeners();
  }

  Future<void> _loadDocuments() async {
    if (_selectedNotebook == null) {
      _documents = <DocumentSource>[];
      return;
    }

    _documents = await _notebookRepository.listDocuments(_selectedNotebook!.id);
  }

  Future<void> _loadDocumentCounts() async {
    final counts = <String, int>{};
    for (final notebook in _notebooks) {
      counts[notebook.id] =
          await _notebookRepository.documentCount(notebook.id);
    }
    _documentCounts = counts;
  }

  String fileNameFromPath(String path) => File(path).uri.pathSegments.last;
}
