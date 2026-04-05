library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/conversation.dart';
import 'package:local_ai_chat/features/chat/repositories/conversation_repository.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/speech/services/speech_service.dart';
import 'package:uuid/uuid.dart';

/// Conversation states for the seamless talk flow.
enum TalkState {
  /// Idle – waiting for user to start a conversation.
  idle,

  /// Actively listening for user speech.
  listening,

  /// User finished speaking, generating LLM response.
  generating,

  /// Speaking the LLM response via TTS.
  speaking,
}

/// A single message in a talk session.
class TalkMessage {
  final String id;
  final MessageRole role;
  String content;

  TalkMessage({
    required this.id,
    required this.role,
    required this.content,
  });
}

class TalkViewModel extends ChangeNotifier {
  final SpeechService _speechService;
  final ModelRuntimeService _runtimeService;
  final SettingsRepository _settingsRepository;
  final ConversationRepository _conversationRepository;

  TalkViewModel(
    this._speechService,
    this._runtimeService,
    this._settingsRepository,
    this._conversationRepository,
  );

  StreamSubscription<SpeechState>? _speechSubscription;

  // ── State ──────────────────────────────────────────────────────────────

  TalkState _state = TalkState.idle;
  TalkState get state => _state;

  bool get isListening => _state == TalkState.listening;
  bool get isGenerating => _state == TalkState.generating;
  bool get isSpeaking => _state == TalkState.speaking;

  /// Whether a conversation session is active (listening loop running).
  bool _conversationActive = false;
  bool get conversationActive => _conversationActive;

  /// The message history for this talk session.
  final List<TalkMessage> _messages = <TalkMessage>[];
  List<TalkMessage> get messages => List.unmodifiable(_messages);

  /// Live transcription of the current user utterance (not yet finalized).
  String _currentSpokenText = '';
  String get currentSpokenText => _currentSpokenText;

  /// Streaming response being generated (not yet finalized).
  String _currentResponse = '';
  String get currentResponse => _currentResponse;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get modelLoaded => _runtimeService.isLoaded;
  int _generationEpoch = 0;

  /// Timer for auto-detecting silence (no speech for N seconds).
  Timer? _silenceTimer;
  static const _silenceTimeout = Duration(seconds: 3);

  /// The persisted conversation entity for this talk session.
  Conversation? _conversation;
  Conversation? get conversation => _conversation;

  /// Whether the session is read-only (loaded from history).
  bool _readOnly = false;
  bool get readOnly => _readOnly;

  static const _uuid = Uuid();

  // ── Initialization ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    final settings = await _settingsRepository.loadAll();
    await _speechService.initialize(
      language: settings.speech.language,
      rate: settings.speech.speechRate,
    );

