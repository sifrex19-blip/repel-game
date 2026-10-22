import 'dart:math';

/// Counts pushups from a stream of elbow angles with **adaptive thresholds**.
///
/// Why adaptive: with the phone lying on the floor the camera sees the body
/// foreshortened, so "arms extended" may look like 130° instead of 175°, and
/// fixed thresholds (150°/100°) never fire. Instead the counter watches the
/// angle range you actually produce and places thresholds inside it:
///
///   * it tracks the observed min/max elbow angle, both with slow decay so
///     stale extremes from a different exercise don't stick forever,
///   * once the observed span reaches [minCalibration] degrees it is
///     "calibrated" and arms,
///   * down = min + 25% of span, up = min + 75% of span (the 25/75 split
///     leaves a wide dead zone that absorbs jitter),
///   * UP (angle >= up)  --bend-->  DOWN (angle <= down)
///   * DOWN              --extend--> UP  => +1 rep
///
/// Reps are rate-limited by [minRepInterval] to reject noise bursts.
class PushupCounter {
  PushupCounter({
    this.minRepInterval = const Duration(milliseconds: 600),
    this.smoothing = 0.4,
    this.minCalibration = 35,
    this.rangeDecayPerSec = 0.5,
  });

  /// Minimum observed angle span (degrees) before the counter will arm.
  final double minCalibration;

  /// How fast the observed extremes relax toward the current angle
  /// (degrees/second) — keeps calibration fresh across breaks/exercise changes.
  final double rangeDecayPerSec;

  /// Minimum time between two counted reps.
  final Duration minRepInterval;

  /// Weight of each new raw sample in the smoothing filter (0..1].
  final double smoothing;

  int reps = 0;
  PushupPhase _phase = PushupPhase.unknown;
  double? _smoothedAngle;
  DateTime? _lastRepAt;
  DateTime? _lastSampleAt;

  /// Observed extremes of the elbow angle (with decay).
  double? _observedMax;
  double? _observedMin;

  PushupPhase get phase => _phase;

  /// The smoothed angle (useful for HUD display).
  double? get smoothedAngle => _smoothedAngle;

  DateTime? get lastRepAt => _lastRepAt;

  /// Current observed span in degrees (null until first sample).
  double? get observedSpan {
    if (_observedMax == null || _observedMin == null) return null;
    return _observedMax! - _observedMin!;
  }

  bool get isCalibrated => (observedSpan ?? 0) >= minCalibration;

  /// Current thresholds (null until calibrated).
  double? get downAngle {
    if (!isCalibrated) return null;
    return _observedMin! + observedSpan! * 0.25;
  }

  double? get upAngle {
    if (!isCalibrated) return null;
    return _observedMin! + observedSpan! * 0.75;
  }

  /// Feed one elbow-angle sample (degrees). Returns the new total rep count
  /// exactly when a rep was just completed, otherwise null.
  int? update(double rawAngle, DateTime time) {
    _smoothedAngle = _smoothedAngle == null
        ? rawAngle
        : _smoothedAngle! * (1 - smoothing) + rawAngle * smoothing;
    final angle = _smoothedAngle!;

    // Decay old extremes, then absorb the current sample.
    final dt = _lastSampleAt == null
        ? 0.0
        : max(0, time.difference(_lastSampleAt!).inMilliseconds) / 1000.0;
    _lastSampleAt = time;
    final drift = rangeDecayPerSec * dt;
    if (_observedMax != null) {
      _observedMax = max(angle, _observedMax! - drift);
      _observedMin = min(angle, _observedMin! + drift);
    } else {
      _observedMax = angle;
      _observedMin = angle;
    }

    if (!isCalibrated) {
      _phase = PushupPhase.unknown;
      return null;
    }
    final down = downAngle!;
    final up = upAngle!;

    switch (_phase) {
      case PushupPhase.unknown:
        // Arm once calibration proves a real span and we sit at an extreme.
        if (angle >= up) {
          _phase = PushupPhase.up;
        } else if (angle <= down) {
          _phase = PushupPhase.down;
        }
        return null;
      case PushupPhase.up:
        if (angle <= down) {
          _phase = PushupPhase.down;
        }
        return null;
      case PushupPhase.down:
        if (angle >= up) {
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
    _lastSampleAt = null;
    _observedMax = null;
    _observedMin = null;
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
