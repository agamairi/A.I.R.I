/// Typed settings models covering all app configuration categories.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Top-level container
// ---------------------------------------------------------------------------

class AppSettings {
  ModelSettings model;
  VisionSettings vision;
  RagSettings rag;
  WebAccessSettings web;
  LanSettings lan;
  SpeechSettings speech;
  PerformanceSettings performance;
  ThemeSettings theme;

  AppSettings({
    ModelSettings? model,
    VisionSettings? vision,
    RagSettings? rag,
    WebAccessSettings? web,
    LanSettings? lan,
    SpeechSettings? speech,
    PerformanceSettings? performance,
    ThemeSettings? theme,
  })  : model = model ?? ModelSettings(),
        vision = vision ?? VisionSettings(),
        rag = rag ?? RagSettings(),
        web = web ?? WebAccessSettings(),
        lan = lan ?? LanSettings(),
        speech = speech ?? SpeechSettings(),
        performance = performance ?? PerformanceSettings(),
        theme = theme ?? ThemeSettings();
}

// ---------------------------------------------------------------------------
// Category models
// ---------------------------------------------------------------------------

class ModelSettings {
  int nCtx;
  int nBatch;
  int nPredict;
  double temperature;
  int topK;
  double topP;

  /// Accelerator backend: 'auto', 'cpu', 'vulkan', 'metal', 'cuda'.
  String accelerator;

  /// CPU thread count override (0 = auto-detect based on cores).
  int threads;

  /// Micro-batch size override (0 = auto).
  int microBatchSize;

  /// Repeat penalty for generation.
  double repeatPenalty;

  /// Random seed for sampling (null = random).
  int? seed;

  ModelSettings({
    this.nCtx = 2048,
    this.nBatch = 512,
    this.nPredict = 512,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.9,
    this.accelerator = 'auto',
    this.threads = 0,
    this.microBatchSize = 0,
    this.repeatPenalty = 1.1,
    this.seed,
  });
}

class VisionSettings {
  bool performanceMode;
  int frameSamplingIntervalMs;
  int maxImageWidth;
  int maxImageHeight;
  int imageQuality;
  bool autoStartCamera;

  VisionSettings({
    this.performanceMode = true,
    this.frameSamplingIntervalMs = 5000,
    this.maxImageWidth = 512,
    this.maxImageHeight = 512,
    this.imageQuality = 80,
    this.autoStartCamera = false,
  });
}

class RagSettings {
  int defaultChunkSize;
  int defaultChunkOverlap;
  int defaultTopK;
  bool strictGrounding;
  bool citationsEnabled;
  String retrievalMode; // 'auto', 'lexical', 'embeddings', 'hybrid'

  RagSettings({
    this.defaultChunkSize = 512,
    this.defaultChunkOverlap = 64,
    this.defaultTopK = 5,
    this.strictGrounding = false,
    this.citationsEnabled = true,
    this.retrievalMode = 'auto',
  });
}

class WebAccessSettings {
  bool allowInternetAccess;
  bool askBeforeSearch;

  WebAccessSettings({
    this.allowInternetAccess = false,
    this.askBeforeSearch = true,
  });
}

class LanSettings {
  bool enabled;
  int port;
  String authToken;

  LanSettings({
    this.enabled = false,
    this.port = 8080,
    this.authToken = '',
  });
}

class SpeechSettings {
  String language;
  double speechRate;
  bool autoStartMic;

  SpeechSettings({
    this.language = 'en-US',
    this.speechRate = 0.5,
    this.autoStartMic = false,
  });
}

class PerformanceSettings {
  int contextCompressionThreshold;
  bool autoCompress;

  PerformanceSettings({
    this.contextCompressionThreshold = 20,
    this.autoCompress = true,
  });
}

class ThemeSettings {
  bool isDarkMode;
  int primaryColorValue;

  ThemeSettings({
    this.isDarkMode = false,
    this.primaryColorValue = 0xFF2196F3, // Colors.blue
  });

  Color get primaryColor => Color(primaryColorValue);
}
