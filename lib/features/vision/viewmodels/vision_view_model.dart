library;

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:llamadart/llamadart.dart' show GenerationParams;
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/vision/services/frame_scheduler.dart';
import 'package:local_ai_chat/features/vision/services/vision_session_service.dart';
import 'package:local_ai_chat/features/speech/services/speech_service.dart';

class VisionViewModel extends ChangeNotifier {
  final VisionSessionService _visionService;
  final ModelRuntimeService _runtimeService;
  final SettingsRepository _settingsRepository;
  final SpeechService _speechService;

  VisionViewModel(
    this._visionService,
    this._runtimeService,
    this._settingsRepository,
    this._speechService,
  );

  StreamSubscription<SpeechState>? _speechSubscription;

  bool _loadingCamera = false;
  bool get loadingCamera => _loadingCamera;

  bool _cameraReady = false;
  bool get cameraReady => _cameraReady;

  bool _cameraEnabled = true;
  bool get cameraEnabled => _cameraEnabled;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  bool _processingFrame = false;
  bool get processingFrame => _processingFrame;

  bool _isModelLoading = false;
  bool get isModelLoading => _isModelLoading;

  VisionMode _mode = VisionMode.performance;
  VisionMode get mode => _mode;

  String _spokenText = '';
  String get spokenText => _spokenText;

  String _latestResponse = '';
  String get latestResponse => _latestResponse;

  Uint8List? _lastFrame;
  Uint8List? get lastFrame => _lastFrame;

  /// Warning shown when model lacks vision support (non-blocking).
  String? _visionWarning;
  String? get visionWarning => _visionWarning;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _frameIntervalMs = 5000;
  int get frameIntervalMs => _frameIntervalMs;

  int _maxWidth = 512;
  int get maxWidth => _maxWidth;
  int _maxHeight = 512;
  int get maxHeight => _maxHeight;

  int _nCtx = 2048;
  int get nCtx => _nCtx;
  int _nPredict = 512;
  int get nPredict => _nPredict;
  double _temperature = 0.7;
  double get temperature => _temperature;
  int _topK = 40;
  int get topK => _topK;
  double _topP = 0.9;
  double get topP => _topP;

  int _quality = 80;
  int _generationEpoch = 0;

  CameraController? get cameraController => _visionService.controller;
  bool get modelLoaded => _runtimeService.isLoaded;
  bool get modelSupportsVision => _runtimeService.capability.supportsVision;
  String? get currentModelPath => _runtimeService.currentModelPath;

  Future<void> onEnter() async {
    _loadingCamera = true;
    _errorMessage = null;
    _visionWarning = null;
    notifyListeners();

    try {
      final settings = await _settingsRepository.loadAll();
      _applySettings(settings.vision);
      _applyModelSettings(settings.model);

      await _speechService.initialize(
        language: settings.speech.language,
        rate: settings.speech.speechRate,
      );

      _speechSubscription ??= _speechService.stateStream.listen((state) {
        _isListening = state.isListening;
        _isSpeaking = state.isSpeaking;

        // Auto-capture when speech finishes
        if (!_isListening && _spokenText.trim().isNotEmpty && !_processingFrame && !_isSpeaking) {
           _captureAndAnalyze();
        }

        // Restart listening after speaking finished
        if (!_isListening && !_isSpeaking && !_processingFrame && _latestResponse.isNotEmpty) {
           if (modelLoaded && _cameraEnabled) {
               Future.delayed(const Duration(milliseconds: 500), () {
                  if (!_isListening && !_isSpeaking) toggleListening();
               });
           }
        }

        notifyListeners();
      });

      if (!_runtimeService.isLoaded) {
        _loadingCamera = false;
        notifyListeners();
        return;
      }

      // Warn early if model doesn't support vision
      _checkVisionSupport();

      await _initCameraWithCurrentResolution();
      _cameraReady = _visionService.isInitialized;

      // Start continuous frame sampling — camera stays live at all times
      _startContinuousFrameSampling();

      // Auto start listening
      toggleListening();

    } catch (e) {
      _cameraReady = false;
      _errorMessage = 'Failed to initialize system: $e';
    } finally {
      _loadingCamera = false;
      notifyListeners();
    }
  }

  void _checkVisionSupport() {
    if (!_runtimeService.capability.supportsVision) {
      _visionWarning =
          'Current model does not support vision. '
          'Load a vision model (e.g. LLaVA) to enable camera analysis. '
          'Text chat still works.';
      _cameraEnabled = false;
    } else if (_runtimeService.capability.supportsVision &&
        !_runtimeService.visionProjectorLoaded) {
      _visionWarning =
          'Vision model loaded but mmproj projector file is missing. '
          'Download the matching *-mmproj-*.gguf file and place it in '
          'the same folder as the model. Falling back to text-only.';
      _cameraEnabled = false;
    } else {
      _visionWarning = null;
    }
    notifyListeners();
  }

