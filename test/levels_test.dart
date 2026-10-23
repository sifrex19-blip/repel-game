import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/levels.dart';

/// The campaign must be valid, distinct and progressively harder — these
/// assertions are the contract the 200-level generator has to keep (M7):
/// eight handcrafted on-ramp levels followed by a generated tail that cycles
/// the same biomes and never gets easier.
void main() {
  group('campaign shape', () {
    test('200 levels with sequential ids', () {
      expect(kCampaignLength, 200);
      expect(kLevels.length, kCampaignLength);
      for (var i = 0; i < kLevels.length; i++) {
        expect(kLevels[i].id, i + 1, reason: 'index $i');
      }
    });

    test('levels 1-8 keep the handcrafted names and tuning', () {
      expect(kLevels[0].name, 'MOSSGATE');
      expect(kLevels[1].name, 'CRIMSON DUSK');
      expect(kLevels[7].name, 'LAST STAND');
      expect(kLevels[0].waves, 4);
      expect(kLevels[0].hpScale, 1.0);
      expect(kLevels[0].bossWave, 0); // the tutorial has no boss
      expect(kLevels[7].clearBonus, 300);
    });

    test('names are pixel-font safe (ASCII uppercase + spaces)', () {
      final safe = RegExp(r'^[A-Z0-9 ]+$');
      for (final l in kLevels) {
        expect(safe.hasMatch(l.name), isTrue, reason: l.name);
        expect(l.name.length, lessThanOrEqualTo(16));
        expect(l.tagline.isNotEmpty, isTrue);
      }
    });

    test('all 200 level names are unique', () {
      final names = kLevels.map((l) => l.name).toSet();
      expect(names.length, kLevels.length,
          reason: 'glued generated names must not collide');
    });

    test('every level defines a completion objective', () {
      for (final l in kLevels) {
        expect(l.waves, inInclusiveRange(4, 12));
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
      expect(
          kLevels.last.mix.keys,
          unorderedEquals(
              EnemyVariant.values.where((v) => v != EnemyVariant.boss)));
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
        expect(cur.hpScale, greaterThanOrEqualTo(prev.hpScale),
            reason: 'hp ${prev.id}→${cur.id}');
        expect(cur.speedScale, greaterThanOrEqualTo(prev.speedScale),
            reason: 'speed ${prev.id}→${cur.id}');
        expect(cur.damageScale, greaterThanOrEqualTo(prev.damageScale),
            reason: 'dmg ${prev.id}→${cur.id}');
        expect(cur.spawnMs, lessThanOrEqualTo(prev.spawnMs),
            reason: 'spawn ${prev.id}→${cur.id}');
        expect(cur.clearBonus, greaterThan(prev.clearBonus),
            reason: 'bonus ${prev.id}→${cur.id}');
      }
      expect(kLevels.first.hpScale, 1.0);
      expect(kLevels.last.hpScale, lessThanOrEqualTo(12.0),
          reason: 'the tail must climb but stay fair');
      expect(kLevels.last.spawnMs, 900, reason: 'spawn gap floor');
    });

    test('waves grow from 4 to the cap of 12', () {
      expect(kLevels.first.waves, 4);
      expect(kLevels.last.waves, 12);
      for (var i = 1; i < kLevels.length; i++) {
        expect(kLevels[i].waves, greaterThanOrEqualTo(kLevels[i - 1].waves),
            reason: 'waves ${kLevels[i - 1].id}→${kLevels[i].id}');
      }
    });
  });

  group('palettes', () {
    test('the eight biomes cycle through all 200 levels', () {
      final washes = kLevels.map((l) => l.palette.wash.toARGB32()).toSet();
      final grunts = kLevels
          .map((l) => l.palette.hueOf(EnemyVariant.grunt).toARGB32())
          .toSet();
      expect(washes.length, kBiomes.length);
      expect(grunts.length, kBiomes.length);
      // Every run of eight consecutive levels wears all eight biomes.
      for (var start = 0; start < 8; start++) {
        final run = kLevels
            .skip(start)
            .take(8)
            .map((l) => l.palette.wash.toARGB32())
            .toSet();
        expect(run.length, 8, reason: 'biome cycle broken at offset $start');
      }
    });

    test('levels 1-8 each wear a distinct atmosphere', () {
      final firstEight =
          kLevels.take(8).map((l) => l.palette.wash.toARGB32()).toSet();
      expect(firstEight.length, 8);
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
      expect(levelById(99).id, 99);
      expect(levelById(200).id, 200);
      expect(levelById(0).id, 1); // clamps low
      expect(levelById(9999).id, kLevels.length); // clamps high
      expect(levelById(-5).id, 1);
    });
  });

  test('color helpers produce opaque-enough derived tones', () {
    final p = kLevels.first.palette;
    expect(p.stoneDark, isA<Color>());
    expect(p.chip, isA<Color>());
  });
}
