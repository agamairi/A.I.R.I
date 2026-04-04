/// User profile repository — local profile CRUD.
library;

import 'package:local_ai_chat/core/models/user_profile.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';

class UserProfileRepository {
  final StorageService _storage;

  UserProfileRepository(this._storage);

  Future<UserProfile?> getProfile() async {
    final rows = await _storage.query('user_profile', limit: 1);
    if (rows.isEmpty) {
      final profile = UserProfile();
      final map = profile.toMap()..['id'] = 1;
      await _storage.insert('user_profile', map);
      return profile;
    }
    return UserProfile.fromMap(rows.first);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final map = profile.toMap();
    map['id'] = 1; // Single-row table
    final updated = await _storage
        .update('user_profile', map, where: 'id = ?', whereArgs: [1]);
    if (updated == 0) {
      await _storage.insert('user_profile', map);
    }
  }
}
