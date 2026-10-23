import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/levels.dart';

/// The campaign must be valid, distinct and progressively harder — these
/// assertions are the contract every future level addition has to keep.
void main() {
  group('campaign shape', () {
    test('eight levels with sequential ids', () {
      expect(kLevels.length, 8);
      for (var i = 0; i < kLevels.length; i++) {
        expect(kLevels[i].id, i + 1);
      }
    });

    test('names are pixel-font safe (ASCII uppercase + spaces)', () {
      final safe = RegExp(r'^[A-Z0-9 ]+$');
      for (final l in kLevels) {
        expect(safe.hasMatch(l.name), isTrue, reason: l.name);
        expect(l.name.length, lessThanOrEqualTo(16));
        expect(l.tagline.isNotEmpty, isTrue);
      }
    });

    test('every level defines a completion objective', () {
      for (final l in kLevels) {
        expect(l.waves, inInclusiveRange(4, 10));
      }
    });
  });

  group('enemy mixes', () {
    test('mixes are non-empty with positive weights of valid variants', () {
      for (final l in kLevels) {
        expect(l.mix, isNotEmpty, reason: l.name);
        l.mix.forEach((variant, weight) {
          expect(EnemyVariant.values.contains(variant), isTrue);
          expect(weight, greaterThan(0));
        });
      }
    });

    test('variants unlock gradually: runner from L2, brute from L4', () {
      expect(kLevels[0].mix.keys, unorderedEquals([EnemyVariant.grunt]));
      expect(kLevels[1].mix.keys, contains(EnemyVariant.runner));
      expect(kLevels[2].mix.keys, contains(EnemyVariant.runner));
      expect(kLevels[3].mix.keys, contains(EnemyVariant.brute));
      expect(kLevels.last.mix.keys,
          unorderedEquals(EnemyVariant.values.where((v) => v != EnemyVariant.boss)));
    });

    test('pickVariant respects weight boundaries', () {
      final l = kLevels[3]; // grunt 5, runner 3, brute 2 → total 10
      expect(l.pickVariant(0.0), EnemyVariant.grunt);
      expect(l.pickVariant(0.49), EnemyVariant.grunt);
      expect(l.pickVariant(0.5), EnemyVariant.runner);
      expect(l.pickVariant(0.79), EnemyVariant.runner);
      expect(l.pickVariant(0.8), EnemyVariant.brute);
      expect(l.pickVariant(0.999), EnemyVariant.brute);
    });
  });

  group('bosses', () {
    test('level 1 teaches without a boss; the rest end on one', () {
      expect(kLevels.first.bossWave, 0);
      for (final l in kLevels.skip(1)) {
        expect(l.bossWave, l.waves, reason: l.name);
      }
    });
  });

  group('difficulty curve', () {
    test('scales rise and spawn pressure tightens monotonically', () {
      for (var i = 1; i < kLevels.length; i++) {
        final prev = kLevels[i - 1], cur = kLevels[i];
        expect(cur.hpScale, greaterThanOrEqualTo(prev.hpScale));
        expect(cur.speedScale, greaterThanOrEqualTo(prev.speedScale));
        expect(cur.damageScale, greaterThanOrEqualTo(prev.damageScale));
        expect(cur.spawnMs, lessThanOrEqualTo(prev.spawnMs));
        expect(cur.clearCoins, greaterThan(prev.clearCoins));
      }
      expect(kLevels.first.hpScale, 1.0);
      expect(kLevels.last.hpScale, lessThanOrEqualTo(3.0),
          reason: 'difficulty must stay fair, not inflate');
    });
  });

  group('palettes', () {
    test('every level has a distinct atmosphere and enemy hue', () {
      final washes = kLevels.map((l) => l.palette.wash.toARGB32()).toSet();
      final grunts = kLevels.map((l) => l.palette.hueOf(EnemyVariant.grunt).toARGB32()).toSet();
      expect(washes.length, kLevels.length);
      expect(grunts.length, kLevels.length);
    });

    test('palettes expose derived castle/ground tones', () {
      for (final l in kLevels) {
        final p = l.palette;
        expect(p.stoneDark, isNot(equals(p.stoneLight)));
        expect(p.mortar, isNot(equals(p.outline)));
        expect(p.lipDark, isNot(equals(p.lipBladeLight)));
        expect(p.hill.a, greaterThan(0));
        // Hue list covers all four variants.
        expect(p.hues.length, EnemyVariant.values.length);
      }
    });

    test('variant stat multipliers are sane', () {
      expect(EnemyVariant.runner.hpMult, lessThan(EnemyVariant.grunt.hpMult));
      expect(EnemyVariant.runner.speedMult,
          greaterThan(EnemyVariant.grunt.speedMult));
      expect(EnemyVariant.brute.hpMult, greaterThan(EnemyVariant.grunt.hpMult));
      expect(EnemyVariant.boss.hpMult, greaterThan(EnemyVariant.brute.hpMult));
      expect(EnemyVariant.boss.radius, greaterThan(EnemyVariant.brute.radius));
    });
  });

  group('levelById', () {
    test('resolves valid ids and clamps corrupt ones', () {
      expect(levelById(1).id, 1);
      expect(levelById(8).id, 8);
      expect(levelById(0).id, 1); // clamps low
      expect(levelById(99).id, 8); // clamps high
      expect(levelById(-5).id, 1);
    });
  });

  test('color helpers produce opaque-enough derived tones', () {
    final p = kLevels.first.palette;
    expect(p.stoneDark, isA<Color>());
    expect(p.chip, isA<Color>());
  });
}
