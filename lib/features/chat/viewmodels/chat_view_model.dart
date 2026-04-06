library;

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/chat/repositories/conversation_repository.dart';
import 'package:local_ai_chat/features/context_assembly/services/context_assembler.dart';
import 'package:local_ai_chat/features/context_assembly/services/context_compression_service.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/core/models/notebook.dart';
import 'package:local_ai_chat/features/notebooks/repositories/notebook_repository.dart';
import 'package:local_ai_chat/features/notebooks/services/rag_pipeline_service.dart';
import 'package:uuid/uuid.dart';

class ChatViewModel extends ChangeNotifier {
  final ConversationRepository _conversationRepository;
  final ModelRuntimeService _runtimeService;
  final ContextAssembler _contextAssembler;
  final ContextCompressionService _compressionService;
  final SettingsRepository _settingsRepository;
  final RagPipelineService _ragPipelineService;
  final NotebookRepository _notebookRepository;

  ChatViewModel(
    this._conversationRepository,
    this._runtimeService,
    this._contextAssembler,
    this._compressionService,
    this._settingsRepository,
    this._ragPipelineService,
    this._notebookRepository,
  );

  Conversation? _conversation;
  Conversation? get conversation => _conversation;

  final List<ChatMessage> _messages = <ChatMessage>[];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  List<Notebook> _notebooks = <Notebook>[];
  List<Notebook> get notebooks => List.unmodifiable(_notebooks);

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  String? _notebookTitle;
  String? get notebookTitle => _notebookTitle;

  bool _isLoadingConversation = false;
  bool get isLoadingConversation => _isLoadingConversation;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get modelLoaded => _runtimeService.isLoaded;

  int _generationEpoch = 0;

  Future<void> loadConversation(String conversationId) async {
    _isLoadingConversation = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _conversation =
          await _conversationRepository.getConversation(conversationId);
      final loaded = _conversation == null
          ? <ChatMessage>[]
          : await _conversationRepository.getMessages(conversationId);
      _messages
        ..clear()
        ..addAll(loaded);
    } catch (e) {
      _errorMessage = 'Failed to load conversation: $e';
    } finally {
      _isLoadingConversation = false;
      notifyListeners();
    }
  }

  Future<void> createConversation({String title = 'New Chat', String? notebookId}) async {
    final now = DateTime.now();

    // Load notebook title for display in the chat view
    if (notebookId != null) {
      final notebook = await _notebookRepository.getNotebook(notebookId);
      _notebookTitle = notebook?.title;
      title = _notebookTitle ?? 'Notebook Chat';
    } else {
      _notebookTitle = null;
    }

    _conversation = Conversation(
      id: const Uuid().v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
      notebookId: notebookId,
    );

    await _conversationRepository.createConversation(_conversation!);
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final input = text.trim();
    if (input.isEmpty || _isGenerating || !_runtimeService.isLoaded) return;

    if (_conversation == null) {
      await createConversation(
        title: input.length > 50 ? '${input.substring(0, 50)}...' : input,
      );
    }

    _errorMessage = null;

    final userMessage = ChatMessage(
      id: const Uuid().v4(),
      conversationId: _conversation!.id,
      role: MessageRole.user,
      content: input,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    await _conversationRepository.addMessage(userMessage);

    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      conversationId: _conversation!.id,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );

    _messages.add(assistantMessage);
    _isGenerating = true;
    final generationEpoch = ++_generationEpoch;
    notifyListeners();

    try {
      final settings = await _settingsRepository.loadAll();

      String? compressedMemory;
      var recentMessages =
          _messages.where((m) => m.content.isNotEmpty).toList();

      if (settings.performance.autoCompress &&
          _compressionService.shouldCompress(
            recentMessages,
            threshold: settings.performance.contextCompressionThreshold,
          )) {
        final (toCompress, toKeep) =
            _compressionService.splitMessages(recentMessages);
        if (toCompress.isNotEmpty) {
          compressedMemory = await _compressionService.compress(toCompress);
          recentMessages = toKeep;
        }
      }

      String? ragContext;
      bool strictGrounding = false;
      String? notebookSystemPrompt;

      if (_conversation!.notebookId != null) {
        final notebook =
            await _notebookRepository.getNotebook(_conversation!.notebookId!);
        if (notebook != null) {
          strictGrounding = notebook.strictGrounding;
          notebookSystemPrompt = notebook.systemPrompt;

          ragContext = await _ragPipelineService.retrieveContext(
            notebookId: _conversation!.notebookId!,
            query: input,
            topK: notebook.topK,
            mode: notebook.retrievalMode,
            includeCitations: notebook.citationsEnabled,
          );
        }
      }

      final prompt = await _contextAssembler.assemble(
        messages: recentMessages,
        conversationId: _conversation!.id,
        notebookId: _conversation!.notebookId,
        customSystemPrompt:
            _conversation!.customSystemPrompt ?? notebookSystemPrompt,
        compressedMemory: compressedMemory,
        ragContext: ragContext,
        strictGrounding: strictGrounding,
      );

      final genParams = GenerationParams(
        maxTokens: settings.model.nPredict,
        temp: settings.model.temperature,
        topK: settings.model.topK,
        topP: settings.model.topP,
        penalty: settings.model.repeatPenalty,
        seed: settings.model.seed,
      );

      final stream = _runtimeService.generateStream(
        prompt,
        generationParams: genParams,
      );
      final buffer = StringBuffer();

      // Throttle UI rebuilds: notify at most every 80ms during streaming
      // to avoid per-token Flutter rebuilds that bottleneck decode throughput.
      const throttleMs = 80;
      var lastNotifyTime = DateTime.now().millisecondsSinceEpoch;

      await for (final token in stream) {
        if (generationEpoch != _generationEpoch) break;
        buffer.write(token);
        assistantMessage.content = buffer.toString();

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotifyTime >= throttleMs) {
          notifyListeners();
          lastNotifyTime = now;
        }
      }

      // Flush final state immediately
      notifyListeners();

      if (assistantMessage.content.trim().isNotEmpty) {
        await _conversationRepository.addMessage(assistantMessage);
      } else {
        _messages.remove(assistantMessage);
      }
    } catch (e) {
      _errorMessage = 'Failed to generate response: $e';
      assistantMessage.content = _errorMessage!;
      await _conversationRepository.addMessage(assistantMessage);
    } finally {
      if (_conversation != null) {
        _conversation!.updatedAt = DateTime.now();
        await _conversationRepository.updateConversation(_conversation!);
      }
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> loadModelWithSettings(String modelPath) async {
    final settings = await _settingsRepository.loadAll();
    await _runtimeService.loadModel(
      modelPath,
      nCtx: settings.model.nCtx,
      nBatch: settings.model.nBatch,
      nPredict: settings.model.nPredict,
      accelerator: settings.model.accelerator,
      threads: settings.model.threads,
      microBatchSize: settings.model.microBatchSize,
    );
    notifyListeners();
  }

  Future<void> loadNotebooks() async {
    _notebooks = await _notebookRepository.listNotebooks();
    notifyListeners();
  }

  Future<void> setNotebook(String? notebookId) async {
    if (_conversation != null) {
      _conversation!.notebookId = notebookId;
      _conversation!.updatedAt = DateTime.now();
      await _conversationRepository.updateConversation(_conversation!);
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void cancelGeneration() {
    if (_isGenerating) {
      _generationEpoch++;
      _isGenerating = false;
      notifyListeners();
    }
  }
}
