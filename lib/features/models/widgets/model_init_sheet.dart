library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_ai_chat/core/models/app_settings.dart';
import 'package:local_ai_chat/features/models/services/model_runtime_service.dart';
import 'package:local_ai_chat/features/settings/repositories/settings_repository.dart';

class ModelInitSheet extends StatefulWidget {
  final ModelRuntimeService runtimeService;
  final SettingsRepository settingsRepository;
  final VoidCallback? onApplied;

  const ModelInitSheet({
    super.key,
    required this.runtimeService,
    required this.settingsRepository,
    this.onApplied,
  });

  @override
  State<ModelInitSheet> createState() => _ModelInitSheetState();
}

class _ModelInitSheetState extends State<ModelInitSheet> {
  final _formKey = GlobalKey<FormState>();

  final _nCtxController = TextEditingController();
  final _nBatchController = TextEditingController();
  final _nPredictController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _topKController = TextEditingController();
  final _topPController = TextEditingController();

  List<String> _models = <String>[];
  String? _selectedModel;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final settings = await widget.settingsRepository.loadAll();
      final models = await widget.runtimeService.listLocalModels();

      _nCtxController.text = settings.model.nCtx.toString();
      _nBatchController.text = settings.model.nBatch.toString();
      _nPredictController.text = settings.model.nPredict.toString();
      _temperatureController.text = settings.model.temperature.toString();
      _topKController.text = settings.model.topK.toString();
      _topPController.text = settings.model.topP.toString();

      _models = models;
      final current = widget.runtimeService.currentModelPath;
      if (current != null && models.contains(current)) {
        _selectedModel = current;
      } else if (models.isNotEmpty) {
        _selectedModel = models.first;
      }
    } catch (e) {
      _errorMessage = 'Unable to load model settings: $e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _readInt(TextEditingController c, int fallback, int min, int max) {
    final parsed = int.tryParse(c.text.trim()) ?? fallback;
    return parsed.clamp(min, max);
  }

  double _readDouble(
    TextEditingController c,
    double fallback,
    double min,
    double max,
  ) {
    final parsed = double.tryParse(c.text.trim()) ?? fallback;
    return parsed.clamp(min, max);
  }

  Future<void> _apply() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final modelSettings = ModelSettings(
      nCtx: _readInt(_nCtxController, 2048, 256, 32768),
      nBatch: _readInt(_nBatchController, 512, 1, 4096),
      nPredict: _readInt(_nPredictController, 512, 1, 8192),
      temperature: _readDouble(_temperatureController, 0.7, 0.0, 2.0),
      topK: _readInt(_topKController, 40, 1, 200),
      topP: _readDouble(_topPController, 0.9, 0.1, 1.0),
    );

    try {
      await widget.settingsRepository.saveModelSettings(modelSettings);

      final selected = _selectedModel;
      if (selected != null && selected.isNotEmpty) {
        await widget.runtimeService.loadModel(
          selected,
          nCtx: modelSettings.nCtx,
          nBatch: modelSettings.nBatch,
          nPredict: modelSettings.nPredict,
        );
      }

      widget.onApplied?.call();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to initialize model: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _nCtxController.dispose();
    _nBatchController.dispose();
    _nPredictController.dispose();
    _temperatureController.dispose();
    _topKController.dispose();
    _topPController.dispose();
    super.dispose();
  }

  String _baseName(String path) => File(path).uri.pathSegments.last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: _loading
            ? const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Model Initialization',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (_models.isEmpty)
                        Text(
                          'No local GGUF models found. Download one from Models first.',
                          style: theme.textTheme.bodyMedium,
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _selectedModel,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            border: OutlineInputBorder(),
                          ),
                          isExpanded: true,
                          items: _models
                              .map(
                                (model) => DropdownMenuItem<String>(
                                  value: model,
                                  child: Text(
                                    _baseName(model),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            _selectedModel = value;
                          }),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _NumberField(
                              controller: _nCtxController,
                              label: 'n_ctx',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NumberField(
                              controller: _nBatchController,
                              label: 'n_batch',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _NumberField(
                        controller: _nPredictController,
                        label: 'n_predict',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _NumberField(
                              controller: _temperatureController,
                              label: 'temperature',
                              allowDecimal: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NumberField(
                              controller: _topPController,
                              label: 'top_p',
                              allowDecimal: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _NumberField(
                        controller: _topKController,
                        label: 'top_k',
                      ),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _apply,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_saving
                              ? 'Initializing...'
                              : 'Save & Initialize'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowDecimal;

  const _NumberField({
    required this.controller,
    required this.label,
    this.allowDecimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return 'Required';
        }
        if (allowDecimal) {
          if (double.tryParse(text) == null) return 'Invalid number';
        } else {
          if (int.tryParse(text) == null) return 'Invalid integer';
        }
        return null;
      },
    );
  }
}
