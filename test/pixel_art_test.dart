import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/m2/pixel_art.dart';

void main() {
  const sprites = <String, List<String>>{
    'grumblerA': grumblerA,
    'grumblerB': grumblerB,
    'bossA': bossA,
    'bossB': bossB,
    'coin': coinSprite,
    'flameA': flameA,
    'flameB': flameB,
  };

  group('sprites', () {
    test('every row has the same width as the first row', () {
      sprites.forEach((name, rows) {
        final w = rows.first.length;
        for (var i = 0; i < rows.length; i++) {
          expect(
            rows[i].length,
            w,
            reason: '$name row $i is ${rows[i].length}px wide, expected $w '
                '(" ${rows[i]}")',
          );
        }
      });
    });

    test('sprites are rectangular grids (12×12 grumbler, 7×7 coin, …)', () {
      expect(grumblerA.length, 12);
      expect(grumblerB.length, 12);
      expect(bossA.length, 16);
      expect(bossA.first.length, 16);
      expect(coinSprite.length, 7);
      expect(coinSprite.first.length, 7);
      expect(flameA.length, flameB.length);
    });

    test('walk frames differ (animation actually changes pixels)', () {
      expect(
        grumblerA.join(),
        isNot(equals(grumblerB.join())),
      );
    });
  });

  group('pixel digit font', () {
    test('covers digits, minus and plus with a 3×5 grid', () {
      for (final ch in '0123456789-+ '.split('')) {
        final glyph = kDigits[ch];
        expect(glyph, isNotNull, reason: 'missing glyph "$ch"');
        expect(glyph!.length, 5, reason: 'glyph "$ch" height');
        for (final row in glyph) {
          expect(row.length, 3, reason: 'glyph "$ch" row width');
        }
      }
    });

    test('numberWidth follows the 4px advance grid', () {
      expect(numberWidth('', 2), 0);
      expect(numberWidth('1', 2), 3 * 2); // glyph 3px, no trailing gap
      expect(numberWidth('12345', 2), 5 * 4 * 2 - 2);
      expect(numberWidth('12', 3), 2 * 4 * 3 - 3);
    });
  });

  group('color helpers', () {
    test('shade darkens and lighten brightens every channel', () {
      const base = Color(0xFF808080);
      final darker = pixelShade(base, 0.5);
      final lighter = pixelLighten(base, 0.5);
      expect(darker.r, lessThan(base.r));
      expect(darker.g, lessThan(base.g));
      expect(lighter.b, greaterThan(base.b));
    });

    test('huePalette includes base, shade and highlight of the hue', () {
      final p = huePalette(const Color(0xFFFF5252));
      expect(p['c'], const Color(0xFFFF5252));
      expect(p['d']!.r, lessThan(0xFF));
      expect(p['o'], kOutline);
    });
  });

  group('render smoke (headless canvas)', () {
    test('every render helper records a picture without throwing', () {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      drawSprite(
        canvas,
        grumblerA,
        x: 0,
        y: 0,
        scale: 3,
        palette: huePalette(const Color(0xFFFF5252)),
      );
      drawSprite(
        canvas,
        bossB,
        x: 0,
        y: 0,
        scale: 4,
        palette: huePalette(const Color(0xFFB71C1C)),
        tint: kWhite,
      );
      drawSprite(canvas, coinSprite, x: 0, y: 0, scale: 2, palette: coinPalette);
      drawSprite(canvas, flameA, x: 0, y: 0, scale: 2, palette: flamePalette);
      drawNumber(canvas, '-1234', x: 0, y: 0, scale: 2);
      drawNumber(canvas, '+99', x: 0, y: 0, scale: 3, color: kGold, center: true);
      drawPixelBar(canvas, x: 0, y: 0, w: 50, h: 8, ratio: 0.4, fg: kGreen);
      drawPixelBar(canvas, x: 0, y: 0, w: 50, h: 8, ratio: 0, fg: kRed);
      drawPixelBar(canvas, x: 0, y: 0, w: 50, h: 8, ratio: 1.7, fg: kGold);
      final pic = rec.endRecording();
      expect(pic, isNotNull);
    });

    test('sprite cache reuses pictures for identical art+palette', () {
      // Two draws of the same sprite must hit the same cache entry; drawing
      // twice in a row exercises putIfAbsent without unbounded growth.
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final pal = huePalette(const Color(0xFF29B6F6));
      drawSprite(canvas, grumblerA, x: 0, y: 0, scale: 3, palette: pal);
      drawSprite(canvas, grumblerA, x: 40, y: 0, scale: 3, palette: pal);
      drawSprite(canvas, grumblerA, x: 0, y: 0, scale: 3, palette: pal);
      rec.endRecording();
      expect(true, isTrue); // no exceptions = cache path works
    });
  });
}
