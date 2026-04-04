library;

import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/core/services/storage_service.dart';
import 'package:local_ai_chat/features/chat/repositories/conversation_repository.dart';
import 'package:local_ai_chat/features/context_assembly/services/context_assembler.dart';
import 'package:local_ai_chat/features/context_assembly/services/context_compression_service.dart';
import 'package:local_ai_chat/features/models/services/model_catalog_service.dart';
import 'package:local_ai_chat/features/models/services/model_download_service.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/network_access/services/lan_server_service.dart';
import 'package:local_ai_chat/features/notebooks/repositories/notebook_repository.dart';
import 'package:local_ai_chat/features/notebooks/services/chunk_store.dart';
import 'package:local_ai_chat/features/notebooks/services/document_parser_service.dart';
import 'package:local_ai_chat/features/notebooks/services/embedding_provider.dart';
import 'package:local_ai_chat/features/notebooks/services/rag_pipeline_service.dart';
import 'package:local_ai_chat/features/notebooks/services/retrieval_service.dart';
import 'package:local_ai_chat/features/profile/repositories/user_profile_repository.dart';
import 'package:local_ai_chat/features/prompts/repositories/system_prompt_repository.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';
import 'package:local_ai_chat/features/speech/services/speech_service.dart';
import 'package:local_ai_chat/features/vision/services/frame_scheduler.dart';
import 'package:local_ai_chat/features/vision/services/vision_session_service.dart';
import 'package:local_ai_chat/features/web_access/services/web_access_service.dart';

class AppServices {
  AppServices._();

  late final StorageService storageService;

  late final SettingsRepository settingsRepository;

  late final ModelRuntimeService modelRuntimeService;
  late final ModelCatalogService modelCatalogService;
  late final ModelDownloadService modelDownloadService;

  late final ConversationRepository conversationRepository;

  late final UserProfileRepository userProfileRepository;
  late final SystemPromptRepository systemPromptRepository;

  late final ContextAssembler contextAssembler;
  late final ContextCompressionService contextCompressionService;

  late final SpeechService speechService;

  late final VisionSessionService visionSessionService;
  late final FrameScheduler frameScheduler;

  late final DocumentParserService documentParserService;
  late final EmbeddingProvider embeddingProvider;
  late final ChunkStore chunkStore;
  late final RetrievalService retrievalService;
  late final RagPipelineService ragPipelineService;
  late final NotebookRepository notebookRepository;

  late final WebAccessService webAccessService;
  late final LanServerService lanServerService;

  static Future<AppServices> create() async {
    final services = AppServices._();

    services.storageService = StorageService();

    services.settingsRepository = SettingsRepository();
    final persistedSettings = await services.settingsRepository.loadAll();

    services.modelRuntimeService = ModelRuntimeService();
    services.modelCatalogService = ModelCatalogService();
    services.modelDownloadService =
        ModelDownloadService(services.storageService);

    services.conversationRepository =
        ConversationRepository(services.storageService);

    services.userProfileRepository =
        UserProfileRepository(services.storageService);
    services.systemPromptRepository =
        SystemPromptRepository(services.storageService);

    services.contextAssembler = ContextAssembler(
      services.systemPromptRepository,
      services.userProfileRepository,
    );
    services.contextCompressionService =
        ContextCompressionService(services.modelRuntimeService);

    services.speechService = SpeechService();

    services.visionSessionService = VisionSessionService();
    services.frameScheduler = FrameScheduler(services.visionSessionService);

    services.documentParserService = DocumentParserService();
    services.embeddingProvider = LexicalEmbeddingProvider();
    services.chunkStore = ChunkStore(services.storageService);
    services.retrievalService = RetrievalService(
      services.chunkStore,
      services.embeddingProvider,
      services.storageService,
    );
    services.ragPipelineService = RagPipelineService(services.retrievalService);
    services.notebookRepository = NotebookRepository(
      services.storageService,
      services.documentParserService,
      services.chunkStore,
      services.embeddingProvider,
    );

    services.webAccessService = WebAccessService(
      policy: WebToolPolicy(
        enabled: persistedSettings.web.allowInternetAccess,
        askBeforeSearch: persistedSettings.web.askBeforeSearch,
      ),
    );
    services.lanServerService = LanServerService(services.modelRuntimeService);

    await services.modelDownloadService.initialize();
    await _restoreLanServerIfEnabled(services, persistedSettings.lan);

    return services;
  }

  static Future<void> _restoreLanServerIfEnabled(
    AppServices services,
    LanSettings settings,
  ) async {
    if (!settings.enabled) return;

    var token = settings.authToken.trim();
    if (token.isEmpty) {
      token = services.lanServerService.regenerateToken();
      settings.authToken = token;
      await services.settingsRepository.saveLanSettings(settings);
    }

    try {
      await services.lanServerService.start(
        port: settings.port,
        token: token,
        exposeToLan: true,
      );
    } catch (_) {
      // Keep startup resilient even if port is unavailable.
    }
  }
}
