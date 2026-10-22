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

  group('PushupCounter', () {
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

    test('counts a clean rep: up -> down -> up', () {
      final c = counter();
      feed(c, 170, t0); // arms extended, arms the counter
      expect(c.phase, PushupPhase.up);

      feed(c, 90, t0.add(const Duration(seconds: 1))); // go down
      expect(c.phase, PushupPhase.down);
      expect(c.reps, 0); // no rep at the bottom

      final rep = feed(c, 170, t0.add(const Duration(seconds: 2))); // push up
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
      // Shake between 105 and 145 — inside the hysteresis band.
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
      // Arm detection with sustained "up".
      for (var i = 0; i < 30; i++) {
        c.update(170 + (i.isEven ? 2 : -2), at);
        at = at.add(const Duration(milliseconds: 33));
      }
      expect(c.phase, PushupPhase.up);
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

    test('reset clears everything', () {
      final c = counter();
      feed(c, 170, t0);
      feed(c, 90, t0.add(const Duration(seconds: 1)));
      feed(c, 170, t0.add(const Duration(seconds: 2)));
      c.reset();
      expect(c.reps, 0);
      expect(c.phase, PushupPhase.unknown);
      expect(c.smoothedAngle, isNull);
    });
  });
}
