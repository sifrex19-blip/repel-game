import 'dart:math' show max, min;
import 'dart:ui' show Color;

import 'pixel_art.dart';

/// Enemy variants — all reuse the existing hand-authored sprites at different
/// integer scales with palette-swapped hues, so new levels add variety with
/// zero new asset bytes.
enum EnemyVariant {
  /// Grumbler at 3× — the baseline foot soldier.
  grunt,

  /// Grumbler at 2× — quick, fragile skirmisher.
  runner,

  /// Grumbler at 4× — slow, heavy damage sponge.
  brute,

  /// Boss sprite at 4× — level finale.
  boss,
}

/// Stat multipliers per variant (applied on top of the level's wave stats).
extension EnemyVariantStats on EnemyVariant {
  double get hpMult => switch (this) {
        EnemyVariant.grunt => 1.0,
        EnemyVariant.runner => 0.55,
        EnemyVariant.brute => 2.4,
        EnemyVariant.boss => 4.0,
      };

  double get speedMult => switch (this) {
        EnemyVariant.grunt => 1.0,
        EnemyVariant.runner => 1.45,
        EnemyVariant.brute => 0.72,
        EnemyVariant.boss => 0.75,
      };

  double get damageMult => switch (this) {
        EnemyVariant.grunt => 1.0,
        EnemyVariant.runner => 0.75,
        EnemyVariant.brute => 1.6,
        EnemyVariant.boss => 1.5,
      };

  /// Collision radius (sprite scale × ~8, matching the original 24/44).
  double get radius => switch (this) {
        EnemyVariant.grunt => 24.0,
        EnemyVariant.runner => 16.0,
        EnemyVariant.brute => 32.0,
        EnemyVariant.boss => 44.0,
      };

  bool get isBoss => this == EnemyVariant.boss;
}

/// Visual identity of a level: a few base colors plus derived shades, enough
/// to repaint ground, castle, atmosphere and enemies into a new biome while
/// reusing every sprite and drawing routine.
class LevelPalette {
  const LevelPalette({
    required this.wash,
    required this.band,
    required this.soil,
    required this.pebble,
    required this.moss,
    required this.lip,
    required this.flag,
    required this.stone,
    required this.hues,
  });

  /// Translucent atmosphere wash drawn over the whole world (the camera
  /// feed ghosts through as living texture).
  final Color wash;

  /// Ground base band (translucent) and lower soil stratum (translucent).
  final Color band;
  final Color soil;

  /// Deterministic ground texture colors.
  final Color pebble;
  final Color moss;

  /// Lit edge line the characters stand in.
  final Color lip;

  /// Castle banner color.
  final Color flag;

  /// Castle mid-brick tone; dark/light/mortar/outline/chip derive from it.
  final Color stone;

  /// Enemy body hues: [grunt, runner, brute, boss].
  final List<Color> hues;

  Color get pebbleLight => pixelLighten(pebble, 0.35);
  Color get crack => pixelShade(soil, 0.55);
  Color get lipDark => pixelShade(lip, 0.62);
  Color get lipBlade => pixelLighten(lip, 0.35);
  Color get lipBladeLight => pixelLighten(lip, 0.62);
  Color get stoneDark => pixelShade(stone, 0.78);
  Color get stoneLight => pixelLighten(stone, 0.22);
  Color get mortar => pixelShade(stone, 0.50);
  Color get outline => pixelShade(stone, 0.38);
  Color get chip => pixelLighten(stone, 0.45);

  /// Distant hill silhouettes — the soil color at fixed transparency.
  Color get hill =>
      Color.fromARGB(0x55, (soil.r * 255).round(), (soil.g * 255).round(),
          (soil.b * 255).round());

  Color hueOf(EnemyVariant v) => hues[v.index];
}

