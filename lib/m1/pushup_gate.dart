import 'dart:math';

/// Anti-cheat plausibility gate ("the AI that can't be fooled by waving
/// your hands"): decides whether the visible pose could actually be a
/// pushup BEFORE its elbow angle is allowed into [PushupCounter].
///
/// The angle counter only sees arms — standing in front of the phone and
/// pumping your hands up and down swings the elbow angle exactly like a
/// real rep. This gate checks the whole body instead, in ML Kit's
/// normalized image space (x across width, y down height, both 0..1, so
/// every threshold is scale-free and camera-distance independent):
///
///   1. both shoulders AND both wrists confidently visible,
///   2. at least one hip visible (a full body in frame — not just arms),
///   3. body big enough for the geometry to mean anything,
///   4. hands planted: every wrist below its shoulder line in the image —
///      a hand that rises above the shoulder is waving, not pushing,
///   5. body horizontal: the shoulder→hip distance (the torso, squashed by
///      pointing at the camera) must be well under the shoulder span.
///      Standing / kneeling / crouching bodies measure ~0.8–1.3× their
///      shoulder span; a real front-view pushup measures ~0.15–0.55× —
///      and unlike raw hip height, this ratio holds at any camera height
///      (shelf, table, or propped on the floor).
///
/// Front-view pushups are the designed orientation: the player faces the
/// upright phone, both arms visible symmetrically, hands planted on the
/// floor below the shoulders.
///
/// Pure geometry, no ML Kit types — fully unit-tested.
/// pose_screen.dart builds the [GateSample] from a Pose.
enum PushupVerdict {
  ok,
  noBody, // shoulders or wrists not confidently visible
  noHips, // no torso in frame — the arm-only / hand-waving case
  tooSmall, // person too far away for reliable geometry
  handsUp, // wrists above the shoulder line — hands not planted
  upright, // torso full length in view — body isn't horizontal
}

/// Short HUD instruction for a failed verdict (image of the form meter).
String verdictMessage(PushupVerdict v) => switch (v) {
      PushupVerdict.ok => 'READY',
      PushupVerdict.noBody => 'BODY NOT VISIBLE',
      PushupVerdict.noHips => 'SHOW YOUR HIPS',
      PushupVerdict.tooSmall => 'MOVE CLOSER',
      PushupVerdict.handsUp => 'PLANT YOUR HANDS',
      PushupVerdict.upright => 'GET IN A PLANK',
    };

/// One normalized landmark with its detector confidence.
class GatePoint {
  const GatePoint(this.x, this.y, this.likelihood);

  final double x;
  final double y;
  final double likelihood;
}

/// The body landmarks the gate needs (null = not detected at all).
class GateSample {
  const GateSample({
    required this.shoulderL,
    required this.shoulderR,
    required this.wristL,
    required this.wristR,
    this.hipL,
    this.hipR,
  });

  final GatePoint? shoulderL;
  final GatePoint? shoulderR;
  final GatePoint? wristL;
  final GatePoint? wristR;
  final GatePoint? hipL;
  final GatePoint? hipR;
}

class PushupGate {
  const PushupGate({
    this.minLikelihood = 0.3,
    this.minShoulderSpan = 0.05,
    this.minTorsoRatio = 0.08,
    this.maxTorsoRatio = 0.75,
    this.wristTolerance = 0.02,
  });

  /// Minimum detector confidence for a landmark to count as visible.
  final double minLikelihood;

  /// Minimum shoulder width in normalized units (below: person too far).
  final double minShoulderSpan;

  /// Torso (shoulder-mid → hip-mid) / shoulder span must stay ABOVE this.
  /// Real front-view pushups measure ~0.15–0.55 (see [maxTorsoRatio]); a
  /// value near zero means a hip landmark was mis-detected onto the
  /// shoulder — with no lower bound that degenerate hip would fake a
  /// perfectly foreshortened torso and a standing body would pass as a
  /// plank. Rejected as [PushupVerdict.noHips] ("we don't trust your
  /// hips") rather than upright, so the HUD tells the player what to fix.
  final double minTorsoRatio;