    _speechSubscription ??= _speechService.stateStream.listen((speechState) {
      // When TTS finishes speaking and conversation is still active,
      // automatically resume listening.
      if (!speechState.isSpeaking &&
          _state == TalkState.speaking &&
          _conversationActive) {
        _resumeListeningAfterSpeech();
      }
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Start a hands-free conversation loop.
  Future<void> startConversation() async {
    if (!_runtimeService.isLoaded) {
      _errorMessage = 'Load a model first.';
      notifyListeners();
      return;
    }

    _conversationActive = true;
    _readOnly = false;
    _errorMessage = null;
    _currentSpokenText = '';
    _currentResponse = '';
    _messages.clear();

    // Create a new persisted conversation.
    final now = DateTime.now();
    _conversation = Conversation(
      id: _uuid.v4(),
      title: 'Talk Session',
      createdAt: now,
      updatedAt: now,
      type: ConversationType.talk,
    );
    await _conversationRepository.createConversation(_conversation!);

    notifyListeners();
    await _beginListening();
  }

  /// Stop the entire conversation – cancel everything in flight.
  Future<void> stopConversation() async {
    _conversationActive = false;
    _cancelSilenceTimer();
    _generationEpoch++; // cancel any in-flight generation

    if (_state == TalkState.listening) {
      await _speechService.stopListening();
    }
    if (_state == TalkState.speaking) {
      await _speechService.stopSpeaking();
    }

    // Finalize any in-progress content into the message list.
    _finalizeInProgress();

    // Update the persisted conversation timestamp.
    if (_conversation != null) {
      _conversation!.updatedAt = DateTime.now();
      await _conversationRepository.updateConversation(_conversation!);
    }

    _state = TalkState.idle;
    notifyListeners();
  }

  /// Interrupt: user taps while AI is generating or speaking.
  /// Cancels current output and resumes listening.
  Future<void> interrupt() async {
    if (!_conversationActive) return;

    _cancelSilenceTimer();
    _generationEpoch++; // cancel generation stream

    if (_state == TalkState.speaking) {
      await _speechService.stopSpeaking();
    }

    // Finalize whatever was in progress before interrupting.
    _finalizeInProgress();

    // Start fresh listening
    _currentSpokenText = '';
    _currentResponse = '';
    _state = TalkState.listening;
    notifyListeners();

    await _beginListening();
  }

  /// Reset the session entirely (used when leaving the page).
  void resetSession() {
    _conversationActive = false;
    _cancelSilenceTimer();
    _generationEpoch++;
    _state = TalkState.idle;
    _messages.clear();
    _currentSpokenText = '';
    _currentResponse = '';
    _errorMessage = null;
    _conversation = null;
    _readOnly = false;

    // Stop services synchronously (fire-and-forget) so TTS/STT
    // doesn't keep running after the page is disposed.
    _speechService.stopListening();
    _speechService.stopSpeaking();

    notifyListeners();
  }

  /// Load a past talk session (read-only mode).
  Future<void> loadFromConversation(String conversationId) async {
    _readOnly = true;
    _conversationActive = false;
    _state = TalkState.idle;
    _messages.clear();
    _currentSpokenText = '';
    _currentResponse = '';
    _errorMessage = null;

    try {
      _conversation =
          await _conversationRepository.getConversation(conversationId);
      if (_conversation == null) {
        _errorMessage = 'Conversation not found.';
        notifyListeners();
        return;
      }

      final chatMessages =
          await _conversationRepository.getMessages(conversationId);
      for (final msg in chatMessages) {
        _messages.add(TalkMessage(
          id: msg.id,
          role: msg.role,
          content: msg.content,
        ));
      }
    } catch (e) {
      _errorMessage = 'Failed to load conversation: $e';
    }

    notifyListeners();
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Moves any in-progress spoken text or response into the messages list.
  void _finalizeInProgress() {
    if (_currentSpokenText.trim().isNotEmpty) {
      final userMsg = TalkMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: _currentSpokenText.trim(),
      );
      _messages.add(userMsg);
      _persistMessage(userMsg);
      _currentSpokenText = '';
    }

    if (_currentResponse.trim().isNotEmpty) {
      final assistantMsg = TalkMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: _currentResponse.trim(),
      );
      _messages.add(assistantMsg);
      _persistMessage(assistantMsg);
      _currentResponse = '';
    }
  }

  Future<void> _persistMessage(TalkMessage msg) async {
    if (_conversation == null) return;
    await _conversationRepository.addMessage(ChatMessage(
      id: msg.id,
      conversationId: _conversation!.id,
      role: msg.role,
      content: msg.content,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _beginListening() async {
    _cancelSilenceTimer();
    _state = TalkState.listening;
    _currentSpokenText = '';
    notifyListeners();

    final started = await _speechService.startListening(
      onResult: (words) {
        _currentSpokenText = words;
        notifyListeners();
        // Reset silence timer on each recognized word
        _resetSilenceTimer();
      },
      onSoundLevel: (level) {
        // Also reset on sound level changes (user is making noise)
        _resetSilenceTimer();
      },
    );

    if (!started) {
      _errorMessage = 'Microphone is unavailable.';
      _state = TalkState.idle;
      _conversationActive = false;
      notifyListeners();
      return;
    }

    // Start initial silence timer
    _resetSilenceTimer();
  }

  void _resetSilenceTimer() {
    _cancelSilenceTimer();
    _silenceTimer = Timer(_silenceTimeout, _onSilenceDetected);
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  /// Called when no speech has been detected for [_silenceTimeout].
  Future<void> _onSilenceDetected() async {
    if (!_conversationActive || _state != TalkState.listening) return;

    await _speechService.stopListening();

    if (_currentSpokenText.trim().isEmpty) {
      // No words detected – keep listening
      if (_conversationActive) {
        await _beginListening();
      }
      return;
    }

    // Finalize user message into the list and clear the live transcription
    // immediately so it doesn't render twice (once finalized + once live).
    final userMsg = TalkMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: _currentSpokenText.trim(),
    );
    _messages.add(userMsg);
    _currentSpokenText = '';
    notifyListeners();
    _persistMessage(userMsg);

    // Update conversation title from first user message.
    if (_conversation != null && _conversation!.title == 'Talk Session') {
      final firstWords = userMsg.content.length > 50
          ? '${userMsg.content.substring(0, 50)}...'
          : userMsg.content;
      _conversation!.title = firstWords;
      await _conversationRepository.updateConversation(_conversation!);
    }

    // Auto-send to LLM
    await _generateAndSpeak();
  }

  Future<void> _generateAndSpeak() async {
    if (!_runtimeService.isLoaded) return;

    _state = TalkState.generating;
    final epoch = ++_generationEpoch;
    _currentResponse = '';
    _errorMessage = null;
    notifyListeners();

    try {
      // Build the prompt from the user's last spoken text (already finalized).
      final lastUserMsg = _messages.lastWhere(
        (m) => m.role == MessageRole.user,
      );
      final stream = _runtimeService.generateStream(lastUserMsg.content);
      final buffer = StringBuffer();
      var lastNotify = DateTime.now().millisecondsSinceEpoch;

      await for (final token in stream) {
        if (epoch != _generationEpoch) break; // cancelled
        buffer.write(token);
        _currentResponse = buffer.toString();

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify >= 80) {
          notifyListeners();
          lastNotify = now;
        }
      }
      notifyListeners();

      // Finalize assistant message.
      if (epoch == _generationEpoch && _currentResponse.trim().isNotEmpty) {
        final assistantMsg = TalkMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: _currentResponse.trim(),
        );
        _messages.add(assistantMsg);
        _persistMessage(assistantMsg);

        final responseForTts = _currentResponse;
        _currentResponse = '';

        // Speak the response
        if (_conversationActive) {
          _state = TalkState.speaking;
          notifyListeners();
          await _speechService.speak(responseForTts);
          // After speak completes, the _speechSubscription listener
          // will call _resumeListeningAfterSpeech automatically.
        }
      } else if (_conversationActive && epoch == _generationEpoch) {
        _currentResponse = '';
        // Empty response – go back to listening
        await _beginListening();
      }
    } catch (e) {
      _errorMessage = 'Generation failed: $e';
      _currentResponse = '';
      if (_conversationActive) {
        // Try to recover by re-listening
        _state = TalkState.listening;
        notifyListeners();
        await _beginListening();
      } else {
        _state = TalkState.idle;
        notifyListeners();
      }
    }

    // Update the conversation timestamp.
    if (_conversation != null) {
      _conversation!.updatedAt = DateTime.now();
      await _conversationRepository.updateConversation(_conversation!);
    }
  }

  /// Resume listening after TTS has finished speaking.
  Future<void> _resumeListeningAfterSpeech() async {
    if (!_conversationActive) return;
    // Small delay to avoid immediately picking up residual audio
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_conversationActive) return;
    await _beginListening();
  }

  @override
  void dispose() {
    _generationEpoch++;
    _cancelSilenceTimer();
    _speechSubscription?.cancel();
    _speechService.stopListening();
    _speechService.stopSpeaking();
    super.dispose();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
