library;

import 'package:flutter/material.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';

class ThemeViewModel extends ChangeNotifier {
  final SettingsRepository _settingsRepository;

  ThemeViewModel(this._settingsRepository);

  ThemeSettings _theme = ThemeSettings();
  ThemeSettings get theme => _theme;

  bool _loading = true;
  bool get loading => _loading;

  Future<void> load() async {
    try {
      final settings = await _settingsRepository.loadAll();
      _theme = settings.theme;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setDarkMode(bool enabled) async {
    _theme.isDarkMode = enabled;
    notifyListeners();
    await _settingsRepository.saveThemeSettings(_theme);
  }

  Future<void> setPrimaryColor(Color color) async {
    _theme.primaryColorValue = color.toARGB32();
    notifyListeners();
    await _settingsRepository.saveThemeSettings(_theme);
  }
}
