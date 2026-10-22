import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The four M3 upgrades (PLAN.md §3): power, speed, fortress, combo.
enum UpgradeType { power, speed, fortress, combo }

// ---------------------------------------------------------------------------
// Pure formulas — unit-tested, single source of truth for game AND shop UI.
// ---------------------------------------------------------------------------

/// Damage dealt by one counted pushup (before combo multiplier).
int repDamage(int powerLevel) => 1 + powerLevel;

/// Seconds between automatic chip-damage shots (idle element).
double autoInterval(int speedLevel) => max(0.75, 4.0 - 0.5 * speedLevel);

/// Damage of an automatic shot.
int autoDamage(int powerLevel) => 1 + powerLevel ~/ 2;

/// Maximum castle HP.
int maxBaseHp(int fortressLevel) => 80 + 25 * fortressLevel;

/// Seconds of grace between two reps before the combo resets.
double comboWindow(int comboLevel) => 3.0 + comboLevel;

/// Combo damage multiplier: 1.0 on the first rep, +0.1 per consecutive rep,
/// capped at 2.0 (11th rep in a row).
double comboMultiplier(int comboCount) => 1.0 + min(comboCount - 1, 10) * 0.1;

/// Coins earned for clearing wave [wave].
int waveClearCoins(int wave) => 10 + 5 * wave;

/// Coins dropped by one killed enemy of wave [wave].
int killCoins(int wave, {required bool boss}) =>
    boss ? 25 + 3 * wave : 3 + wave;

int _baseCost(UpgradeType t) => switch (t) {
      UpgradeType.power => 10,
      UpgradeType.speed => 15,
      UpgradeType.fortress => 10,
      UpgradeType.combo => 15,
    };

int upgradeMaxLevel(UpgradeType t) => switch (t) {
      UpgradeType.power => 10,
      UpgradeType.speed => 8,
      UpgradeType.fortress => 8,
      UpgradeType.combo => 5,
    };

/// Cost of buying level [level] (i.e. going from level → level+1).
/// Returns null when the upgrade is maxed out.
int? upgradeCost(UpgradeType t, int level) {
  if (level >= upgradeMaxLevel(t)) return null;
  return (_baseCost(t) * pow(1.6, level)).round();
}

String upgradeName(UpgradeType t) => switch (t) {
      UpgradeType.power => 'POWER',
      UpgradeType.speed => 'SPEED',
      UpgradeType.fortress => 'FORTRESS',
      UpgradeType.combo => 'COMBO',
    };

/// Short effect line for the shop card: what buying the NEXT level gives.
String upgradeEffect(UpgradeType t, int level) => switch (t) {
      UpgradeType.power =>
        'rep dmg ${repDamage(level)} → ${repDamage(level + 1)}',
      UpgradeType.speed =>
        'auto ${(autoInterval(level)).toStringAsFixed(2)}s → '
        '${autoInterval(level + 1).toStringAsFixed(2)}s',
      UpgradeType.fortress =>
        'base HP ${maxBaseHp(level)} → ${maxBaseHp(level + 1)}',
      UpgradeType.combo =>
        'combo hold ${(comboWindow(level)).toStringAsFixed(0)}s → '
        '${(comboWindow(level + 1)).toStringAsFixed(0)}s · ×'
        '${comboMultiplier(level + 11).toStringAsFixed(1)} max',
    };

// ---------------------------------------------------------------------------
// Persistent save
// ---------------------------------------------------------------------------

/// Everything that survives an app restart, stored in shared_preferences.
class PlayerSave {
  PlayerSave({
    this.coins = 0,
    Map<UpgradeType, int>? levels,
    this.bestWave = 0,
  }) : levels = levels ?? {for (final t in UpgradeType.values) t: 0};

  int coins;
  final Map<UpgradeType, int> levels;
  int bestWave;

  int levelOf(UpgradeType t) => levels[t] ?? 0;

  static Future<PlayerSave> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerSave(
      coins: prefs.getInt('coins') ?? 0,
      bestWave: prefs.getInt('best_wave') ?? 0,
      levels: {
        for (final t in UpgradeType.values)
          t: prefs.getInt('up_${t.name}') ?? 0,
      },
    );
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins', coins);
    await prefs.setInt('best_wave', bestWave);
    for (final t in UpgradeType.values) {
      await prefs.setInt('up_${t.name}', levelOf(t));
    }
  }

  /// Attempts to buy the next level of [t]; persists on success.
  bool buy(UpgradeType t) {
    final cost = upgradeCost(t, levelOf(t));
    if (cost == null || coins < cost) return false;
    coins -= cost;
    levels[t] = levelOf(t) + 1;
    persist();
    return true;
  }
}
