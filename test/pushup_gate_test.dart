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

  group('PushupGate — degenerate torso floor (M6.1)', () {
    test('hip mis-detected onto the shoulder mid → noHips, not ok', () {
      // Without a lower bound, a zero-length torso fakes perfect
      // foreshortening and a standing body passes as a plank.
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.50, 0.62, 0.9), // collapsed onto the shoulder mid
      );
      expect(gate.evaluate(sample), PushupVerdict.noHips);
    });

    test('both hips collapsed just above the shoulders → noHips', () {
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.49, 0.615, 0.8),
        hipR: GatePoint(0.51, 0.615, 0.8), // torso ratio ≈ 0.03 < 0.08
      );
      expect(gate.evaluate(sample), PushupVerdict.noHips);
    });

    test('a strongly foreshortened but real torso still passes', () {
      // Just above the 0.08 floor: extreme camera angles must not lock
      // out a genuine pushup.
      const sample = GateSample(
        shoulderL: GatePoint(0.42, 0.62, 0.9),
        shoulderR: GatePoint(0.58, 0.62, 0.9),
        wristL: GatePoint(0.40, 0.74, 0.8),
        wristR: GatePoint(0.60, 0.74, 0.8),
        hipL: GatePoint(0.50, 0.635, 0.7), // torso ratio ≈ 0.094 > 0.08
      );
      expect(gate.evaluate(sample), PushupVerdict.ok);
    });
  });

  group('VerdictHoldFilter — stream restarts (M6.1)', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('a long gap cannot let ONE glitchy frame finish an old streak',
        () {
      final f = VerdictHoldFilter();
      expect(f.filter(PushupVerdict.noHips, at(0)), PushupVerdict.ok);
      expect(f.filter(PushupVerdict.noHips, at(200)), PushupVerdict.ok);
      // The app was paused for 10 minutes; the stream resumes on a single
      // glitchy frame. Without the gap guard, the stale streak timestamp
      // would make that ONE frame interrupt a real rep instantly.
      final resume = 10 * 60 * 1000;
      expect(f.filter(PushupVerdict.noHips, at(resume)), PushupVerdict.ok);
      // Persistence is judged from the resumed stream onward.
      expect(f.filter(PushupVerdict.noHips, at(resume + 200)),
          PushupVerdict.ok);
      expect(f.filter(PushupVerdict.noHips, at(resume + 300)),
          PushupVerdict.noHips);
    });

    test('a gap at the frame-gap boundary still counts as continuous', () {
      // 1500ms exactly is a slow stream, not a restart…
      final f = VerdictHoldFilter();
      f.filter(PushupVerdict.handsUp, at(0));
      expect(
          f.filter(PushupVerdict.handsUp, at(1500)), PushupVerdict.handsUp);
      // …one millisecond more is a restart.
      final g = VerdictHoldFilter();
      g.filter(PushupVerdict.handsUp, at(0));
      expect(g.filter(PushupVerdict.handsUp, at(1501)), PushupVerdict.ok);
    });

    test('sub-second stream gaps still accumulate (no false grace)', () {
      // A laggy camera dropping to ~1fps must not buy the cheat extra
      // grace — only a true stream break resets the streak.
      final f = VerdictHoldFilter();
      f.filter(PushupVerdict.upright, at(0));
      expect(f.filter(PushupVerdict.upright, at(1000)), PushupVerdict.upright);
    });

    test('reset also forgets the call-gap history', () {
      final f = VerdictHoldFilter();
      f.filter(PushupVerdict.noBody, at(0));
      f.reset();
      expect(f.filter(PushupVerdict.noBody, at(0)), PushupVerdict.ok);
    });
  });

  group('CalibrationGate — the "2 full pushups" promise (M6.1)', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    /// Steady samples at the top of a rep for [ms] milliseconds.
    void feedTop(CalibrationGate g, int startMs, double top, int ms) {
      for (var t = 0; t < ms; t += 33) {
        g.update(top, at(startMs + t));
      }
    }

    /// One triangle-wave pushup: [top]→[bottom]→[top] as ~30fps samples.
    /// Returns true if any sample opened the gate.
    bool feedRep(CalibrationGate g, int startMs,
        {required double top, required double bottom, int frames = 10}) {
      var opened = false;
      for (var i = 1; i <= frames; i++) {
        if (g.update(top - (top - bottom) * i / frames,
            at(startMs + i * 33))) {
          opened = true;
        }
      }
      for (var i = 1; i <= frames; i++) {
        if (g.update(bottom + (top - bottom) * i / frames,
            at(startMs + (frames + i) * 33))) {
          opened = true;
        }
      }
      return opened;
    }

    test('two proper full pushups open the gate — one does not', () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 200);
      expect(g.isOpen, isFalse);
      expect(g.observedCycleSpan, isNull);

      expect(feedRep(g, 300, top: 160, bottom: 125), isFalse,
          reason: 'the HUD promises TWO pushups, not one');
      expect(g.provenReps, 1);
      expect(g.isOpen, isFalse);

      expect(feedRep(g, 1200, top: 160, bottom: 125), isTrue);
      expect(g.provenReps, 2);
      expect(g.isOpen, isTrue);
    });

    test('shallow half-movement never opens the gate', () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 200);
      // Ten lazy 12° pumps — the classic "barely bend the elbows" cheat.
      for (var r = 0; r < 10; r++) {
        feedRep(g, 500 + r * 900, top: 160, bottom: 148);
      }
      expect(g.provenReps, 0);
      expect(g.isOpen, isFalse);
    });

    test('a single noisy angle spike never opens the gate', () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 1000); // 1s steady at the top
      g.update(110, at(1000)); // one mis-tracked frame: a 50° spike down
      feedTop(g, 1033, 160, 1000);
      expect(g.provenReps, 0);
      expect(g.isOpen, isFalse,
          reason: 'a 33ms spike is detector noise, not a pushup');

      // A 3-frame spike train (≈100ms) is still not a pushup.
      final h = CalibrationGate();
      feedTop(h, 0, 160, 1000);
      h.update(140, at(1000));
      h.update(115, at(1033));
      h.update(140, at(1066));
      feedTop(h, 1099, 160, 1000);
      expect(h.provenReps, 0);
      expect(h.isOpen, isFalse);
    });

    test('jitter band at the top never opens the gate', () {
      final g = CalibrationGate();
      for (var i = 0; i < 300; i++) {
        g.update(160 + ((i % 5) - 2), at(i * 33)); // 10s of ±2° jitter
      }
      expect(g.provenReps, 0);
      expect(g.isOpen, isFalse);
    });

    test('exact span boundary: 20° counts, 19.9° never does', () {
      // decayPerSec 0 isolates the boundary semantics from drift.
      final g = CalibrationGate(decayPerSec: 0);
      feedTop(g, 0, 160, 200);
      feedRep(g, 300, top: 160, bottom: 140); // exactly 20° of motion
      expect(g.provenReps, 1);

      final h = CalibrationGate(decayPerSec: 0);
      feedTop(h, 0, 160, 200);
      feedRep(h, 300, top: 160, bottom: 140.1); // 19.9° — one notch short
      expect(h.provenReps, 0);
      expect(h.isOpen, isFalse);
    });

    test('exact duration boundary: 250ms counts, 249ms never does', () {
      final g = CalibrationGate(decayPerSec: 0);
      g.update(160, at(0));
      g.update(150, at(100)); // 10° drop → the cycle starts here
      g.update(130, at(150)); // bottom
      g.update(156, at(350)); // back in the top band exactly 250ms later
      expect(g.provenReps, 1);

      final h = CalibrationGate(decayPerSec: 0);
      h.update(160, at(0));
      h.update(150, at(100));
      h.update(130, at(150));
      h.update(156, at(349)); // one millisecond short of the bar
      expect(h.provenReps, 0);
      expect(h.isOpen, isFalse);
    });

    test('the gate does not flap: open latches until reset', () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 200);
      feedRep(g, 300, top: 160, bottom: 125);
      feedRep(g, 1200, top: 160, bottom: 125);
      expect(g.isOpen, isTrue);

      // Shallow pumps, a deep spike and standing jitter afterwards must
      // never close a proven gate (the old span-decay rule flapped back
      // to "CALIBRATING" after ~40s at the top).
      feedRep(g, 2500, top: 160, bottom: 150);
      g.update(90, at(3500));
      for (var i = 0; i < 60; i++) {
        g.update(160 + ((i % 7) - 3), at(3600 + i * 33));
      }
      expect(g.isOpen, isTrue,
          reason: 'proven evidence never un-proves itself');

      // Only an explicit reset closes it — and then both pushups are
      // required again.
      g.reset();
      expect(g.isOpen, isFalse);
      expect(g.provenReps, 0);
      feedRep(g, 6000, top: 160, bottom: 125);
      expect(g.isOpen, isFalse, reason: 'one rep is not enough again');
      feedRep(g, 7000, top: 160, bottom: 125);
      expect(g.isOpen, isTrue);
    });

    test('interrupt drops the in-flight cycle — halves cannot stitch', () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 200);
      g.update(150, at(300)); // start descending…
      g.update(120, at(500)); // …deep bottom — but the pose gate fails here
      g.interrupt(); // …so this half-segment is discarded
      g.update(160, at(700)); // back at the top
      expect(g.provenReps, 0,
          reason: 'the descent happened under a failing pose verdict');

      expect(feedRep(g, 1200, top: 160, bottom: 125), isFalse);
      expect(g.provenReps, 1,
          reason: 'a full clean cycle counts again after the interrupt');
      expect(g.isOpen, isFalse);
      feedRep(g, 2200, top: 160, bottom: 125);
      expect(g.isOpen, isTrue);
    });

    test('a camera bump (baseline shift) recovers — no permanent lockout',
        () {
      final g = CalibrationGate();
      feedTop(g, 0, 160, 1000);
      // The phone is nudged mid-set: the same body now reads 145°.
      feedTop(g, 1000, 145, 6600); // ~6.6s at the new baseline
      expect(g.provenReps, 0,
          reason: 'a baseline shift alone is not rep evidence');
      expect(g.isOpen, isFalse);

      // Real pushups from the new baseline count immediately.
      feedRep(g, 8000, top: 145, bottom: 110);
      expect(g.provenReps, 1);
      feedRep(g, 9000, top: 145, bottom: 110);
      expect(g.isOpen, isTrue);
    });

    test('repsRequired is configurable (one pushup when set to 1)', () {
      final g = CalibrationGate(repsRequired: 1);
      feedTop(g, 0, 160, 200);
      expect(feedRep(g, 300, top: 160, bottom: 125), isTrue);
      expect(g.provenReps, 1);
      expect(g.isOpen, isTrue);
    });
  });
}
