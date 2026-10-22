import 'dart:math';

/// Counts pushups from a stream of elbow angles.
///
/// State machine with hysteresis:
///
///   UP (angle >= [upAngle])  --bend-->  DOWN (angle <= [downAngle])
///   DOWN                     --extend--> UP  =>  +1 rep
///
/// The dead zone between [downAngle] and [upAngle] absorbs sensor jitter,
/// and reps are rate-limited by [minRepInterval] to reject noise bursts.
class PushupCounter {
  PushupCounter({
    this.downAngle = 100,
    this.upAngle = 150,
    this.minRepInterval = const Duration(milliseconds: 500),
    this.smoothing = 0.4,
  }) : assert(downAngle < upAngle);

  /// Elbow angle considered "bottom" of the pushup.
  final double downAngle;

  /// Elbow angle considered "arms extended" (top).
  final double upAngle;

  /// Minimum time between two counted reps.
  final Duration minRepInterval;

  /// Weight of each new raw sample in the smoothing filter (0..1].
  /// 1 = no smoothing, 0.4 = fairly smooth. Purely cosmetic jitter removal.
  final double smoothing;

  int reps = 0;
  PushupPhase _phase = PushupPhase.unknown;
  double? _smoothedAngle;
  DateTime? _lastRepAt;

  PushupPhase get phase => _phase;

  /// The smoothed angle (useful for HUD display).
  double? get smoothedAngle => _smoothedAngle;

  DateTime? get lastRepAt => _lastRepAt;

  /// Feed one elbow-angle sample (degrees). Returns the new total rep count
  /// exactly when a rep was just completed, otherwise null.
  int? update(double rawAngle, DateTime time) {
    _smoothedAngle = _smoothedAngle == null
        ? rawAngle
        : _smoothedAngle! * (1 - smoothing) + rawAngle * smoothing;
    final angle = _smoothedAngle!;

    switch (_phase) {
      case PushupPhase.unknown:
        // Arm the counter once we see a believable top position.
        if (angle >= upAngle) {
          _phase = PushupPhase.up;
        }
        return null;
      case PushupPhase.up:
        if (angle <= downAngle) {
          _phase = PushupPhase.down;
        }
        return null;
      case PushupPhase.down:
        if (angle >= upAngle) {
          _phase = PushupPhase.up;
          if (_lastRepAt == null ||
              time.difference(_lastRepAt!) >= minRepInterval) {
            _lastRepAt = time;
            reps++;
            return reps;
          }
        }
        return null;
    }
  }

  void reset() {
    reps = 0;
    _phase = PushupPhase.unknown;
    _smoothedAngle = null;
    _lastRepAt = null;
  }
}

enum PushupPhase { unknown, up, down }

/// Angle [b] in degrees, formed by the points a–b–c.
double computeAngle({
  required double ax,
  required double ay,
  required double bx,
  required double by,
  required double cx,
  required double cy,
}) {
  final abx = ax - bx;
  final aby = ay - by;
  final cbx = cx - bx;
  final cby = cy - by;
  final mag = sqrt(abx * abx + aby * aby) * sqrt(cbx * cbx + cby * cby);
  if (mag == 0) return 180;
  final cos = (abx * cbx + aby * cby) / mag;
  return acos(cos.clamp(-1.0, 1.0)) * 180 / pi;
}
