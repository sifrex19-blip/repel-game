import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'economy.dart';
import 'enemy.dart';
import 'pixel_art.dart';

enum GamePhase { intro, fighting, waveCleared, defeat }

/// Immutable snapshot the Flutter side (HUD/shop) listens to.
class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.wave,
    required this.coins,
    required this.baseHp,
    required this.maxBaseHp,
    required this.combo,
    required this.restSeconds,
    required this.bestWave,
    required this.levels,
  });

  final GamePhase phase;
  final int wave;
  final int coins;
  final int baseHp;
  final int maxBaseHp;
  final int combo;
  final int restSeconds;
  final int bestWave;
  final Map<UpgradeType, int> levels;
}

/// The combat game: waves of monsters march at your castle, every counted
/// pushup deals damage, kills drop coins, coins buy upgrades between waves.
///
/// Rendering is pixel art throughout: hand-built ground/castle pictures
/// (cached, rebuilt only on resize), animated torch flames and flag, pixel
/// fonts for all text, and restrained feedback (sparks, poof, hit-stop,
/// short screen shake) over the live camera feed.
class RepelGame extends FlameGame with TapCallbacks {
  /// X position of the castle gate — enemies stop just right of it and attack.
  static const double gateX = 96;

  /// How far past the gate an enemy center stops (sprite presses the wall).
  static const double gateReach = 30;

  static const double introSeconds = 2.2;
  static const double restSeconds = 10;

  /// Castle geometry — local art is built around these, drawn at gateX.
  static const double _castleW = 60;
  static const double _castleH = 100; // merlons (14) + body (86)

  late PlayerSave save;

  int wave = 1;
  late int baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
  GamePhase phase = GamePhase.intro;

  /// Counts down: intro "get ready" time, or seconds until the next wave.
  double phaseTimer = introSeconds;

  /// Current combo chain (consecutive reps inside the combo window).
  int combo = 0;
  DateTime? _lastRepAt;
  double _autoTimer = 0;

  int _toSpawn = 0;
  double _spawnTimer = 0;
  final _rng = Random();
  double _baseFlash = 0;

  // ---- feedback state ------------------------------------------------------
  double _shake = 0; // screen shake amplitude (px, decays)
  double _hitStop = 0; // frozen frames after a kill
  double _comboPop = 0; // combo HUD pop animation clock
  double _time = 0; // always-running clock for ambient animation
  double _emberT = 0.8;

  // ---- cached pictures (rebuilt on resize) ---------------------------------
  ui.Picture? _groundPic;
  ui.Picture? _lipPic;
  ui.Picture? _castlePic;
  ui.Picture? _castleHitPic;

  /// Emitted whenever the shop/HUD-visible state changes.
  final ValueNotifier<GameSnapshot> snapshot = ValueNotifier(const GameSnapshot(
    phase: GamePhase.intro,
    wave: 1,
    coins: 0,
    baseHp: 80,
    maxBaseHp: 80,
    combo: 0,
    restSeconds: 10,
    bestWave: 0,
    levels: {},
  ));

  /// Ground line — enemies and castle stand on it.
  double get groundY => size.y - 96;

  int get _enemiesAlive => children.whereType<Enemy>().length;
  int get enemiesLeft => _toSpawn + _enemiesAlive;

  // ---- Wave configuration (prototype balance — tune after playtest) ----
  int enemyCountFor(int w) => min(3 + w, 12);
  int hpFor(int w) => 2 + w + (w ~/ 3);
  double speedFor(int w) => min(30 + w * 2.5, 66.0);
  int damageFor(int w) => 3 + w ~/ 2;

