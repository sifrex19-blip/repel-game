import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'levels.dart';

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

/// Coins earned per counted pushup — upgrades are bought with pushups, so
/// every rep pays the shop currency directly (combo scales it like damage:
/// ×1.5 and up → 2 coins).
int repCoins(int comboCount) => comboMultiplier(comboCount) >= 1.5 ? 2 : 1;

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
///
/// M4 adds campaign progression (unlocked/cleared levels, resume point,
/// lifetime stats). The pre-M4 flat keys (`coins`, `best_wave`, `up_*`) are
/// kept as-is, so old saves migrate with full progress intact — every value
/// is clamped on load, so corrupted or hand-edited storage can't break the
/// game, and missing keys simply read as a fresh profile.
class PlayerSave {
  PlayerSave({
    this.coins = 0,
    Map<UpgradeType, int>? levels,
    this.bestWave = 0,
    this.unlockedLevel = 1,
    this.clearedLevel = 0,
    this.lastLevel = 1,
    this.totalReps = 0,
    this.totalKills = 0,
    this.bestCombo = 0,
  }) : levels = levels ?? {for (final t in UpgradeType.values) t: 0};

  /// Save-format version written by this build (diagnostic marker; loading
  /// is shape-based, so pre-version saves migrate transparently).
  static const int saveVersion = 2;

  int coins;
  final Map<UpgradeType, int> levels;
  int bestWave;

  /// Highest playable level id, highest first-cleared level id, and the
  /// level the player entered last (resume point for the menu).
  int unlockedLevel;
  int clearedLevel;
  int lastLevel;

  /// Lifetime stats shown on the menu.
  int totalReps;
  int totalKills;
  int bestCombo;

  int levelOf(UpgradeType t) => levels[t] ?? 0;

  bool isUnlocked(int levelId) => levelId <= unlockedLevel;

  static int _readInt(SharedPreferences prefs, String key,
      {int fallback = 0, int min = 0, int? max}) {
    // Missing keys and wrong-typed (corrupt) values both read as fallback.
    var v = prefs.getInt(key) ?? fallback;
    if (v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  /// Loads from preferences, migrating any older layout and clamping every
  /// value into its legal range.
  static PlayerSave fromPrefs(SharedPreferences prefs) {
    final maxLevel = kLevels.length;
    final unlocked =
        _readInt(prefs, 'unlocked', fallback: 1, min: 1, max: maxLevel);
    return PlayerSave(
      coins: _readInt(prefs, 'coins'),
      bestWave: _readInt(prefs, 'best_wave'),
      levels: {
        for (final t in UpgradeType.values)
          t: _readInt(prefs, 'up_${t.name}', max: upgradeMaxLevel(t)),
      },
      unlockedLevel: unlocked,
      clearedLevel: _readInt(prefs, 'cleared', max: maxLevel),
      lastLevel:
          _readInt(prefs, 'last_level', fallback: 1, min: 1, max: unlocked),
      totalReps: _readInt(prefs, 'total_reps'),
      totalKills: _readInt(prefs, 'total_kills'),
      bestCombo: _readInt(prefs, 'best_combo'),
    );
  }

  static Future<PlayerSave> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return fromPrefs(prefs);
    } catch (_) {
      // Unreadable storage: start fresh rather than crash the game.
      return PlayerSave();
    }
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('save_version', saveVersion);
    await prefs.setInt('coins', coins);
    await prefs.setInt('best_wave', bestWave);
    await prefs.setInt('unlocked', unlockedLevel);
    await prefs.setInt('cleared', clearedLevel);
    await prefs.setInt('last_level', lastLevel);
    await prefs.setInt('total_reps', totalReps);
    await prefs.setInt('total_kills', totalKills);
    await prefs.setInt('best_combo', bestCombo);
    for (final t in UpgradeType.values) {
      await prefs.setInt('up_${t.name}', levelOf(t));
    }
  }

  /// Grants the first-clear bonus for completing [levelId] *in campaign
  /// order*. Returns true exactly once per level: replays, repeated
  /// completion events and out-of-order jumps grant nothing, so rewards can
  /// never be double-credited.
  bool grantLevelClear(int levelId, int bonus) {
    if (levelId != clearedLevel + 1) return false;
    clearedLevel = levelId;
    if (levelId + 1 > unlockedLevel) {
      unlockedLevel = min(levelId + 1, kLevels.length);
    }
    coins += bonus;
    persist();
    return true;
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
