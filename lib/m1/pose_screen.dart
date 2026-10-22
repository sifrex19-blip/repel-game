import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_detector_service.dart';
import 'pose_overlay.dart';
import 'pushup_counter.dart';

/// M1 screen: live camera preview + pose skeleton + pushup rep counter.
class PoseScreen extends StatefulWidget {
  const PoseScreen({
    super.key,
    required this.controller,
    required this.camera,
  });

  final CameraController controller;
  final CameraDescription camera;

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> with WidgetsBindingObserver {
  static const _orientationChannel =
      MethodChannel('repel/device_orientation');

  final _service = PoseDetectorService();
  final _counter = PushupCounter();

  /// Display rotation in degrees (0/90/180/270) as reported by Android's
  /// Surface.ROTATION — portrait is the natural orientation of phones.
  int _deviceDegrees = 0;

  Pose? _pose;
  DateTime? _lastPoseAt;
  double? _elbowAngle;
  Size? _imageSize; // raw (unrotated) frame size of the latest image
  double _inferenceFps = 0;
  int _fpsCounter = 0;
  DateTime _fpsWindow = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readOrientation();
    _startStream();
  }

  /// Asks Android which way the screen is currently rotated.
  /// (iOS: falls back to portrait — revisit when building for iPhone.)
  Future<void> _readOrientation() async {
    try {
      final degrees =
          await _orientationChannel.invokeMethod<int>('getRotationDegrees');
      if (degrees != null && mounted) {
        setState(() => _deviceDegrees = degrees);
      }
    } on PlatformException {
      // Keep the last known value.
    } on MissingPluginException {
      // Non-Android platform without the channel — keep the default.
    }
  }

  Future<void> _startStream() async {
    try {
      if (!widget.controller.value.isStreamingImages) {
        await widget.controller.startImageStream(_onFrame);
      }
    } on CameraException catch (e) {
      debugPrint('Image stream start error: $e');
    }
  }

  Future<void> _stopStream() async {
    try {
      if (widget.controller.value.isStreamingImages) {
        await widget.controller.stopImageStream();
      }
    } on CameraException catch (e) {
      debugPrint('Image stream stop error: $e');
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = _rotationForCamera();
    await _service.processCameraImage(
      image,
      InputImageRotationValue.fromRawValue(rotation) ??
          InputImageRotation.rotation0deg,
      onPose: _onPose,
    );

    // Rolling inference-FPS meter (updated roughly once per second).
    _fpsCounter++;
    final now = DateTime.now();
    final elapsed = now.difference(_fpsWindow).inMilliseconds;
    if (elapsed >= 1000) {
      _inferenceFps = _fpsCounter * 1000 / elapsed;
      _fpsCounter = 0;
      _fpsWindow = now;
      if (mounted) setState(() {});
    }
  }

  void _onPose(Pose? pose, Duration inference) {
    if (!mounted) return;
    setState(() {
      _pose = pose;
      if (pose != null) {
        _lastPoseAt = DateTime.now();
        final angle = _elbowAngleOf(pose);
        _elbowAngle = angle;
        if (angle != null) {
          _counter.update(angle, _lastPoseAt!);
        }
      }
    });
  }

  /// Average elbow angle across whichever arms are confidently visible.
  double? _elbowAngleOf(Pose pose) {
    final angles = <double>[];
    for (final (s, e, w) in [
      (
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist
      ),
      (
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist
      ),
    ]) {
      final shoulder = pose.landmarks[s];
      final elbow = pose.landmarks[e];
      final wrist = pose.landmarks[w];
      if (shoulder == null || elbow == null || wrist == null) continue;
      if (shoulder.likelihood < 0.5 ||
          elbow.likelihood < 0.5 ||
          wrist.likelihood < 0.5) {
        continue;
      }
      angles.add(computeAngle(
        ax: shoulder.x,
        ay: shoulder.y,
        bx: elbow.x,
        by: elbow.y,
        cx: wrist.x,
        cy: wrist.y,
      ));
    }
    if (angles.isEmpty) return null;
    return angles.reduce((a, b) => a + b) / angles.length;
  }

  /// Compensates the fixed sensor orientation for how the device is held, so
  /// ML Kit sees the image upright. Front and back cameras compensate
  /// differently (mirroring) — canonical Android camera2 formulas.
  int _rotationForCamera() {
    final sensor = widget.camera.sensorOrientation;
    final device = _deviceDegrees;
    if (widget.camera.lensDirection == CameraLensDirection.front) {
      return (sensor + device) % 360;
    }
    return (sensor - device + 360) % 360;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _readOrientation();
      _startStream();
    }
  }

  @override
  void didChangeMetrics() {
    // Screen rotation changes metrics — refresh the device rotation.
    _readOrientation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final rotation = _rotationForCamera();

    // Landmarks are pixels of the image *after* ML Kit applied the rotation
    // we reported to it. Until the first frame, assume a portrait sensor.
    final raw = _imageSize ?? Size(screen.height, screen.width);
    final rotated = rotation % 180 == 90 ? Size(raw.height, raw.width) : raw;

    final mapper = PoseMapper(
      rotatedImageSize: rotated,
      screenSize: screen,
      mirror: widget.camera.lensDirection == CameraLensDirection.front,
    );

    final poseAge = _lastPoseAt == null
        ? null
        : DateTime.now().difference(_lastPoseAt!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(widget.controller),
          CustomPaint(
            painter: PoseOverlayPainter(pose: _pose, mapper: mapper),
          ),

          // Rep counter (top center) — the future attack strength.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_counter.reps}',
                    style: const TextStyle(
                      fontSize: 72,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                    ),
                  ),
                  const Text(
                    'PUSHUPS',
                    style: TextStyle(
                      letterSpacing: 4,
                      fontSize: 13,
                      color: Colors.deepOrangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // M1 status chip (top left).
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.deepOrange.shade400),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: poseAge != null && poseAge.inMilliseconds < 1500
                            ? Colors.greenAccent.shade400
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'M1 · ${_inferenceFps.toStringAsFixed(0)} fps '
                      '· ${_service.lastInference.inMilliseconds} ms',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Angle / phase debug strip (bottom left) — used for on-device
          // threshold tuning during M1 testing.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'angle ${_elbowAngle?.toStringAsFixed(0) ?? "--"}°'
                  ' · ${_counter.phase.name.toUpperCase()}'
                  '\nrot $rotation° · sensor ${widget.camera.sensorOrientation}°'
                  ' · frame ${_imageSize?.width.toInt() ?? "?"}'
                  '×${_imageSize?.height.toInt() ?? "?"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),

          // "Get into position" hint.
          if (poseAge == null || poseAge.inMilliseconds > 1500)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Step back — let the camera see your whole body',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ),
            ),

          // Reset button (bottom right).
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filled(
                  onPressed: () => setState(() => _counter.reset()),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset counter',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