  /// Torso (shoulder-mid → hip-mid) / shoulder span must stay BELOW this.
  /// Standing bodies measure ~0.8–1.3; a front-view pushup ~0.15–0.55.
  final double maxTorsoRatio;

  /// How far a wrist may sit above its shoulder line before it counts as
  /// raised (image y grows downward; jitter margin).
  final double wristTolerance;

  PushupVerdict evaluate(GateSample s) {
    final shL = s.shoulderL;
    final shR = s.shoulderR;
    final wrL = s.wristL;
    final wrR = s.wristR;
    if (shL == null || shR == null || wrL == null || wrR == null) {
      return PushupVerdict.noBody;
    }
    if (shL.likelihood < minLikelihood ||
        shR.likelihood < minLikelihood ||
        wrL.likelihood < minLikelihood ||
        wrR.likelihood < minLikelihood) {
      return PushupVerdict.noBody;
    }

    // Body big enough for the geometry to mean anything.
    final span = (shR.x - shL.x).abs();
    if (span < minShoulderSpan) return PushupVerdict.tooSmall;

    // Full body in frame: at least one confidently visible hip.
    final hips = [s.hipL, s.hipR]
        .where((h) => h != null && h.likelihood >= minLikelihood)
        .cast<GatePoint>()
        .toList();
    if (hips.isEmpty) return PushupVerdict.noHips;

    // Hands planted on the floor: wrists below the shoulder line. Waving
    // crosses the line — that's the cheat this check exists for.
    if (wrL.y < shL.y - wristTolerance || wrR.y < shR.y - wristTolerance) {
      return PushupVerdict.handsUp;
    }

    // Torso foreshortened: the body points at the camera (horizontal), so
    // shoulder→hip measures much less than the shoulder span. Standing,
    // kneeling and crouching bodies keep a full-length torso in view.
    final shMidX = (shL.x + shR.x) / 2;
    final shMidY = (shL.y + shR.y) / 2;
    final hipMidX = hips.map((h) => h.x).reduce((a, b) => a + b) / hips.length;
    final hipMidY = hips.map((h) => h.y).reduce((a, b) => a + b) / hips.length;
    final dx = hipMidX - shMidX;
    final dy = hipMidY - shMidY;
    final torso = sqrt(dx * dx + dy * dy);
    // Degenerate torso: a hip landmark mis-detected onto the shoulder
    // (or both hips collapsed together) measures ~zero distance and would
    // otherwise fake perfect foreshortening for a standing body. Real
    // pushups never compress below ~0.15× span, so 0.08 is a safe floor.
    if (torso < span * minTorsoRatio) return PushupVerdict.noHips;
    if (torso >= span * maxTorsoRatio) return PushupVerdict.upright;
    return PushupVerdict.ok;
  }
}

/// Temporal consensus for [PushupGate] verdicts (M6 hardening).
///
/// The gate judges ONE frame, and camera detectors flicker: a wrist
/// blinks below confidence for 33ms, a hip leaves frame for a moment at
/// the bottom of a deep rep, one shoulder y jitters at the top. If the
/// counter obeyed every single failing frame it would drop real reps at
/// exactly the worst moments.
///
/// This filter turns the per-frame stream into a decision: a failing
/// verdict only counts once it has persisted CONTINUOUSLY for [hold]
/// (default 300ms ≈ 9 frames at 30fps). Any `ok` frame in between clears
/// the streak — flicker is detector noise, not a pose. A cheat has no
/// ok frames: standing and waving stays `handsUp` for as long as you
/// stand there, so it still interrupts within the window.
///
/// Pure time logic, no ML Kit types — fully unit-tested.
class VerdictHoldFilter {
  VerdictHoldFilter({
    this.hold = const Duration(milliseconds: 300),
    this.maxFrameGap = const Duration(milliseconds: 1500),
  });

  /// How long a failing verdict must persist before it takes effect.
  final Duration hold;

