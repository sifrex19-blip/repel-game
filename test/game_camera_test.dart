import 'dart:math' as math;

import 'package:flame/extensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/game_camera.dart';

/// Camera math: the arena must map onto every screen the same way — same
/// sprite proportions, bounded runway, nothing outside the world ever shown.
void main() {
  group('ArenaCamera.resize', () {
    test('standard 20:9 phone fills the screen exactly', () {
      final cam = ArenaCamera()..resize(Vector2(800, 360));
      expect(cam.scale, closeTo(1.0, 1e-9));
      expect(cam.worldWidth, closeTo(800, 1e-9));
      expect(cam.originX, closeTo(0, 1e-9));
    });

    test('taller 20.6:9 phone keeps world-height fill, adapts width', () {
      final cam = ArenaCamera()..resize(Vector2(915, 411));
      expect(cam.scale, closeTo(411 / 360, 1e-9));
      // Width follows aspect: 915 / (411/360) ≈ 801.4, inside the clamp.
      expect(cam.worldWidth, closeTo(915 / (411 / 360), 1e-9));
      expect(cam.originX, closeTo(0, 1e-9));
    });

    test('narrow 16:10 tablet crops the right, keeps castle visible', () {
      final cam = ArenaCamera()..resize(Vector2(1280, 800));
      expect(cam.worldWidth, ArenaCamera.minWorldWidth);
      expect(cam.originX, closeTo(0, 1e-9));
      // The world is wider than the visible area (crop, not letterbox).
      expect(cam.worldWidth * cam.scale, greaterThan(1280));
    });

    test('ultra-wide caps the runway and letterboxes with ink margins', () {
      final cam = ArenaCamera()..resize(Vector2(3000, 1000));
      expect(cam.worldWidth, ArenaCamera.maxWorldWidth);
      final worldPx = cam.worldWidth * cam.scale;
      expect(worldPx, lessThan(3000));
      expect(cam.originX, closeTo((3000 - worldPx) / 2, 1e-9));
    });

    test('guard: zero-size screen keeps the previous mapping', () {
      final cam = ArenaCamera()..resize(Vector2(800, 360));
      cam.resize(Vector2.zero());
      expect(cam.scale, closeTo(1.0, 1e-9));
      expect(cam.worldWidth, closeTo(800, 1e-9));
    });
  });

  group('coordinate conversion', () {
    test('screenToWorld is the inverse of worldToScreen', () {
      final cam = ArenaCamera()..resize(Vector2(915, 411));
      for (final p in [
        Vector2.zero(),
        Vector2(96, 264),
        Vector2(800.3, 12.7),
        Vector2(450, 359),
      ]) {
        final back = cam.screenToWorld(cam.worldToScreen(p));
        expect(back.x, closeTo(p.x, 1e-9));
        expect(back.y, closeTo(p.y, 1e-9));
      }
    });

    test('castle gate maps inside the visible screen on a phone', () {
      final cam = ArenaCamera()..resize(Vector2(800, 360));
      final gate = cam.worldToScreen(Vector2(96, 264));
      expect(gate.x, inInclusiveRange(0, 800));
      expect(gate.y, inInclusiveRange(0, 360));
    });

    test('world bottom edge is the screen bottom edge', () {
      for (final screen in [
        Vector2(800, 360),
        Vector2(915, 411),
        Vector2(1280, 800),
        Vector2(3000, 1000),
      ]) {
        final cam = ArenaCamera()..resize(screen);
        final bottom = cam.worldToScreen(Vector2(0, ArenaCamera.virtualHeight));
        expect(bottom.y, closeTo(screen.y, 1e-9));
      }
    });
  });

  group('quantizedShake', () {
    test('zero amplitude means zero shake', () {
      final cam = ArenaCamera();
      final s = cam.quantizedShake(0, math.Random(42));
      expect(s.x, 0);
      expect(s.y, 0);
    });

    test('shake steps are whole world pixels within the amplitude', () {
      final cam = ArenaCamera();
      final rng = math.Random(42);
      for (var i = 0; i < 200; i++) {
        final s = cam.quantizedShake(8, rng);
        expect(s.x, s.x.roundToDouble());
        expect(s.y, s.y.roundToDouble());
        expect(s.x.abs(), lessThanOrEqualTo(8));
        expect(s.y.abs(), lessThanOrEqualTo(8));
      }
    });
  });
}
