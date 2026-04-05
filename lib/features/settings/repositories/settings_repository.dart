/// Settings repository — persists all app settings.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';

class SettingsRepository {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ---------------------------------------------------------------------------
  // Load all settings
  // ---------------------------------------------------------------------------

  Future<AppSettings> loadAll() async {
    final prefs = await _preferences;
    final lanPort = (prefs.getInt('lan.port') ?? 8080).clamp(1, 65535);
    final frameInterval =
        (prefs.getInt('vision.frameSamplingIntervalMs') ?? 5000)
            .clamp(500, 60000);
    final speechRate = (prefs.getDouble('speech.speechRate') ?? 0.5)
        .clamp(0.1, 1.0)
        .toDouble();

    return AppSettings(
      model: ModelSettings(
        nCtx: prefs.getInt('model.nCtx') ?? 2048,
        nBatch: prefs.getInt('model.nBatch') ?? 512,
        nPredict: prefs.getInt('model.nPredict') ?? 512,
        temperature: prefs.getDouble('model.temperature') ?? 0.7,
        topK: prefs.getInt('model.topK') ?? 40,
        topP: prefs.getDouble('model.topP') ?? 0.9,
        accelerator: prefs.getString('model.accelerator') ?? 'auto',
        threads: prefs.getInt('model.threads') ?? 0,
        microBatchSize: prefs.getInt('model.microBatchSize') ?? 0,
        repeatPenalty: prefs.getDouble('model.repeatPenalty') ?? 1.1,
        seed: prefs.getInt('model.seed'),
      ),
      vision: VisionSettings(
        performanceMode: prefs.getBool('vision.performanceMode') ?? true,
        frameSamplingIntervalMs: frameInterval,
        maxImageWidth: prefs.getInt('vision.maxImageWidth') ?? 512,
        maxImageHeight: prefs.getInt('vision.maxImageHeight') ?? 512,
        imageQuality: prefs.getInt('vision.imageQuality') ?? 80,
        autoStartCamera: prefs.getBool('vision.autoStartCamera') ?? false,
      ),
      rag: RagSettings(
        defaultChunkSize: prefs.getInt('rag.defaultChunkSize') ?? 512,
        defaultChunkOverlap: prefs.getInt('rag.defaultChunkOverlap') ?? 64,
        defaultTopK: prefs.getInt('rag.defaultTopK') ?? 5,
        strictGrounding: prefs.getBool('rag.strictGrounding') ?? false,
        citationsEnabled: prefs.getBool('rag.citationsEnabled') ?? true,
        retrievalMode: prefs.getString('rag.retrievalMode') ?? 'auto',
      ),
      web: WebAccessSettings(
        allowInternetAccess: prefs.getBool('web.allowInternetAccess') ?? false,
        askBeforeSearch: prefs.getBool('web.askBeforeSearch') ?? true,
      ),
      lan: LanSettings(
        enabled: prefs.getBool('lan.enabled') ?? false,
        port: lanPort,
        authToken: prefs.getString('lan.authToken') ?? '',
      ),
      speech: SpeechSettings(
        language: prefs.getString('speech.language') ?? 'en-US',
        speechRate: speechRate,
        autoStartMic: prefs.getBool('speech.autoStartMic') ?? false,
      ),
      performance: PerformanceSettings(
        contextCompressionThreshold:
            prefs.getInt('perf.contextCompressionThreshold') ?? 20,
        autoCompress: prefs.getBool('perf.autoCompress') ?? true,
      ),
      theme: ThemeSettings(
        isDarkMode: prefs.getBool('theme.isDarkMode') ?? false,
        primaryColorValue:
            prefs.getInt('theme.primaryColorValue') ?? 0xFF2196F3,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Save individual categories
  // ---------------------------------------------------------------------------

  Future<void> saveModelSettings(ModelSettings s) async {
    final prefs = await _preferences;
    await prefs.setInt('model.nCtx', s.nCtx);
    await prefs.setInt('model.nBatch', s.nBatch);
    await prefs.setInt('model.nPredict', s.nPredict);
    await prefs.setDouble('model.temperature', s.temperature);
    await prefs.setInt('model.topK', s.topK);
    await prefs.setDouble('model.topP', s.topP);
    await prefs.setString('model.accelerator', s.accelerator);
    await prefs.setInt('model.threads', s.threads);
    await prefs.setInt('model.microBatchSize', s.microBatchSize);
    await prefs.setDouble('model.repeatPenalty', s.repeatPenalty);
    if (s.seed != null) {
      await prefs.setInt('model.seed', s.seed!);
    } else {
      await prefs.remove('model.seed');
    }
  }

  Future<void> saveVisionSettings(VisionSettings s) async {
    final prefs = await _preferences;
    await prefs.setBool('vision.performanceMode', s.performanceMode);
    await prefs.setInt(
        'vision.frameSamplingIntervalMs', s.frameSamplingIntervalMs);
    await prefs.setInt('vision.maxImageWidth', s.maxImageWidth);
    await prefs.setInt('vision.maxImageHeight', s.maxImageHeight);
    await prefs.setInt('vision.imageQuality', s.imageQuality);
    await prefs.setBool('vision.autoStartCamera', s.autoStartCamera);
  }

  Future<void> saveRagSettings(RagSettings s) async {
    final prefs = await _preferences;
    await prefs.setInt('rag.defaultChunkSize', s.defaultChunkSize);
    await prefs.setInt('rag.defaultChunkOverlap', s.defaultChunkOverlap);
    await prefs.setInt('rag.defaultTopK', s.defaultTopK);
    await prefs.setBool('rag.strictGrounding', s.strictGrounding);
    await prefs.setBool('rag.citationsEnabled', s.citationsEnabled);
    await prefs.setString('rag.retrievalMode', s.retrievalMode);
  }

  Future<void> saveWebSettings(WebAccessSettings s) async {
    final prefs = await _preferences;
    await prefs.setBool('web.allowInternetAccess', s.allowInternetAccess);
    await prefs.setBool('web.askBeforeSearch', s.askBeforeSearch);
  }

  Future<void> saveLanSettings(LanSettings s) async {
    final prefs = await _preferences;
    await prefs.setBool('lan.enabled', s.enabled);
    await prefs.setInt('lan.port', s.port);
    await prefs.setString('lan.authToken', s.authToken);
  }

  Future<void> saveSpeechSettings(SpeechSettings s) async {
    final prefs = await _preferences;
    await prefs.setString('speech.language', s.language);
    await prefs.setDouble('speech.speechRate', s.speechRate);
    await prefs.setBool('speech.autoStartMic', s.autoStartMic);
  }

  Future<void> savePerformanceSettings(PerformanceSettings s) async {
    final prefs = await _preferences;
    await prefs.setInt(
        'perf.contextCompressionThreshold', s.contextCompressionThreshold);
    await prefs.setBool('perf.autoCompress', s.autoCompress);
  }

  Future<void> saveThemeSettings(ThemeSettings s) async {
    final prefs = await _preferences;
    await prefs.setBool('theme.isDarkMode', s.isDarkMode);
    await prefs.setInt('theme.primaryColorValue', s.primaryColorValue);
  }
}
