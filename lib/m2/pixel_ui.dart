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
            border: Border.all(color: kInk, width: 2),
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
