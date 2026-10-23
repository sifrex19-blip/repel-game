import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import 'economy.dart';
import 'enemy.dart';
import 'game_camera.dart';
import 'levels.dart';
import 'pixel_art.dart';

enum GamePhase { menu, intro, fighting, waveCleared, victory, defeat }

/// Immutable snapshot the Flutter side (HUD/shop/panels) listens to.
class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.levelId,
    required this.levelName,
    required this.wave,
    required this.totalWaves,
    required this.coins,
    required this.baseHp,
    required this.maxBaseHp,
    required this.combo,
    required this.restSeconds,
    required this.bestWave,
    required this.unlockedLevel,
    required this.clearedLevel,
    required this.victoryBonus,
    required this.totalReps,
    required this.totalKills,
    required this.bestCombo,
    required this.levels,
  });

  final GamePhase phase;
  final int levelId;
  final String levelName;
  final int wave;
  final int totalWaves;
  final int coins;
  final int baseHp;
  final int maxBaseHp;
  final int combo;
  final int restSeconds;
  final int bestWave;
  final int unlockedLevel;
  final int clearedLevel;
  final int victoryBonus;
  final int totalReps;
  final int totalKills;
  final int bestCombo;
  final Map<UpgradeType, int> levels;
}

/// The combat game: waves of monsters march at your castle, every counted
/// pushup deals damage, kills drop coins, coins buy upgrades between waves —
/// now structured as a campaign of [kLevels] with distinct biomes, enemy
/// mixes and a boss finale per level.
///
/// Rendering is pixel art throughout: hand-built background/ground/castle
/// pictures (cached, rebuilt on resize or level change), animated torch
/// flames and flag, pixel fonts for all text, and restrained feedback
/// (sparks, poof, hit-stop, short screen shake) over the live camera feed.
///
/// The world renders in virtual 360p-high pixels through [ArenaCamera]; the
/// HUD renders in screen space so it never moves with the world.
class RepelGame extends FlameGame with TapCallbacks {
  /// X position of the castle gate — enemies stop just right of it and attack.
  static const double gateX = 96;

  /// How far past the gate an enemy center stops (sprite presses the wall).
  static const double gateReach = 30;

  static const double introSeconds = 2.2;
  static const double restSeconds = 10;

  /// Castle geometry — local art is built around these, drawn at gateX.
  static const double _castleW = 60;

  /// Fortress level the cached castle pictures were built for; kept in sync
  /// on load and on fortress buys, driving the M7 appearance ladder.
  int _castleFort = 0;

  int get _castleStage => castleStage(_castleFort);

  /// Stage-driven wall height: 82px wooden fort → 122px gold-trimmed keep.
  double get _castleH => castleHeight(_castleStage);

  /// Ground line — a fixed world constant now (the camera, not the device,
  /// decides where it lands on screen).
  static const double groundY = ArenaCamera.virtualHeight - 96;

  final ArenaCamera cam = ArenaCamera();

  late PlayerSave save;

  /// The level being played (also carries palette + enemy mix + pacing).
  LevelDef currentLevel = kLevels.first;

  int wave = 1;
  late int baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
  GamePhase phase = GamePhase.menu;

  /// Counts down: seconds until the next wave auto-starts (the intro banner
  /// itself no longer counts — a pushup or a tap starts the wave, M7).
  double phaseTimer = introSeconds;

  /// Intro banner pop-in / blink clock (intro waits indefinitely now).
  double _introT = 0;

  /// Coin bonus granted by the last level victory (0 on replays).
  int victoryBonus = 0;

  /// Current combo chain (consecutive reps inside the combo window).
  int combo = 0;
  DateTime? _lastRepAt;
  double _autoTimer = 0;

  int _toSpawn = 0;
  double _spawnTimer = 0;
  final _rng = Random();
  double _baseFlash = 0;

  /// Coin/state changes are debounced: persisted at wave clears, level
  /// starts, purchases and app pause — never once per kill.
  bool _saveDirty = false;

  void _markDirty() => _saveDirty = true;

  /// Persists if anything changed since the last write. Called on phase
  /// transitions and by the screen lifecycle (pause/dispose).
  Future<void> saveIfDirty() async {
    if (!_saveDirty) return;
    _saveDirty = false;
    await save.persist();
  }

  // ---- feedback state ------------------------------------------------------
  double _shake = 0; // screen shake amplitude (px, decays)
  double _hitStop = 0; // frozen frames after a kill
  double _time = 0; // always-running clock for ambient animation
  double _emberT = 0.8;

  // ---- cached pictures (rebuilt on resize / level change) ------------------
  ui.Picture? _bgPic;
  ui.Picture? _groundPic;
  ui.Picture? _lipPic;
  ui.Picture? _castlePic;
  ui.Picture? _castleHitPic;

  /// Emitted whenever the shop/HUD-visible state changes.
  final ValueNotifier<GameSnapshot> snapshot = ValueNotifier(const GameSnapshot(
    phase: GamePhase.menu,
    levelId: 1,
    levelName: 'MOSSGATE',
    wave: 1,
    totalWaves: 4,
    coins: 0,
    baseHp: 80,
    maxBaseHp: 80,
    combo: 0,
    restSeconds: 10,
    bestWave: 0,
    unlockedLevel: 1,
    clearedLevel: 0,
    victoryBonus: 0,
    totalReps: 0,
    totalKills: 0,
    bestCombo: 0,
    levels: {},
  ));

  int get _enemiesAlive => children.whereType<Enemy>().length;
  int get enemiesLeft => _toSpawn + _enemiesAlive;

  // ---- Wave configuration: level-scaled prototype balance ----------------
  int enemyCountFor(int w) => min(3 + w, 12);
  int hpFor(int w) => max(1, ((2 + w + w ~/ 3) * currentLevel.hpScale).round());
  double speedFor(int w) =>
      min(30 + w * 2.5, 66.0) * currentLevel.speedScale;
  int damageFor(int w) =>
      max(1, ((3 + w ~/ 2) * currentLevel.damageScale).round());

