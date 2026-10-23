import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m1/pushup_counter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  PushupCounter counter({double smoothing = 1}) =>
      PushupCounter(smoothing: smoothing);

  /// Feeds [angle] repeatedly, returning any rep completed while feeding.
  int? feed(PushupCounter c, double angle, DateTime at, {int frames = 10}) {
    int? result;
    for (var i = 0; i < frames; i++) {
      result = c.update(angle, at.add(Duration(milliseconds: 33 * i))) ?? result;
    }
    return result;
  }

  group('computeAngle', () {
    test('straight line is 180°', () {
      expect(
        computeAngle(ax: 0, ay: 0, bx: 1, by: 0, cx: 2, cy: 0),
        closeTo(180, 0.001),
      );
    });

    test('right angle is 90°', () {
      expect(
        computeAngle(ax: 0, ay: 0, bx: 0, by: 1, cx: 1, cy: 1),
        closeTo(90, 0.001),
      );
    });
  });

  group('PushupCounter calibration', () {
    test('does not arm until the observed span is wide enough', () {
      final c = counter();
      feed(c, 160, t0);
      feed(c, 150, t0.add(const Duration(seconds: 1))); // span only 10°
      expect(c.isCalibrated, isFalse);
      expect(c.phase, PushupPhase.unknown);
      expect(c.reps, 0);
    });

    test('learns thresholds from the observed range (compressed camera)', () {
      // Simulates a foreshortened floor view: top looks like 132°, bottom 88°.
      final c = counter();
      feed(c, 88, t0);
      feed(c, 132, t0.add(const Duration(seconds: 1)));
      expect(c.isCalibrated, isTrue);
      // down = 88 + 0.25*44 = 99, up = 88 + 0.75*44 = 121
      expect(c.downAngle, closeTo(99, 0.5));
      expect(c.upAngle, closeTo(121, 0.5));
    });

    test('arms even with a foreshortened 25° span (M5: easier calibration)', () {
      // Floor view: top only reaches 165°, bottom 140°. The old 35°
      // requirement never armed this range, so no rep could ever count.
      final c = counter();
      feed(c, 165, t0);
      feed(c, 140, t0.add(const Duration(seconds: 1)));
      expect(c.isCalibrated, isTrue);
      // down = 140 + 0.25*25 ≈ 146, up = 140 + 0.75*25 ≈ 158
      feed(c, 165, t0.add(const Duration(seconds: 2)));
      expect(c.phase, PushupPhase.up);
      expect(c.reps, 1); // arming happened at the bottom → this ascent counts
      feed(c, 140, t0.add(const Duration(seconds: 3)));
      expect(c.phase, PushupPhase.down);
      expect(c.reps, 1); // no rep at the bottom
      feed(c, 165, t0.add(const Duration(seconds: 4)));
      expect(c.reps, 2);
    });

    test('stays unknown at the bottom, arms at the top, no free rep', () {
      final c = counter();
      feed(c, 90, t0); // seen at the bottom first: stays unarmed
      expect(c.phase, PushupPhase.unknown);
      feed(c, 170, t0.add(const Duration(seconds: 1))); // arms the counter
      expect(c.phase, PushupPhase.up);
      expect(c.reps, 0); // rising from unknown did NOT count
      // Now a full cycle counts.
      feed(c, 90, t0.add(const Duration(seconds: 2)));
      feed(c, 170, t0.add(const Duration(seconds: 3)));
      expect(c.reps, 1);
    });
  });

  group('PushupCounter counting', () {
    test('counts a clean rep: up -> down -> up', () {
      final c = counter();
      feed(c, 90, t0); // calibrate low first
      feed(c, 170, t0.add(const Duration(seconds: 1))); // arms
      expect(c.phase, PushupPhase.up);

      feed(c, 90, t0.add(const Duration(seconds: 2))); // go down
      expect(c.phase, PushupPhase.down);
      expect(c.reps, 0); // no rep at the bottom

      final rep = feed(c, 170, t0.add(const Duration(seconds: 3))); // push up
      expect(rep, 1);
      expect(c.reps, 1);
      expect(c.phase, PushupPhase.up);
    });

    test('half pushup (down but never up) does not count', () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(seconds: 1)));
      expect(c.reps, 0);
    });

    test('jitter in the dead zone does not count extra reps', () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(seconds: 1)));
      // Shake between 105 and 145 — must stay inside the hysteresis band.
      feed(c, 145, t0.add(const Duration(seconds: 2)));
      feed(c, 105, t0.add(const Duration(seconds: 3)));
      feed(c, 145, t0.add(const Duration(seconds: 4)));
      feed(c, 105, t0.add(const Duration(seconds: 5)));
      feed(c, 170, t0.add(const Duration(seconds: 6)));
      expect(c.reps, 1); // exactly one rep from the full cycle
    });

    test('respects the minimum rep interval', () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(milliseconds: 100)));
      feed(c, 170, t0.add(const Duration(milliseconds: 200))); // rep 1
      feed(c, 90, t0.add(const Duration(milliseconds: 300)));
      feed(c, 170, t0.add(const Duration(milliseconds: 400))); // too fast!
      expect(c.reps, 1);
      // A later, honest rep still counts.
      feed(c, 90, t0.add(const Duration(seconds: 2)));
      feed(c, 170, t0.add(const Duration(seconds: 3)));
      expect(c.reps, 2);
    });

    test('counts 20 honest pushups as 20', () {
      final c = counter();
      feed(c, 170, t0);
      var at = t0.add(const Duration(seconds: 1));
      for (var i = 0; i < 20; i++) {
        feed(c, 90, at);
        at = at.add(const Duration(seconds: 2));
        feed(c, 170, at);
        at = at.add(const Duration(seconds: 2));
      }
      expect(c.reps, 20);
    });

    test('smoothing still counts when noise is added', () {
      final c = counter(smoothing: 0.4);
      var at = t0;
      // Observe the top with noise (establishes the high extreme).
      for (var i = 0; i < 30; i++) {
        c.update(170 + (i.isEven ? 2 : -2), at);
        at = at.add(const Duration(milliseconds: 33));
      }
      expect(c.reps, 0);
      for (var rep = 0; rep < 5; rep++) {
        for (var i = 0; i < 20; i++) {
          c.update(90 + (i.isEven ? 3 : -3), at);
          at = at.add(const Duration(milliseconds: 33));
        }
        at = at.add(const Duration(seconds: 1)); // honest pause
        for (var i = 0; i < 20; i++) {
          c.update(170 + (i.isEven ? 3 : -3), at);
          at = at.add(const Duration(milliseconds: 33));
        }
        at = at.add(const Duration(seconds: 1));
      }
      expect(c.reps, 5);
    });

    test('range relaxation un-calibrates after a long break', () {
      final c = counter();
      feed(c, 90, t0);
      feed(c, 170, t0.add(const Duration(seconds: 1)));
      expect(c.isCalibrated, isTrue);
      // 5 minutes of only top-position samples: the low extreme decays away.
      feed(c, 170, t0.add(const Duration(minutes: 5)));
      expect(c.isCalibrated, isFalse);
      expect(c.phase, PushupPhase.unknown);
    });

    test('interrupt drops the half-cycle but keeps calibration and reps',
        () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(seconds: 1)));
      feed(c, 170, t0.add(const Duration(seconds: 2))); // rep 1
      expect(c.reps, 1);
      expect(c.phase, PushupPhase.up);

      // A faked pose frame mid-set: the half-cycle must not survive, but
      // calibration and the rep total must.
      feed(c, 90, t0.add(const Duration(seconds: 3))); // down again
      c.interrupt();
      expect(c.phase, PushupPhase.unknown);
      expect(c.reps, 1);
      expect(c.isCalibrated, isTrue);

      // Re-arm at the top and finish another honest rep.
      feed(c, 170, t0.add(const Duration(seconds: 4)));
      expect(c.phase, PushupPhase.up);
      feed(c, 90, t0.add(const Duration(seconds: 5)));
      feed(c, 170, t0.add(const Duration(seconds: 6))); // rep 2
      expect(c.reps, 2);
    });

    test('reset clears everything', () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(seconds: 1)));
      feed(c, 170, t0.add(const Duration(seconds: 2)));
      c.reset();
      expect(c.reps, 0);
      expect(c.phase, PushupPhase.unknown);
      expect(c.smoothedAngle, isNull);
      expect(c.isCalibrated, isFalse);
    });
  });

  group('combineArmAngles (M6 arm fusion)', () {
    test('no readings → null; one reading passes through', () {
      expect(combineArmAngles([]), isNull);
      expect(combineArmAngles([const ArmReading(123, 0.9)]), 123);
    });

    test('agreeing arms → confidence-weighted mean', () {
      final a = combineArmAngles([
        const ArmReading(100, 0.9),
        const ArmReading(110, 0.5),
      ]);
      // (100·0.9 + 110·0.5) / 1.4 ≈ 103.57 — the shaky arm contributes,
      // but the confident one pulls harder than a plain average would.
      expect(a, closeTo(103.57, 0.01));
    });

    test('wildly disagreeing arms trust the more confident one', () {
      // A mis-tracked wrist flips one arm's angle 60° away (the classic
      // mid-rep joint swap). Averaging that with the good arm would drag
      // the smoothed angle across a threshold — the outlier must lose.
      final a = combineArmAngles([
        const ArmReading(150, 0.9),
        const ArmReading(90, 0.45),
      ]);
      expect(a, 150);
      // …and mirrored: the confident arm still wins from either slot.
      final b = combineArmAngles([
        const ArmReading(90, 0.4),
        const ArmReading(155, 0.8),
      ]);
      expect(b, 155);
    });

    test('a gap exactly at maxGap still averages', () {
      final a = combineArmAngles([
        const ArmReading(100, 0.9),
        const ArmReading(135, 0.5),
      ], maxGap: 35);
      // 35 is not > 35 → no outlier, weighted mean applies.
      expect(a, closeTo((100 * 0.9 + 135 * 0.5) / 1.4, 0.01));
    });
  });
}
