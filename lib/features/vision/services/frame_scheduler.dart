/// Frame scheduler — throttles frame capture for performance vs regular mode.
library;

import 'dart:typed_data';

import 'package:local_ai_chat/features/vision/services/vision_session_service.dart';

enum VisionMode { performance, regular }

class FrameScheduler {
  final VisionSessionService _visionService;

  VisionMode _mode = VisionMode.performance;
  VisionMode get mode => _mode;

  bool _inferenceBusy = false;
  bool _running = false;
  void Function(Uint8List frame)? _onFrame;
  Duration _performanceInterval = const Duration(seconds: 5);
  Duration _regularInterval = const Duration(seconds: 2);

  FrameScheduler(this._visionService);

  /// Sets the vision mode.
  void setMode(VisionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    if (_running && _onFrame != null) {
      start(onFrame: _onFrame!);
    }
  }

  /// Allows settings to override default frame intervals.
  void configureIntervals({
    Duration? performanceInterval,
    Duration? regularInterval,
  }) {
    if (performanceInterval != null) {
      _performanceInterval = performanceInterval;
    }
    if (regularInterval != null) {
      _regularInterval = regularInterval;
    }
    if (_running && _onFrame != null) {
      start(onFrame: _onFrame!);
    }
  }

  /// Marks inference as busy (prevents overlapping inference).
  void setInferenceBusy(bool busy) {
    _inferenceBusy = busy;
  }

  /// Gets the frame interval based on mode.
  Duration get frameInterval {
    switch (_mode) {
      case VisionMode.performance:
        return _performanceInterval;
      case VisionMode.regular:
        return _regularInterval;
    }
  }

  /// Starts frame capture with mode-appropriate throttling.
  /// [onFrame] is only called when inference is not busy.
  void start({required void Function(Uint8List frame) onFrame}) {
    _onFrame = onFrame;
    _running = true;
    _visionService.startFrameSampling(
      interval: frameInterval,
      onFrame: (frame) {
        if (!_inferenceBusy) {
          onFrame(frame);
        }
      },
    );
  }

  /// Stops frame capture.
  void stop() {
    _running = false;
    _visionService.stopFrameSampling();
  }
}