/// One playable level. Everything is data: levels 1-8 are handcrafted, the
/// tail up to [kCampaignLength] is generated from the [kBiomes] table — no
/// new code paths, no duplicated logic.
class LevelDef {
  const LevelDef({
    required this.id,
    required this.name,
    required this.tagline,
    required this.waves,
    required this.mix,
    required this.bossWave,
    required this.hpScale,
    required this.speedScale,
    required this.damageScale,
    required this.spawnMs,
    required this.clearBonus,
    required this.palette,
  });

  /// 1-based level id (also the unlock order).
  final int id;

  /// Shown in banners and menus — ASCII only (pixel font).
  final String name;
  final String tagline;

  /// Waves to clear the level (completion objective).
  final int waves;

  /// Enemy variant spawn weights, e.g. {grunt: 5, runner: 3, brute: 2}.
  final Map<EnemyVariant, int> mix;

  /// Wave number that spawns the boss, or 0 for no boss.
  final int bossWave;

  /// Difficulty scaling applied on top of the per-wave base formulas.
  final double hpScale;
  final double speedScale;
  final double damageScale;

  /// Milliseconds between spawns (spawn pressure).
  final int spawnMs;

  /// First-clear bonus in PUSHUPS (the only currency; never re-granted on
  /// replays).
  final int clearBonus;

  final LevelPalette palette;

  /// Weighted variant pick from [mix] given [r] in [0, 1).
  EnemyVariant pickVariant(double r) {
    var total = 0;
    for (final w in mix.values) {
      total += w;
    }
    var roll = r * total;
    for (final entry in mix.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return EnemyVariant.grunt;
  }
}

/// Campaign length (M7): 200 levels that keep getting harder.
const int kCampaignLength = 200;

/// One biome archetype: palette + enemy mix. Levels 1-8 wear the eight
/// biomes in order; levels 9-200 cycle them again, so the campaign revisits
/// every atmosphere five times on the way up.
class BiomeDef {
  const BiomeDef({required this.palette, required this.mix});

