import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'levels.dart';
import 'pixel_art.dart';
import 'pixel_ui.dart';
import 'repel_game.dart';

/// Main menu / level select (phase == menu): pick any unlocked level,
/// see campaign stats, and the coin balance carried into battle.
///
/// Same pixel-UI language as the shop: ink-outlined panel, beveled cards,
/// Press Start 2P, buttons that press into the face. Locked levels are dim
/// and inert; cleared ones wear a gold border.
class MenuPanel extends StatelessWidget {
  const MenuPanel({super.key, required this.game});

  final RepelGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameSnapshot>(
      valueListenable: game.snapshot,
      builder: (context, snap, _) {
        if (snap.phase != GamePhase.menu) return const SizedBox.shrink();

        final maxH = MediaQuery.sizeOf(context).height - 24;
        return Container(
          color: const Color(0xB30D0B14),
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final level in kLevels)
                            _LevelCard(game: game, snap: snap, level: level),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${level.id}',
                    style: pixelText(
                      16,
                      unlocked ? kWhite : const Color(0xFF5A5470),
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
                      ? const Color(0xFF5A5470)
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
/// here exactly once, with continue / replay / menu choices.
class VictoryPanel extends StatelessWidget {
  const VictoryPanel({super.key, required this.game});

  final RepelGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameSnapshot>(
      valueListenable: game.snapshot,
      builder: (context, snap, _) {
        if (snap.phase != GamePhase.victory) return const SizedBox.shrink();

        final isLast = snap.levelId >= kLevels.length;
        final maxH = MediaQuery.sizeOf(context).height - 24;
        return Container(
          color: const Color(0xB30D0B14),
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
                              '+${snap.victoryBonus} COINS — FIRST CLEAR!',
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
                                game.startLevel(snap.levelId + 1);
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
                              game.startLevel(snap.levelId);
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
                              game.toMenu();
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
        );
      },
    );
  }
}