  /// A gap between two filter calls longer than this is treated as a
  /// stream restart (app pause/resume, camera restart) rather than a
  /// continuation: without it, the streak timestamp from before the gap
  /// makes the FIRST failing frame after the gap instantly "persistent"
  /// and a single glitchy frame would interrupt a real rep the moment
  /// the stream comes back. 1500ms matches the pose screen's own
  /// "nobody in frame" hint threshold.
  final Duration maxFrameGap;

  DateTime? _since;
  DateTime? _lastCallAt;
  PushupVerdict _last = PushupVerdict.ok;

  /// Filters [raw] at time [at]. Pass [hold] to override the default
  /// window (Settings → REP SENSITIVITY binds to it).
  PushupVerdict filter(PushupVerdict raw, DateTime at, {Duration? hold}) {
    final window = hold ?? this.hold;
    // A long silence means the stream was interrupted (app paused, camera
    // restarted) — evidence from before the gap no longer describes the
    // present, so the streak restarts from this frame.
    final streamRestarted = _lastCallAt != null &&
        at.difference(_lastCallAt!) > maxFrameGap;
    _lastCallAt = at;
    if (raw == PushupVerdict.ok) {
      _since = null;
      _last = PushupVerdict.ok;
      return PushupVerdict.ok;
    }
    // A streak tracks ONE kind of failure; a different failure restarting
    // means the pose changed, so the clock starts over for it.
    if (_since == null || raw != _last || streamRestarted) {
      _since = at;
      _last = raw;
      return PushupVerdict.ok;
    }
    if (at.difference(_since!) >= window) return raw;
    return PushupVerdict.ok; // grace: the bad pose must persist
  }

  void reset() {
    _since = null;
    _lastCallAt = null;
    _last = PushupVerdict.ok;
  }
}

/// Enforces the HUD calibration promise as a real acceptance rule (M6.1
/// hardening). pose_screen passes [repsRequired]: 1 so the proof bar is
/// exactly its shipped hint "ONE FULL PUSHUP TO CALIBRATE" — one real
/// cycle is proven on the very rep the counter counts, so hint, count and
/// wave-start all flip together; the class default of 2 stands for
/// callers that promise two.
///
/// The counter's own arming rule (observed angle span ≥ 20°, with slow
/// decay) fires on ONE dip of the elbow angle — or even on a single noisy
/// spike, because the extremes absorb every smoothed sample. The hint
/// text tells the player two full pushups are required; this gate makes
/// that literally true before the counter is allowed to count:
///
///   * a CYCLE = leave the top of the rep by more than [_downDrop]
///     degrees, then come back within [_riseBand] degrees of the top,
///   * a cycle only COUNTS if its own range of motion reaches
///     [minCycleSpan] degrees AND it took at least [minCycleMs]
///     milliseconds — a 1–3 frame detector spike is physically not a
///     pushup, and a shallow 10° pump never reaches the bar,
///   * [repsRequired] (default 2) counted cycles open the gate,
///   * open LATCHES until [reset]: proven evidence never un-proves
///     itself, so the HUD can't flap between CALIBRATING and READY, and
///     a long shop break can't lock a calibrated player out again.
///
/// Wiring (pose_screen, owned by the main session — this class is pure
/// additive API, nothing breaks until it is wired):
///
///   * feed [update] with the fused elbow angle at exactly the moments
///     the counter is fed — i.e. only on frames where the pose gate's
///     filtered verdict was ok,
///   * call [interrupt] wherever `_counter.interrupt()` is called, so a
///     faked or garbled pose segment can never stitch half a cycle,
///   * call [reset] wherever `_counter.reset()` is called (MORE →
///     RESET COUNTER, and any level/stream restart),
///   * gate the HUD hint and `_counter.update` on [isOpen] instead of
///     `_counter.isCalibrated` so the promise and the rule match.
///
/// Like everything in this file: pure time/angle logic, no ML Kit types
/// — fully unit-tested.
class CalibrationGate {
  CalibrationGate({
    this.repsRequired = 2,
    this.minCycleSpan = 20,
    this.minCycleMs = 250,
    this.decayPerSec = 2.0,
  });

  /// How many counted cycles ([minCycleSpan] + [minCycleMs] each) must be
  /// proven before the gate opens. 2 = the promise in the HUD hint.
  final int repsRequired;

