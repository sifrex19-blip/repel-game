import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import 'levels.dart';
import 'pixel_art.dart';
import 'repel_game.dart';

/// A monster marching from the right edge toward your base on the left.
///
/// Rendered as a hand-authored pixel sprite with frame-based animation:
///  - a 2-frame stride while marching (per-enemy phase so groups don't sync),
///  - irregular weight-shift idles at the gate (no sine-wave bobbing),
///  - a strike lunge synced to the attack, stepped in whole pixels,
///  - hit flash + knockback with contact sparks,
///  - a strobe-and-sink death animation with a particle poof.
class Enemy extends CircleComponent with HasGameReference<RepelGame> {
  Enemy({
    required this.maxHp,
    required this.speed,
    required this.baseDamage,
    required Vector2 spawnPosition,
    required this.variant,
    required this._color,
  })  : hp = maxHp,
        super(
          position: spawnPosition,
          radius: variant.radius,
          anchor: Anchor.center,
        );

  int hp;
  final int maxHp;
  final double speed;
  final int baseDamage;

  /// Body type — decides sprite, scale, radius and stat multipliers.
  final EnemyVariant variant;

  /// Level-palette hue this enemy was spawned with (public arg: [color]).
  final Color _color;

  bool get isBoss => variant.isBoss;

  /// Art scale: boss sprite at 4×; grumbler art at the variant's scale
  /// (grunt 3×, runner 2×, brute 4× — radius/8).
  int get _artScale => isBoss ? 4 : (variant.radius / 8).round();

  /// Subtle per-enemy tone shift so one variant marching as a squad is not
  /// visually flat. Deterministic per enemy, never re-rolled per frame.
  late final Color _baseColor = isBoss
      ? _color
      : switch (identityHashCode(this) % 3) {
          0 => pixelShade(_color, 0.88),
          1 => _color,
          _ => pixelLighten(_color, 0.10),
        };

  /// Full sprite palette: hue body shades + shared outline/face colors.
  late final Map<String, Color> _pal = huePalette(_baseColor);

  double _flash = 0;
  double _attackCooldown = 1.2;
  bool dead = false;

  // -- animation state -----------------------------------------------------
  static const _lungeDuration = 0.30;
  static const _deathDuration = 0.34;
  static const _stepPeriod = 0.16; // seconds per stride frame

  bool _moving = true;
  double _walkT = 0;
  double _idleT = 0;
  int _idleFrame = 0;
  int _idleFlips = 0;
  double _lungeT = 0;
  double _deathT = 0;

  /// Per-enemy walk phase — a group of monsters never steps in sync.
  late final double _walkPhase = (identityHashCode(this) % 97) / 97 * 0.32;

  /// Per-enemy seed for the irregular idle cadence.
  late final int _seed = identityHashCode(this) % 100;
  double _nextIdleFlip = 0.6;

  int get _frame {
    if (dead) return 0;
    if (_lungeT > 0) return 1; // strike pose
    if (_moving) return ((_walkT + _walkPhase) / _stepPeriod).floor() & 1;
    return _idleFrame;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_flash > 0) _flash -= dt;

    if (dead) {
      _deathT += dt;
      if (_deathT >= _deathDuration) removeFromParent();
      return;
    }

    if (_lungeT > 0) _lungeT -= dt;

