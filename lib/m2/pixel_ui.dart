import 'package:flutter/material.dart';

import 'pixel_art.dart';

/// Shared handcrafted pixel-UI kit: hard square corners, ink outlines,
/// beveled panel faces, Press Start 2P text with 1px hard shadows, buttons
/// that press *into* the panel, and sprites/numbers drawn through the shared
/// cached-picture renderer (crisp and cheap).
///
/// Extracted in M4 so the shop, the level menu and the victory screen all
/// speak the same visual language without duplicating widgets.

Border pixelBevel(double w) => Border(
      top: BorderSide(color: kPanelLight, width: w),
      left: BorderSide(color: kPanelLight, width: w),
      bottom: BorderSide(color: kPanelDark, width: w),
      right: BorderSide(color: kPanelDark, width: w),
    );

/// Dimmed text color for secondary labels on panels.
const kDimText = Color(0xFF8B84A8);

TextStyle pixelText(double size, Color color, {double shadow = 1}) =>
    TextStyle(
      fontFamily: kPixelFont,
      fontSize: size,
      color: color,
      shadows: [
        Shadow(color: kInk, offset: Offset(shadow, shadow), blurRadius: 0),
      ],
    );

/// Square pixel button: no Material chrome, ink outline, hard drop shadow,
/// and a press state that shoves the face 2px down (shadow swallows it).
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fill = kOrange,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget label;
  final VoidCallback? onPressed;
  final Color fill;
  final EdgeInsets padding;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fill = !enabled
        ? kPanelDark
        : _down
            ? pixelShade(widget.fill, 0.78)
            : widget.fill;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed!();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      child: Transform.translate(
        offset: Offset(0, _down ? 2 : 0),
        child: Container(
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            // Top edge catches the light (a 2px bevel); the other three
            // stay ink — the button reads as a chunky raised pixel block.
            border: enabled
                ? Border(
                    top: BorderSide(
                        color: pixelLighten(fill, 0.25), width: 2),
                    left: BorderSide(color: kInk, width: 2),
                    right: BorderSide(color: kInk, width: 2),
                    bottom: BorderSide(color: kInk, width: 2),
                  )
                : Border.all(color: kInk, width: 2),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: kInk,
                      offset: Offset(0, 3),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: widget.label,
        ),
      ),
    );
  }
}

/// Ink-outlined, beveled panel face — the frame every HUD block sits in
/// (rep counter, form meter, settings, chips). Same language as the shop
/// and menu panels, scaled down for on-screen readouts.
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.face = const Color(0xE60D0B14),
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.outline = 3,
    this.bevel = 2,
  });

  final Widget child;

  /// Panel face fill — keep it translucent enough for the camera to read.
  final Color face;
  final EdgeInsets padding;
  final double outline;
  final double bevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(outline),
      color: kInk,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(color: face, border: pixelBevel(bevel)),
        child: child,
      ),
    );
  }
}

/// Square ink-outlined gear button (opens settings) — shared by the home
/// menu and the in-game HUD so both speak the same pixel language.
class PixelGearButton extends StatefulWidget {
  const PixelGearButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<PixelGearButton> createState() => _PixelGearButtonState();
}

class _PixelGearButtonState extends State<PixelGearButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _down = false),
      child: Transform.translate(
        offset: Offset(0, _down ? 2 : 0),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0B14),
            border: Border.all(color: kInk, width: 2),
          ),
          child: const Icon(Icons.settings, size: 20, color: kWhite),
        ),
      ),
    );
  }
}

/// Hand-authored sprite as a Flutter widget (draws through the shared
/// cached-picture renderer, so it stays crisp and cheap).
class PixelSprite extends StatelessWidget {
  const PixelSprite(
    this.art, {
    super.key,
    this.scale = 2,
    this.palette = const {},
  });

  final List<String> art;
  final int scale;
  final Map<String, Color> palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        art.first.length * scale.toDouble(),
        art.length * scale.toDouble(),
      ),
      painter: _SpritePainter(art, scale, palette),
    );
  }
}

class _SpritePainter extends CustomPainter {
  const _SpritePainter(this.art, this.scale, this.palette);

  final List<String> art;
  final int scale;
  final Map<String, Color> palette;

  @override
  void paint(Canvas canvas, Size size) =>
      drawSprite(canvas, art, x: 0, y: 0, scale: scale, palette: palette);

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.art != art || old.scale != scale || old.palette != palette;
}

/// 3×5 pixel digits as a Flutter widget (same font as the game world).
class PixelNumber extends StatelessWidget {
  const PixelNumber(this.text, {super.key, this.scale = 2, this.color = kWhite});

  final String text;
  final int scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        numberWidth(text, scale).toDouble(),
        5 * scale.toDouble(),
      ),
      painter: _NumberPainter(text, scale, color),
    );
  }
}

class _NumberPainter extends CustomPainter {
  const _NumberPainter(this.text, this.scale, this.color);

  final String text;
  final int scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      drawNumber(canvas, text, x: 0, y: 0, scale: scale, color: color);

  @override
  bool shouldRepaint(_NumberPainter old) =>
      old.text != text || old.scale != scale || old.color != color;
}

/// Two-frame torch flame that ticks on its own clock — menu decoration
/// that reuses the game's own fire sprite with zero asset bytes.
class PixelFlame extends StatefulWidget {
  const PixelFlame({super.key, this.scale = 3});

  final int scale;

  @override
  State<PixelFlame> createState() => _PixelFlameState();
}

class _PixelFlameState extends State<PixelFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1280),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Irregular frame cadence — mostly alternates with occasional holds,
    // same trick as the in-game castle flames.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final bucket = (_t.value * 14).floor();
        final frame = (bucket ^ (bucket >> 2)) & 1;
        return CustomPaint(
          size: Size(
            5 * widget.scale.toDouble(),
            7 * widget.scale.toDouble(),
          ),
          painter: _FlamePainter(frame == 0 ? flameA : flameB, widget.scale),
        );
      },
    );
  }
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter(this.art, this.scale);

  final List<String> art;
  final int scale;

  @override
  void paint(Canvas canvas, Size size) => drawSprite(
        canvas,
        art,
        x: 0,
        y: 0,
        scale: scale,
        palette: flamePalette,
      );

  @override
  bool shouldRepaint(_FlamePainter old) => old.art != art;
}