  /// Minimum range of motion (degrees) for ONE cycle to count as proof.
  /// 20 matches the counter's field-proven arming bar (M5 floor-camera
  /// evidence: genuine full reps move the foreshortened angle ~25°), so
  /// this gate never locks out a player the counter itself would arm.
  final double minCycleSpan;

  /// Minimum duration of one cycle (leaving the top until returning to
  /// it) for it to count. A real pushup takes well over half a second;
  /// 250ms sits far above detector spike trains (1–3 frames ≈ 33–100ms)
  /// while still accepting explosive reps.
  final int minCycleMs;

  /// How fast the in-flight top/bottom references relax toward the
  /// current angle (degrees/second) — after a camera bump or a moved
  /// phone the absolute angles shift, and without decay the stale top
  /// would block every descent until the player restarts the app.
  final double decayPerSec;

  /// Drop from the running top that starts a cycle (bottom hunting).
  static const double _downDrop = 8;

  /// Rise back within this band of the running top that ends it.
  static const double _riseBand = 5;

  _CyclePhase _phase = _CyclePhase.up;
  double? _cycleMax; // running top of the in-flight cycle
  double? _cycleMin; // bottom of the in-flight cycle (down phase only)
  DateTime? _leftTopAt; // when the descent crossed the down trigger
  DateTime? _lastSampleAt;
  int _proven = 0;
  bool _open = false;

  /// True once [repsRequired] real cycles have been proven (latched).
  bool get isOpen => _open;

  /// How many full cycles were proven so far (never decreases).
  int get provenReps => _proven;

  /// Live range of motion of the in-flight cycle (null until a descent
  /// has started) — for HUD/debug display.
  double? get observedCycleSpan =>
      _cycleMin == null ? null : _cycleMax! - _cycleMin!;

  /// Feeds one elbow-angle sample (degrees). Only samples from frames
  /// the pose gate approved may reach this method (see class doc).
  /// Returns true exactly when this sample opened the gate.
  bool update(double angle, DateTime time) {
    if (_open) return false; // latched — nothing left to prove
    final dt = _lastSampleAt == null
        ? 0.0
        : max(0, time.difference(_lastSampleAt!).inMilliseconds) / 1000.0;
    _lastSampleAt = time;
    final drift = decayPerSec * dt;

    switch (_phase) {
      case _CyclePhase.up:
        _cycleMax = _cycleMax == null ? angle : max(angle, _cycleMax! - drift);
        if (_cycleMax! - angle >= _downDrop) {
          _phase = _CyclePhase.down;
          _cycleMin = angle;
          _leftTopAt = time;
        }
        return false;
      case _CyclePhase.down:
        _cycleMax = max(angle, _cycleMax! - drift);
        _cycleMin = min(angle, _cycleMin! + drift);
        if (_cycleMax! - angle > _riseBand) return false; // still descending
        // Back at the top: did this cycle look like a real pushup?
        final span = _cycleMax! - _cycleMin!;
        final tookMs = time.difference(_leftTopAt!).inMilliseconds;
        _phase = _CyclePhase.up;
        _cycleMax = angle;
        _cycleMin = null;
        _leftTopAt = null;
        if (span < minCycleSpan || tookMs < minCycleMs) return false;
        _proven++;
        if (_proven >= repsRequired) {
          _open = true;
          return true;
        }
        return false;
    }
  }

  /// The pose gate decided the body isn't plausibly in a pushup: drop the
  /// in-flight cycle so a faked or garbled segment can never stitch half
  /// a cycle that a real rep would then finish. Proven cycles and the
  /// open latch survive — they were proven under approved poses.
  void interrupt() {
    _phase = _CyclePhase.up;
    _cycleMax = null;
    _cycleMin = null;
    _leftTopAt = null;
  }

  /// Full restart: closes the gate and forgets all proof (MORE → RESET
  /// COUNTER, level restart).
  void reset() {
    interrupt();
    _lastSampleAt = null;
    _proven = 0;
    _open = false;
  }
}

enum _CyclePhase { up, down }