    // March toward the base; attack when in reach.
    if (position.x > RepelGame.gateX + RepelGame.gateReach) {
      _moving = true;
      _walkT += dt;
      position.x -= speed * dt;
    } else {
      _moving = false;
      // Irregular weight shifts: cadence varies per enemy and per flip.
      _idleT += dt;
      if (_idleT >= _nextIdleFlip) {
        _idleT = 0;
        _idleFlips++;
        _idleFrame = _idleFrame == 0 ? 1 : 0;
        _nextIdleFlip =
            (isBoss ? 0.95 : 0.68) + ((_idleFlips * 37 + _seed) % 53) / 100;
      }
      if (game.baseHp > 0) {
        _attackCooldown -= dt;
        if (_attackCooldown <= 0) {
          _attackCooldown = 1.4;
          _lungeT = _lungeDuration;
          game.damageBase(baseDamage);
        }
      }
    }
  }

  /// Lunge step in whole pixels: strike forward, ease back (bosses hit harder).
  int get _lungeOffset {
    final s = isBoss ? 6 : 4;
    if (_lungeT > 0.22) return s;
    if (_lungeT > 0.14) return s - 1;
    if (_lungeT > 0.07) return s - 2;
    if (_lungeT > 0.03) return s - 3;
    return 0;
  }

  Color? _deathTint() {
    if (_deathT < 0.24) {
      return ((_deathT * 16).floor().isEven)
          ? const Color(0xFFFFFFFF)
          : const Color(0x66FFFFFF);
    }
    if (_deathT < 0.29) return const Color(0x22FFFFFF);
    return null;
  }

  @override
  void render(Canvas canvas) {
    final sprite = isBoss
        ? (_frame == 0 ? bossA : bossB)
        : (_frame == 0 ? grumblerA : grumblerB);
    final scale = _artScale;
    final sw = sprite.first.length * scale;
    final sh = sprite.length * scale;

    // Contact shadow — grounds the sprite on the grass line.
    final shadowW = (sw * 0.84 / 2).floor() * 2;
    canvas.drawRect(
      Rect.fromLTWH(radius - shadowW / 2, 2 * radius - 5, shadowW.toDouble(), 5),
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0x59000000),
    );

    // Integer pixel offsets only — no sub-pixel drift.
    var ox = (radius - sw / 2).round();
    var oy = (2 * radius - sh).round();

    if (dead) {
      oy += (sh * 0.5 * (_deathT / _deathDuration)).floor();
    } else if (_lungeT > 0) {
      ox -= _lungeOffset; // strike toward the gate (left)
    } else if (!_moving && _idleFrame == 1) {
      oy += 1; // weight settle during idle shift
    }

    drawSprite(
      canvas,
      sprite,
      x: ox.toDouble(),
      y: oy.toDouble(),
      scale: scale,
      palette: _pal,
      tint: dead ? _deathTint() : (_flash > 0 ? _flashTint() : null),
    );

    if (!dead) _renderHud(canvas);
  }

  /// Hit flash tint, per Settings → Hit flash: FULL = white strobe,
  /// DIM = soft lighten of the body hue, OFF = nothing.
  Color? _flashTint() => switch (AppSettings.instance.hitFlash) {
        'FULL' => kWhite,
        'DIM' => pixelLighten(_baseColor, 0.45),
        _ => null,
      };

  void _renderHud(Canvas canvas) {
    final canvasHudW = isBoss ? 84.0 : 50.0;
    final ratio = (hp / maxHp).clamp(0.0, 1.0);
    // Discrete color steps — no smooth gradient.
    final fg =
        ratio > 0.55 ? kGreen : ratio > 0.25 ? kGold : kRed;
    drawPixelBar(
      canvas,
      x: radius - canvasHudW / 2,
      y: -18,
      w: canvasHudW,
      h: 8,
      ratio: ratio,
      fg: fg,
      cell: 6,
      borderW: 2,
    );
  }

  /// One pushup's worth of damage lands here.
  void takeHit(int amount) {
    if (dead) return;
    hp -= amount;
    _flash = 0.09;

    // Physical reaction: shove back from the gate (bosses barely budge).
    if (position.x > RepelGame.gateX + RepelGame.gateReach) position.x += isBoss ? 3 : 7;
    game.spawnSparks(
      position + Vector2(0, isBoss ? -20 : -8),
      _baseColor,
      count: isBoss ? 7 : 5,
    );
    game.add(FloatingText(
      position: position + Vector2(0, -(radius + 30)),
      text: '-$amount',
      color: kWhite,
    ));
    if (hp <= 0) {
      dead = true;
      _deathT = 0;
      game.spawnPoof(position, _baseColor);
      game.enemyKilled(this);
      // The corpse animates out over [_deathDuration]; `dead` already keeps it
      // out of targeting, and wave logic waits for this component to leave.
    }
  }
}

/// A shot fired from your castle gate toward the hit enemy.
/// (Damage is applied instantly on rep — this is the visual tracer.)
class Projectile extends PositionComponent with HasGameReference<RepelGame> {
  Projectile({
    required Vector2 start,
    required this.target,
    this.auto = false,
    this.small = false,
  })  : _dir = (target - start).normalized(),
        super(position: start, anchor: Anchor.center);

  final Vector2 target;

  /// True for automatic chip-damage shots (cooler color to tell them apart).
  final bool auto;

  /// True for pushup rep shots: a small, fast gold dart with a hot white
  /// core — visibly different from the chunky blue auto tracer.
  final bool small;
  final Vector2 _dir;
  double get _speed => small ? 860.0 : 640.0;