  /// Deterministic scatter hash — handcrafted-looking, never random per frame.
  static int _hash(int v) {
    var h = v & 0x7fffffff;
    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  @override
  Future<void> onLoad() async {
    save = await PlayerSave.load();
    baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
    startWave(1);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _groundPic = _buildGround(size.x);
    _lipPic = _buildLip(size.x);
    _castlePic = _buildCastle(hit: false);
    _castleHitPic = _buildCastle(hit: true);
  }

  void startWave(int w) {
    wave = w;
    baseHp = maxBaseHp(save.levelOf(UpgradeType.fortress));
    for (final e in children.whereType<Enemy>()) {
      e.removeFromParent();
    }
    for (final p in children.whereType<Projectile>()) {
      p.removeFromParent();
    }
    _toSpawn = enemyCountFor(w);
    _spawnTimer = 0;
    combo = 0;
    _autoTimer = autoInterval(save.levelOf(UpgradeType.speed));
    phase = GamePhase.intro;
    phaseTimer = introSeconds;
    _publish();
  }

  /// Called by the pose screen whenever the pushup counter counts a rep.
  void onRep() {
    if (phase != GamePhase.fighting) return;

    // Combo: chain consecutive reps, reset after the upgrade-scaled window.
    final now = DateTime.now();
    final window = comboWindow(save.levelOf(UpgradeType.combo));
    if (_lastRepAt != null &&
        now.difference(_lastRepAt!) > Duration(milliseconds: (window * 1000).round())) {
      combo = 0;
    }
    _lastRepAt = now;
    combo++;
    _comboPop = 0.18; // HUD pop on every new combo step

    final damage =
        (repDamage(save.levelOf(UpgradeType.power)) * comboMultiplier(combo))
            .round();

    final enemies = children
        .whereType<Enemy>()
        .where((e) => !e.dead)
        .toList()
      ..sort((a, b) => a.position.x.compareTo(b.position.x));
    if (enemies.isEmpty) return;

    final target = enemies.first; // most advanced enemy gets hit
    add(Projectile(
      start: Vector2(gateX, groundY - 46),
      target: target.position.clone(),
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
      _publish();
    }
  }

  void enemyKilled(Enemy enemy) {
    final drop = killCoins(wave, boss: enemy.isBoss);
    save.coins += drop;
    save.persist();
    _hitStop = max(_hitStop, 0.05); // short freeze makes the kill land
    add(FloatingText(
      position: enemy.position + Vector2(0, -30),
      text: '+$drop',
      color: kGold,
      coin: true,
    ));
    _publish();
  }

  /// Chunky impact sparks in the pixel palette (event-driven, self-removing).
  void spawnSparks(Vector2 pos, Color color, {int count = 5, double spread = 120}) {
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
    }
    if (ok) _publish();
    return ok;
  }

  /// Flutter-facing triggers (shop buttons / taps on banners).
  void nextWave() => startWave(wave + 1);
  void retryWave() => startWave(wave);

  void _publish() {
    snapshot.value = GameSnapshot(
      phase: phase,
      wave: wave,
      coins: save.coins,
      baseHp: baseHp,
      maxBaseHp: maxBaseHp(save.levelOf(UpgradeType.fortress)),
      combo: combo,
      restSeconds: max(0, phaseTimer.ceil()),
      bestWave: save.bestWave,
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
    if (_comboPop > 0) _comboPop = max(0.0, _comboPop - dt);
    _time += dt;
    if (_baseFlash > 0) _baseFlash -= step;

    super.update(step);

    // Ambient: a stray ember drifts up off a torch now and then.
    _emberT -= step;
    if (_emberT <= 0) {
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
      case GamePhase.intro:
        phaseTimer -= step;
        if (phaseTimer <= 0) phase = GamePhase.fighting;

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

        _spawnTimer -= step;
        if (_toSpawn > 0 && _spawnTimer <= 0) {
          _spawnEnemy();
          _spawnTimer = 2.2;
        }
        if (_toSpawn == 0 && _enemiesAlive == 0) {
          phase = GamePhase.waveCleared;
          phaseTimer = restSeconds;
          save.coins += waveClearCoins(wave);
          save.bestWave = max(save.bestWave, wave);
          save.persist();
          _publish();
        }

      case GamePhase.waveCleared:
        phaseTimer -= step;
        final s = max(0, phaseTimer.ceil());
        if (s != snapshot.value.restSeconds) _publish();
        if (phaseTimer <= 0) nextWave();

      case GamePhase.defeat:
        break;
    }
  }

  void _spawnEnemy() {
    final spawnIndex = enemyCountFor(wave) - _toSpawn - 1;
    final isBoss = wave % 5 == 0 && spawnIndex == 0;
    _toSpawn--;

    final radius = isBoss ? 44.0 : 24.0;
    final y =
        groundY - radius + (_rng.nextDouble() * 16 - 8); // slight lane jitter
    add(Enemy(
      maxHp: hpFor(wave) * (isBoss ? 4 : 1),
      speed: speedFor(wave) * (isBoss ? 0.75 : 1),
      baseDamage: damageFor(wave),
      isBoss: isBoss,
      spawnPosition: Vector2(size.x + 70, y),
    ));
  }

  @override
  void onTapUp(TapUpEvent event) {
    // Taps on the shop/banner UI are consumed by Flutter widgets on top;
    // these are fallbacks for taps on empty areas.
    if (phase == GamePhase.defeat) {
      retryWave();
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

  TextPaint _comboStyle(Color c) => TextPaint(
        style: TextStyle(
          fontFamily: kPixelFont,
          fontSize: 10,
          color: c,
          shadows: const [Shadow(color: kInk, offset: Offset(1, 1), blurRadius: 0)],
        ),
      );

  late final TextPaint _comboW = _comboStyle(kWhite);
  late final TextPaint _comboG = _comboStyle(kGold);
  late final TextPaint _comboO = _comboStyle(const Color(0xFFFF6B4A));

  @override
  void render(Canvas canvas) {
    // Short, integer-pixel screen shake — world shakes, HUD stays readable.
    var sx = 0.0, sy = 0.0;
    if (_shake > 0) {
      sx = ((_rng.nextDouble() * 2 - 1) * _shake).roundToDouble();
      sy = ((_rng.nextDouble() * 2 - 1) * _shake).roundToDouble();
    }
    canvas.save();
    canvas.translate(sx, sy);

    if (_groundPic != null) canvas.drawPicture(_groundPic!);
    super.render(canvas); // enemies, tracers, particles, numbers
    if (_lipPic != null) canvas.drawPicture(_lipPic!); // grass in front of feet
    _renderBase(canvas);

    canvas.restore();

    _renderHud(canvas);
    _renderBanners(canvas);
  }

  // -- ground (built once per size) -----------------------------------------

  ui.Picture _buildGround(double w) {
    const bandH = 96.0;
    const soilY = 44.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;

    // Base — dark mossy ground, semi-translucent so the camera ghosts
    // through as living texture instead of a flat black bar.
    p.color = const Color(0xC71A241D);
    c.drawRect(Rect.fromLTWH(0, 0, w, bandH), p);
    // Deeper soil stratum.
    p.color = const Color(0xD9141118);
    c.drawRect(Rect.fromLTWH(0, soilY, w, bandH - soilY), p);

    // Deterministic hand-scattered texture: pebbles, tufts of moss, cracks.
    for (var gx = 0; gx < w + 12; gx += 12) {
      final h = _hash(gx * 7 + 11);
      if (h % 5 <= 1) {
        final px = (gx + h % 11).toDouble();
        final py = (soilY + 6 + (h ~/ 3) % 44).toDouble();
        p.color = const Color(0xFF3A4048);
        c.drawRect(Rect.fromLTWH(px, py, 6, 3), p);
        p.color = const Color(0xFF4E5663);
        c.drawRect(Rect.fromLTWH(px, py, 3, 1), p);
      } else if (h % 5 == 2) {
        final sx = (gx + h % 9).toDouble();
        final sy = (8 + (h ~/ 5) % 76).toDouble();
        p.color = const Color(0xFF2B321F);
        c.drawRect(Rect.fromLTWH(sx, sy, 4, 4), p);
      } else if (h % 7 == 3) {
        final cx = (gx + h % 5).toDouble();
        p.color = const Color(0xFF0F120F);
        c.drawRect(Rect.fromLTWH(cx, soilY + 4, 2, 26), p);
      }
    }
    return rec.endRecording();
  }

  /// The lit grass lip — drawn *after* characters so they stand in the grass.
  ui.Picture _buildLip(double w) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    p.color = const Color(0xFF33543F);
    c.drawRect(Rect.fromLTWH(0, 0, w, 3), p);
    p.color = const Color(0xFF1E3327);
    c.drawRect(Rect.fromLTWH(0, 3, w, 2), p);
    for (var gx = 0; gx < w + 8; gx += 12) {
      final h = _hash(gx * 3 + 5);
      if (h % 5 == 0 || h % 7 == 3) {
        final bx = (gx + h % 7).toDouble();
        p.color = const Color(0xFF4E8C63);
        c.drawRect(Rect.fromLTWH(bx, -5, 3, 7), p);
        if (h % 3 == 0) {
          p.color = const Color(0xFF6FBF73);
          c.drawRect(Rect.fromLTWH(bx, -5, 1, 4), p);
        }
      }
    }
    return rec.endRecording();
  }

  // -- castle (built once; hit variant is a brightened flash) ---------------

  ui.Picture _buildCastle({required bool hit}) {
    Color tone(Color c) => hit ? pixelLighten(c, 0.72) : c;
    const mortar = Color(0xFF263238);
    const outline = Color(0xFF1C262B);
    const chip = Color(0xFF607D8B);

    Color stone(int h) {
      final m = h % 10;
      if (m == 0 || m == 1) return const Color(0xFF37474F);
      if (m == 2) return const Color(0xFF546E7A);
      return const Color(0xFF455A64);
    }

    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    const w = _castleW;
    const bodyTop = 14.0, bodyBottom = _castleH;

    // Body mortar base (shows through 1px brick gaps).
    p.color = tone(mortar);
    c.drawRect(Rect.fromLTWH(0, bodyTop, w, bodyBottom - bodyTop), p);

    // Brick courses with alternating offset — deterministic tone + chips.
    var row = 0;
    for (var y = bodyTop; y < bodyBottom; y += 11, row++) {
      final bh = min(11.0, bodyBottom - y);
      final off = row.isEven ? 0.0 : 7.5;
      for (var x = -off; x < w; x += 15) {
        final left = max(0.0, x);
        final right = min(w, x + 15);
        final bw = right - left - 1;
        if (bw <= 0) continue;
        final h = _hash(x.round() * 31 ^ y.round() * 17);
        p.color = tone(stone(h));
        c.drawRect(Rect.fromLTWH(left, y, bw, bh - 1), p);
        if (h % 11 == 0) {
          p.color = tone(chip);
          c.drawRect(Rect.fromLTWH(left, y, min(6.0, bw), 2), p);
        }
        if (h % 17 == 0) {
          p.color = tone(mortar);
          c.drawRect(Rect.fromLTWH(left + bw - 3, y + 3, 2, 5), p);
        }
      }
    }

    // Merlons.
    for (var i = 0; i < 3; i++) {
      final mx = i * 22.0;
      p.color = tone(stone(_hash(i * 7 + 3)));
      c.drawRect(Rect.fromLTWH(mx, 0, 14, 14), p);
      p.color = tone(outline);
      c.drawRect(Rect.fromLTWH(mx, 0, 14, 1), p);
      c.drawRect(Rect.fromLTWH(mx, 0, 1, 14), p);
      c.drawRect(Rect.fromLTWH(mx + 13, 0, 1, 14), p);
    }

    // Wall outline (readability over the camera feed).
    p.color = tone(outline);
    c.drawRect(Rect.fromLTWH(0, 0, 1, _castleH), p);
    c.drawRect(Rect.fromLTWH(w - 1, 0, 1, _castleH), p);
    c.drawRect(Rect.fromLTWH(0, _castleH - 1, w, 1), p);

    // Gate: frame, wooden planks, pixel arch corners, iron bands + rivets.
    p.color = tone(outline);
    c.drawRect(Rect.fromLTWH(14, 64, 32, 36), p);
    for (var i = 0; i < 4; i++) {
      p.color = tone(i.isEven ? const Color(0xFF5D4037) : const Color(0xFF4E342E));
      c.drawRect(Rect.fromLTWH(16 + i * 7, 66, 7, 34), p);
    }
    p.color = tone(const Color(0xFF3E2723));
    for (final sx in [22.0, 29.0, 36.0]) {
      c.drawRect(Rect.fromLTWH(sx, 66, 1, 34), p);
    }
    p.color = tone(mortar); // arch corners knocked out of the plank tops
    c.drawRect(Rect.fromLTWH(16, 66, 4, 4), p);
    c.drawRect(Rect.fromLTWH(40, 66, 4, 4), p);
    p.color = tone(const Color(0xFF37474F));
    c.drawRect(Rect.fromLTWH(16, 74, 28, 3), p);
    c.drawRect(Rect.fromLTWH(16, 90, 28, 3), p);
    p.color = tone(const Color(0xFF90A4AE));
    for (final rx in [20.0, 30.0, 40.0]) {
      c.drawRect(Rect.fromLTWH(rx, 74, 2, 2), p);
      c.drawRect(Rect.fromLTWH(rx, 90, 2, 2), p);
    }
    c.drawRect(Rect.fromLTWH(33, 81, 3, 5), p); // handle

    // Torch brackets flanking the gate.
    p.color = tone(const Color(0xFF37474F));
    c.drawRect(Rect.fromLTWH(4, 54, 5, 8), p);
    c.drawRect(Rect.fromLTWH(50, 54, 5, 8), p);
    p.color = tone(const Color(0xFF263238));
    c.drawRect(Rect.fromLTWH(5, 54, 3, 2), p);
    c.drawRect(Rect.fromLTWH(51, 54, 3, 2), p);

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
      y: groundY - 114,
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
    final top = groundY - 128;
    final p = Paint()..isAntiAlias = false;

    p.color = const Color(0xFF37474F);
    canvas.drawRect(Rect.fromLTWH(x, top, 2, 28), p);
    p.color = const Color(0xFF78909C);
    canvas.drawRect(Rect.fromLTWH(x, top, 2, 3), p);

    final bucket = (_time * 1.6).floor();
    final f = (bucket ^ (bucket >> 2)) & 1; // mostly alternates, occasional hold
    p.color = kOrange;
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
      'WAVE $wave',
      Vector2(size.x - 16, 14),
      anchor: Anchor.topRight,
    );
    _hudPaint.render(
      canvas,
      '$enemiesLeft LEFT',
      Vector2(size.x - 16, 36),
      anchor: Anchor.topRight,
    );

    final coinText = '${save.coins} COINS';
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

    if (combo >= 2) {
      final m = comboMultiplier(combo);
      final text = 'COMBO ${m.toStringAsFixed(1)}x';
      final paint = m >= 1.8 ? _comboO : m >= 1.5 ? _comboG : _comboW;
      // 3 discrete pop frames — frame-by-frame, never smoothly scaled.
      final s = _comboPop > 0.12 ? 1.7 : _comboPop > 0.05 ? 1.3 : 1.0;
      if (s == 1.0) {
        paint.render(canvas, text, Vector2(size.x - 16, 80),
            anchor: Anchor.topRight);
      } else {
        canvas.save();
        canvas.translate(size.x - 16, 80);
        canvas.scale(s, s);
        paint.render(canvas, text, Vector2.zero(), anchor: Anchor.topRight);
        canvas.restore();
      }
    }
  }

  // -- banners (intro pop-in; later phases are covered by the shop) ----------

  void _renderBanners(Canvas canvas) {
    switch (phase) {
      case GamePhase.intro:
        final t = introSeconds - phaseTimer;
        final center = Vector2(size.x / 2, size.y * 0.34);
        final step = (t * 9).floor().clamp(0, 2);
        if (step >= 2) {
          _bannerPaint.render(canvas, 'WAVE $wave', center,
              anchor: Anchor.center);
        } else {
          final s = step == 0 ? 2.0 : 1.5;
          canvas.save();
          canvas.translate(center.x, center.y);
          canvas.scale(s, s);
          _bannerPaint.render(canvas, 'WAVE $wave', Vector2.zero(),
              anchor: Anchor.center);
          canvas.restore();
        }
        if (t > 0.35 && (t * 3).floor().isEven) {
          _subPaint.render(canvas, 'GET READY', center + Vector2(0, 46),
              anchor: Anchor.center);
        }

      case GamePhase.fighting:
        break;

      case GamePhase.waveCleared:
      case GamePhase.defeat:
        break; // Flutter shop panel covers these phases
    }
  }
}
