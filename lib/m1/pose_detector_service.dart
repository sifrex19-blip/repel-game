import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'camera_image_converter.dart';

/// Thin wrapper around ML Kit's pose detector, tuned for a live camera feed.
///
/// Frames arriving while a previous inference is still running are dropped —
/// the detector always works on the newest frame, so the overlay never lags
/// more than one inference behind reality.
class PoseDetectorService {
  PoseDetectorService()
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream, // optimized for video feeds
            model: PoseDetectionModel.base, // lightest model, real-time
          ),
        );

  final PoseDetector _detector;
  bool _busy = false;

  int processedFrames = 0;
  Duration lastInference = Duration.zero;

  /// Process one camera frame. [onPose] is called with the most complete pose
  /// found (or null when nobody is visible) plus the inference time.
  Future<void> processCameraImage(
    CameraImage image,
    InputImageRotation rotation, {
    required void Function(Pose? pose, Duration inference) onPose,
  }) async {
    if (_busy) return; // drop frame, previous inference still running
    _busy = true;
    try {
      final input = cameraImageToInputImage(image, rotation);
      if (input == null) return;

      final stopwatch = Stopwatch()..start();
      final poses = await _detector.processImage(input);
      stopwatch.stop();

      processedFrames++;
      lastInference = stopwatch.elapsed;

      Pose? best;
      for (final pose in poses) {
        if (best == null || pose.landmarks.length > best.landmarks.length) {
          best = pose;
        }
      }
      onPose(best, stopwatch.elapsed);
    } on Exception catch (e) {
      // A bad frame shouldn't kill the stream — log and continue.
      debugPrint('Pose detection error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> close() => _detector.close();
}
