import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'economy.dart';
import 'pixel_art.dart';
import 'repel_game.dart';

Border _bevel(double w) => Border(
      top: BorderSide(color: kPanelLight, width: w),
      left: BorderSide(color: kPanelLight, width: w),
      bottom: BorderSide(color: kPanelDark, width: w),
      right: BorderSide(color: kPanelDark, width: w),
    );

const _dimText = Color(0xFF8B84A8);

TextStyle _px(double size, Color color, {double shadow = 1}) => TextStyle(
      fontFamily: kPixelFont,
      fontSize: size,
      color: color,
      shadows: [
        Shadow(color: kInk, offset: Offset(shadow, shadow), blurRadius: 0),
      ],
    );

/// The between-waves shop (and the defeat screen): buy the 4 upgrades with
/// coins earned from kills and wave clears, then start the next wave.
///
/// Handcrafted pixel UI: hard square corners, ink outlines, beveled panel
/// faces, Press Start 2P headings, buttons that press *into* the panel, a
/// segmented rest bar, and purchase feedback that floats off the card.
class ShopPanel extends StatelessWidget {
  const ShopPanel({super.key, required this.game});

  final RepelGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameSnapshot>(
      valueListenable: game.snapshot,
      builder: (context, snap, _) {
        final showShop =
            snap.phase == GamePhase.waveCleared || snap.phase == GamePhase.defeat;
        if (!showShop) return const SizedBox.shrink();

        final defeated = snap.phase == GamePhase.defeat;
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final maxH = MediaQuery.sizeOf(context).height - 24;

        return Container(
          color: const Color(0xB30D0B14),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 620, maxHeight: maxH),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(3), // hard ink outline
              color: kInk,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: kPanelBg,
                  border: _bevel(2),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(game: game, snap: snap, defeated: defeated),
                      const SizedBox(height: 14),
                      // Upgrade cards — a row on landscape, stacked otherwise.
                      if (landscape)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final t in UpgradeType.values)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: _UpgradeCard(
                                    game: game,
                                    snap: snap,
                                    type: t,
                                  ),
                                ),
                              ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (final t in UpgradeType.values)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: _UpgradeCard(
                                  game: game,
                                  snap: snap,
                                  type: t,
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: _PixelButton(
                          fill: defeated ? kRed : kOrange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            defeated ? game.retryWave() : game.nextWave();
                          },
                          label: Text(
                            defeated
                                ? 'RETRY WAVE ${snap.wave}'
                                : 'START NEXT WAVE',
                            style: _px(12, kWhite, shadow: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.game, required this.snap, required this.defeated});

  final RepelGame game;
  final GameSnapshot snap;
  final bool defeated;

  @override
  Widget build(BuildContext context) {
    final rest = snap.restSeconds.clamp(0, 10);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                defeated ? 'BASE DESTROYED' : 'WAVE ${snap.wave} CLEARED',
                style: _px(16, defeated ? kRed : kWhite, shadow: 2),
              ),
              if (!defeated) ...[
                const SizedBox(height: 8),
                // Rest countdown — tapping it starts the wave early,
                // exactly as the subtitle promises.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    game.nextWave();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('REST', style: _px(9, _dimText)),
                          const SizedBox(width: 8),
                          for (var i = 0; i < 10; i++)
                            Container(
                              width: 9,
                              height: 9,
                              margin: EdgeInsets.only(right: i < 9 ? 2 : 0),
                              color: i < rest
                                  ? kOrange
                                  : const Color(0xFF3A3352),
                            ),
                          const SizedBox(width: 8),
                          Text('${snap.restSeconds}', style: _px(9, kWhite)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Rest ${snap.restSeconds}s — tap to start early',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 5),
                Text(
                  'Best wave ${snap.bestWave} — upgrade and go again',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Coin badge: pixel coin + count that pops when it changes.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: kPanelFace,
            border: _bevel(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PixelSprite(coinSprite, scale: 2, palette: coinPalette),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 1.4, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
                child: Text(
                  '${snap.coins}',
                  key: ValueKey(snap.coins),
                  style: _px(14, kGold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpgradeCard extends StatefulWidget {
  const _UpgradeCard({
    required this.game,
    required this.snap,
    required this.type,
  });

  final RepelGame game;
  final GameSnapshot snap;
  final UpgradeType type;

  @override
  State<_UpgradeCard> createState() => _UpgradeCardState();
}

class _UpgradeCardState extends State<_UpgradeCard> {
  int _purchases = 0;
  int _lastPaid = 0;

  @override
  Widget build(BuildContext context) {
    final level = widget.snap.levels[widget.type] ?? 0;
    final cost = upgradeCost(widget.type, level);
    final affordable = cost != null && widget.snap.coins >= cost;
    final maxLv = upgradeMaxLevel(widget.type);
    final paid = _lastPaid;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2), // accent outline when affordable
          color: affordable ? kOrange : kPanelDark,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: affordable ? kPanelFace : kPanelBg,
              border: _bevel(1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  upgradeName(widget.type),
                  style: _px(10, affordable ? kWhite : _dimText),
                ),
                const SizedBox(height: 6),
                // Level pips on an ink backing — instant level read.
                Container(
                  padding: const EdgeInsets.all(2),
                  color: kInk,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < maxLv; i++)
                        Container(
                          width: 5,
                          height: 5,
                          margin:
                              EdgeInsets.only(right: i < maxLv - 1 ? 2 : 0),
                          color: i < level
                              ? kGold
                              : const Color(0xFF3A3352),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  upgradeEffect(widget.type, level),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: _PixelButton(
                    fill: kOrange,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    onPressed: (cost == null || !affordable)
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            final paidCost = cost;
                            final ok = widget.game.buyUpgrade(widget.type);
                            if (ok) {
                              setState(() {
                                _purchases++;
                                _lastPaid = paidCost;
                              });
                            }
                          },
                    label: cost == null
                        ? Text('MAX LEVEL', style: _px(10, _dimText))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('BUY', style: _px(10, kWhite)),
                              const SizedBox(width: 8),
                              const _PixelSprite(coinSprite,
                                  scale: 2, palette: coinPalette),
                              const SizedBox(width: 4),
                              Text('$cost', style: _px(10, kWhite)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Purchase feedback: the paid amount floats up and fades, pixel style.
        if (_purchases > 0)
          Positioned(
            top: -10,
            right: 6,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_purchases),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              builder: (context, t, child) => Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(0, -20 * t), child: child),
              ),
              child: IgnorePointer(
                child: _PixelNumber('-$paid', color: kGold, scale: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Square pixel button: no Material chrome, ink outline, hard drop shadow,
/// and a press state that shoves the face 2px down (shadow swallows it).
class _PixelButton extends StatefulWidget {
  const _PixelButton({
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
  State<_PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<_PixelButton> {
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
class _PixelSprite extends StatelessWidget {
  const _PixelSprite(
    this.art, {
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
class _PixelNumber extends StatelessWidget {
  const _PixelNumber(this.text, {this.scale = 2, this.color = kWhite});

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
