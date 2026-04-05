library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/vision/viewmodels/vision_view_model.dart';

class VisionView extends StatefulWidget {
  final int drawerIndex;

  const VisionView({super.key, this.drawerIndex = 3});

  @override
  State<VisionView> createState() => _VisionViewState();
}

class _VisionViewState extends State<VisionView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VisionViewModel>().onEnter();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    final vm = context.read<VisionViewModel>();
    vm.onExit();
    super.dispose();
  }

  void _showSettingsSheet(BuildContext context, VisionViewModel vm) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        return _VisionSettingsForm(vm: vm);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionViewModel>(
      builder: (context, vm, _) {
        if (vm.isListening || vm.isSpeaking || vm.processingFrame) {
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
        } else {
          _pulseController.stop();
          _pulseController.value = 0.0;
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.black,
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('A.I.R.I Live', style: TextStyle(color: Colors.white)),
            elevation: 0,
            leading: Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () {
                     Scaffold.of(context).openDrawer();
                  },
                );
              }
            ),
            actions: [
              Builder(
                builder: (ctx) => Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: () => _showSettingsSheet(context, vm),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (vm.cameraEnabled && vm.modelLoaded)
                _CameraPanel(controller: vm.cameraController)
              else
                _buildGlowingBackground(vm),
                
              _buildOverlay(context, vm),

              // Model Loading Overlay
              if (vm.isModelLoading)
                Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 20),
                        Text(
                          "Initializing A.I.R.I Intelligence...",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Loading weights and preparing vision projector...",
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlowingBackground(VisionViewModel vm) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.2);
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                vm.isListening ? Colors.red.shade900 : (vm.isSpeaking ? Colors.blue.shade900 : Colors.indigo.shade900),
                Colors.black,
              ],
              radius: scale,
            ),
          ),
          child: !vm.modelLoaded 
              ? const Center(child: Text("Model not loaded.\nPlease load a model in settings.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 18)))
              : null,
        );
      },
    );
  }

  Widget _buildOverlay(BuildContext context, VisionViewModel vm) {
    return SafeArea(
      child: Column(
        children: [
          if (vm.errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                   Expanded(child: Text(vm.errorMessage!, style: const TextStyle(color: Colors.white))),
                   IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: vm.clearError),
                ],
              ),
            ),

          // Top floating status text
          if (vm.modelLoaded && !vm.isModelLoading)
             Padding(
               padding: const EdgeInsets.only(top: 16.0),
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 decoration: BoxDecoration(
                   color: Colors.black45,
                   borderRadius: BorderRadius.circular(20),
                 ),
                 child: Text(
                   _getStatusText(vm),
                   style: const TextStyle(color: Colors.white, fontSize: 16),
                 ),
               ),
             ),

          const Spacer(),

          if (vm.processingFrame)
             const Padding(
               padding: EdgeInsets.symmetric(horizontal: 32),
               child: LinearProgressIndicator(),
             ),
          if (vm.spokenText.isNotEmpty)
            _buildTextBubble(vm.spokenText, isUser: true),
          if (vm.latestResponse.isNotEmpty)
            _buildTextBubble(vm.latestResponse, isUser: false),
            
          const SizedBox(height: 20),
          
          if (vm.modelLoaded && !vm.isModelLoading)
             _buildBottomControlBar(context, vm),
             
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _getStatusText(VisionViewModel vm) {
     if (vm.isSpeaking) return "A.I.R.I is speaking...";
     if (vm.processingFrame) return "A.I.R.I is thinking...";
     if (vm.isListening) return "A.I.R.I is listening...";
     return "Ready";
  }

  Widget _buildTextBubble(String text, {required bool isUser}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
         color: isUser ? Colors.blue.withOpacity(0.8) : Colors.grey.shade900.withOpacity(0.8),
         borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        textAlign: isUser ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  Widget _buildBottomControlBar(BuildContext context, VisionViewModel vm) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 60),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.7),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Camera Toggle
          IconButton(
             icon: Icon(vm.cameraEnabled ? Icons.videocam : Icons.videocam_off, 
                        color: vm.cameraEnabled ? Colors.white : Colors.white54),
             onPressed: vm.toggleCameraEnabled,
          ),
          
          // Camera Flip Icon
          if (vm.cameraEnabled && vm.cameraReady)
            IconButton(
               icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
               onPressed: vm.switchCamera,
            )
          else 
            const SizedBox(width: 48), 
          
          // Disconnect / End Call
          Container(
             decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
             child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: vm.endCall,
             ),
          )
        ],
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  final CameraController? controller;

  const _CameraPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ready = controller != null && controller!.value.isInitialized;

    if (!ready) {
       return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller!.value.previewSize?.height ?? 1,
          height: controller!.value.previewSize?.width ?? 1,
          child: CameraPreview(controller!),
        ),
      ),
    );
  }
}

