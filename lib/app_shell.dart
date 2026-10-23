import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'camera_gate.dart';
import 'm2/pixel_art.dart';
import 'm2/pixel_ui.dart';
import 'settings_panel.dart';

/// App entry flow (M5): the menu fades in growing small → big with PLAY and
/// EXIT; PLAY boots the camera and drops into the level stack, EXIT closes
/// the app. Settings (debug toggles) open as an overlay on top of either.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

enum _ShellPhase { home, game }

class _AppShellState extends State<AppShell> {
  _ShellPhase _phase = _ShellPhase.home;
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_phase == _ShellPhase.home)
            _HomeMenu(
              onPlay: () => setState(() => _phase = _ShellPhase.game),
              onSettings: () => setState(() => _showSettings = true),
            )
          else
            const CameraGate(),
          if (_showSettings)
            SettingsPanel(
              onClose: () => setState(() => _showSettings = false),
            ),
        ],
      ),
    );
  }
}

class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.onPlay, required this.onSettings});

  final VoidCallback onPlay;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Menu sky: quiet static stars behind everything (zero tick cost).
        const Positioned.fill(
          child: CustomPaint(painter: _StarfieldPainter()),
        ),
        // Entrance: fade in while growing small → big (settles with a pop).
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.55 + 0.45 * t, child: child),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Two-tone title — 'REP' wears the chosen accent hue,
                    // live-updating while the settings panel is open.
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) => Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'REP',
                              style: pixelText(
                                40,
                                AppSettings.instance.accent,
                                shadow: 3,
                              ),
                            ),
                            TextSpan(
                              text: 'EL',
                              style: pixelText(40, kWhite, shadow: 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) => Text(
                        'PUSHUPS ARE ATTACKS — HOLD THE GATE',
                        style: pixelText(8, AppSettings.instance.accent),
                      ),
                    ),
                    const SizedBox(height: 44),
                    // Torches flank the PLAY button — the menu's hearth.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PixelFlame(scale: 3),
                        const SizedBox(width: 22),
                        SizedBox(
                          width: 240,
                          child: PixelButton(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            onPressed: onPlay,
                            label: Text('PLAY',
                                style: pixelText(18, kWhite, shadow: 2)),
                          ),
                        ),
                        const SizedBox(width: 22),
                        const PixelFlame(scale: 3),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PixelButton(
                      fill: kPanelDark,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 10),
                      onPressed: () => SystemNavigator.pop(),
                      label: Text('EXIT', style: pixelText(10, kDimText)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Gear: debug/settings live behind it, off the menu buttons.
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PixelGearButton(onPressed: onSettings),
            ),
          ),
        ),
        // Build tag, kept quiet in the corner.
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('REPEL v0.1-m6', style: pixelText(7, kDimText)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Quiet static starfield behind the home menu — deterministic dots, no
/// animation cost (the entrance animation and torches play on top).
class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter();

  static int _hash(int v) {
    var h = v & 0x7fffffff;
    h ^= h >> 13;
    h *= 0x5bd1e995;
    h ^= h >> 15;
    return h & 0x7fffffff;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width.floor().clamp(1, 1 << 20);
    final ht = size.height.floor().clamp(1, 1 << 20);
    final p = Paint()..isAntiAlias = false;
    for (var i = 0; i < 48; i++) {
      final h = _hash(i * 97 + 17);
      final x = (h % w).toDouble();
      final y = ((h ~/ 11) % ht).toDouble();
      final bright = h % 5 == 0;
      p.color =
          kWhite.withValues(alpha: bright ? 0.75 : 0.22 + (h % 3) * 0.12);
      final s = bright ? 2.0 : 1.0;
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => false;
}