  /// Continuously captures frames at the configured FPS.
  /// Stores the latest frame so inference always uses the most recent view.
  void _startContinuousFrameSampling() {
    if (!_cameraEnabled || !_cameraReady) return;
    _visionService.startFrameSampling(
      interval: Duration(milliseconds: _frameIntervalMs),
      onFrame: (frame) {
        _lastFrame = frame;
      },
    );
  }

  void _stopContinuousFrameSampling() {
    _visionService.stopFrameSampling();
  }

  Future<void> _initCameraWithCurrentResolution() async {
     ResolutionPreset preset = ResolutionPreset.medium;
     if (_maxHeight >= 1080) {
       preset = ResolutionPreset.veryHigh;
     } else if (_maxHeight >= 720) {
       preset = ResolutionPreset.high;
     } else if (_maxHeight >= 480) {
       preset = ResolutionPreset.medium;
     } else {
       preset = ResolutionPreset.low;
     }

     final currentIndex = _visionService.controller?.description != null ? 
        _visionService.hasCameras ? 0 : 0 // fallback
        : 0;

     await _visionService.initialize(cameraIndex: currentIndex, resolution: preset);
  }

  Future<void> onExit() async {
    _generationEpoch++;
    _speechSubscription?.cancel();
    _speechSubscription = null;
    _stopContinuousFrameSampling();
    await _speechService.stopListening();
    await _speechService.stopSpeaking();
    await _visionService.releaseCamera();
    _cameraReady = false;
    _processingFrame = false;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (!_cameraEnabled) return;
    try {
      await _visionService.switchCamera();
      _cameraReady = _visionService.isInitialized;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to switch camera: $e';
      notifyListeners();
    }
  }

  Future<List<String>> listLocalModels() async {
    return _runtimeService.listLocalModels();
  }

  Future<void> loadModelWithSettings(String modelPath) async {
    _isModelLoading = true;
    _errorMessage = null;
    _visionWarning = null;
    _stopContinuousFrameSampling();
    notifyListeners();
    try {
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
       _applySettings(settings.vision);
       _applyModelSettings(settings.model);

       // Check vision support for newly loaded model
       _checkVisionSupport();

       if (_cameraEnabled) {
          await _initCameraWithCurrentResolution();
          _cameraReady = true;
          _startContinuousFrameSampling();
          toggleListening();
       }
    } catch (e) {
       _errorMessage = 'Failed to load model: $e';
    } finally {
       _isModelLoading = false;
       notifyListeners();
    }
  }

  Future<void> saveModelSettings({
    int? nCtx,
    int? nPredict,
    double? temperature,
    int? topK,
    double? topP,
  }) async {
    final settings = await _settingsRepository.loadAll();
    if (nCtx != null) settings.model.nCtx = nCtx;
    if (nPredict != null) settings.model.nPredict = nPredict;
    if (temperature != null) settings.model.temperature = temperature;
    if (topK != null) settings.model.topK = topK;
    if (topP != null) settings.model.topP = topP;

    await _settingsRepository.saveModelSettings(settings.model);
    _applyModelSettings(settings.model);
    notifyListeners();
  }

  void _applyModelSettings(ModelSettings settings) {
    _nCtx = settings.nCtx;
    _nPredict = settings.nPredict;
    _temperature = settings.temperature;
    _topK = settings.topK;
    _topP = settings.topP;
  }

  void toggleCameraEnabled() {
    _cameraEnabled = !_cameraEnabled;
    if (_cameraEnabled && modelLoaded && !_cameraReady) {
       _initCameraWithCurrentResolution().then((_) {
          _cameraReady = true;
          _startContinuousFrameSampling();
          notifyListeners();
       });
    } else if (_cameraEnabled && _cameraReady) {
       _startContinuousFrameSampling();
    } else if (!_cameraEnabled) {
       _stopContinuousFrameSampling();
    }
    notifyListeners();
  }

