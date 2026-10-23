import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m1/pushup_gate.dart';

/// Synthetic pose samples in ML Kit's normalized image space (x across
/// width, y down height, both 0..1).
///
/// The gate's job: a real FRONT-VIEW pushup passes, and the cheap fakes
/// don't — especially "stand in front of the phone and pump your hands",
/// which swings the elbow angle exactly like a rep.
void main() {
  const gate = PushupGate();

  group('PushupGate — real pushups pass', () {
    test('front-view pushup (camera on a shelf)', () {
      // Shoulders low and wide, hands planted below them, hips
      // foreshortened away behind the torso (much closer to the
      // shoulders than the shoulder span).
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.46, 0.55, 0.7),
        hipR: GatePoint(0.54, 0.55, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.ok);
    });

    test('same pushup mirrored (other side toward the camera)', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.60, 0.9),
        shoulderR: GatePoint(0.58, 0.60, 0.9),
        wristL: GatePoint(0.41, 0.71, 0.8),
        wristR: GatePoint(0.59, 0.70, 0.8),
        hipL: GatePoint(0.47, 0.54, 0.7),
        hipR: GatePoint(0.53, 0.56, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.ok);
    });

    test('passing pose with one hip below the other still passes', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.63, 0.9),
        shoulderR: GatePoint(0.60, 0.63, 0.9),
        wristL: GatePoint(0.38, 0.78, 0.8),
        wristR: GatePoint(0.62, 0.76, 0.8),
        hipL: GatePoint(0.45, 0.55, 0.7),
        hipR: GatePoint(0.55, 0.62, 0.7), // averaged hips stay foreshortened
      );
      expect(gate.evaluate(sample), PushupVerdict.ok);
    });
  });

  group('PushupGate — the hand-waving cheat is rejected', () {
    test('standing, hands pumped above the shoulders → handsUp', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.30, 0.9),
        shoulderR: GatePoint(0.60, 0.30, 0.9),
        wristL: GatePoint(0.36, 0.18, 0.9),
        wristR: GatePoint(0.64, 0.16, 0.9),
        hipL: GatePoint(0.45, 0.55, 0.8),
        hipR: GatePoint(0.55, 0.55, 0.8),
      );
      expect(gate.evaluate(sample), PushupVerdict.handsUp);
    });

    test('standing, arms hanging down → upright (torso not foreshortened)',
        () {
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.30, 0.9),
        shoulderR: GatePoint(0.60, 0.30, 0.9),
        wristL: GatePoint(0.38, 0.52, 0.9),
        wristR: GatePoint(0.62, 0.52, 0.9),
        hipL: GatePoint(0.45, 0.55, 0.8),
        hipR: GatePoint(0.55, 0.55, 0.8),
      );
      expect(gate.evaluate(sample), PushupVerdict.upright);
    });

    test('bench-press on your back (hands up, body horizontal) → handsUp',
        () {
      // Torso IS foreshortened, so only the planted-hands rule can catch
      // this one — and at the top of the lift the wrists are above the
      // shoulders, exactly what that rule rejects.
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.50, 0.9),
        shoulderR: GatePoint(0.60, 0.50, 0.9),
        wristL: GatePoint(0.42, 0.35, 0.9),
        wristR: GatePoint(0.58, 0.34, 0.9),
        hipL: GatePoint(0.46, 0.48, 0.7),
        hipR: GatePoint(0.54, 0.48, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.handsUp);
    });

    test('crouched in front of the phone → upright', () {
      // Crouch: shoulders at ~0.45, hips at ~0.62 — a full-length torso
      // in view, ratio well above the 0.75 cutoff.
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.45, 0.9),
        shoulderR: GatePoint(0.60, 0.45, 0.9),
        wristL: GatePoint(0.38, 0.60, 0.9),
        wristR: GatePoint(0.62, 0.60, 0.9),
        hipL: GatePoint(0.46, 0.62, 0.8),
        hipR: GatePoint(0.54, 0.62, 0.8),
      );
      expect(gate.evaluate(sample), PushupVerdict.upright);
    });

    test('kneeling upright → upright', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.40, 0.35, 0.9),
        shoulderR: GatePoint(0.60, 0.35, 0.9),
        wristL: GatePoint(0.39, 0.52, 0.9),
        wristR: GatePoint(0.61, 0.52, 0.9),
        hipL: GatePoint(0.46, 0.62, 0.8),
        hipR: GatePoint(0.54, 0.62, 0.8),
      );
      expect(gate.evaluate(sample), PushupVerdict.upright);
    });
  });

  group('PushupGate — incomplete frames', () {
    test('arms only, no hips in frame → noHips', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
      );
      expect(gate.evaluate(sample), PushupVerdict.noHips);
    });

    test('hips seen but too unsure → noHips', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.46, 0.55, 0.2), // below likelihood floor
        hipR: GatePoint(0.54, 0.55, 0.2),
      );
      expect(gate.evaluate(sample), PushupVerdict.noHips);
    });

    test('missing wrists → noBody', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: null,
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.46, 0.55, 0.7),
        hipR: GatePoint(0.54, 0.55, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.noBody);
    });

    test('low-likelihood shoulders → noBody', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.1),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.46, 0.55, 0.7),
        hipR: GatePoint(0.54, 0.55, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.noBody);
    });

    test('person too far away (tiny shoulder span) → tooSmall', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.49, 0.62, 0.9),
        shoulderR: GatePoint(0.51, 0.62, 0.9), // span 0.02 < 0.05
        wristL: GatePoint(0.488, 0.70, 0.8),
        wristR: GatePoint(0.512, 0.70, 0.8),
        hipL: GatePoint(0.495, 0.60, 0.7),
        hipR: GatePoint(0.505, 0.60, 0.7),
      );
      expect(gate.evaluate(sample), PushupVerdict.tooSmall);
    });
  });

  test('every failed verdict has a HUD instruction', () {
    for (final v in PushupVerdict.values) {
      expect(verdictMessage(v), isNotEmpty);
    }
  });

  test('wrist jitter tolerance: wrists just at shoulder height still ok', () {
    // Wrists exactly on the shoulder line (within the 0.02 tolerance)
    // shouldn't flap into handsUp on detector jitter.
    const sample = GateSample(
      shoulderL: GatePoint(0.42, 0.62, 0.9),
      shoulderR: GatePoint(0.58, 0.62, 0.9),
      wristL: GatePoint(0.40, 0.63, 0.8),
      wristR: GatePoint(0.60, 0.63, 0.8),
      hipL: GatePoint(0.46, 0.55, 0.7),
      hipR: GatePoint(0.54, 0.55, 0.7),
    );
    expect(gate.evaluate(sample), PushupVerdict.ok);
  });
}
