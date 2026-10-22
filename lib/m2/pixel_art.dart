/// Pixel-art rendering helpers: hand-authored sprites drawn as crisp
/// integer-scaled rectangles (nearest-neighbor, no antialiasing, no
/// gradients), a 3×5 pixel digit font for numbers, and segmented bars.
///
/// Sprites are recorded to [ui.Picture]s once per (art, scale, palette)
/// combination and cached, so per-frame cost is a single `drawPicture`.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bundled 8-bit UI font (Press Start 2P, SIL OFL).
const kPixelFont = 'PressStart2P';

// ---------------------------------------------------------------------------
// Shared palette — limited, warm, consistent across the whole game.
// ---------------------------------------------------------------------------
const kOutline = Color(0xFF17131F); // sprite outlines / borders
const kInk = Color(0xFF0D0B14); // deepest shadow, panel outline
const kWhite = Color(0xFFF4F0E6); // warm white (eyes, glints, text)
const kPanelBg = Color(0xFF241E38); // UI panel face
const kPanelFace = Color(0xFF2B2447); // card face (slightly lighter)
const kPanelLight = Color(0xFF4A4166); // bevel highlight
const kPanelDark = Color(0xFF17121F); // bevel shadow
const kGold = Color(0xFFF2B33D); // coins
const kGoldLight = Color(0xFFFFD75E);
const kGoldDark = Color(0xFFB57A21);
const kOrange = Color(0xFFE8622A); // brand accent (buttons, ground edge)
const kOrangeDark = Color(0xFFB34A1F);
const kRed = Color(0xFFD64550); // danger
const kRedDark = Color(0xFF8E2733);
const kBlue = Color(0xFF4FC3F7); // auto-attack tracers
const kGreen = Color(0xFF6FBF73);

/// Multiply toward black (shade a base color).
Color pixelShade(Color c, double f) {
  final argb = c.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return Color.fromARGB(
    (argb >> 24) & 0xFF,
    (r * f).round(),
    (g * f).round(),
    (b * f).round(),
  );
}

/// Mix toward white (highlight a base color).
Color pixelLighten(Color c, double f) {
  final argb = c.toARGB32();
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return Color.fromARGB(
    a,
    (r + (255 - r) * f).round(),
    (g + (255 - g) * f).round(),
    (b + (255 - b) * f).round(),
  );
}

/// Palette for the blob enemies: base/dark/light shades of one hue plus the
/// shared outline + face colors.
Map<String, Color> huePalette(Color base) => {
      'o': kOutline,
      'c': base,
      'd': pixelShade(base, 0.55),
      'l': pixelLighten(base, 0.35),
      'w': kWhite,
      'p': kInk,
      'y': kGoldLight,
    };

// ---------------------------------------------------------------------------
// Hand-authored sprites. Characters: '.' = transparent, everything else is
// resolved through the palette passed to [drawSprite].
// ---------------------------------------------------------------------------

/// Grumbler (basic enemy) — 12×12, facing left. Frame A = stance, B = step.
const grumblerA = <String>[
  '...oooooo...',
  '.ooccccccoo.',
  'oclllcccccco',
  'occwwccwwcco',
  'occpwccpwcco',
  'occlldccccco',
  'occlllccccco',
  'occccllccccc',
  'occcccccccco',
  '.occcccccco.',
  '.oooccccooo.',
  '..o.oo.oo...',
];
const grumblerB = <String>[
  '...oooooo...',
  '.ooccccccoo.',
  'oclllcccccco',
  'occwwccwwcco',
  'occpwccpwcco',
  'occlldccccco',
  'occlllccccco',
  'occccllccccc',
  'occcccccccco',
  '.occcccccco.',
  '..ooccccoo..',
  '...oo..oo...',
];