  /// Deterministic scatter hash — handcrafted-looking, never random per frame.
  static int _hash(int v) {
    var h = v & 0x7fffffff;
    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  /// The GameWidget paints this behind the world on every frame. Flame's
  /// default is opaque black, which covered the CameraPreview layer beneath
  /// the game and hid the player's camera completely (M5 root-cause fix) —
  /// the background must stay clear so the camera feed shows through.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    save = await PlayerSave.load();
    baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
    _castleFort = save.levelOf(UpgradeType.fortress); // M7 tower appearance
    // Resume the campaign where the player left off (menu shows the roster).
    currentLevel = levelById(save.lastLevel);
    if (size.x > 0) _rebuildPictures();
    phase = GamePhase.menu;
    _publish();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // The world occupies the top band; the camera view keeps the rest
    // (portrait M5 layout) — the camera feeds everything below it.
    cam.resize(Vector2(size.x, size.y * kGameZoneFraction));
    _rebuildPictures();
  }

  /// Rebuild the per-level cached pictures (resize or level change).
  void _rebuildPictures() {
    if (size.x <= 0 || size.y <= 0) return;
    final w = cam.worldWidth;
    final pal = currentLevel.palette;
    _bgPic = _buildBackground(w, pal);
    _groundPic = _buildGround(w, pal);
    _lipPic = _buildLip(w, pal);
    _castlePic = _buildCastle(hit: false, pal: pal);
    _castleHitPic = _buildCastle(hit: true, pal: pal);
  }

  /// Enters level [id]: resets the camera/field/state and starts wave 1.
  void startLevel(int id) {
    currentLevel = levelById(id);
    save.lastLevel = currentLevel.id;
    _markDirty();
    saveIfDirty();
    _shake = 0;
    _hitStop = 0;
    _victoryCleanup();
    _rebuildPictures();
    baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
    _startWave(1);
  }

  void _victoryCleanup() {
    for (final e in children.whereType<Enemy>()) {
      e.removeFromParent();
    }
    for (final p in children.whereType<Projectile>()) {
      p.removeFromParent();
    }
    for (final t in children.whereType<FloatingText>()) {
      t.removeFromParent();
    }
    for (final p in children.whereType<PixelParticle>()) {
      p.removeFromParent();
    }
  }

  void _startWave(int w) {
    wave = w;
    baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
    _victoryCleanup();
    _toSpawn = enemyCountFor(w);
    _spawnTimer = 0;
    combo = 0;
    _lastRepAt = null;
    _autoTimer = autoInterval(save.levelOf(UpgradeType.speed));
    phase = GamePhase.intro;
    phaseTimer = introSeconds;
    _introT = 0; // banner animation restarts; no countdown though (M7)
    _publish();
  }

  /// The wave goes live (M7). Reached by a counted pushup (which doubles as
  /// the calibration rep — the counter must see a real range before it can
  /// count anything), a tap on the banner, or an explicit shop "start".
  void _beginFight() {
    phase = GamePhase.fighting;
    _introT = 0;
    _publish();
  }

  /// Called by the pose screen whenever the pushup counter counts a rep.
  /// Outside the fight a pushup does exactly one thing: START THE WAVE —
  /// that's the M7 "start with a pushup" moment, and it is what the player
  /// calibrates against after opening the app or resetting the counter.
  void onRep() {
    if (phase == GamePhase.intro) {
      _beginFight();
    } else if (phase == GamePhase.waveCleared) {
      if (wave >= currentLevel.waves) return; // victory already decided
      _startWave(wave + 1);
      _beginFight();
    }
    // menu / victory / defeat fall through too: pushups pay in EVERY phase
    // (M7 — the currency promise). Combat below no-ops on an empty field.

    // Combo: chain consecutive reps, reset after the upgrade-scaled window.
    final now = DateTime.now();
    final window = comboWindow(save.levelOf(UpgradeType.combo));
    if (_lastRepAt != null &&
        now.difference(_lastRepAt!) >
            Duration(milliseconds: (window * 1000).round())) {
      combo = 0;
    }
    _lastRepAt = now;
    combo++;

    save.totalReps++;
    if (combo > save.bestCombo) save.bestCombo = combo;
    _markDirty();

    // Every pushup pays (M7: pushups are THE currency) — the shop wallet is
    // earned directly from the workout, even with an empty field: idle
    // training still pays.
    final gained = repCoins(combo);
    save.coins += gained;
    add(FloatingText(
      position: Vector2(gateX, groundY - 76),
      text: '+$gained',
      color: kGold,
      coin: true,
    ));

    final damage =
        (repDamage(save.levelOf(UpgradeType.power)) * comboMultiplier(combo))
            .round();

    final enemies = children
        .whereType<Enemy>()
        .where((e) => !e.dead)
        .toList()
      ..sort((a, b) => a.position.x.compareTo(b.position.x));
    if (enemies.isEmpty) {
      _publish(); // combo HUD still updates while the field is empty
      return;
    }

    final target = enemies.first; // most advanced enemy gets hit
    add(Projectile(
      start: Vector2(gateX, groundY - 46),
      target: target.position.clone(),
      small: true, // rep shots are small gold darts (auto shots = blue)
    ));
    target.takeHit(damage);
    _publish();
  }

  void damageBase(int amount) {
    if (baseHp <= 0) return;
    baseHp = max(0, baseHp - amount);
    _baseFlash = 0.15;
    _shake = max(_shake, 4.0);
    spawnSparks(
      Vector2(gateX, groundY - 44),
      const Color(0xFFEF5350),
      count: 4,
      spread: 90,
    );
    if (baseHp == 0) {
      phase = GamePhase.defeat;
      _shake = 8;
      saveIfDirty(); // persist progress at the moment it's at risk
      _publish();
    }
  }

