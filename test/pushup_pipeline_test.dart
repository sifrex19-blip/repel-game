import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m1/pushup_counter.dart';
import 'package:repel_game/m1/pushup_gate.dart';

/// End-to-end M6 proof: the gate → filter → counter pipeline fed a
/// scripted workout at ~30fps, with detector glitches injected mid-rep
/// (exactly the frames real cameras produce — a hip blinking out for
/// 33ms while you're on the way up).
///
/// Without the temporal filter, one glitchy frame during the dead-zone
/// ascent resets the counter's half-cycle and the whole rep is silently
/// lost — every time, on every rep. With the filter, the flicker costs
/// nothing and the same script counts every clean rep.
void main() {
  DateTime at(int ms) =>
      DateTime(2026, 1, 1, 12).add(Duration(milliseconds: ms));

  /// One pushup as 37 frames (~1.2s at 30fps): a triangle wave from 170°
  /// to 85° and back. With [glitchOnAscent], frame 26 (solidly inside the
  /// threshold dead zone on the way up) reports noHips for that one frame
  /// — the angle itself is normal, only the gate verdict flickers.
  List<(double, PushupVerdict)> swing({bool glitchOnAscent = false}) {
    const frames = 36;
    return [
      for (var i = 0; i <= frames; i++)
        (
          i <= frames ~/ 2
              ? 170 - (i / (frames / 2)) * 85
              : 85 + ((i - frames / 2) / (frames / 2)) * 85,
          glitchOnAscent && i == 26 ? PushupVerdict.noHips : PushupVerdict.ok,
        ),
    ];
  }

  /// Runs the frames through the pipeline exactly like pose_screen does:
  /// filter (or not), interrupt on failing verdicts, feed angles otherwise.
  int run(List<(double, PushupVerdict)> frames, {required bool filtered}) {
    final counter = PushupCounter();
    final filter = VerdictHoldFilter();
    var t = 0;
    for (final (angle, verdict) in frames) {
      final effective = filtered ? filter.filter(verdict, at(t)) : verdict;
      if (effective != PushupVerdict.ok) {
        counter.interrupt();
      } else {
        counter.update(angle, at(t));
      }
      t += 33;
    }
    return counter.reps;
  }

  // 3 clean calibration swings + 10 real reps. The first 3 are always
  // clean; the last 10 carry one glitchy ascent frame each when scripted.
  final clean = <(double, PushupVerdict)>[
    for (var i = 0; i < 3; i++) ...swing(),
    for (var i = 0; i < 10; i++) ...swing(),
  ];
  final glitched = <(double, PushupVerdict)>[
    for (var i = 0; i < 3; i++) ...swing(),
    for (var i = 0; i < 10; i++) ...swing(glitchOnAscent: true),
  ];

  test('with the filter, glitchy frames cost nothing — every rep counts',
      () {
    final baseline = run(clean, filtered: true);
    expect(
      run(glitched, filtered: true),
      baseline,
      reason: 'the same workout must count the same reps with or without '
          'detector flicker',
    );
  });

  test('without the filter, per-frame glitches silently drop most reps',
      () {
    final baseline = run(clean, filtered: true);
    final unfiltered = run(glitched, filtered: false);
    expect(
      unfiltered,
      lessThan(baseline - 7),
      reason: 'each dead-zone glitch resets the half-cycle and loses its '
          'rep — this is the bug M6 fixes',
    );
  });

  test('a sustained cheat still dies through the filter', () {
    // ~2s of standing-and-waving (handsUp every frame): the first few
    // frames ride the grace window, then counting pauses for good.
    final counter = PushupCounter();
    final filter = VerdictHoldFilter();
    var interruptFrames = 0;
    var t = 0;
    for (var i = 0; i < 60; i++) {
      final effective = filter.filter(PushupVerdict.handsUp, at(t));
      if (effective != PushupVerdict.ok) {
        counter.interrupt();
        interruptFrames++;
      }
      t += 33;
    }
    expect(counter.reps, 0);
    expect(
      interruptFrames,
      greaterThan(45),
      reason: 'after ~9 grace frames the standing wave must interrupt on '
          'every remaining frame',
    );
  });
}