/// Boss grumbler — 16×16, horns + tusks + angry gold eyes.
const bossA = <String>[
  'o..oooooooo..o.o', // placeholder horns row (fixed in tests if odd)
  '.oooyyyyyyoooo..',
  'ooyyyyyyyyyyyoo.',
  'oyywwyyyywwyyyo.',
  'oyywpyyyyywpyyo.',
  'oyyyyyyyyyyyyyo.',
  'oyyyooooyyyyo.y.',
  'oyyooccooyyyoy.o',
  'oyyyyoooyyyyoy.o',
  'oyyyyyyyyyyyyo..',
  'oyyllyyyyyyllyo.',
  'oyyyyyyyyyyyyyo.',
  '.oyyyyyyyyyyyo..',
  '.oyoyyyyyoyoo...',
  '..ooooooo.oo....',
  '...oo..oo.......',
];
const bossB = <String>[
  'o..oooooooo..o.o',
  '.oooyyyyyyoooo..',
  'ooyyyyyyyyyyyoo.',
  'oyywwyyyywwyyyo.',
  'oyywpyyyyywpyyo.',
  'oyyyyyyyyyyyyyo.',
  'oyyyooooyyyyo.y.',
  'oyyooccooyyyoy.o',
  'oyyyyoooyyyyoy.o',
  'oyyyyyyyyyyyyo..',
  'oyyllyyyyyyllyo.',
  'oyyyyyyyyyyyyyo.',
  '.oyyyyyyyyyyyo..',
  '.oyoyyyyyoyoo...',
  '..ooooooo.oo....',
  '.....oo.........',
];

/// Coin — 7×7, beveled gold with a single bright glint pixel.
const coinSprite = <String>[
  '..ooo..',
  '.olmmo.',
  'olwmmdo',
  'olmmmdo',
  'olmmmdo',
  '.olmmo.',
  '..ooo..',
];

/// Torch flame — 5×7, two flicker frames.
const flameA = <String>[
  '..y..',
  '.yyy.',
  '.ywy.',
  'ymmmy',
  'ymmmy',
  'odmmo',
  '.ooo.',
];
const flameB = <String>[
  '.y...',
  'yyy..',
  '.ywy.',
  'ymmmy',
  'ymmmy',
  'odmmo',
  '.ooo.',
];

/// Palette for [coinSprite] (beveled gold, dark outline + glint).
const coinPalette = <String, Color>{
  'o': Color(0xFF6E4A16),
  'l': kGoldLight,
  'm': kGold,
  'd': kGoldDark,
  'w': Color(0xFFFFF6C8),
};

/// Palette for [flameA]/[flameB] (torch fire: white-hot core, ember base).
const flamePalette = <String, Color>{
  'o': Color(0xFF8A2E12),
  'y': Color(0xFFFFD54F),
  'm': Color(0xFFFF8A3D),
  'd': Color(0xFFD84315),
  'w': Color(0xFFFFF8E1),
};

// ---------------------------------------------------------------------------
// 3×5 pixel digit font (used for all in-world numbers: damage, coins).
// ---------------------------------------------------------------------------
const kDigits = <String, List<String>>{
  '0': ['111', '101', '101', '101', '111'],
  '1': ['010', '110', '010', '010', '111'],
  '2': ['111', '001', '111', '100', '111'],
  '3': ['111', '001', '111', '001', '111'],
  '4': ['101', '101', '111', '001', '001'],
  '5': ['111', '100', '111', '001', '111'],
  '6': ['111', '100', '111', '101', '111'],
  '7': ['111', '001', '001', '010', '010'],
  '8': ['111', '101', '111', '101', '111'],
  '9': ['111', '101', '111', '001', '111'],
  '-': ['000', '000', '111', '000', '000'],
  '+': ['000', '010', '111', '010', '000'],
  ' ': ['000', '000', '000', '000', '000'],
};

/// Pixel width of [text] drawn by [drawNumber] at [scale] (glyph 3px + 1px
/// gap, minus the trailing gap).
int numberWidth(String text, int scale) =>
    text.isEmpty ? 0 : text.length * 4 * scale - scale;

