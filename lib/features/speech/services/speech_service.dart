/// SpeechService wraps STT + TTS, migrated from talk_page.dart.
library;

import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _disposed = false;
  bool _ttsConfigured = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  final _stateController = StreamController<SpeechState>.broadcast();
  Stream<SpeechState> get stateStream => _stateController.stream;

  SpeechService() {
    _tts.setCompletionHandler(_handleTtsDone);
    _tts.setCancelHandler(_handleTtsDone);
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
      _broadcastState();
    });
  }

  /// Initializes TTS defaults.
  Future<void> initialize(
      {String language = 'en-US', double rate = 0.5}) async {
    if (_disposed) return;
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    _ttsConfigured = true;
  }

  /// Starts listening for speech input.
  /// [onResult] called with recognized words (cumulative).
  /// [onSoundLevel] called with sound level changes.
  Future<bool> startListening({
    required void Function(String words) onResult,
    void Function(double level)? onSoundLevel,
  }) async {
    if (_disposed) return false;
    if (_isListening) return true;
    if (_isSpeaking) {
      await stopSpeaking();
    }

    final available = await _stt.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          _broadcastState();
        }
      },
      onError: (_) {
        _isListening = false;
        _broadcastState();
      },
    );
    if (!available) return false;

    _isListening = true;
    _broadcastState();

    await _stt.listen(
      onResult: (result) => onResult(result.recognizedWords),
      onSoundLevelChange: onSoundLevel,
    );

    return true;
  }

  /// Stops speech recognition.
  Future<void> stopListening() async {
    if (_disposed) return;
    if (!_isListening) return;
    _isListening = false;
    await _stt.stop();
    _broadcastState();
  }

  /// Speaks the given text via TTS.
  Future<void> speak(String text) async {
    if (_disposed) return;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (_isListening) {
      await stopListening();
    }
    if (!_ttsConfigured) {
      await initialize();
    }
    _isSpeaking = true;
    _broadcastState();
    await _tts.speak(normalized);
  }

  /// Stops TTS.
  Future<void> stopSpeaking() async {
    if (_disposed) return;
    await _tts.stop();
    _isSpeaking = false;
    _broadcastState();
  }

  void _handleTtsDone() {
    _isSpeaking = false;
    _broadcastState();
  }

  void _broadcastState() {
    if (_disposed || _stateController.isClosed) return;
    _stateController.add(SpeechState(
      isListening: _isListening,
      isSpeaking: _isSpeaking,
    ));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _isListening = false;
    _isSpeaking = false;
    await _stt.stop();
    await _tts.stop();
    await _stateController.close();
  }
}

class SpeechState {
  final bool isListening;
  final bool isSpeaking;

  const SpeechState({
    this.isListening = false,
    this.isSpeaking = false,
  });
}
