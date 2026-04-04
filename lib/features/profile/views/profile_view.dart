library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/models/user_profile.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/profile/viewmodels/profile_view_model.dart';

class ProfileView extends StatefulWidget {
  final int drawerIndex;

  const ProfileView({super.key, this.drawerIndex = 6});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _preferences = TextEditingController();
  final _goals = TextEditingController();
  final _style = TextEditingController();
  final _notes = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _preferences.dispose();
    _goals.dispose();
    _style.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(UserProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _name.text = profile.name;
    _bio.text = profile.bio;
    _preferences.text = profile.preferences;
    _goals.text = profile.goals;
    _style.text = profile.communicationStyle;
    _notes.text = profile.persistentNotes;
  }

  Future<void> _save(ProfileViewModel vm) async {
    final profile = vm.profile;
    profile.name = _name.text.trim();
    profile.bio = _bio.text.trim();
    profile.preferences = _preferences.text.trim();
    profile.goals = _goals.text.trim();
    profile.communicationStyle = _style.text.trim();
    profile.persistentNotes = _notes.text.trim();

    vm.update(profile);
    await vm.save();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileViewModel>(
      builder: (context, vm, _) {
        if (vm.loading) {
          return Scaffold(
            drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
            appBar: AppBar(title: const Text('Profile')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        _hydrate(vm.profile);

        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            title: const Text('Profile Context'),
            actions: [
              IconButton(
                onPressed: () => _save(vm),
                icon: const Icon(Icons.save),
                tooltip: 'Save profile',
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Field(controller: _name, label: 'Name'),
                const SizedBox(height: 10),
                _Field(controller: _bio, label: 'Bio', maxLines: 3),
                const SizedBox(height: 10),
                _Field(
                  controller: _preferences,
                  label: 'Preferences',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                _Field(controller: _goals, label: 'Goals', maxLines: 3),
                const SizedBox(height: 10),
                _Field(
                  controller: _style,
                  label: 'Communication style',
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _Field(
                  controller: _notes,
                  label: 'Persistent notes',
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: vm.profile.injectInAllChats,
                  onChanged: (value) {
                    final profile = vm.profile;
                    profile.injectInAllChats = value;
                    vm.update(profile);
                  },
                  title: const Text('Inject in all chats'),
                ),
                SwitchListTile(
                  value: vm.profile.injectInNotebookMode,
                  onChanged: (value) {
                    final profile = vm.profile;
                    profile.injectInNotebookMode = value;
                    vm.update(profile);
                  },
                  title: const Text('Inject in notebook chats'),
                ),
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      vm.errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _save(vm),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Profile'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;

  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
