library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/core/app_router.dart';
import 'package:local_ai_chat/core/app_services.dart';
import 'package:local_ai_chat/features/app_shell/viewmodels/theme_view_model.dart';
import 'package:local_ai_chat/features/app_shell/views/app_shell_view.dart';
import 'package:local_ai_chat/features/chat/viewmodels/chat_view_model.dart';
import 'package:local_ai_chat/features/chat/viewmodels/conversations_view_model.dart';
import 'package:local_ai_chat/features/models/viewmodels/model_manager_view_model.dart';
import 'package:local_ai_chat/features/notebooks/viewmodels/notebooks_view_model.dart';
import 'package:local_ai_chat/features/profile/viewmodels/profile_view_model.dart';
import 'package:local_ai_chat/features/settings/viewmodels/settings_view_model.dart';
import 'package:local_ai_chat/features/speech/viewmodels/talk_view_model.dart';
import 'package:local_ai_chat/features/vision/viewmodels/vision_view_model.dart';

class AiriApp extends StatelessWidget {
  final AppServices services;

  const AiriApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider.value(value: services.settingsRepository),
        Provider.value(value: services.modelRuntimeService),
        Provider.value(value: services.modelCatalogService),
        Provider.value(value: services.modelDownloadService),
        Provider.value(value: services.conversationRepository),
        Provider.value(value: services.userProfileRepository),
        Provider.value(value: services.systemPromptRepository),
        Provider.value(value: services.contextAssembler),
        Provider.value(value: services.contextCompressionService),
        Provider.value(value: services.speechService),
        Provider.value(value: services.visionSessionService),
        Provider.value(value: services.frameScheduler),
        Provider.value(value: services.notebookRepository),
        Provider.value(value: services.ragPipelineService),
        Provider.value(value: services.webAccessService),
        Provider.value(value: services.lanServerService),
        ChangeNotifierProvider<ThemeViewModel>(
          create: (_) => ThemeViewModel(services.settingsRepository)..load(),
        ),
        ChangeNotifierProvider<ChatViewModel>(
          create: (_) => ChatViewModel(
            services.conversationRepository,
            services.modelRuntimeService,
            services.contextAssembler,
            services.contextCompressionService,
            services.settingsRepository,
            services.ragPipelineService,
            services.notebookRepository,
          ),
        ),
        ChangeNotifierProvider<ConversationsViewModel>(
          create: (_) =>
              ConversationsViewModel(services.conversationRepository),
        ),
        ChangeNotifierProvider<ModelManagerViewModel>(
          create: (_) => ModelManagerViewModel(
            services.modelRuntimeService,
            services.modelCatalogService,
            services.modelDownloadService,
            services.settingsRepository,
          )..initialize(),
        ),
        ChangeNotifierProvider<TalkViewModel>(
          create: (_) => TalkViewModel(
            services.speechService,
            services.modelRuntimeService,
            services.settingsRepository,
          )..initialize(),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(services.settingsRepository)..load(),
        ),
        ChangeNotifierProvider<ProfileViewModel>(
          create: (_) =>
              ProfileViewModel(services.userProfileRepository)..load(),
        ),
        ChangeNotifierProvider<NotebooksViewModel>(
          create: (_) => NotebooksViewModel(
              services.notebookRepository, services.ragPipelineService)
            ..load(),
        ),
        ChangeNotifierProvider<VisionViewModel>(
          create: (_) => VisionViewModel(
            services.visionSessionService,
            services.frameScheduler,
            services.modelRuntimeService,
            services.settingsRepository,
          ),
        ),
      ],
      child: Consumer<ThemeViewModel>(
        builder: (context, themeVm, _) {
          final themeSettings = themeVm.theme;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'A.I.R.I',
            theme: ThemeData(
              useMaterial3: true,
              brightness:
                  themeSettings.isDarkMode ? Brightness.dark : Brightness.light,
              colorSchemeSeed: themeSettings.primaryColor,
            ),
            home: const AppShellView(),
            routes: {
              AppRoutes.chat: (_) => const AppShellView(initialIndex: 0),
              AppRoutes.talk: (_) => const AppShellView(initialIndex: 1),
              AppRoutes.conversations: (_) =>
                  const AppShellView(initialIndex: 2),
              AppRoutes.vision: (_) => const AppShellView(initialIndex: 3),
              AppRoutes.notebooks: (_) => const AppShellView(initialIndex: 4),
              AppRoutes.models: (_) => const AppShellView(initialIndex: 5),
              AppRoutes.profile: (_) => const AppShellView(initialIndex: 6),
              AppRoutes.settings: (_) => const AppShellView(initialIndex: 7),
            },
          );
        },
      ),
    );
  }
}
