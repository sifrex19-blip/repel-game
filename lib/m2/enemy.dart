import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'repel_game.dart';

/// A monster marching from the right edge toward your base on the left.
class Enemy extends CircleComponent with HasGameReference<RepelGame> {
  Enemy({
    required this.maxHp,
    required this.speed,
    required this.baseDamage,
    required Vector2 spawnPosition,
    required this.isBoss,
  })  : hp = maxHp,
        super(
          position: spawnPosition,
          radius: isBoss ? 44 : 24,
          anchor: Anchor.center,
        );

  int hp;
  final int maxHp;
  final double speed;
  final int baseDamage;
  final bool isBoss;

  static const _palette = [
    Color(0xFFFF5252),
    Color(0xFFFF9800),
    Color(0xFFE040FB),
    Color(0xFF29B6F6),
    Color(0xFF66BB6A),
  ];

  late final Color _baseColor = isBoss
      ? const Color(0xFFB71C1C)
      : _palette[identityHashCode(this) % _palette.length];

  final Paint _paint = Paint();
  double _flash = 0;
  double _attackCooldown = 1.2;
  bool dead = false;

  @override
  void update(double dt) {
    super.update(dt);
    if (dead) return;

    if (_flash > 0) {
      _flash -= dt;
    }

    // March toward the base; attack when in reach.
    if (position.x > RepelGame.gateX + 44) {
      position.x -= speed * dt;
    } else if (game.baseHp > 0) {
      _attackCooldown -= dt;
      if (_attackCooldown <= 0) {
        _attackCooldown = 1.4;
        game.damageBase(baseDamage);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(radius, radius);
    _paint.color = _flash > 0 ? Colors.white : _baseColor;

    // Body + outline for readability over the camera feed.
    canvas.drawCircle(c, radius, _paint);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black54,
    );

    // Angry eyes — placeholder face until real art lands (M4).
    if (!isBoss) {
      final eye = Paint()..color = Colors.black;
      canvas.drawCircle(c + const Offset(-8, -6), 4, eye);
      canvas.drawCircle(c + const Offset(8, -6), 4, eye);
    } else {
      final eye = Paint()..color = const Color(0xFFFFD54F);
      canvas.drawCircle(c + const Offset(-14, -10), 7, eye);
      canvas.drawCircle(c + const Offset(14, -10), 7, eye);
    }

    // HP bar above the head.
    final w = isBoss ? 84.0 : 50.0;
    const h = 7.0;
    final bar = Rect.fromLTWH(radius - w / 2, -h - 10, w, h);
    canvas.drawRect(
      bar,
      Paint()..color = const Color(0xCC000000),
    );
    final ratio = (hp / maxHp).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(bar.left + 1, bar.top + 1, (bar.width - 2) * ratio, bar.height - 2),
      Paint()
        ..color = Color.lerp(
          const Color(0xFFEF5350),
          const Color(0xFF66BB6A),
          ratio,
        )!,
    );
  }

  /// One pushup's worth of damage lands here.
  void takeHit(int amount) {
    if (dead) return;
    hp -= amount;
    _flash = 0.12;
    game.add(FloatingText(
      position: position + Vector2(0, -(radius + 30)),
      text: '-$amount',
    ));
    if (hp <= 0) {
      dead = true;
      game.enemyKilled(this);
      removeFromParent();
    }
  }
}

/// A shot fired from your castle gate toward the hit enemy.
/// (Damage is applied instantly on rep — this is the visual tracer.)
class Projectile extends CircleComponent {
  Projectile({required Vector2 start, required this.target})
      : super(position: start, radius: 6, anchor: Anchor.center);

  final Vector2 target;
  static const _speed = 640.0;

  @override
  void update(double dt) {
    final dir = target - position;
    final step = _speed * dt;
    if (dir.length <= step) {
      removeFromParent();
      return;
    }
    position += dir.normalized() * step;
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(radius, radius);
    canvas.drawCircle(c, radius, Paint()..color = const Color(0xFFFFAB40));
    canvas.drawCircle(c, radius * 0.5, Paint()..color = Colors.white);
  }
}

/// Rising damage number.
class FloatingText extends PositionComponent {
  FloatingText({required super.position, required this.text});

  final String text;
  double _life = 0;
  static const _duration = 0.8;

  @override
  void update(double dt) {
    _life += dt;
    position.y -= 38 * dt;
    if (_life >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final alpha = (1 - _life / _duration).clamp(0.0, 1.0);
    TextPaint(
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
        color: const Color(0xFFFFD54F).withValues(alpha: alpha),
      ),
    ).render(canvas, text, Vector2.zero(), anchor: Anchor.center);
  }
}
