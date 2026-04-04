/// Local user profile for personal context injection.
library;

class UserProfile {
  String name;
  String preferences;
  String goals;
  String bio;
  String communicationStyle;
  String persistentNotes;

  /// Where to inject profile context
  bool injectInAllChats;
  bool injectInSelectedChats;
  bool injectInNotebookMode;

  UserProfile({
    this.name = '',
    this.preferences = '',
    this.goals = '',
    this.bio = '',
    this.communicationStyle = '',
    this.persistentNotes = '',
    this.injectInAllChats = false,
    this.injectInSelectedChats = false,
    this.injectInNotebookMode = false,
  });

  bool get hasContent =>
      name.isNotEmpty ||
      preferences.isNotEmpty ||
      goals.isNotEmpty ||
      bio.isNotEmpty ||
      communicationStyle.isNotEmpty ||
      persistentNotes.isNotEmpty;

  /// Formats profile as context string for injection into prompts.
  String toContextString() {
    final parts = <String>[];
    if (name.isNotEmpty) parts.add('Name: $name');
    if (bio.isNotEmpty) parts.add('About: $bio');
    if (preferences.isNotEmpty) parts.add('Preferences: $preferences');
    if (goals.isNotEmpty) parts.add('Goals: $goals');
    if (communicationStyle.isNotEmpty) {
      parts.add('Communication style: $communicationStyle');
    }
    if (persistentNotes.isNotEmpty) parts.add('Notes: $persistentNotes');
    return parts.join('\n');
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'preferences': preferences,
        'goals': goals,
        'bio': bio,
        'communicationStyle': communicationStyle,
        'persistentNotes': persistentNotes,
        'injectInAllChats': injectInAllChats ? 1 : 0,
        'injectInSelectedChats': injectInSelectedChats ? 1 : 0,
        'injectInNotebookMode': injectInNotebookMode ? 1 : 0,
      };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        name: map['name'] as String? ?? '',
        preferences: map['preferences'] as String? ?? '',
        goals: map['goals'] as String? ?? '',
        bio: map['bio'] as String? ?? '',
        communicationStyle: map['communicationStyle'] as String? ?? '',
        persistentNotes: map['persistentNotes'] as String? ?? '',
        injectInAllChats: (map['injectInAllChats'] as int?) == 1,
        injectInSelectedChats: (map['injectInSelectedChats'] as int?) == 1,
        injectInNotebookMode: (map['injectInNotebookMode'] as int?) == 1,
      );
}
