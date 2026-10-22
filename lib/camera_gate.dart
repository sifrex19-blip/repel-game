import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'm1/pose_screen.dart';

enum CameraPhase { loading, permissionDenied, noCamera, error, ready }

/// Requests the camera permission and either shows the pose-tracking screen
/// or a friendly screen explaining what to do.
class CameraGate extends StatefulWidget {
  const CameraGate({super.key});

  @override
  State<CameraGate> createState() => _CameraGateState();
}

class _CameraGateState extends State<CameraGate> {
  CameraPhase _phase = CameraPhase.loading;
  CameraController? _controller;
  CameraDescription? _description;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _phase = CameraPhase.loading);

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _phase = CameraPhase.permissionDenied);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _phase = CameraPhase.noCamera);
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium, // enough for pose tracking, light on CPU
        enableAudio: false,
        // Android delivers YUV frames, iOS delivers BGRA — ML Kit needs both
        // paths handled in the converter.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _description = camera;
        _phase = CameraPhase.ready;
      });
    } on CameraException catch (e) {
      setState(() {
        _message = e.description ?? e.code;
        _phase = CameraPhase.error;
      });
    } catch (e) {
      setState(() {
        _message = '$e';
        _phase = CameraPhase.error;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case CameraPhase.loading:
        return const _StatusScreen(
          icon: Icons.videocam_outlined,
          title: 'Waking up the camera…',
        );
      case CameraPhase.permissionDenied:
        return _StatusScreen(
          icon: Icons.no_photography_outlined,
          title: 'Camera access needed',
          message:
              'Repel watches you with the camera to count your pushups. '
              'Nothing ever leaves your phone.',
          actionLabel: 'Open settings',
          onAction: openAppSettings,
          onRetry: _boot,
        );
      case CameraPhase.noCamera:
        return _StatusScreen(
          icon: Icons.videocam_off_outlined,
          title: 'No camera found',
          message: 'This device doesn\'t seem to have a camera.',
          actionLabel: 'Try again',
          onAction: _boot,
        );
      case CameraPhase.error:
        return _StatusScreen(
          icon: Icons.error_outline,
          title: 'Camera failed to start',
          message: _message,
          actionLabel: 'Try again',
          onAction: _boot,
        );
      case CameraPhase.ready:
        return PoseScreen(controller: _controller!, camera: _description!);
    }
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: Colors.deepOrange.shade300),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
                const SizedBox(height: 24),
                if (actionLabel != null)
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.settings),
                    label: Text(actionLabel!),
                  ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Refresh'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