  void enemyKilled(Enemy enemy) {
    // M7: kills pay NOTHING — pushups are the only currency in the game.
    // The kill still counts for stats and keeps its hit-stop for feel.
    save.totalKills++;
    _markDirty(); // persisted at wave clear / level start / app pause
    _hitStop = max(_hitStop, 0.05); // short freeze makes the kill land
    _publish();
  }

  /// Chunky impact sparks in the pixel palette (event-driven, self-removing).
  void spawnSparks(Vector2 pos, Color color, {int count = 5, double spread = 120}) {
    if (!AppSettings.instance.particles) return; // Settings → Particles off
    if (children.length > 320) return; // hard cap keeps spikes bounded
    final light = pixelLighten(color, 0.5);
    for (var i = 0; i < count; i++) {
      final ang = _rng.nextDouble() * pi * 2;
      final sp = spread * (0.5 + _rng.nextDouble());
      add(PixelParticle(
        position: pos.clone(),
        color: i.isEven ? light : color,
        side: 5,
        vel: Vector2(cos(ang) * sp, sin(ang) * sp - 40),
        life: 0.28 + _rng.nextDouble() * 0.2,
        gravity: 420,
      ));
    }
  }

  /// Death poof: a ring of body-colored squares that pops and settles.
  void spawnPoof(Vector2 pos, Color color) {
    if (!AppSettings.instance.particles) return;
    if (children.length > 320) return;
    final light = pixelLighten(color, 0.45);
    for (var i = 0; i < 9; i++) {
      final ang = (i / 9) * pi * 2 + _rng.nextDouble() * 0.6;
      final sp = 55 + _rng.nextDouble() * 75;
      add(PixelParticle(
        position: pos.clone(),
        color: i % 3 == 0 ? kWhite : i % 3 == 1 ? light : color,
        side: i.isEven ? 9.0 : 6.0,
        vel: Vector2(cos(ang) * sp, sin(ang) * sp - 55),
        life: 0.42 + _rng.nextDouble() * 0.3,
        gravity: 300,
      ));
    }
  }

  /// Buys the next level of [t]; returns false when unaffordable/maxed.
  bool buyUpgrade(UpgradeType t) {
    final ok = save.buy(t);
    if (ok && t == UpgradeType.fortress) {
      baseHp = min(baseHp + 25, maxBaseHp(save.levelOf(t)));
      _castleFort = save.levelOf(t);
      _rebuildPictures(); // the tower visibly rebuilds (wood → … → gold)
    }
    if (ok) _publish();
    return ok;
  }

  /// Flutter-facing trigger (shop "start early" button, tap on the rest
  /// banner): an explicit start goes straight into the fight — the pushup
  /// start applies to arriving at a wave from a pause, not to an impatient
  /// tap that already proved readiness.
  void nextWave() {
    if (phase != GamePhase.waveCleared) return;
    if (wave >= currentLevel.waves) return; // final wave ends in victory
    _startWave(wave + 1);
    _beginFight();
  }

  void retryWave() {
    if (phase != GamePhase.defeat) return;
    _startWave(wave);
  }

  /// Back to the level select (progress and coins stay persisted).
  void toMenu() {
    phase = GamePhase.menu;
    saveIfDirty();
    _publish();
  }

  void _publish() {
    snapshot.value = GameSnapshot(
      phase: phase,
      levelId: currentLevel.id,
      levelName: currentLevel.name,
      wave: wave,
      totalWaves: currentLevel.waves,
      coins: save.coins,
      baseHp: baseHp,
      maxBaseHp: maxBaseHp(save.levelOf(UpgradeType.fortress)),
      combo: combo,
      restSeconds: max(0, phaseTimer.ceil()),
      bestWave: save.bestWave,
      unlockedLevel: save.unlockedLevel,
      clearedLevel: save.clearedLevel,
      victoryBonus: victoryBonus,
      totalReps: save.totalReps,
      totalKills: save.totalKills,
      bestCombo: save.bestCombo,
      levels: Map.unmodifiable(save.levels),
    );
  }

  @override
  void update(double dt) {
    // Hit-stop: a few frozen frames after kills make impacts feel physical.
    var step = dt;
    if (_hitStop > 0) {
      _hitStop -= dt;
      step = 0;
    }
    if (_shake > 0) _shake = max(0.0, _shake - dt * 16);
    _time += dt;
    if (_baseFlash > 0) _baseFlash -= step;

    super.update(step);

    // Ambient: a stray ember drifts up off a torch now and then.
    _emberT -= step;
    if (_emberT <= 0 &&
        phase != GamePhase.menu &&
        AppSettings.instance.particles &&
        children.length < 320) {
      _emberT = 0.55 + _rng.nextDouble() * 0.7;
      final left = _rng.nextBool();
      add(PixelParticle(
        position: Vector2(left ? 45 : 91, groundY - 62),
        color: _rng.nextBool() ? kOrange : kGold,
        side: 3,
        vel: Vector2(_rng.nextDouble() * 20 - 10, -26 - _rng.nextDouble() * 26),
        life: 0.6 + _rng.nextDouble() * 0.4,
        gravity: -16,
      ));
    }

    switch (phase) {
      case GamePhase.menu:
        break; // the world idles behind the Flutter menu overlay

      case GamePhase.intro:
        // No auto-countdown (M7): the banner waits for the pushup that
        // starts the wave — this clock only drives the pop-in and blink.
        _introT += step;

      case GamePhase.fighting:
        // Idle element: automatic chip damage on the most advanced enemy.
        _autoTimer -= step;
        if (_autoTimer <= 0) {
          _autoTimer = autoInterval(save.levelOf(UpgradeType.speed));
          final targets = children
              .whereType<Enemy>()
              .where((e) => !e.dead)
                .toList()
              ..sort((a, b) => a.position.x.compareTo(b.position.x));
          if (targets.isNotEmpty) {
            add(Projectile(
              start: Vector2(gateX, groundY - 46),
              target: targets.first.position.clone(),
              auto: true,
            ));
            targets.first.takeHit(autoDamage(save.levelOf(UpgradeType.power)));
          }
        }

        _spawnTimer -= step * 1000;
        if (_toSpawn > 0 && _spawnTimer <= 0) {
          _spawnEnemy();
          _spawnTimer = currentLevel.spawnMs.toDouble();
        }
        if (_toSpawn == 0 && _enemiesAlive == 0) {
          // M7: no wave-clear money — pushups are the only income.
          save.bestWave = max(save.bestWave, wave);
          _markDirty();
          if (wave >= currentLevel.waves) {
            // Level complete: grant the first-clear bonus exactly once.
            victoryBonus = save.grantLevelClear(
                    currentLevel.id, currentLevel.clearBonus)
                ? currentLevel.clearBonus
                : 0;
            phase = GamePhase.victory;
            _shake = max(_shake, 5);
            saveIfDirty();
          } else {
            phase = GamePhase.waveCleared;
            phaseTimer = restSeconds;
            saveIfDirty();
          }
          _publish();
        }

      case GamePhase.waveCleared:
        phaseTimer -= step;
        final s = max(0, phaseTimer.ceil());
        if (s != snapshot.value.restSeconds) _publish();
        // Rest over: enter the next wave's intro, which waits for a pushup
        // (or a tap) — nobody starts fighting while the player is away.
        if (phaseTimer <= 0 && wave < currentLevel.waves) _startWave(wave + 1);

      case GamePhase.victory:
      case GamePhase.defeat:
        break; // Flutter panels drive these transitions
    }
  }

