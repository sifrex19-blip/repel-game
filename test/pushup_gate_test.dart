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

  group('VerdictHoldFilter — glitch tolerance (M6)', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('a single-frame glitch does not interrupt', () {
      final f = VerdictHoldFilter();
      expect(f.filter(PushupVerdict.ok, at(0)), PushupVerdict.ok);
      // One 33ms bad frame (hip blinks out, wrist flickers)…
      expect(f.filter(PushupVerdict.noHips, at(33)), PushupVerdict.ok);
      // …then good frames again: the streak died with the glitch.
      expect(f.filter(PushupVerdict.ok, at(66)), PushupVerdict.ok);
      expect(f.filter(PushupVerdict.noHips, at(99)), PushupVerdict.ok);
    });

    test('a sustained bad pose interrupts after the hold window', () {
      final f = VerdictHoldFilter();
      expect(f.filter(PushupVerdict.handsUp, at(0)), PushupVerdict.ok);
      expect(f.filter(PushupVerdict.handsUp, at(100)), PushupVerdict.ok);
      // 300ms of continuous handsUp = a standing wave, not detector noise.
      expect(f.filter(PushupVerdict.handsUp, at(300)), PushupVerdict.handsUp);
      expect(f.filter(PushupVerdict.handsUp, at(400)), PushupVerdict.handsUp);
    });

    test('any ok frame clears the streak (flicker never accumulates)', () {
      // Two seconds of bad/ok alternation every 100ms — the flickery
      // pattern real cameras produce — must never interrupt.
      final f = VerdictHoldFilter();
      var t = 0;
      for (var i = 0; i < 10; i++) {
        expect(f.filter(PushupVerdict.upright, at(t)), PushupVerdict.ok);
        t += 100;
        expect(f.filter(PushupVerdict.ok, at(t)), PushupVerdict.ok);
        t += 100;
      }
    });

    test('a changed failure kind restarts the window', () {
      final f = VerdictHoldFilter();
      f.filter(PushupVerdict.noHips, at(0));
      expect(f.filter(PushupVerdict.noHips, at(250)), PushupVerdict.ok);
      // The failure changes shape — the pose changed, start the clock over.
      expect(f.filter(PushupVerdict.handsUp, at(260)), PushupVerdict.ok);
      expect(f.filter(PushupVerdict.handsUp, at(559)), PushupVerdict.ok);
      expect(f.filter(PushupVerdict.handsUp, at(560)), PushupVerdict.handsUp);
    });

    test('a custom hold window is respected (REP SENSITIVITY)', () {
      final strict = VerdictHoldFilter(
          hold: const Duration(milliseconds: 150));
      strict.filter(PushupVerdict.tooSmall, at(0));
      expect(
          strict.filter(PushupVerdict.tooSmall, at(150)), PushupVerdict.tooSmall);

      final forgiving = VerdictHoldFilter(
          hold: const Duration(milliseconds: 600));
      forgiving.filter(PushupVerdict.tooSmall, at(0));
      expect(forgiving.filter(PushupVerdict.tooSmall, at(300)),
          PushupVerdict.ok);
      expect(forgiving.filter(PushupVerdict.tooSmall, at(600)),
          PushupVerdict.tooSmall);
    });

    test('reset clears a pending streak', () {
      final f = VerdictHoldFilter();
      f.filter(PushupVerdict.handsUp, at(0));
      f.filter(PushupVerdict.handsUp, at(290));
      f.reset();
      expect(f.filter(PushupVerdict.handsUp, at(295)), PushupVerdict.ok);
    });
  });
}
