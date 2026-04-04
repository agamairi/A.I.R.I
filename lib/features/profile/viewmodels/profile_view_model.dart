library;

import 'package:flutter/foundation.dart';
import 'package:local_ai_chat/core/models/user_profile.dart';
import 'package:local_ai_chat/features/profile/repositories/user_profile_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  final UserProfileRepository _profileRepository;

  ProfileViewModel(this._profileRepository);

  UserProfile _profile = UserProfile();
  UserProfile get profile => _profile;

  bool _loading = true;
  bool get loading => _loading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _profileRepository.getProfile() ?? UserProfile();
    } catch (e) {
      _errorMessage = 'Failed to load profile: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save() async {
    try {
      await _profileRepository.saveProfile(_profile);
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save profile: $e';
      notifyListeners();
    }
  }

  void update(UserProfile profile) {
    _profile = profile;
    notifyListeners();
  }
}
