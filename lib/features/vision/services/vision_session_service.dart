/// Vision session service — camera lifecycle, frame capture, image preprocessing.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Manages camera session lifecycle for multimodal vision chat.
class VisionSessionService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Timer? _frameTimer;
  bool _isCapturing = false;
  bool _captureInProgress = false;
  bool _disposed = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get hasCameras => _cameras.isNotEmpty;

  /// Discovers available cameras.
  Future<void> discoverCameras() async {
    _cameras = await availableCameras();
  }

  /// Initializes the camera (defaults to back camera).
  Future<void> initialize({
    int cameraIndex = 0,
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    if (_disposed) {
      throw StateError('VisionSessionService is disposed');
    }
    if (_cameras.isEmpty) await discoverCameras();
    if (_cameras.isEmpty) {
      throw CameraException('no_camera', 'No cameras available');
    }

    await releaseCamera();

    final controller = CameraController(
      _cameras[cameraIndex < _cameras.length ? cameraIndex : 0],
      resolution,
      enableAudio: false,
    );

    await controller.initialize();
    _controller = controller;
  }

  /// Captures a single still image and returns JPEG bytes.
  Future<Uint8List?> captureStillImage() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (_captureInProgress) return null;
    _captureInProgress = true;

    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final tempFile = File(file.path);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _captureInProgress = false;
    }
  }

  /// Starts periodic frame sampling at the given interval.
  /// [onFrame] is called with JPEG bytes for each captured frame.
  void startFrameSampling({
    required Duration interval,
    required void Function(Uint8List frame) onFrame,
  }) {
    if (_disposed || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    stopFrameSampling();
    _isCapturing = true;
    _frameTimer = Timer.periodic(interval, (_) async {
      if (!_isCapturing || _captureInProgress) return;
      final frame = await captureStillImage();
      if (frame != null) onFrame(frame);
    });
  }

  /// Stops periodic frame sampling.
  void stopFrameSampling() {
    _isCapturing = false;
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  /// Switches between front/back camera.
  Future<void> switchCamera() async {
    final controller = _controller;
    if (_cameras.length < 2 || controller == null) return;

    final currentIndex = _cameras.indexOf(controller.description);
    final nextIndex = (currentIndex + 1) % _cameras.length;

    await initialize(cameraIndex: nextIndex);
  }

  /// Releases active camera resources but keeps the service reusable.
  Future<void> releaseCamera() async {
    stopFrameSampling();
    await _controller?.dispose();
    _controller = null;
  }

  /// Resizes image bytes to fit within max dimensions.
  /// Returns resized JPEG bytes.
  /// Note: Full image resizing requires dart:ui or image package.
  /// This is a placeholder — in production, use the `image` package.
  Future<Uint8List> preprocessImage(
    Uint8List imageBytes, {
    int maxWidth = 512,
    int maxHeight = 512,
    int quality = 80,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return imageBytes;
    }

    final shouldResize = decoded.width > maxWidth || decoded.height > maxHeight;

    final resized = shouldResize
        ? img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? maxWidth : null,
            height: decoded.height >= decoded.width ? maxHeight : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final jpgQuality = quality.clamp(1, 100);
    return Uint8List.fromList(img.encodeJpg(resized, quality: jpgQuality));
  }

  /// Disposes the camera controller and timers.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await releaseCamera();
  }
}
