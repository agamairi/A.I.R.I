library;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/vision/services/frame_scheduler.dart';
import 'package:local_ai_chat/features/vision/services/vision_session_service.dart';

class VisionViewModel extends ChangeNotifier {
  final VisionSessionService _visionService;
  final FrameScheduler _frameScheduler;
  final ModelRuntimeService _runtimeService;
  final SettingsRepository _settingsRepository;

  VisionViewModel(
    this._visionService,
    this._frameScheduler,
    this._runtimeService,
    this._settingsRepository,
  );

  bool _loadingCamera = false;
  bool get loadingCamera => _loadingCamera;

  bool _cameraReady = false;
  bool get cameraReady => _cameraReady;

  bool _sampling = false;
  bool get sampling => _sampling;

  bool _processingFrame = false;
  bool get processingFrame => _processingFrame;

  VisionMode _mode = VisionMode.performance;
  VisionMode get mode => _mode;

  String _prompt = 'Describe this scene briefly.';
  String get prompt => _prompt;

  String _latestResponse = '';
  String get latestResponse => _latestResponse;

  Uint8List? _lastFrame;
  Uint8List? get lastFrame => _lastFrame;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _frameIntervalMs = 5000;
  int _maxWidth = 512;
  int _maxHeight = 512;
  int _quality = 80;
  int _generationEpoch = 0;

  CameraController? get cameraController => _visionService.controller;
  bool get modelLoaded => _runtimeService.isLoaded;
  bool get modelSupportsVision => _runtimeService.capability.supportsVision;

  Future<void> onEnter() async {
    _loadingCamera = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final settings = await _settingsRepository.loadAll();
      _applySettings(settings.vision);

      await _visionService.initialize();
      _cameraReady = _visionService.isInitialized;

      if (settings.vision.autoStartCamera) {
        startSampling();
      }
    } catch (e) {
      _cameraReady = false;
      _errorMessage = 'Failed to initialize camera: $e';
    } finally {
      _loadingCamera = false;
      notifyListeners();
    }
  }

  Future<void> onExit() async {
    stopSampling();
    await _visionService.releaseCamera();
    _cameraReady = false;
    _generationEpoch++;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    try {
      await _visionService.switchCamera();
      _cameraReady = _visionService.isInitialized;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to switch camera: $e';
      notifyListeners();
    }
  }

  void updatePrompt(String value) {
    _prompt = value;
    notifyListeners();
  }

  Future<void> setPerformanceMode(bool enabled) async {
    _mode = enabled ? VisionMode.performance : VisionMode.regular;
    _frameScheduler.setMode(_mode);

    final settings = await _settingsRepository.loadAll();
    settings.vision.performanceMode = enabled;
    await _settingsRepository.saveVisionSettings(settings.vision);

    notifyListeners();
  }

  void startSampling() {
    if (!_cameraReady || _sampling) return;
    _sampling = true;
    _frameScheduler.setMode(_mode);
    _frameScheduler.configureIntervals(
      performanceInterval: Duration(milliseconds: _frameIntervalMs),
      regularInterval: Duration(
        milliseconds: (_frameIntervalMs / 2).round().clamp(500, 60000),
      ),
    );
    _frameScheduler.start(onFrame: _onFrame);
    notifyListeners();
  }

  void stopSampling() {
    if (!_sampling) return;
    _sampling = false;
    _frameScheduler.stop();
    _frameScheduler.setInferenceBusy(false);
    notifyListeners();
  }

  Future<void> captureAndAnalyze() async {
    final frame = await _visionService.captureStillImage();
    if (frame == null) return;
    await _inferOnFrame(frame);
  }

  Future<void> _onFrame(Uint8List frame) async {
    await _inferOnFrame(frame);
  }

  Future<void> _inferOnFrame(Uint8List frame) async {
    if (_processingFrame) return;

    _processingFrame = true;
    _errorMessage = null;
    _frameScheduler.setInferenceBusy(true);
    final epoch = ++_generationEpoch;
    notifyListeners();

    try {
      _lastFrame = frame;

      if (!_runtimeService.isLoaded) {
        _errorMessage = 'Load a model before using live vision.';
        return;
      }
      if (!_runtimeService.capability.supportsVision) {
        _errorMessage = 'Loaded model is text-only. Vision requires a VLM.';
        return;
      }

      final prepared = await _visionService.preprocessImage(
        frame,
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        quality: _quality,
      );

      final prompt = _prompt.trim().isEmpty
          ? 'Describe the current scene.'
          : _prompt.trim();

      final buffer = StringBuffer();
      final stream = _runtimeService.generateVisionStream(
        prompt,
        images: [prepared],
      );

      await for (final token in stream) {
        if (epoch != _generationEpoch) {
          break;
        }
        buffer.write(token);
        _latestResponse = buffer.toString();
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Vision inference failed: $e';
    } finally {
      _processingFrame = false;
      _frameScheduler.setInferenceBusy(false);
      notifyListeners();
    }
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