/// Draws [text] with the 3×5 pixel font. Monospace grid — no font loading,
/// perfectly crisp at any integer [scale].
void drawNumber(
  Canvas canvas,
  String text, {
  required double x,
  required double y,
  int scale = 2,
  Color color = kWhite,
  bool center = false,
}) {
  final w = numberWidth(text, scale);
  final ox = center ? x - w / 2 : x;
  final paint = Paint()..isAntiAlias = false..color = color;
  var cursor = ox;
  for (final ch in text.split('')) {
    final glyph = kDigits[ch];
    if (glyph == null) {
      cursor += 4 * scale;
      continue;
    }
    for (var r = 0; r < glyph.length; r++) {
      final row = glyph[r];
      for (var c = 0; c < row.length; c++) {
        if (row[c] != '1') continue;
        canvas.drawRect(
          Rect.fromLTWH(
            cursor + c * scale,
            y + r * scale,
            scale.toDouble(),
            scale.toDouble(),
          ),
          paint,
        );
      }
    }
    cursor += 4 * scale;
  }
}

// ---------------------------------------------------------------------------
// Sprite drawing with picture cache.
// ---------------------------------------------------------------------------
final Map<String, ui.Picture> _spriteCache = {};

/// Draws hand-authored [rows] at (x, y), each art-pixel becoming [scale]×[scale]
/// screen pixels. Rendering is cached per (art, scale, palette, tint).
void drawSprite(
  Canvas canvas,
  List<String> rows, {
  required double x,
  required double y,
  int scale = 1,
  Map<String, Color> palette = const {},
  Color? tint,
}) {
  final key = '${identityHashCode(rows)}|$scale|'
      '${tint == null ? '' : tint.toARGB32().toRadixString(16)}|'
      '${palette.entries.map((e) => '${e.key}${e.value.toARGB32().toRadixString(16)}').join()}';
  final picture = _spriteCache.putIfAbsent(
    key,
    () => _recordSprite(rows, scale, palette, tint),
  );
  canvas.save();
  canvas.translate(x, y);
  canvas.drawPicture(picture);
  canvas.restore();
}

ui.Picture _recordSprite(
  List<String> rows,
  int scale,
  Map<String, Color> palette,
  Color? tint,
) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..isAntiAlias = false;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      if (ch == '.') continue;
      final color = tint ?? palette[ch];
      if (color == null) continue;
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTWH(
          (c * scale).toDouble(),
          (r * scale).toDouble(),
          scale.toDouble(),
          scale.toDouble(),
        ),
        paint,
      );
    }
  }
  return recorder.endRecording();
}

/// Segmented pixel health/progress bar: hard border, quantized fill steps,
/// tick marks between cells — no gradients.
void drawPixelBar(
  Canvas canvas, {
  required double x,
  required double y,
  required double w,
  required double h,
  required double ratio,
  Color fg = kGreen,
  Color bg = kPanelDark,
  Color border = kInk,
  double cell = 6,
  int borderW = 2,
}) {
  ratio = ratio.clamp(0.0, 1.0);
  final outer = Paint()..isAntiAlias = false..color = border;
  final fill = Paint()..isAntiAlias = false;
  canvas.drawRect(Rect.fromLTWH(x, y, w, h), outer);
  final ix = x + borderW, iy = y + borderW;
  final iw = w - borderW * 2, ih = h - borderW * 2;
  fill.color = bg;
  canvas.drawRect(Rect.fromLTWH(ix, iy, iw, ih), fill);
  if (ratio <= 0) return;
  // Quantize to whole cells so the bar advances in chunky pixel steps.
  final cells = (iw / cell).ceil();
  final on = (ratio * cells).ceil();
  fill.color = fg;
  for (var i = 0; i < on; i++) {
    final cw = cell.clamp(0, iw - i * cell).toDouble();
    canvas.drawRect(Rect.fromLTWH(ix + i * cell, iy, cw, ih), fill);
  }
}
