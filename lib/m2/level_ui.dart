import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'levels.dart';
import 'pixel_art.dart';
import 'pixel_ui.dart';
import 'repel_game.dart';

/// Main menu / level select (phase == menu): pick any unlocked level from
/// a paged grid (12 cards a page over the 200-level campaign), see campaign
/// stats, and the pushup balance carried into battle.
///
/// Same pixel-UI language as the shop: ink-outlined panel, beveled cards,
/// Press Start 2P, buttons that press into the face. Locked levels are dim
/// and inert; cleared ones wear a gold border. The grid follows the freshly
/// unlocked level until the player browses pages by hand.
class MenuPanel extends StatefulWidget {
  const MenuPanel({super.key, required this.game});

  final RepelGame game;

  @override
  State<MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<MenuPanel> {
  /// Levels per page — 12 cards in a 4 × 3 grid.
  static const int _perPage = 12;

  static int get _pages => (kLevels.length + _perPage - 1) ~/ _perPage;

  int _page = 0;
  int _lastUnlocked = 0;
  bool _browsed = false; // set once the player pages manually

  int _pageOf(int unlocked) =>
      ((unlocked - 1) ~/ _perPage).clamp(0, _pages - 1);

  void _goto(int page) {
    HapticFeedback.selectionClick();
    setState(() {
      _browsed = true;
      _page = page.clamp(0, _pages - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameSnapshot>(
      valueListenable: widget.game.snapshot,
      builder: (context, snap, _) {
        if (snap.phase != GamePhase.menu) return const SizedBox.shrink();

        // Jump to the page holding the next level whenever it unlocks;
        // manual browsing wins from then on.
        if (snap.unlockedLevel != _lastUnlocked) {
          _lastUnlocked = snap.unlockedLevel;
          _page = _pageOf(snap.unlockedLevel);
          _browsed = false;
        }
        final page = _browsed ? _page : _pageOf(snap.unlockedLevel);
        final pageLevels = kLevels
            .skip(page * _perPage)
            .take(_perPage)
            .toList(growable: false);

        final maxH = MediaQuery.sizeOf(context).height - 24;
        return Container(
          color: const Color(0x590D0B14), // translucent: camera stays visible
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 660, maxHeight: maxH),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(3), // hard ink outline
              color: kInk,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: kPanelBg,
                  border: pixelBevel(2),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MenuHeader(snap: snap),
                      const SizedBox(height: 10),
                      // Page row — arrows + "PAGE n / m" over 200 levels.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PixelButton(
                            fill: kPanelDark,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            onPressed:
                                page == 0 ? null : () => _goto(page - 1),
                            label: Text('<',
                                style:
                                    pixelText(10, page == 0 ? kDimText : kWhite)),
                          ),
                          const SizedBox(width: 12),
                          Text('PAGE ${page + 1} / $_pages',
                              style: pixelText(9, kDimText)),
                          const SizedBox(width: 12),
                          PixelButton(
                            fill: kPanelDark,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            onPressed: page >= _pages - 1
                                ? null
                                : () => _goto(page + 1),
                            label: Text('>',
                                style: pixelText(
                                    10, page >= _pages - 1 ? kDimText : kWhite)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final level in pageLevels)
                            _LevelCard(
                                game: widget.game, snap: snap, level: level),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'REPS ${snap.totalReps} · KILLS ${snap.totalKills} '
                        '· BEST COMBO ${snap.bestCombo} · BEST WAVE ${snap.bestWave}',
                        style: pixelText(8, kDimText),
                        textAlign: TextAlign.center,
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

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.snap});

  final GameSnapshot snap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REPEL', style: pixelText(20, kWhite, shadow: 2)),
              const SizedBox(height: 6),
              Text(
                'PUSHUPS ARE ATTACKS — HOLD THE GATE',
                style: pixelText(8, kOrange),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Coin badge: pixel coin + balance.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: kPanelFace,
            border: pixelBevel(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelSprite(coinSprite, scale: 2, palette: coinPalette),
              const SizedBox(width: 8),
              Text('${snap.coins}', style: pixelText(14, kGold)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.game,
    required this.snap,
    required this.level,
  });

  final RepelGame game;
  final GameSnapshot snap;
  final LevelDef level;

  @override
  Widget build(BuildContext context) {
    final unlocked = snap.unlockedLevel >= level.id;
    final cleared = snap.clearedLevel >= level.id;
    final accent = !unlocked
        ? kPanelDark
        : cleared
            ? kGold
            : kOrange;

    final face = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !unlocked
          ? null
          : () {
              HapticFeedback.selectionClick();
              game.startLevel(level.id);
            },
      child: Container(
        width: 138,
        padding: const EdgeInsets.all(2), // accent outline
        color: accent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: unlocked ? kPanelFace : kPanelBg,
            border: pixelBevel(1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Biome strip — each card wears its level's flag hue, so the
              // eight cards read as eight worlds at a glance.
              Container(
                height: 5,
                margin: const EdgeInsets.only(bottom: 7),
                color: unlocked ? level.palette.flag : kLocked,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${level.id}',
                    style: pixelText(
                      16,
                      unlocked ? kWhite : kLocked,
                      shadow: 2,
                    ),
                  ),
                  if (level.bossWave != 0)
                    Text('BOSS', style: pixelText(7, unlocked ? kRed : kDimText))
                  else
                    Text('CALM', style: pixelText(7, kDimText)),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                level.name,
                style: pixelText(8, unlocked ? kWhite : kDimText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                level.tagline,
                style: const TextStyle(fontSize: 9, color: Colors.white54, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                !unlocked
                    ? 'LOCKED'
                    : cleared
                        ? '${level.waves} WAVES · CLEARED'
                        : '${level.waves} WAVES',
                style: pixelText(
                  7,
                  !unlocked
                      ? kLocked
                      : cleared
                          ? kGold
                          : kDimText,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (unlocked) return face;
    return Tooltip(message: 'Clear the previous level to unlock', child: face);
  }
}

/// Victory screen (phase == victory): the level's first-clear bonus lands
/// here exactly once, with continue / replay / menu choices — plus a
/// falling coin-and-star confetti behind the panel.
class VictoryPanel extends StatefulWidget {
  const VictoryPanel({super.key, required this.game});

  final RepelGame game;

  @override
  State<VictoryPanel> createState() => _VictoryPanelState();
}

class _VictoryPanelState extends State<VictoryPanel>
    with SingleTickerProviderStateMixin {
  /// Confetti clock — runs only while the victory panel is visible.
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameSnapshot>(
      valueListenable: widget.game.snapshot,
      builder: (context, snap, _) {
        final visible = snap.phase == GamePhase.victory;
        if (visible && !_t.isAnimating) _t.repeat();
        if (!visible && _t.isAnimating) _t.stop();
        if (!visible) return const SizedBox.shrink();

        final isLast = snap.levelId >= kLevels.length;
        final maxH = MediaQuery.sizeOf(context).height - 24;
        return Stack(
          children: [
            Container(
              color: const Color(0x730D0B14), // translucent: camera stays visible
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 460, maxHeight: maxH),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(3),
                  color: kInk,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kPanelBg,
                      border: pixelBevel(2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LEVEL ${snap.levelId} CLEARED',
                          style: pixelText(16, kGold, shadow: 2),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(snap.levelName, style: pixelText(10, kWhite)),
                        const SizedBox(height: 12),
                        // Reward line — first clear pays out, replays don't.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: kPanelFace,
                            border: pixelBevel(1),
                          ),
                          child: Column(
                            children: [
                          if (snap.victoryBonus > 0)
                            Text(
                              '+${snap.victoryBonus} PUSHUPS — FIRST CLEAR!',
                              style: pixelText(9, kGold),
                            )
                          else
                            Text(
                              'FIRST-CLEAR BONUS ALREADY CLAIMED',
                              style: pixelText(7, kDimText),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PixelSprite(coinSprite,
                                  scale: 2, palette: coinPalette),
                              const SizedBox(width: 8),
                              Text('${snap.coins}', style: pixelText(12, kWhite)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: PixelButton(
                        fill: kOrange,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: isLast
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                widget.game.startLevel(snap.levelId + 1);
                              },
                        label: Text(
                          isLast ? 'CAMPAIGN COMPLETE!' : 'NEXT LEVEL',
                          style: pixelText(11, isLast ? kDimText : kWhite,
                              shadow: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PixelButton(
                            fill: kPanelDark,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.game.startLevel(snap.levelId);
                            },
                            label: Text('REPLAY',
                                style: pixelText(9, kWhite)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PixelButton(
                            fill: kPanelDark,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.game.toMenu();
                            },
                            label: Text('LEVEL SELECT',
                                style: pixelText(9, kWhite)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
          // Coin-and-star confetti raining over the celebration.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) => CustomPaint(
                  painter: _CoinRainPainter(_t.value),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  }
}

/// Falling coins and stars behind the victory panel — deterministic
/// positions, quantized alpha steps, sprite pictures cached by the
/// shared renderer.
class _CoinRainPainter extends CustomPainter {
  const _CoinRainPainter(this.t);

  final double t;

  static int _hash(int v) {
    var h = v & 0x7fffffff;
    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 24 || size.height <= 24) return;
    for (var i = 0; i < 12; i++) {
      final h = _hash(i * 71 + 13);
      final phase = (h % 100) / 100;
      final progress = (t + phase) % 1;
      final x = ((h ~/ 3) % (size.width - 24).floor()).toDouble();
      final y = -24.0 + progress * (size.height + 48);
      // Quantized fade: in at the top, out at the bottom (3 hard steps).
      final fade = progress < 0.12
          ? progress / 0.12
          : progress > 0.82
              ? (1 - progress) / 0.18
              : 1.0;
      final alpha = ((fade.clamp(0.0, 1.0) * 3).floor() / 3) * 0.9;
      final star = h % 3 == 0;
      drawSprite(
        canvas,
        star ? starIcon : coinSprite,
        x: x,
        y: y,
        scale: 2,
        palette: star ? iconPalette(kGold) : coinPalette,
        tint: kGold.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_CoinRainPainter old) => old.t != t;
}
