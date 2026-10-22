import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/economy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('upgrade costs', () {
    test('every upgrade starts affordable in early waves', () {
      // Wave 1 clear alone gives 15 coins + ~4 kills ≈ 4 more.
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
    test('wave clears pay more as waves climb', () {
      expect(waveClearCoins(1), 15);
      expect(waveClearCoins(10), greaterThan(waveClearCoins(5)));
    });

    test('bosses drop far more than normal enemies', () {
      expect(killCoins(3, boss: false), 6);
      expect(killCoins(3, boss: true), 34);
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
}