  void _spawnEnemy() {
    final spawnIndex = enemyCountFor(wave) - _toSpawn - 1;
    final isBoss = currentLevel.bossWave != 0 &&
        wave == currentLevel.bossWave &&
        spawnIndex == 0;
    final variant = isBoss
        ? EnemyVariant.boss
        : currentLevel.pickVariant(_rng.nextDouble());
    _toSpawn--;

    final radius = variant.radius;
    final y =
        groundY - radius + (_rng.nextDouble() * 16 - 8); // slight lane jitter
    add(Enemy(
      maxHp: (hpFor(wave) * variant.hpMult).round(),
      speed: speedFor(wave) * variant.speedMult,
      baseDamage: (damageFor(wave) * variant.damageMult).round(),
      variant: variant,
      color: currentLevel.palette.hueOf(variant),
      spawnPosition: Vector2(cam.worldWidth + 70, y),
    ));
  }

  @override
  void onTapUp(TapUpEvent event) {
    // Taps on the shop/banner UI are consumed by Flutter widgets on top;
    // these are fallbacks for taps on empty areas.
    if (phase == GamePhase.defeat) {
      retryWave();
    } else if (phase == GamePhase.intro) {
      _beginFight(); // fallback start when no camera/rep is available (M7)
    } else if (phase == GamePhase.waveCleared) {
      nextWave();
    }
  }

  // ------------------------------ rendering ------------------------------

  late final TextPaint _bannerPaint = TextPaint(
    style: const TextStyle(
      fontFamily: kPixelFont,
      fontSize: 32,
      color: kWhite,
      shadows: [Shadow(color: kInk, offset: Offset(2, 2), blurRadius: 0)],
    ),
  );
  late final TextPaint _subPaint = TextPaint(
    style: const TextStyle(
      fontFamily: kPixelFont,
      fontSize: 12,
      color: Color(0xFFFFC46B),
      shadows: [Shadow(color: kInk, offset: Offset(1, 1), blurRadius: 0)],
    ),
  );
  late final TextPaint _hudPaint = TextPaint(
    style: const TextStyle(
      fontFamily: kPixelFont,
      fontSize: 10,
      color: kWhite,
      shadows: [Shadow(color: kInk, offset: Offset(1, 1), blurRadius: 0)],
    ),
  );

  @override
  void render(Canvas canvas) {
    // Short, integer-pixel screen shake — applied to the world transform
    // only; the HUD below renders outside it and stays put. Gated by
    // Settings → Screen shake.
    var sx = 0.0, sy = 0.0;
    if (_shake > 0 && AppSettings.instance.screenShake) {
      sx = ((_rng.nextDouble() * 2 - 1) * _shake).roundToDouble();
      sy = ((_rng.nextDouble() * 2 - 1) * _shake).roundToDouble();
    }
    canvas.save();
    canvas.translate(sx, sy);

    // World: virtual-resolution camera transform (fixed arena — the camera
    // maps world pixels to the screen, it never moves or follows).
    cam.beginWorld(canvas);
    if (_bgPic != null) canvas.drawPicture(_bgPic!);
    _renderTwinkle(canvas);
    if (_groundPic != null) canvas.drawPicture(_groundPic!);
    super.render(canvas); // enemies, tracers, particles, numbers
    if (_lipPic != null) canvas.drawPicture(_lipPic!); // grass in front of feet
    _renderBase(canvas);
    cam.endWorld(canvas);

    canvas.restore();

    // Screen space: letterbox margins (ultra-wide only) + fixed HUD.
    cam.paintLetterbox(canvas, size);
    _renderHud(canvas);
    _renderBanners(canvas);
  }

  // -- background: atmosphere wash + stars + hills + moon (built per level) --

  ui.Picture _buildBackground(double w, LevelPalette pal) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;

    // Atmosphere wash over the whole world (camera ghosts through).
    p.color = pal.wash;
    c.drawRect(Rect.fromLTWH(0, 0, w, ArenaCamera.virtualHeight), p);

    // Star field — deterministic dots above the hills; every biome reads
    // as dusk/night, so the sky always has depth.
    for (var i = 0; i < 34; i++) {
      final h = _hash(i * 97 + 31);
      final sx = (h % (w - 12).floor()).floorToDouble() + 6;
      final sy = 10 + (h ~/ 7) % (groundY - 140).clamp(40, 150);
      final bright = h % 5 == 0;
      p.color = kWhite.withValues(alpha: bright ? 0.85 : 0.30 + (h % 3) * 0.15);
      final s = bright ? 2.0 : 1.0;
      c.drawRect(Rect.fromLTWH(sx, sy.toDouble(), s, s), p);
    }

