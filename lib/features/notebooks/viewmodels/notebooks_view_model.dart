library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/features/notebooks/repositories/notebook_repository.dart';
import 'package:local_ai_chat/features/notebooks/services/rag_pipeline_service.dart';
import 'package:uuid/uuid.dart';

class NotebooksViewModel extends ChangeNotifier {
  final NotebookRepository _notebookRepository;
  final RagPipelineService _ragPipelineService;

  NotebooksViewModel(this._notebookRepository, this._ragPipelineService);

  List<Notebook> _notebooks = <Notebook>[];
  List<Notebook> get notebooks => List.unmodifiable(_notebooks);

  Notebook? _selectedNotebook;
  Notebook? get selectedNotebook => _selectedNotebook;

  List<DocumentSource> _documents = <DocumentSource>[];
  List<DocumentSource> get documents => List.unmodifiable(_documents);

  bool _loading = false;
  bool get loading => _loading;

  String _ragContext = '';
  String get ragContext => _ragContext;

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
  }

  Future<void> selectNotebook(Notebook notebook) async {
    _selectedNotebook = notebook;
    await _loadDocuments();
    notifyListeners();
  }

  Future<void> importDocument() async {
    if (_selectedNotebook == null) return;

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;

    await _notebookRepository.importDocument(
      notebookId: _selectedNotebook!.id,
      filePath: filePath,
      fileName: fileName,
      chunkSize: _selectedNotebook!.chunkSize,
      chunkOverlap: _selectedNotebook!.chunkOverlap,
    );

    await _loadDocuments();
    notifyListeners();
  }

  Future<void> retrieveContext(String query) async {
    if (_selectedNotebook == null || query.trim().isEmpty) return;

    _ragContext = await _ragPipelineService.retrieveContext(
      notebookId: _selectedNotebook!.id,
      query: query.trim(),
      topK: _selectedNotebook!.topK,
      mode: _selectedNotebook!.retrievalMode,
      includeCitations: _selectedNotebook!.citationsEnabled,
    );

    notifyListeners();
  }

  Future<void> _loadDocuments() async {
    if (_selectedNotebook == null) {
      _documents = <DocumentSource>[];
      return;
    }

    _documents = await _notebookRepository.listDocuments(_selectedNotebook!.id);
  }

  String fileNameFromPath(String path) => File(path).uri.pathSegments.last;
}