  Color get _color =>
      auto ? const Color(0xFF4FC3F7) : const Color(0xFFFFAB40);

  @override
  void update(double dt) {
    final toTarget = target - position;
    final step = _speed * dt;
    if (toTarget.length <= step) {
      game.spawnSparks(position, _color, count: small ? 2 : 3, spread: 70);
      removeFromParent();
      return;
    }
    position += _dir * step;
  }

  @override
  void render(Canvas canvas) {
    final color = _color;
    final paint = Paint()..isAntiAlias = false;

    if (small) {
      // Pushup rep dart: one trailing pixel, 5px gold head, 2px white core.
      paint.color = color.withValues(alpha: 0.45);
      canvas.drawRect(
        Rect.fromLTWH(
          (-_dir.x * 7 - 1.5).roundToDouble(),
          (-_dir.y * 7 - 1.5).roundToDouble(),
          3,
          3,
        ),
        paint,
      );
      paint.color = color;
      canvas.drawRect(const Rect.fromLTWH(-2.5, -2.5, 5, 5), paint);
      paint.color = kWhite;
      canvas.drawRect(const Rect.fromLTWH(-1, -1, 2, 2), paint);
      return;
    }

    // Trailing pixels — quantized alpha, chunky, no glow gradient.
    paint.color = color.withValues(alpha: 0.30);
    canvas.drawRect(
      Rect.fromLTWH(
        (-_dir.x * 11 - 2).roundToDouble(),
        (-_dir.y * 11 - 2).roundToDouble(),
        4,
        4,
      ),
      paint,
    );
    paint.color = color.withValues(alpha: 0.55);
    canvas.drawRect(
      Rect.fromLTWH(
        (-_dir.x * 6 - 3).roundToDouble(),
        (-_dir.y * 6 - 3).roundToDouble(),
        6,
        6,
      ),
      paint,
    );
    // Head + hot core.
    paint.color = color;
    canvas.drawRect(const Rect.fromLTWH(-5, -5, 10, 10), paint);
    paint.color = kWhite;
    canvas.drawRect(const Rect.fromLTWH(-2, -2, 4, 4), paint);
  }
}

/// Rising damage number (or coin pickup text) in the 3×5 pixel font.
class FloatingText extends PositionComponent {
  FloatingText({
    required super.position,
    required this.text,
    this.color = kGold,
    this.coin = false,
  });

  final String text;
  final Color color;

  /// Prefix the number with a little coin sprite (kill / wave rewards).
  final bool coin;
  double _life = 0;
  static const _duration = 0.8;

  @override
  void update(double dt) {
    _life += dt;
    position.y -= 42 * dt;
    if (_life >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    // Quantized 4-step fade — pixel style, no smooth gradient.
    final alpha = ((1 - _life / _duration).clamp(0.0, 1.0) * 4).floor() / 4;
    if (alpha <= 0) return;
    final w = numberWidth(text, 2).toDouble();
    if (coin) {
      drawSprite(
        canvas,
        coinSprite,
        x: -w / 2 - 17,
        y: -7,
        scale: 2,
        palette: coinPalette,
        tint: color.withValues(alpha: alpha),
      );
    }
    drawNumber(
      canvas,
      text,
      x: -w / 2,
      y: -5,
      scale: 2,
      color: color.withValues(alpha: alpha),
    );
  }
}

/// A chunky square particle: sparks, poof, embers. Fixed palette colors and a
/// quantized fade — no gradients, no allocations beyond the drawn rect.
class PixelParticle extends PositionComponent {
  PixelParticle({
    required super.position,
    required this.color,
    required this.side,
    required this.vel,
    required this.life,
    this.gravity = 320,
  });

  final Color color;
  final double side;
  final Vector2 vel;
  final double life;
  final double gravity;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= life) {
      removeFromParent();
      return;
    }
    vel.y += gravity * dt;
    position.x += vel.x * dt;
    position.y += vel.y * dt;
  }

  @override
  void render(Canvas canvas) {
    final progress = (_t / life).clamp(0.0, 1.0);
    const steps = 4;
    final alpha = ((steps * (1 - progress)).floor() / steps).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(-side / 2, -side / 2, side, side),
      Paint()
        ..isAntiAlias = false
        ..color = color.withValues(alpha: alpha),
    );
  }
}
