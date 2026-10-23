import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';

import 'pixel_art.dart';

/// Fixed-arena camera for Repel (M4).
///
/// Root cause of the old "broken camera": there was none. Every element was
/// positioned in raw screen coordinates, so the arena literally *was* the
/// screen — enemy runway, sprite proportions, ground band and banner
/// placement all changed with the device, and the only camera-like behaviour
/// was an ad-hoc `canvas.translate` used for screen shake.
///
/// Repel is a fixed arena (castle on the left, monsters march in from the
/// right), so the correct camera for it is a *fixed, virtual-resolution*
/// camera — not a following one. The world is defined once in virtual pixels
/// with a fixed height of 360 and this camera maps it onto the device screen:
///
///  * Scale fills the screen height exactly and the world width follows the
///    screen aspect ratio (clamped to [minWorldWidth]–[maxWorldWidth]), so
///    sprite proportions and the vertical layout are identical on every
///    device; only the visible runway length varies, within a fixed bound.
///  * The arena always fills the screen: wide screens show more battlefield,
///    narrow screens crop the (unbounded) right side — the castle side stays
///    visible. Ultra-wide outliers are letterboxed with solid ink margins so
///    nothing outside the world is ever shown.
///  * The world transform is applied by [beginWorld]/[endWorld]; the HUD is
///    drawn outside that transform, so it stays pinned to the screen while
///    the world (including shake) moves underneath.
///  * Shake is quantized to whole world pixels — chunky pixel-art shake,
///    never subpixel smear, and never applied to the HUD.
///
/// The camera holds no transient state to reset per level: [resize] is
/// re-run on layout changes, and starting a level simply re-anchors the
/// (already fixed) view.
class ArenaCamera {
  /// Virtual world height in pixels. Landscape phones are 360–411 logical
  /// pixels tall; 360 keeps the playfield proportions identical to the
  /// original design on the most common device class.
  static const double virtualHeight = 360;

  /// Narrowest world. Below this screen aspect the world is cropped on the
  /// right (enemies still spawn beyond it and walk in), keeping the runway —
  /// and with it the game's difficulty — identical on every device.
  static const double minWorldWidth = 640;

  /// Widest world. Beyond this aspect the arena is letterboxed with ink
  /// margins so the runway stays bounded and the world never stretches.
  static const double maxWorldWidth = 900;

  /// Current world-to-screen scale (screen px per world px).
  double scale = 1;

  /// Current world width in virtual pixels.
  double worldWidth = minWorldWidth;

  /// X offset of the world's left edge on screen (letterbox only).
  double originX = 0;

  /// Recompute the mapping for a new screen size (in logical pixels).
  void resize(Vector2 screen) {
    if (screen.x <= 0 || screen.y <= 0) return;
    scale = screen.y / virtualHeight;
    final fit = screen.x / scale; // width the screen *could* show
    if (fit < minWorldWidth) {
      // Narrow screen: keep the minimum runway, crop the unbounded right
      // side. The castle (left) is always visible.
      worldWidth = minWorldWidth;
      originX = 0;
    } else if (fit > maxWorldWidth) {
      // Ultra-wide: cap the runway, center the world, letterbox the rest.
      worldWidth = maxWorldWidth;
      originX = (screen.x - worldWidth * scale) / 2;
    } else {
      // Standard phone/tablet aspects: the world exactly fills the screen.
      worldWidth = fit;
      originX = 0;
    }
  }

  /// World → screen conversion (useful for aligning screen-space overlays
  /// with world-space anchors).
  Vector2 worldToScreen(Vector2 world) =>
      Vector2(originX + world.x * scale, world.y * scale);

  /// Screen → world conversion (e.g. for taps).
  Vector2 screenToWorld(Vector2 screen) =>
      Vector2((screen.x - originX) / scale, screen.y / scale);

  /// Apply the world transform. Everything drawn between [beginWorld] and
  /// [endWorld] is in virtual world pixels.
  void beginWorld(ui.Canvas canvas) {
    canvas.save();
    canvas.translate(originX, 0);
    canvas.scale(scale);
  }

  void endWorld(ui.Canvas canvas) => canvas.restore();

  /// Solid margins for screens wider than [maxWorldWidth], drawn in screen
  /// space so the world never appears to leak past its bounds.
  void paintLetterbox(ui.Canvas canvas, Vector2 screen) {
    final world = worldWidth * scale;
    if (world >= screen.x) return;
    final margin = (screen.x - world) / 2;
    final paint = ui.Paint()
      ..isAntiAlias = false
      ..color = kInk;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, margin, screen.y), paint);
    canvas.drawRect(
        ui.Rect.fromLTWH(screen.x - margin, 0, margin, screen.y), paint);
  }

  /// Shake offset in whole world pixels — quantized so a scaled rect never
  /// lands on fractional device pixels mid-shake.
  Vector2 quantizedShake(double amplitude, math.Random rng) {
    if (amplitude <= 0) return Vector2.zero();
    final offset = Vector2(
      (rng.nextDouble() * 2 - 1) * amplitude,
      (rng.nextDouble() * 2 - 1) * amplitude,
    );
    offset.round(); // in place — whole world pixels only
    return offset;
  }
}