class _VisionSettingsForm extends StatefulWidget {
  final VisionViewModel vm;
  const _VisionSettingsForm({required this.vm});

  @override
  State<_VisionSettingsForm> createState() => _VisionSettingsFormState();
}

class _VisionSettingsFormState extends State<_VisionSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nCtxController;
  late final TextEditingController _nPredictController;
  late final TextEditingController _tempController;
  late final TextEditingController _topKController;
  late final TextEditingController _topPController;

  @override
  void initState() {
    super.initState();
    _nCtxController = TextEditingController(text: widget.vm.nCtx.toString());
    _nPredictController = TextEditingController(text: widget.vm.nPredict.toString());
    _tempController = TextEditingController(text: widget.vm.temperature.toString());
    _topKController = TextEditingController(text: widget.vm.topK.toString());
    _topPController = TextEditingController(text: widget.vm.topP.toString());
  }

  @override
  void dispose() {
    _nCtxController.dispose();
    _nPredictController.dispose();
    _tempController.dispose();
    _topKController.dispose();
    _topPController.dispose();
    super.dispose();
  }

  int _closestFps(int ms) {
    if (ms <= 16) return 60;
    if (ms <= 33) return 30;
    if (ms <= 41) return 24;
    if (ms <= 83) return 12;
    if (ms <= 250) return 4;
    return 1;
  }

  int _closestRes(int val) {
    if (val >= 1080) return 1080;
    if (val >= 720) return 720;
    if (val >= 480) return 480;
    if (val >= 360) return 360;
    return 240;
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    
    await widget.vm.saveModelSettings(
       nCtx: int.tryParse(_nCtxController.text),
       nPredict: int.tryParse(_nPredictController.text),
       temperature: double.tryParse(_tempController.text),
       topK: int.tryParse(_topKController.text),
       topP: double.tryParse(_topPController.text),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = widget.vm;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: FutureBuilder<List<String>>(
          future: vm.listLocalModels(),
          builder: (context, snapshot) {
            final models = snapshot.data ?? [];
            return SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vision & Model Settings',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: vm.currentModelPath,
                      decoration: const InputDecoration(
                        labelText: 'Active Model',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      hint: const Text('Select a model to initialize'),
                      items: models.map((path) => DropdownMenuItem<String>(
                        value: path,
                        child: Text(p.basename(path), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (path) {
                        if (path != null) {
                           vm.loadModelWithSettings(path);
                           Navigator.pop(context);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '⚠ High performance settings increase compute load and thermal output.',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _closestRes(vm.maxWidth),
                            decoration: const InputDecoration(
                              labelText: 'Resolution',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 240, child: Text("240p")),
                              DropdownMenuItem(value: 360, child: Text("360p")),
                              DropdownMenuItem(value: 480, child: Text("480p")),
                              DropdownMenuItem(value: 720, child: Text("720p HD")),
                              DropdownMenuItem(value: 1080, child: Text("1080p FHD")),
                            ],
                            onChanged: (res) {
                              if (res != null) vm.saveVisionResolution(res, res);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _closestFps(vm.frameIntervalMs),
                            decoration: const InputDecoration(
                              labelText: 'Frame Rate',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("1 fps")),
                              DropdownMenuItem(value: 4, child: Text("4 fps")),
                              DropdownMenuItem(value: 12, child: Text("12 fps")),
                              DropdownMenuItem(value: 24, child: Text("24 fps")),
                              DropdownMenuItem(value: 30, child: Text("30 fps")),
                            ],
                            onChanged: (fps) {
                              if (fps != null) vm.saveVisionFramerate(1000 ~/ fps);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text('Generation Parameters', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _SmallNumberField(controller: _tempController, label: 'Temp', allowDecimal: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _SmallNumberField(controller: _topPController, label: 'Top-P', allowDecimal: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _SmallNumberField(controller: _topKController, label: 'Top-K')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _SmallNumberField(controller: _nCtxController, label: 'Context Size')),
                        const SizedBox(width: 12),
                        Expanded(child: _SmallNumberField(controller: _nPredictController, label: 'Max Tokens')),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _apply,
                        icon: const Icon(Icons.check),
                        label: const Text('Apply Settings'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SmallNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowDecimal;

  const _SmallNumberField({
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 14),
      validator: (v) => (v == null || v.isEmpty) ? '!' : null,
    );
  }
}
