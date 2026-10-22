import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'enemy.dart';

enum GamePhase { intro, fighting, waveCleared, defeat }

/// The M2 combat prototype: waves of monsters march at your base and every
/// counted pushup fires a shot.
///
/// The game world is screen-sized and renders *on top of* the live camera
/// feed, so the player always sees themselves and the monsters at once.
class RepelGame extends FlameGame with TapCallbacks {
  /// X position of the castle gate — enemies stop here and attack.
  static const double gateX = 96;

  static const int maxBaseHp = 80;
  static const double introSeconds = 2.2;
  static const double restSeconds = 10;

  int wave = 1;
  int baseHp = maxBaseHp;
  GamePhase phase = GamePhase.intro;

  /// Counts down: intro "get ready" time, or seconds until the next wave.
  double phaseTimer = introSeconds;

  int _toSpawn = 0;
  double _spawnTimer = 0;
  final _rng = Random();
  double _baseFlash = 0;

  /// Ground line — enemies and castle stand on it.
  double get groundY => size.y - 96;

  int get _enemiesAlive => children.whereType<Enemy>().length;
  int get enemiesLeft => _toSpawn + _enemiesAlive;

  // ---- Wave configuration (prototype balance — tune after playtest) ----
  int enemyCountFor(int w) => min(3 + w, 12);
  int hpFor(int w) => 2 + w + (w ~/ 3);
  double speedFor(int w) => min(30 + w * 2.5, 66.0);
  int damageFor(int w) => 3 + w ~/ 2;

  @override
  Future<void> onLoad() async {
    startWave(1);
  }

  void startWave(int w) {
    wave = w;
    baseHp = maxBaseHp;
    for (final e in children.whereType<Enemy>()) {
      e.removeFromParent();
    }
    for (final p in children.whereType<Projectile>()) {
      p.removeFromParent();
    }
    _toSpawn = enemyCountFor(w);
    _spawnTimer = 0;
    phase = GamePhase.intro;
    phaseTimer = introSeconds;
  }

  /// Called by the pose screen whenever the pushup counter counts a rep.
  void onRep() {
    if (phase != GamePhase.fighting) return;
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
    target.takeHit(1); // M3 will make this damage an upgradeable stat
  }

  void damageBase(int amount) {
    if (baseHp <= 0) return;
    baseHp = max(0, baseHp - amount);
    _baseFlash = 0.15;
    if (baseHp == 0) {
      phase = GamePhase.defeat;
    }
  }

  void enemyKilled(Enemy enemy) {
    // Hook for coins/score in M3.
  }

  void _nextWave() => startWave(wave + 1);
  void _retryWave() => startWave(wave);

  @override
  void update(double dt) {
    super.update(dt);
    if (_baseFlash > 0) _baseFlash -= dt;

    switch (phase) {
      case GamePhase.intro:
        phaseTimer -= dt;
        if (phaseTimer <= 0) phase = GamePhase.fighting;

      case GamePhase.fighting:
        _spawnTimer -= dt;
        if (_toSpawn > 0 && _spawnTimer <= 0) {
          _spawnEnemy();
          _spawnTimer = 2.2;
        }
        if (_toSpawn == 0 && _enemiesAlive == 0) {
          phase = GamePhase.waveCleared;
          phaseTimer = restSeconds;
        }

      case GamePhase.waveCleared:
        phaseTimer -= dt;
        if (phaseTimer <= 0) _nextWave();

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
    if (phase == GamePhase.defeat) {
      _retryWave();
    } else if (phase == GamePhase.waveCleared) {
      _nextWave();
    }
  }

  // ------------------------------ rendering ------------------------------

  late final TextPaint _bannerPaint = TextPaint(
    style: const TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      color: Colors.white,
      shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
    ),
  );
  late final TextPaint _subPaint = TextPaint(
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: Colors.white70,
    ),
  );
  late final TextPaint _hudPaint = TextPaint(
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    ),
  );

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Ground strip — translucent so the camera stays visible underneath.
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.x, size.y - groundY),
      Paint()..color = const Color(0x59000000),
    );
    canvas.drawLine(
      Offset(0, groundY),
      Offset(size.x, groundY),
      Paint()
        ..color = const Color(0xAAFF6E40)
        ..strokeWidth = 3,
    );

    _renderBase(canvas);
    _renderHud(canvas);
    _renderBanners(canvas);
  }

  void _renderBase(Canvas canvas) {
    const x = 36.0, w = 60.0, h = 86.0;
    final top = groundY - h;
    final bodyColor =
        _baseFlash > 0 ? const Color(0xFFEF5350) : const Color(0xFF455A64);
    final body = Paint()..color = bodyColor;

    // Body + battlements + gate.
    canvas.drawRect(Rect.fromLTWH(x, top, w, h), body);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(x + i * 22, top - 14, 14, 14), body);
    }
    canvas.drawRect(
      Rect.fromLTWH(x + 16, groundY - 34, 28, 34),
      Paint()..color = const Color(0xFF263238),
    );

    // HP bar above the castle.
    final ratio = (baseHp / maxBaseHp).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(x - 8, top - 36, w + 16, 13),
      Paint()..color = const Color(0xCC000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 6, top - 34, (w + 12) * ratio, 9),
      Paint()
        ..color = Color.lerp(
          const Color(0xFFEF5350),
          const Color(0xFF66BB6A),
          ratio,
        )!,
    );
    _hudPaint.render(
      canvas,
      'BASE',
      Vector2(x - 6, top - 56),
      anchor: Anchor.topLeft,
    );
  }

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
  }

  void _renderBanners(Canvas canvas) {
    final center = Vector2(size.x / 2, size.y * 0.38);
    switch (phase) {
      case GamePhase.intro:
        _bannerPaint.render(canvas, 'WAVE $wave', center, anchor: Anchor.center);
        _subPaint.render(
          canvas,
          'GET READY',
          center + Vector2(0, 44),
          anchor: Anchor.center,
        );

      case GamePhase.fighting:
        break;

      case GamePhase.waveCleared:
        _bannerPaint.render(
          canvas,
          'WAVE $wave CLEARED',
          center,
          anchor: Anchor.center,
        );
        _subPaint.render(
          canvas,
          'next wave in ${phaseTimer.ceil()}s — TAP TO SKIP',
          center + Vector2(0, 44),
          anchor: Anchor.center,
        );

      case GamePhase.defeat:
        _bannerPaint.render(
          canvas,
          'BASE DESTROYED',
          center,
          anchor: Anchor.center,
        );
        _subPaint.render(
          canvas,
          'TAP TO RETRY WAVE $wave',
          center + Vector2(0, 44),
          anchor: Anchor.center,
        );
    }
  }
}
