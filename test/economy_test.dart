import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/economy.dart';
import 'package:repel_game/m2/levels.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('upgrade costs', () {
    test('every upgrade starts affordable in early waves', () {
      // Pushups are the only income (M7): the first upgrade costs 10 —
      // about ten counted reps, earned during the very first wave.
      for (final t in UpgradeType.values) {
        expect(upgradeCost(t, 0)! <= 15, isTrue, reason: '$t first level');
      }
    });

    test('costs grow geometrically and end at max level', () {
      for (final t in UpgradeType.values) {
        var level = 0;
        int? cost = upgradeCost(t, level);
        while (cost != null) {
          level++;
          final next = upgradeCost(t, level);
          if (next != null) {
            expect(next, greaterThan(cost), reason: '${t.name} Lv$level');
          }
          cost = next;
        }
        expect(level, upgradeMaxLevel(t));
      }
    });
  });

  group('effects scale with levels', () {
    test('power increases rep and auto damage', () {
      expect(repDamage(0), 1);
      expect(repDamage(10), 11);
      expect(autoDamage(0), 1);
      expect(autoDamage(4), 3);
      expect(autoDamage(5), 3); // integer division steps
    });

    test('speed speeds up auto-attack but never past 0.75s', () {
      expect(autoInterval(0), 4.0);
      expect(autoInterval(2), 3.0);
      expect(autoInterval(100), 0.75);
      // Monotonically non-increasing.
      for (var i = 1; i <= 8; i++) {
        expect(autoInterval(i), lessThanOrEqualTo(autoInterval(i - 1)));
      }
    });

    test('fortress grants +25 HP per level from a base of 80', () {
      expect(maxBaseHp(0), 80);
      expect(maxBaseHp(4), 180);
    });

    test('combo multiplier grows per chained rep and caps at 2.0', () {
      expect(comboMultiplier(1), 1.0);
      expect(comboMultiplier(6), 1.5);
      expect(comboMultiplier(11), 2.0);
      expect(comboMultiplier(999), 2.0); // hard cap
    });

    test('combo upgrade extends the hold window', () {
      expect(comboWindow(0), 3.0);
      expect(comboWindow(5), 8.0);
    });
  });

  group('rewards', () {
    test('every pushup pays coins; big combos pay double', () {
      // M7: pushups are THE currency — 1 coin per counted rep, 2 once the
      // combo multiplier reaches ×1.5. Kills and wave clears pay nothing.
      expect(repCoins(1), 1);
      expect(repCoins(5), 1); // ×1.4
      expect(repCoins(6), 2); // ×1.5
      expect(repCoins(11), 2); // ×2.0 cap
      expect(repCoins(999), 2); // hard cap
      // Never zero: idle training always pays.
      for (var c = 1; c <= 20; c++) {
        expect(repCoins(c), greaterThanOrEqualTo(1));
      }
    });
  });

  group('castle appearance ladder', () {
    test('two fortress levels per stage, capped at the top stage', () {
      expect(castleStage(0), 0); // the small wooden fort you start with
      expect(castleStage(1), 0);
      expect(castleStage(2), 1);
      expect(castleStage(4), 2);
      expect(castleStage(9), 4);
      expect(castleStage(upgradeMaxLevel(UpgradeType.fortress)), 5);
      expect(castleStage(99), 5); // clamps, never crashes
    });

    test('every stage has a short shop name', () {
      for (var s = 0; s <= 5; s++) {
        expect(castleStageName(s).isNotEmpty, isTrue, reason: 'stage $s');
      }
      expect(castleStageName(0), 'WOOD');
      expect(castleStageName(5), 'GOLD STEEL');
    });

    test('the tower grows with every stage', () {
      for (var s = 1; s <= 5; s++) {
        expect(castleHeight(s), greaterThan(castleHeight(s - 1)));
      }
      expect(castleHeight(0), 82); // small wooden fort
      expect(castleHeight(5), 122); // gold-trimmed keep
    });

    test('fortress tops out at 10 levels and 330 HP', () {
      expect(upgradeMaxLevel(UpgradeType.fortress), 10);
      expect(maxBaseHp(upgradeMaxLevel(UpgradeType.fortress)), 330);
    });
  });

  group('PlayerSave.buy', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('deducts coins and increments level on success', () {
      final save = PlayerSave(coins: 100);
      expect(save.buy(UpgradeType.power), isTrue);
      expect(save.coins, 100 - upgradeCost(UpgradeType.power, 0)!);
      expect(save.levelOf(UpgradeType.power), 1);
    });

    test('rejects purchases without enough coins', () {
      final save = PlayerSave(coins: 1);
      expect(save.buy(UpgradeType.power), isFalse);
      expect(save.coins, 1);
      expect(save.levelOf(UpgradeType.power), 0);
    });

    test('rejects purchases at max level', () {
      final save = PlayerSave(
        coins: 100000,
        levels: {for (final t in UpgradeType.values) t: upgradeMaxLevel(t)},
      );
      for (final t in UpgradeType.values) {
        expect(save.buy(t), isFalse, reason: '${t.name} already maxed');
      }
      expect(save.coins, 100000);
    });
  });

  group('PlayerSave migration', () {
    test('v1 save (flat keys only) keeps coins, upgrades and best wave',
        () async {
      SharedPreferences.setMockInitialValues({
        'coins': 120,
        'best_wave': 7,
        'up_power': 3,
        'up_combo': 2,
      });
      final save = await PlayerSave.load();
      expect(save.coins, 120);
      expect(save.bestWave, 7);
      expect(save.levelOf(UpgradeType.power), 3);
      expect(save.levelOf(UpgradeType.combo), 2);
      expect(save.levelOf(UpgradeType.speed), 0);
      // Progression defaults for pre-M4 saves.
      expect(save.unlockedLevel, 1);
      expect(save.clearedLevel, 0);
      expect(save.lastLevel, 1);
      expect(save.totalReps, 0);
    });

    test('fresh install loads a clean profile', () async {
      SharedPreferences.setMockInitialValues({});
      final save = await PlayerSave.load();
      expect(save.coins, 0);
      expect(save.unlockedLevel, 1);
      expect(save.isUnlocked(1), isTrue);
      expect(save.isUnlocked(2), isFalse);
    });

    test('corrupt values are clamped into legal ranges', () async {
      SharedPreferences.setMockInitialValues({
        'coins': -50,
        'up_power': 99,
        'unlocked': 999,
        'cleared': -3,
        'last_level': 50,
        'total_reps': -1,
      });
      final save = await PlayerSave.load();
      expect(save.coins, 0);
      expect(save.levelOf(UpgradeType.power),
          upgradeMaxLevel(UpgradeType.power));
      expect(save.unlockedLevel, kLevels.length);
      expect(save.clearedLevel, 0);
      expect(save.lastLevel, lessThanOrEqualTo(save.unlockedLevel));
      expect(save.totalReps, 0);
    });

    test('v2 roundtrip survives persist + reload', () async {
      SharedPreferences.setMockInitialValues({});
      var save = await PlayerSave.load();
      save.coins = 55;
      save.unlockedLevel = 3;
      save.clearedLevel = 2;
      save.lastLevel = 3;
      save.totalReps = 41;
      save.totalKills = 23;
      save.bestCombo = 6;
      save.levels[UpgradeType.speed] = 4;
      await save.persist();

      save = await PlayerSave.load();
      expect(save.coins, 55);
      expect(save.unlockedLevel, 3);
      expect(save.clearedLevel, 2);
      expect(save.lastLevel, 3);
      expect(save.totalReps, 41);
      expect(save.totalKills, 23);
      expect(save.bestCombo, 6);
      expect(save.levelOf(UpgradeType.speed), 4);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('save_version'), PlayerSave.saveVersion);
    });
  });

  group('PlayerSave.grantLevelClear', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('pays the bonus and unlocks the next level exactly once', () {
      final save = PlayerSave(coins: 10);
      expect(save.grantLevelClear(1, 40), isTrue);
      expect(save.coins, 50);
      expect(save.clearedLevel, 1);
      expect(save.unlockedLevel, 2);

      // Replaying level 1 grants nothing.
      expect(save.grantLevelClear(1, 40), isFalse);
      expect(save.coins, 50);

      // Sequential progression continues.
      expect(save.grantLevelClear(2, 60), isTrue);
      expect(save.coins, 110);
      expect(save.unlockedLevel, 3);

      // Out-of-order jumps grant nothing.
      expect(save.grantLevelClear(5, 999), isFalse);
      expect(save.coins, 110);
    });

    test('unlocks never exceed the campaign length', () {
      final save = PlayerSave(
        clearedLevel: kLevels.length - 1,
        unlockedLevel: kLevels.length - 1,
      );
      expect(save.grantLevelClear(kLevels.length, 300), isTrue);
      expect(save.unlockedLevel, kLevels.length);
      expect(save.isUnlocked(kLevels.length), isTrue);
    });
  });
}
