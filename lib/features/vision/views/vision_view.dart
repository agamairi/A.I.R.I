library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_ai_chat/features/app_shell/widgets/app_shell_drawer.dart';
import 'package:local_ai_chat/features/vision/services/frame_scheduler.dart';
import 'package:local_ai_chat/features/vision/viewmodels/vision_view_model.dart';

class VisionView extends StatefulWidget {
  final int drawerIndex;

  const VisionView({super.key, this.drawerIndex = 3});

  @override
  State<VisionView> createState() => _VisionViewState();
}

class _VisionViewState extends State<VisionView> {
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<VisionViewModel>();
      _promptController.text = vm.prompt;
      vm.onEnter();
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    context.read<VisionViewModel>().onExit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          drawer: AppShellDrawer(selectedIndex: widget.drawerIndex),
          appBar: AppBar(
            title: const Text('Vision'),
            actions: [
              IconButton(
                onPressed: vm.switchCamera,
                icon: const Icon(Icons.cameraswitch_outlined),
                tooltip: 'Switch camera',
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CameraPanel(controller: vm.cameraController),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: vm.cameraReady
                            ? (vm.sampling ? vm.stopSampling : vm.startSampling)
                            : null,
                        icon:
                            Icon(vm.sampling ? Icons.pause : Icons.play_arrow),
                        label: Text(vm.sampling ? 'Stop Live' : 'Start Live'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: vm.cameraReady ? vm.captureAndAnalyze : null,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Capture Once'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: vm.mode == VisionMode.performance,
                  onChanged: vm.setPerformanceMode,
                  title: const Text('Performance mode'),
                  subtitle:
                      const Text('Lower frequency for better battery/thermals'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Vision prompt',
                    hintText: 'What should A.I.R.I focus on?',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: vm.updatePrompt,
                ),
                const SizedBox(height: 12),
                if (vm.processingFrame)
                  const LinearProgressIndicator(minHeight: 2),
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      vm.errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Response',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      vm.latestResponse.isEmpty
                          ? 'No response yet.'
                          : vm.latestResponse,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CameraPanel extends StatelessWidget {
  final CameraController? controller;

  const _CameraPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ready = controller != null && controller!.value.isInitialized;

    return AspectRatio(
      aspectRatio: ready ? controller!.value.aspectRatio : (16 / 9),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? CameraPreview(controller!)
              : const Center(
                  child: Text(
                    'Camera not initialized',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
        ),
      ),
    );
  }
}
