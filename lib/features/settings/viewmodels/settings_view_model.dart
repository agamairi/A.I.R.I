library;

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  final SettingsRepository _settingsRepository;

  SettingsViewModel(this._settingsRepository);

  AppSettings _settings = AppSettings();
  AppSettings get settings => _settings;

  bool _loading = true;
  bool get loading => _loading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await _settingsRepository.loadAll();
    } catch (e) {
      _errorMessage = 'Failed to load settings: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> saveVisionSettings(VisionSettings settings) async {
    _settings.vision = settings;
    await _settingsRepository.saveVisionSettings(settings);
    notifyListeners();
  }

  Future<void> saveWebSettings(WebAccessSettings settings) async {
    _settings.web = settings;
    await _settingsRepository.saveWebSettings(settings);
    notifyListeners();
  }

  Future<void> saveLanSettings(LanSettings settings) async {
    _settings.lan = settings;
    await _settingsRepository.saveLanSettings(settings);
    notifyListeners();
  }

  Future<void> saveSpeechSettings(SpeechSettings settings) async {
    _settings.speech = settings;
    await _settingsRepository.saveSpeechSettings(settings);
    notifyListeners();
  }

  Future<void> savePerformanceSettings(PerformanceSettings settings) async {
    _settings.performance = settings;
    await _settingsRepository.savePerformanceSettings(settings);
    notifyListeners();
  }

  Future<void> saveModelSettings(ModelSettings settings) async {
    _settings.model = settings;
    await _settingsRepository.saveModelSettings(settings);
    notifyListeners();
  }
}