  Future<void> endCall() async {
    _generationEpoch++;
    _stopContinuousFrameSampling();
    await _speechService.stopListening();
    await _speechService.stopSpeaking();
    await _visionService.releaseCamera();
    await _runtimeService.dispose();
    
    _cameraReady = false;
    _processingFrame = false;
    _spokenText = '';
    _latestResponse = '';
    _cameraEnabled = true;

    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (_processingFrame) return;
    if (_cameraEnabled && !_cameraReady) return;

    if (_isListening) {
      await _speechService.stopListening();
      return;
    }

    _spokenText = '';
    _latestResponse = '';
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

  Future<void> _captureAndAnalyze() async {
    if (_processingFrame) return;

    if (_cameraEnabled && modelSupportsVision) {
      // Use latest frame from continuous sampling — no camera interruption
      final frame = _lastFrame ?? await _visionService.captureStillImage();
      if (frame == null) {
        _errorMessage = 'Failed to capture frame.';
        notifyListeners();
        return;
      }
      await _inferOnFrame(frame);
    } else {
      await _inferTextOnly();
    }
  }

  Future<void> _inferTextOnly() async {
    _processingFrame = true;
    _errorMessage = null;
    final epoch = ++_generationEpoch;
    notifyListeners();

    try {
      if (!_runtimeService.isLoaded) {
        _errorMessage = 'Load a model in chat before using live chat.';
        return;
      }

      final prompt = _spokenText.trim().isEmpty
          ? 'Hello.'
          : _spokenText.trim();

      final genParams = GenerationParams(
        maxTokens: _nPredict,
        temp: _temperature,
        topK: _topK,
        topP: _topP,
      );

      final buffer = StringBuffer();
      final stream = _runtimeService.generateStream(
        prompt,
        generationParams: genParams,
      );
      var lastNotify = DateTime.now().millisecondsSinceEpoch;

      await for (final token in stream) {
        if (epoch != _generationEpoch) {
          break;
        }
        buffer.write(token);
        _latestResponse = buffer.toString();

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify >= 80) {
          notifyListeners();
          lastNotify = now;
        }
      }
      notifyListeners();

      if (_latestResponse.trim().isNotEmpty) {
        await _speechService.speak(_latestResponse);
      }
    } catch (e) {
      _errorMessage = 'Chat inference failed: $e';
    } finally {
      if (epoch == _generationEpoch) {
          _spokenText = '';
          _processingFrame = false;
          notifyListeners();
      }
    }
  }

  Future<void> _inferOnFrame(Uint8List frame) async {
    _processingFrame = true;
    _errorMessage = null;
    final epoch = ++_generationEpoch;
    notifyListeners();

    try {
      _lastFrame = frame;

      if (!_runtimeService.isLoaded) {
        _errorMessage = 'Load a model in chat before using live vision.';
        return;
      }
      if (!_runtimeService.capability.supportsVision) {
         _errorMessage = 'Model does not support vision. Switch to a vision model (e.g. LLaVA).';
         _processingFrame = false;
         notifyListeners();
         return;
      }

      final prepared = await _visionService.preprocessImage(
        frame,
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        quality: _quality,
      );

      final prompt = _spokenText.trim().isEmpty
          ? 'Describe what you see briefly.'
          : _spokenText.trim();

      final genParams = GenerationParams(
        maxTokens: _nPredict,
        temp: _temperature,
        topK: _topK,
        topP: _topP,
      );

      final buffer = StringBuffer();
      final stream = _runtimeService.generateVisionStream(
        prompt,
        images: [prepared],
        generationParams: genParams,
      );
      var lastNotifyV = DateTime.now().millisecondsSinceEpoch;

      await for (final token in stream) {
        if (epoch != _generationEpoch) {
          break;
        }
        buffer.write(token);
        _latestResponse = buffer.toString();

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotifyV >= 80) {
          notifyListeners();
          lastNotifyV = now;
        }
      }
      notifyListeners();

      // After generation is done, let it speak!
      if (_latestResponse.trim().isNotEmpty) {
        await _speechService.speak(_latestResponse);
      }
    } catch (e) {
      _errorMessage = 'Vision inference failed: $e';
    } finally {
      if (epoch == _generationEpoch) {
         _spokenText = '';
         _processingFrame = false;
         notifyListeners();
      }
    }
  }

  // --- Settings modifications

  Future<void> saveVisionResolution(int width, int height) async {
     _maxWidth = width.clamp(128, 2048);
     _maxHeight = height.clamp(128, 2048);
     final settings = await _settingsRepository.loadAll();
     settings.vision.maxImageWidth = _maxWidth;
     settings.vision.maxImageHeight = _maxHeight;
     await _settingsRepository.saveVisionSettings(settings.vision);

     // Reinit camera with new resolution preset if running
     if (_cameraReady && _cameraEnabled) {
        _stopContinuousFrameSampling();
        await _initCameraWithCurrentResolution();
        _startContinuousFrameSampling();
     }
     notifyListeners();
  }

  Future<void> saveVisionFramerate(int ms) async {
     _frameIntervalMs = ms.clamp(16, 60000);
     final settings = await _settingsRepository.loadAll();
     settings.vision.frameSamplingIntervalMs = _frameIntervalMs;
     await _settingsRepository.saveVisionSettings(settings.vision);

     // Restart frame sampling with new interval
     if (_cameraReady && _cameraEnabled) {
        _stopContinuousFrameSampling();
        _startContinuousFrameSampling();
     }
     notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _applySettings(VisionSettings settings) {
    _mode =
        settings.performanceMode ? VisionMode.performance : VisionMode.regular;
    _frameIntervalMs = settings.frameSamplingIntervalMs;
    _maxWidth = settings.maxImageWidth;
    _maxHeight = settings.maxImageHeight;
    _quality = settings.imageQuality;
  }
}