    // Moon/sun: flag-tinted pixel disc, fixed spot, 2-frame-free.
    final mx = (w * 0.62).floorToDouble();
    p.color = pal.flag.withValues(alpha: 0.35);
    c.drawRect(Rect.fromLTWH(mx + 4, 44, 12, 4), p);
    c.drawRect(Rect.fromLTWH(mx, 48, 20, 12), p);
    c.drawRect(Rect.fromLTWH(mx + 4, 60, 12, 4), p);
    p.color = pal.flag.withValues(alpha: 0.18);
    c.drawRect(Rect.fromLTWH(mx + 2, 50, 5, 5), p); // crater nick

    // Distant hill silhouettes — chunky deterministic bumps on the horizon.
    p.color = pal.hill;
    for (var gx = -20.0; gx < w + 40; gx += 44) {
      final h = _hash(gx.round() * 13 + 7);
      final hh = 18.0 + (h % 40); // 18–57 px tall
      final hw = 30.0 + (h ~/ 3) % 26;
      c.drawRect(Rect.fromLTWH(gx, groundY - hh, hw, hh), p);
      if (h % 3 == 0) {
        c.drawRect(Rect.fromLTWH(gx + 6, groundY - hh - 6, hw - 14, 6), p);
      }
    }
    return rec.endRecording();
  }

  /// A handful of bright stars blink in whole frames (no fades) — the sky
  /// reads alive without any per-frame allocation.
  void _renderTwinkle(Canvas canvas) {
    final w = cam.worldWidth;
    final p = Paint()..isAntiAlias = false;
    final flip = (_time * 2).floor() & 1;
    for (var i = 0; i < 5; i++) {
      final on = ((flip + i) & 1) == 0;
      p.color = kWhite.withValues(alpha: on ? 0.9 : 0.25);
      final sx = w * (0.12 + 0.19 * i);
      final sy = 16.0 + (i * 43) % 80;
      canvas.drawRect(Rect.fromLTWH(sx.roundToDouble(), sy, 2, 2), p);
    }
  }

  // -- ground (built once per size + level) --------------------------------

  ui.Picture _buildGround(double w, LevelPalette pal) {
    const bandH = 96.0;
    const soilY = 44.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;

    // Base — semi-translucent so the camera ghosts through as living
    // texture instead of a flat black bar.
    p.color = pal.band;
    c.drawRect(Rect.fromLTWH(0, 0, w, bandH), p);
    // Deeper soil stratum.
    p.color = pal.soil;
    c.drawRect(Rect.fromLTWH(0, soilY, w, bandH - soilY), p);

    // Deterministic hand-scattered texture: pebbles, tufts of moss, cracks,
    // and little blossoms (stem + 2px head in the biome's flag hue).
    for (var gx = 0; gx < w + 12; gx += 12) {
      final h = _hash(gx * 7 + 11);
      if (h % 5 <= 1) {
        final px = (gx + h % 11).toDouble();
        final py = (soilY + 6 + (h ~/ 3) % 44).toDouble();
        p.color = pal.pebble;
        c.drawRect(Rect.fromLTWH(px, py, 6, 3), p);
        p.color = pal.pebbleLight;
        c.drawRect(Rect.fromLTWH(px, py, 3, 1), p);
      } else if (h % 5 == 2) {
        final sx = (gx + h % 9).toDouble();
        final sy = (8 + (h ~/ 5) % 76).toDouble();
        p.color = pal.moss;
        c.drawRect(Rect.fromLTWH(sx, sy, 4, 4), p);
      } else if (h % 7 == 3) {
        final cx = (gx + h % 5).toDouble();
        p.color = pal.crack;
        c.drawRect(Rect.fromLTWH(cx, soilY + 4, 2, 26), p);
      } else if (h % 13 == 5) {
        // Blossom: 1px stem, 3px head — flag hue, pink or warm white.
        final fx = (gx + h % 7).toDouble();
        final fy = (3 + (h ~/ 9) % 30).toDouble();
        p.color = pal.lipDark;
        c.drawRect(Rect.fromLTWH(fx, fy + 2, 1, 5), p);
        p.color = h % 26 == 5
            ? pal.flag
            : h % 39 == 5
                ? kPink
                : kWhite;
        c.drawRect(Rect.fromLTWH(fx - 1, fy, 3, 2), p);
      }
    }
    return rec.endRecording();
  }

  /// The lit grass lip — drawn *after* characters so they stand in the grass.
  ui.Picture _buildLip(double w, LevelPalette pal) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    p.color = pal.lip;
    c.drawRect(Rect.fromLTWH(0, 0, w, 3), p);
    p.color = pal.lipDark;
    c.drawRect(Rect.fromLTWH(0, 3, w, 2), p);
    for (var gx = 0; gx < w + 8; gx += 12) {
      final h = _hash(gx * 3 + 5);
      if (h % 5 == 0 || h % 7 == 3) {
        final bx = (gx + h % 7).toDouble();
        p.color = pal.lipBlade;
        c.drawRect(Rect.fromLTWH(bx, -5, 3, 7), p);
        if (h % 3 == 0) {
          p.color = pal.lipBladeLight;
          c.drawRect(Rect.fromLTWH(bx, -5, 1, 4), p);
        }
      }
    }
    return rec.endRecording();
  }

  // -- castle (built per level + fortress stage; hit = brightened flash) -----

  ui.Picture _buildCastle({required bool hit, required LevelPalette pal}) {
    Color tone(Color c) => hit ? pixelLighten(c, 0.72) : c;
    final stage = _castleStage;
    final h = _castleH;
    final mortar = pal.mortar;
    final outline = pal.outline;
    final chip = pal.chip;

    // M7 appearance ladder material tones: wood → biome stone → steel → gold.
    const woodA = Color(0xFF6D4C43), woodB = Color(0xFF5D4037);
    const woodDark = Color(0xFF4E342E), woodLight = Color(0xFF8D6E63);
    const woodLash = Color(0xFFA1887F), woodBack = Color(0xFF332418);
    const woodOutline = Color(0xFF2C1F16);
    const steel = Color(0xFF607D8B), steelDark = Color(0xFF455A64);
    const steelLight = Color(0xFF90A4AE), steelOutline = Color(0xFF263238);
    const gold = Color(0xFFFFD54F), goldDark = Color(0xFFFFB300);

    final isWood = stage <= 1;
    final isSteel = stage >= 4;
    final edge = isWood ? woodOutline : isSteel ? steelOutline : outline;

    Color stone(int hh) {
      final m = hh % 10;
      if (m == 0 || m == 1) return pal.stoneDark;
      if (m == 2) return pal.stoneLight;
      return pal.stone;
    }

    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    const w = _castleW;
    const bodyTop = 14.0;
    final bodyBottom = h;

    if (isWood) {
      // Stage 0-1: the small wooden fort — a lashed log stockade (stage 1
      // set into a stone footing). Sharpened tips crown the logs.
      final woodBottom = stage == 1 ? bodyBottom - 34 : bodyBottom;
      p.color = tone(woodBack); // dark backing between the logs
      c.drawRect(Rect.fromLTWH(0, bodyTop, w, woodBottom - bodyTop), p);
      for (var x = 0.0; x < w; x += 7) {
        final even = (x ~/ 7).isEven;
        p.color = tone(even ? woodA : woodB);
        c.drawRect(Rect.fromLTWH(x, bodyTop, 6, woodBottom - bodyTop), p);
        p.color = tone(even ? woodLight : woodA); // lit left edge
        c.drawRect(Rect.fromLTWH(x, bodyTop, 1, woodBottom - bodyTop), p);
        p.color = tone(woodLight); // sharpened tip
        c.drawRect(Rect.fromLTWH(x + 1, bodyTop - 4, 4, 2), p);
        c.drawRect(Rect.fromLTWH(x + 2, bodyTop - 6, 2, 2), p);
      }
      // Rope lashings binding the stockade in two courses.
      for (final ly in [bodyTop + 24, woodBottom - 20]) {
        p.color = tone(woodLash);
        c.drawRect(Rect.fromLTWH(0, ly, w, 3), p);
        p.color = tone(woodDark);
        c.drawRect(Rect.fromLTWH(0, ly + 3, w, 1), p);
      }
      if (stage == 1) {
        // Stone footing the logs are set into (brick courses, clipped short).
        p.color = tone(mortar);
        c.drawRect(Rect.fromLTWH(0, woodBottom, w, bodyBottom - woodBottom), p);
        var row = 0;
        for (var y = woodBottom; y < bodyBottom; y += 11, row++) {
          final bh = min(11.0, bodyBottom - y);
          final off = row.isEven ? 0.0 : 7.5;
          for (var x = -off; x < w; x += 15) {
            final left = max(0.0, x);
            final right = min(w, x + 15);
            final bw = right - left - 1;
            if (bw <= 0) continue;
            p.color = tone(stone(_hash(x.round() * 31 ^ y.round() * 17)));
            c.drawRect(Rect.fromLTWH(left, y, bw, bh - 1), p);
          }
        }
      }
    } else {
      // Stage 2+: stone brick courses with alternating offset — the wall
      // the campaign shipped with, wearing iron/steel/gold at higher stages.
      p.color = tone(mortar);
      c.drawRect(Rect.fromLTWH(0, bodyTop, w, bodyBottom - bodyTop), p);
      var row = 0;
      for (var y = bodyTop; y < bodyBottom; y += 11, row++) {
        final bh = min(11.0, bodyBottom - y);
        final off = row.isEven ? 0.0 : 7.5;
        for (var x = -off; x < w; x += 15) {
          final left = max(0.0, x);
          final right = min(w, x + 15);
          final bw = right - left - 1;
          if (bw <= 0) continue;
          final hh = _hash(x.round() * 31 ^ y.round() * 17);
          p.color = tone(stone(hh));
          c.drawRect(Rect.fromLTWH(left, y, bw, bh - 1), p);
          if (hh % 11 == 0) {
            p.color = tone(chip);
            c.drawRect(Rect.fromLTWH(left, y, min(6.0, bw), 2), p);
          }
          if (hh % 17 == 0) {
            p.color = tone(mortar);
            c.drawRect(Rect.fromLTWH(left + bw - 3, y + 3, 2, 5), p);
          }
        }
      }

      if (stage <= 3) {
        // Weathering: moss clings to the mortar lines, and a watch light
        // burns behind an arrow slit — stone castles feel inhabited.
        for (var i = 0; i < 9; i++) {
          final hh = _hash(i * 53 + 29);
          final mx = (2 + hh % (w - 8)).toDouble();
          final my = (bodyTop + 8 + (hh ~/ 5) % (bodyBottom - bodyTop - 20))
              .toDouble();
          p.color = tone(pal.moss);
          c.drawRect(Rect.fromLTWH(mx, my, 3, 2), p);
          if (hh % 3 == 0) {
            p.color = tone(pal.pebble);
            c.drawRect(Rect.fromLTWH(mx + 1, my - 2, 1, 2), p);
          }
        }
        // Arrow slit with a warm watch light behind it (upper right of body).
        p.color = tone(outline);
        c.drawRect(Rect.fromLTWH(44, 24, 6, 13), p);
        p.color = tone(kAmber);
        c.drawRect(Rect.fromLTWH(45, 25, 4, 11), p);
        p.color = tone(pixelShade(kAmber, 0.55));
        c.drawRect(Rect.fromLTWH(47, 27, 2, 7), p); // slit shadow
      }

      if (stage >= 4) {
        // Riveted steel plates sheath the upper wall (iron plate → gold).
        final plateBottom = bodyTop + (bodyBottom - bodyTop) * 0.62;
        var prow = 0;
        for (var y = bodyTop; y < plateBottom; y += 13, prow++) {
          final ph = min(13.0, plateBottom - y);
          final off = prow.isEven ? 0.0 : 9.0;
          for (var x = -off; x < w; x += 18) {
            final left = max(0.0, x);
            final right = min(w, x + 18);
            final pw = right - left - 1;
            if (pw <= 0) continue;
            final hh = _hash(x.round() * 13 ^ y.round() * 7);
            p.color = tone(
                hh % 7 == 0 ? steelLight : hh % 5 == 0 ? steelDark : steel);
            c.drawRect(Rect.fromLTWH(left, y, pw, ph - 1), p);
            p.color = tone(steelLight);
            c.drawRect(Rect.fromLTWH(left + 2, y + 2, 2, 2), p); // rivets
            if (pw > 12) {
              c.drawRect(Rect.fromLTWH(right - 5, y + 2, 2, 2), p);
            }
          }
        }
        p.color = tone(steelOutline); // seam where plate meets stone
        c.drawRect(Rect.fromLTWH(0, plateBottom - 1, w, 2), p);
      }

      if (stage >= 3) {
        // Iron bands bolted across the wall (gold-riveted at stage 5).
        for (final by
            in [bodyTop + 16.0, bodyTop + (bodyBottom - bodyTop) * 0.66]) {
          p.color = tone(isSteel ? steelDark : const Color(0xFF37474F));
          c.drawRect(Rect.fromLTWH(0, by, w, 5), p);
          p.color = tone(isSteel ? steelLight : const Color(0xFF546E7A));
          c.drawRect(Rect.fromLTWH(0, by, w, 1), p);
          for (var rx = 3.0; rx < w - 3; rx += 9) {
            p.color = tone(stage >= 5 ? gold : steelLight);
            c.drawRect(Rect.fromLTWH(rx, by + 2, 2, 2), p);
          }
        }
      }
    }

    // Merlons — wood, biome stone or steel caps (gold-capped at stage 5).
    for (var i = 0; i < 3; i++) {
      final mx = i * 22.0;
      p.color = tone(isWood
          ? (i.isEven ? woodA : woodB)
          : isSteel
              ? steel
              : stone(_hash(i * 7 + 3)));
      c.drawRect(Rect.fromLTWH(mx, 0, 14, 14), p);
      if (stage >= 5) {
        p.color = tone(gold); // gold crown on every merlon
        c.drawRect(Rect.fromLTWH(mx, 0, 14, 3), p);
        p.color = tone(goldDark);
        c.drawRect(Rect.fromLTWH(mx, 3, 14, 1), p);
      }
      p.color = tone(isWood ? woodOutline : isSteel ? steelOutline : outline);
      c.drawRect(Rect.fromLTWH(mx, 0, 14, 1), p);
      c.drawRect(Rect.fromLTWH(mx, 0, 1, 14), p);
      c.drawRect(Rect.fromLTWH(mx + 13, 0, 1, 14), p);
    }

    // Wall outline (readability over the camera feed).
    p.color = tone(edge);
    c.drawRect(Rect.fromLTWH(0, 0, 1, h), p);
    c.drawRect(Rect.fromLTWH(w - 1, 0, 1, h), p);
    c.drawRect(Rect.fromLTWH(0, h - 1, w, 1), p);

    // Gate: frame, planks, pixel arch corners, bands + rivets — always
    // bottom-aligned (gate top = h − 36), so enemies and projectiles aim at
    // a fixed line no matter how tall the tower grows.
    final gateTop = h - 36;
    p.color = tone(edge);
    c.drawRect(Rect.fromLTWH(14, gateTop, 32, 36), p);
    for (var i = 0; i < 4; i++) {
      p.color = tone(isSteel
          ? (i.isEven ? steel : steelDark)
          : isWood
              ? (i.isEven ? woodDark : woodBack)
              : (i.isEven ? const Color(0xFF5D4037) : const Color(0xFF4E342E)));
      c.drawRect(Rect.fromLTWH(16 + i * 7, gateTop + 2, 7, 34), p);
    }
    p.color = tone(
        isWood ? woodOutline : isSteel ? steelOutline : const Color(0xFF3E2723));
    for (final sx in [22.0, 29.0, 36.0]) {
      c.drawRect(Rect.fromLTWH(sx, gateTop + 2, 1, 34), p);
    }
    p.color = tone(isWood ? woodBack : mortar); // arch corners knocked out
    c.drawRect(Rect.fromLTWH(16, gateTop + 2, 4, 4), p);
    c.drawRect(Rect.fromLTWH(40, gateTop + 2, 4, 4), p);
    p.color = tone(isSteel ? steelDark : pal.stoneDark); // cross bands
    c.drawRect(Rect.fromLTWH(16, gateTop + 10, 28, 3), p);
    c.drawRect(Rect.fromLTWH(16, gateTop + 26, 28, 3), p);
    p.color = tone(stage >= 5 ? gold : isSteel ? steelLight : pal.stoneLight);
    for (final rx in [20.0, 30.0, 40.0]) {
      c.drawRect(Rect.fromLTWH(rx, gateTop + 10, 2, 2), p); // band rivets
      c.drawRect(Rect.fromLTWH(rx, gateTop + 26, 2, 2), p);
    }
    c.drawRect(Rect.fromLTWH(33, gateTop + 17, 3, 5), p); // handle

    // Torch brackets flanking the gate (bottom-relative: any wall height).
    p.color = tone(isWood ? woodDark : isSteel ? steelDark : pal.stoneDark);
    c.drawRect(Rect.fromLTWH(4, h - 46, 5, 8), p);
    c.drawRect(Rect.fromLTWH(50, h - 46, 5, 8), p);
    p.color = tone(isWood ? woodLash : mortar);
    c.drawRect(Rect.fromLTWH(5, h - 46, 3, 2), p);
    c.drawRect(Rect.fromLTWH(51, h - 46, 3, 2), p);

    return rec.endRecording();
  }

  // -- base: picture + torch flames + flag + HP bar --------------------------

  void _renderBase(Canvas canvas) {
    final pic = _baseFlash > 0 ? _castleHitPic : _castlePic;
    if (pic != null) {
      canvas.save();
      canvas.translate(gateX - _castleW, groundY - _castleH);
      canvas.drawPicture(pic);
      canvas.restore();
    }

    // Torch flames — two frames at different rates so they never sync up.
    final f1 = (_time * 7).floor() & 1;
    final f2 = (_time * 9 + 2).floor() & 1;
    drawSprite(
      canvas,
      f1 == 0 ? flameA : flameB,
      x: gateX - _castleW + 4,
      y: groundY - 60,
      scale: 2,
      palette: flamePalette,
    );
    drawSprite(
      canvas,
      f2 == 0 ? flameA : flameB,
      x: gateX - _castleW + 50,
      y: groundY - 60,
      scale: 2,
      palette: flamePalette,
    );

    _renderFlag(canvas);

    // Base HP — segmented pixel bar, discrete color steps.
    final ratio =
        (baseHp / maxBaseHp(save.levelOf(UpgradeType.fortress))).clamp(0.0, 1.0);
    final fg = ratio > 0.55 ? kGreen : ratio > 0.25 ? kGold : kRed;
    drawPixelBar(
      canvas,
      x: gateX - _castleW - 6,
      y: groundY - _castleH - 14,
      w: _castleW + 12,
      h: 10,
      ratio: ratio,
      fg: fg,
      cell: 8,
      borderW: 2,
    );
  }

  /// Banner on the middle merlon — 2-frame cloth flutter, irregular cadence.
  void _renderFlag(Canvas canvas) {
    final x = gateX - _castleW + 28;
    final top = groundY - _castleH - 28;
    final p = Paint()..isAntiAlias = false;

    p.color = currentLevel.palette.stoneDark;
    canvas.drawRect(Rect.fromLTWH(x, top, 2, 28), p);
    p.color = currentLevel.palette.stoneLight;
    canvas.drawRect(Rect.fromLTWH(x, top, 2, 3), p);

    final bucket = (_time * 1.6).floor();
    final f = (bucket ^ (bucket >> 2)) & 1; // mostly alternates, occasional hold
    p.color = currentLevel.palette.flag;
    if (f == 0) {
      canvas.drawRect(Rect.fromLTWH(x + 2, top + 2, 10, 11), p);
      p.color = kInk;
      canvas.drawRect(Rect.fromLTWH(x + 5, top + 6, 4, 4), p);
    } else {
      canvas.drawRect(Rect.fromLTWH(x + 2, top + 2, 10, 8), p);
      canvas.drawRect(Rect.fromLTWH(x + 2, top + 10, 6, 3), p);
      p.color = kInk;
      canvas.drawRect(Rect.fromLTWH(x + 5, top + 4, 4, 3), p);
    }
  }

  // -- HUD (pixel font, hard 1px shadows, right-aligned column) --------------

  void _renderHud(Canvas canvas) {
    _hudPaint.render(
      canvas,
      'WAVE $wave/${currentLevel.waves}',
      Vector2(size.x - 16, 14),
      anchor: Anchor.topRight,
    );
    _hudPaint.render(
      canvas,
      '$enemiesLeft LEFT',
      Vector2(size.x - 16, 36),
      anchor: Anchor.topRight,
    );

    final coinText = '${save.coins} PUSHUPS';
    final cw = (coinText.length * 10).toDouble(); // pixel font: 1em advance
    drawSprite(
      canvas,
      coinSprite,
      x: size.x - 16 - cw - 17,
      y: 56,
      scale: 2,
      palette: coinPalette,
    );
    _hudPaint.render(
      canvas,
      coinText,
      Vector2(size.x - 16, 58),
      anchor: Anchor.topRight,
    );
    // Combo lives in the Flutter rep panel (pixel meter + pop) since M5.1.
  }

  // -- banners (intro pop-in; later phases are covered by Flutter panels) ----

  void _renderBanners(Canvas canvas) {
    switch (phase) {
      case GamePhase.intro:
        // Centered inside the game zone, never drifting into the camera band.
        final center = Vector2(size.x / 2, cam.zoneHeight * 0.5);
        final step = (_introT * 9).floor().clamp(0, 2);
        final label = 'WAVE $wave';
        if (step >= 2) {
          _bannerPaint.render(canvas, label, center, anchor: Anchor.center);
        } else {
          final s = step == 0 ? 2.0 : 1.5;
          canvas.save();
          canvas.translate(center.x, center.y);
          canvas.scale(s, s);
          _bannerPaint.render(canvas, label, Vector2.zero(),
              anchor: Anchor.center);
          canvas.restore();
        }
        // M7: the pushup that starts the wave doubles as calibration — blink
        // the instruction until one counts (or the banner gets tapped).
        if (_introT > 0.4 && (_introT * 2).floor().isEven) {
          _subPaint.render(canvas, 'DO A PUSHUP TO START',
              center + Vector2(0, 46), anchor: Anchor.center);
        }
        // Wave 1 doubles as the level intro — name the biome; after a longer
        // wait, reveal the tap fallback instead.
        final sub = _introT > 4
            ? 'OR TAP TO START'
            : wave == 1
                ? currentLevel.name
                : 'GET READY';
        _subPaint.render(canvas, sub, center + Vector2(0, 66),
            anchor: Anchor.center);

      case GamePhase.menu:
      case GamePhase.fighting:
      case GamePhase.victory:
      case GamePhase.waveCleared:
      case GamePhase.defeat:
        break; // Flutter panels cover these phases
    }
  }
}
