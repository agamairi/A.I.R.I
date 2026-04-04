library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/speech/services/speech_service.dart';

class TalkViewModel extends ChangeNotifier {
  final SpeechService _speechService;
  final ModelRuntimeService _runtimeService;
  final SettingsRepository _settingsRepository;

  TalkViewModel(
    this._speechService,
    this._runtimeService,
    this._settingsRepository,
  );

  StreamSubscription<SpeechState>? _speechSubscription;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  String _spokenText = '';
  String get spokenText => _spokenText;

  String _response = '';
  String get response => _response;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get modelLoaded => _runtimeService.isLoaded;
  int _generationEpoch = 0;

  Future<void> initialize() async {
    final settings = await _settingsRepository.loadAll();
    await _speechService.initialize(
      language: settings.speech.language,
      rate: settings.speech.speechRate,
    );

    _speechSubscription ??= _speechService.stateStream.listen((state) {
      _isListening = state.isListening;
      _isSpeaking = state.isSpeaking;
      notifyListeners();
    });
  }

  Future<void> toggleListening() async {
    if (_isGenerating) return;

    if (_isListening) {
      await _speechService.stopListening();
      return;
    }

    _spokenText = '';
    _response = '';
    _errorMessage = null;
    notifyListeners();

    final started = await _speechService.startListening(
      onResult: (words) {
        _spokenText = words;
        notifyListeners();
      },
    );

    if (!started) {
      _errorMessage = 'Microphone is unavailable.';
      notifyListeners();
    }
  }

  Future<void> generateResponse() async {
    if (_isGenerating ||
        _spokenText.trim().isEmpty ||
        !_runtimeService.isLoaded) {
      return;
    }

    _isGenerating = true;
    final epoch = ++_generationEpoch;
    _response = '';
    _errorMessage = null;
    notifyListeners();

    try {
      final stream = _runtimeService.generateStream(_spokenText.trim());
      final buffer = StringBuffer();

      await for (final token in stream) {
        if (epoch != _generationEpoch) {
          break;
        }
        buffer.write(token);
        _response = buffer.toString();
        notifyListeners();
      }

      if (_response.trim().isNotEmpty) {
        await _speechService.speak(_response);
      }
    } catch (e) {
      _errorMessage = 'Talk generation failed: $e';
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _generationEpoch++;
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
