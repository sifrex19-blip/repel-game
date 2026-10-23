import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Maps ML Kit landmark coordinates (normalized to the *rotated* camera
/// image) onto screen coordinates of a contained, centered preview — the
/// same fit CameraPreview uses, optionally translated into a zone ([origin])
/// so the skeleton lands exactly on the bottom-band preview (M5).
class PoseMapper {
  PoseMapper({
    required this.rotatedImageSize,
    required this.screenSize,
    required this.mirror,
    this.origin = Offset.zero,
  });

  /// Size of the camera image after applying the rotation ML Kit was given
  /// (width/height swapped for 90°/270°).
  final Size rotatedImageSize;

  /// The area the preview occupies (camera zone size, not the full screen).
  final Size screenSize;

  /// Whether the preview displays a mirrored image (front camera).
  final bool mirror;

  /// Top-left of the preview zone in screen coordinates (0,0 = full screen
  /// fits the pre-M5 layout).
  final Offset origin;

  late final double _scale = [
    (screenSize.width / rotatedImageSize.width),
    (screenSize.height / rotatedImageSize.height),
  ].reduce((a, b) => a < b ? a : b); // contain: CameraPreview fits the image
                                      // inside the zone, centered

  late final double _dx = (screenSize.width - rotatedImageSize.width * _scale) / 2;
  late final double _dy = (screenSize.height - rotatedImageSize.height * _scale) / 2;

  Offset map(double x, double y) {
    final px = _dx + x * _scale;
    final py = _dy + y * _scale;
    return Offset(
      origin.dx + (mirror ? screenSize.width - px : px),
      origin.dy + py,
    );
  }
}

/// Draws the detected body as a stick figure so the player can see exactly
/// what the AI sees (and position the phone correctly).
class PoseOverlayPainter extends CustomPainter {
  PoseOverlayPainter({required this.pose, required this.mapper});

  final Pose? pose;
  final PoseMapper mapper;

  static const _bones = <(PoseLandmarkType, PoseLandmarkType)>[
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null) return;

    final bonePaint = Paint()
      ..color = Colors.deepOrangeAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final jointPaint = Paint()..color = Colors.white;

    // Bones.
    for (final (from, to) in _bones) {
      final a = p.landmarks[from];
      final b = p.landmarks[to];
      if (a == null || b == null) continue;
      if (a.likelihood < 0.5 || b.likelihood < 0.5) continue;
      canvas.drawLine(mapper.map(a.x, a.y), mapper.map(b.x, b.y), bonePaint);
    }

    // Joints.
    for (final landmark in p.landmarks.values) {
      if (landmark.likelihood < 0.5) continue;
      canvas.drawCircle(mapper.map(landmark.x, landmark.y), 6, jointPaint);
    }
  }

  @override
  bool shouldRepaint(PoseOverlayPainter oldDelegate) =>
      oldDelegate.pose != pose || oldDelegate.mapper != mapper;
}
