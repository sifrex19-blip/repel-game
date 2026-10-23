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
    this.maxTorsoRatio = 0.75,
    this.wristTolerance = 0.02,
  });

  /// Minimum detector confidence for a landmark to count as visible.
  final double minLikelihood;

  /// Minimum shoulder width in normalized units (below: person too far).
  final double minShoulderSpan;

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
    if (torso >= span * maxTorsoRatio) return PushupVerdict.upright;
    return PushupVerdict.ok;
  }
}