  final LevelPalette palette;
  final Map<EnemyVariant, int> mix;
}

const kBiomes = <BiomeDef>[
  // 1 — tutorial atmosphere: mossy gate, grunts only.
  BiomeDef(
    mix: {EnemyVariant.grunt: 10},
    palette: LevelPalette(
      wash: Color(0x140D1A14),
      band: Color(0xC71A241D),
      soil: Color(0xD9141118),
      pebble: Color(0xFF3A4048),
      moss: Color(0xFF2B321F),
      lip: Color(0xFF33543F),
      flag: Color(0xFFE8622A),
      stone: Color(0xFF455A64),
      hues: [
        Color(0xFF7FA06B),
        Color(0xFFA8C46A),
        Color(0xFF5E8460),
        Color(0xFFD9A441),
      ],
    ),
  ),
  // 2 — crimson dusk, runners join.
  BiomeDef(
    mix: {EnemyVariant.grunt: 7, EnemyVariant.runner: 3},
    palette: LevelPalette(
      wash: Color(0x18300E12),
      band: Color(0xC72A1A22),
      soil: Color(0xD91F1018),
      pebble: Color(0xFF4A3844),
      moss: Color(0xFF33202A),
      lip: Color(0xFF5A3340),
      flag: Color(0xFFD64550),
      stone: Color(0xFF5A4A52),
      hues: [
        Color(0xFFB45C6E),
        Color(0xFFE08A5A),
        Color(0xFF8A4058),
        Color(0xFFF0B33D),
      ],
    ),
  ),
  // 3 — frostfield, the runner-heavy speed check.
  BiomeDef(
    mix: {EnemyVariant.grunt: 4, EnemyVariant.runner: 6},
    palette: LevelPalette(
      wash: Color(0x18102838),
      band: Color(0xC71A2430),
      soil: Color(0xD9121A26),
      pebble: Color(0xFF3A4A5C),
      moss: Color(0xFF25323E),
      lip: Color(0xFF4E7A8C),
      flag: Color(0xFF4FC3F7),
      stone: Color(0xFF4A5E6E),
      hues: [
        Color(0xFF7FB8D9),
        Color(0xFFA8E0F0),
        Color(0xFF5A86B8),
        Color(0xFFE8D060),
      ],
    ),
  ),
  // 4 — deepwood, brutes join: target priority matters.
  BiomeDef(
    mix: {EnemyVariant.grunt: 5, EnemyVariant.runner: 3, EnemyVariant.brute: 2},
    palette: LevelPalette(
      wash: Color(0x18180830),
      band: Color(0xC71E1A2C),
      soil: Color(0xD9161222),
      pebble: Color(0xFF3A3450),
      moss: Color(0xFF241E36),
      lip: Color(0xFF443A66),
      flag: Color(0xFFB388FF),
      stone: Color(0xFF443E5A),
      hues: [
        Color(0xFF9B7FD4),
        Color(0xFFC89AE8),
        Color(0xFF6E52A8),
        Color(0xFFE05A7A),
      ],
    ),
  ),
  // 5 — sunken ruins, mixed cadence.
  BiomeDef(
    mix: {EnemyVariant.grunt: 4, EnemyVariant.runner: 4, EnemyVariant.brute: 2},
    palette: LevelPalette(
      wash: Color(0x1808282A),
      band: Color(0xC71A2626),
      soil: Color(0xD9121C20),
      pebble: Color(0xFF3A4A48),
      moss: Color(0xFF24322E),
      lip: Color(0xFF4E7A6E),
      flag: Color(0xFF66D9C4),
      stone: Color(0xFF4A5A56),
      hues: [
        Color(0xFF66B8A8),
        Color(0xFF9AD8B8),
        Color(0xFF4A8A88),
        Color(0xFFE0B84A),
      ],
    ),
  ),
  // 6 — emberfall: fast spawns, hot hues.
  BiomeDef(
    mix: {EnemyVariant.grunt: 3, EnemyVariant.runner: 4, EnemyVariant.brute: 3},
    palette: LevelPalette(
      wash: Color(0x1E3A0E06),
      band: Color(0xC72A1410),
      soil: Color(0xD9200E0C),
      pebble: Color(0xFF4A3228),
      moss: Color(0xFF331E16),
      lip: Color(0xFF6A3A26),
      flag: Color(0xFFFF8A3D),
      stone: Color(0xFF5A463C),
      hues: [
        Color(0xFFE07038),
        Color(0xFFF0A848),
        Color(0xFFB84A28),
        Color(0xFFFFD05E),
      ],
    ),
  ),
  // 7 — cursed hollow: the brute wall.
  BiomeDef(
    mix: {EnemyVariant.grunt: 3, EnemyVariant.runner: 3, EnemyVariant.brute: 4},
    palette: LevelPalette(
      wash: Color(0x1818300A),
      band: Color(0xC71C2412),
      soil: Color(0xD9141A0E),
      pebble: Color(0xFF3A4A28),
      moss: Color(0xFF24301A),
      lip: Color(0xFF4E6A2E),
      flag: Color(0xFFA8D84A),
      stone: Color(0xFF4A5440),
      hues: [
        Color(0xFF8FC44A),
        Color(0xFFC4E06A),
        Color(0xFF5E8A3A),
        Color(0xFFD8E85A),
      ],
    ),
  ),
  // 8 — last stand: the everything-at-once finale palette.
  BiomeDef(
    mix: {EnemyVariant.grunt: 2, EnemyVariant.runner: 3, EnemyVariant.brute: 5},
    palette: LevelPalette(
      wash: Color(0x24200610),
      band: Color(0xC7200E14),
      soil: Color(0xD9160A10),
      pebble: Color(0xFF3A2430),
      moss: Color(0xFF24141E),
      lip: Color(0xFF4A2030),
      flag: Color(0xFFD64550),
      stone: Color(0xFF4A3440),
      hues: [
        Color(0xFFC43A4A),
        Color(0xFFE06A4A),
        Color(0xFF8A2438),
        Color(0xFF2B2430),
      ],
    ),
  ),
];

/// Levels 1-8: handcrafted tuning on top of the [kBiomes] palettes — the
/// on-ramp the campaign has shipped since M4, values unchanged.
final kHandcraftedLevels = <LevelDef>[
  // 1 — tutorial: grunts only, no boss, current M3 look.
  LevelDef(
    id: 1,
    name: 'MOSSGATE',
    tagline: 'The first breach at the wall.',
    waves: 4,
    mix: kBiomes[0].mix,
    bossWave: 0,
    hpScale: 1.0,
    speedScale: 1.0,
    damageScale: 1.0,
    spawnMs: 2200,
    clearBonus: 40,
    palette: kBiomes[0].palette,
  ),
  // 2 — runners join; first boss.
  LevelDef(
    id: 2,
    name: 'CRIMSON DUSK',
    tagline: 'Fast shadows at sundown.',
    waves: 5,
    mix: kBiomes[1].mix,
    bossWave: 5,
    hpScale: 1.15,
    speedScale: 1.0,
    damageScale: 1.0,
    spawnMs: 2200,
    clearBonus: 60,
    palette: kBiomes[1].palette,
  ),
  // 3 — runner-heavy: the speed check.
  LevelDef(
    id: 3,
    name: 'FROSTFIELD',
    tagline: 'Cold ground, quicker feet.',
    waves: 5,
    mix: kBiomes[2].mix,
    bossWave: 5,
    hpScale: 1.3,
    speedScale: 1.05,
    damageScale: 1.1,
    spawnMs: 2100,
    clearBonus: 80,
    palette: kBiomes[2].palette,
  ),
  // 4 — brutes join: target priority matters.
  LevelDef(
    id: 4,
    name: 'DEEPWOOD',
    tagline: 'Heavy steps in the dark.',
    waves: 6,
    mix: kBiomes[3].mix,
    bossWave: 6,
    hpScale: 1.5,
    speedScale: 1.05,
    damageScale: 1.2,
    spawnMs: 2000,
    clearBonus: 110,
    palette: kBiomes[3].palette,
  ),
  // 5 — mixed cadence.
  LevelDef(
    id: 5,
    name: 'SUNKEN RUINS',
    tagline: 'Old stones, older grudges.',
    waves: 6,
    mix: kBiomes[4].mix,
    bossWave: 6,
    hpScale: 1.75,
    speedScale: 1.1,
    damageScale: 1.3,
    spawnMs: 1900,
    clearBonus: 140,
    palette: kBiomes[4].palette,
  ),
  // 6 — ember pressure: fast spawns, hot hues.
  LevelDef(
    id: 6,
    name: 'EMBERFALL',
    tagline: 'The earth itself burns.',
    waves: 7,
    mix: kBiomes[5].mix,
    bossWave: 7,
    hpScale: 2.0,
    speedScale: 1.15,
    damageScale: 1.4,
    spawnMs: 1800,
    clearBonus: 180,
    palette: kBiomes[5].palette,
  ),
  // 7 — brute wall.
  LevelDef(
    id: 7,
    name: 'CURSED HOLLOW',
    tagline: 'Nothing here stays dead.',
    waves: 7,
    mix: kBiomes[6].mix,
    bossWave: 7,
    hpScale: 2.3,
    speedScale: 1.2,
    damageScale: 1.5,
    spawnMs: 1600,
    clearBonus: 220,
    palette: kBiomes[6].palette,
  ),
  // 8 — the finale: everything at once.
  LevelDef(
    id: 8,
    name: 'LAST STAND',
    tagline: 'Hold the gate. End it.',
    waves: 8,
    mix: kBiomes[7].mix,
    bossWave: 8,
    hpScale: 2.6,
    speedScale: 1.3,
    damageScale: 1.6,
    spawnMs: 1500,
    clearBonus: 300,
    palette: kBiomes[7].palette,
  ),
];

// ---------------------------------------------------------------------------
// Generated tail (9..200): names glued from two word lists, biomes cycling
// every 8, and stats that rise monotonically past level 8's handcrafted
// values — difficulty keeps climbing without hand-authoring 192 entries.

/// Name halves: 16 × 16 = 256 unique glued names (the tail needs 192).
/// The heads avoid the handcrafted names' words, so no glued name can
/// collide with MOSSGATE / FROSTFIELD / DEEPWOOD / EMBERFALL either.
const _nameHeads = [
  'IRON', 'GOLD', 'NIGHT', 'STORM', 'ASHEN', 'RAVEN', 'BONE', 'DUSK',
  'THORN', 'SALT', 'CRIMSON', 'PALE', 'WOLF', 'GRIM', 'VENOM', 'WINTER',
];
const _nameTails = [
  'FALL', 'KEEP', 'HOLLOW', 'MIRE', 'REACH', 'SPIRE', 'MARK', 'FEN',
  'WATCH', 'RIFT', 'SPUR', 'DUNE', 'BROOK', 'CRAG', 'HURST', 'VEIL',
];

/// Tagline halves — subjects are singular, predicates 3rd-person singular,
/// so every join reads as a sentence.
const _tagSubs = [
  'The horde', 'The watch', 'Night', 'Dawn', 'The march', 'The tide',
  'Steel', 'Silence', 'Old iron', 'Broken honor', 'The siege', 'Last light',
  'Iron rain', 'The wild', 'The dark', 'The long road',
];
const _tagPreds = [
  'presses on.', 'stirs.', 'gathers.', 'descends.', 'waits.', 'endures.',
  'advances.', 'rises.', 'deepens.', 'burns.', 'rests.', 'comes.', 'looms.',
  'hangs heavy.', 'cracks.', 'falls silent.',
];

/// Level [id] for id > 8. Every stat starts exactly where level 8 left off
/// and climbs from there: hp +4.5%/level, speed +0.15%/level (post-scale),
/// damage +0.6%/level, spawn gap −4ms/level down to a 900ms floor, waves
/// +1 per six levels capped at 12, clear bonus +20/level.
LevelDef _generatedLevel(int id) {
  final i = id - kHandcraftedLevels.length - 1; // 0-based tail index
  final headIdx = i % _nameHeads.length;
  final tailIdx = (i ~/ _nameHeads.length) % _nameTails.length;
  final biome = kBiomes[(id - 1) % kBiomes.length];
  final waves = min(8 + (id - 8) ~/ 6, 12);
  return LevelDef(
    id: id,
    name: '${_nameHeads[headIdx]}${_nameTails[tailIdx]}',
    tagline: '${_tagSubs[tailIdx]} ${_tagPreds[headIdx]}',
    waves: waves,
    mix: biome.mix,
    bossWave: waves, // the tail always ends on a boss
    hpScale: 2.6 + (id - 8) * 0.045,
    speedScale: 1.3 + (id - 8) * 0.0015,
    damageScale: 1.6 + (id - 8) * 0.006,
    spawnMs: max(900, 1500 - (id - 8) * 4),
    clearBonus: 300 + (id - 8) * 20,
    palette: biome.palette,
  );
}

/// The campaign: 200 levels — the 8 handcrafted on-ramp followed by a
/// generated tail that cycles the same biomes and keeps getting harder.
/// Difficulty rises through composition and pressure, not just HP.
final kLevels = <LevelDef>[
  ...kHandcraftedLevels,
  for (var id = kHandcraftedLevels.length + 1; id <= kCampaignLength; id++)
    _generatedLevel(id),
];

/// Level by id, clamped into the campaign range (corrupt saves fall back to
/// the first level, out-of-range high ids to the finale).
LevelDef levelById(int id) =>
    kLevels[(id - 1).clamp(0, kLevels.length - 1)];
