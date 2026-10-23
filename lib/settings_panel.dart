import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'm2/pixel_art.dart';
import 'm2/pixel_ui.dart';

/// Pixel-styled settings overlay (M5.3): accent theme swatches, game-feel
/// switches (shake / hit flash / particles / haptics), and the debug
/// telemetry section from M5.
///
/// [renderFps] is passed when opened in-game; on the home menu there is no
/// frame pipeline to sample, so readouts show '--'.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.onClose,
    this.renderFps,
    this.inferenceFps,
    this.inferenceMs,
  });

  final VoidCallback onClose;
  final double? renderFps;
  final double? inferenceFps;
  final int? inferenceMs;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final maxH = MediaQuery.sizeOf(context).height - 48;

    return Container(
      color: const Color(0x990D0B14),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxH),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(3), // hard ink outline
          color: kInk,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: kPanelBg,
              border: pixelBevel(2),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('SETTINGS', style: pixelText(16, kWhite, shadow: 2)),
                      PixelButton(
                        fill: kPanelDark,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        onPressed: onClose,
                        label: Text('X', style: pixelText(10, kDimText)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: settings,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ---- accent theme --------------------------------
                        _SectionLabel('ACCENT'),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kPanelFace,
                            border: pixelBevel(1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final e in kAccents.entries)
                                    _AccentSwatch(
                                      name: e.key,
                                      color: e.value,
                                      selected:
                                          settings.accentName == e.key,
                                      onTap: () => settings.setAccent(e.key),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${settings.accentName} — tints buttons, '
                                'labels and the menu tagline',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ---- game feel ----------------------------------
                        _SectionLabel('GAME FEEL'),
                        const SizedBox(height: 6),
                        _RowCard(
                          title: 'SCREEN SHAKE',
                          hint: 'Camera punch on hits and kills',
                          trailing: _SwitchButton(
                            on: settings.screenShake,
                            onTap: () => settings
                                .setScreenShake(!settings.screenShake),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RowCard(
                          title: 'HIT FLASH',
                          hint: 'How hard enemies light up when hit',
                          trailing: _CycleButton(
                            values: AppSettings.flashModes,
                            value: settings.hitFlash,
                            colorOf: (v) => switch (v) {
                              'FULL' => kGreen,
                              'DIM' => kGold,
                              _ => kPanelDark,
                            },
                            onTap: () {
                              final i = AppSettings.flashModes
                                  .indexOf(settings.hitFlash);
                              settings.setHitFlash(AppSettings
                                  .flashModes[(i + 1) %
                                      AppSettings.flashModes.length]);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RowCard(
                          title: 'PARTICLES',
                          hint: 'Sparks, poofs and drifting embers',
                          trailing: _SwitchButton(
                            on: settings.particles,
                            onTap: () =>
                                settings.setParticles(!settings.particles),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RowCard(
                          title: 'HAPTICS',
                          hint: 'Vibration on every counted rep',
                          trailing: _SwitchButton(
                            on: settings.haptics,
                            onTap: () =>
                                settings.setHaptics(!settings.haptics),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RowCard(
                          title: 'REP SENSITIVITY',
                          hint: 'How long a bad pose pauses counting — '
                              'FORGIVING if real reps get dropped',
                          trailing: _CycleButton(
                            values: AppSettings.repSensitivityModes,
                            value: settings.repSensitivity,
                            colorOf: (v) => switch (v) {
                              'STRICT' => kRed,
                              'NORMAL' => kGreen,
                              _ => kGold,
                            },
                            onTap: () {
                              final i = AppSettings.repSensitivityModes
                                  .indexOf(settings.repSensitivity);
                              settings.setRepSensitivity(AppSettings
                                  .repSensitivityModes[(i + 1) %
                                      AppSettings.repSensitivityModes.length]);
                            },
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ---- debug --------------------------------------
                        _SectionLabel('DEBUG'),
                        const SizedBox(height: 6),
                        _RowCard(
                          title: 'DEBUG OVERLAY',
                          hint: 'FPS, ping and pose telemetry on screen',
                          trailing: _SwitchButton(
                            on: settings.debugOverlay,
                            onTap: () => settings
                                .setDebugOverlay(!settings.debugOverlay),
                          ),
                        ),
                        if (settings.debugOverlay) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kPanelFace,
                              border: pixelBevel(1),
                            ),
                            child: Text(
                              'UI FPS ${_fmt(renderFps)}'
                              ' · POSE ${_fmt(inferenceFps)} FPS'
                              '${inferenceMs != null ? ' $inferenceMs MS' : ''}'
                              ' · PING --',
                              style: pixelText(8, kWhite),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Ping shows real latency once online play ships; '
                            'until then there is no server to talk to.',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double? v) => v == null ? '--' : v.toStringAsFixed(0);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: pixelText(8, kDimText)),
        const SizedBox(width: 8),
        const Expanded(
          child: ColoredBox(
            color: kPanelLight,
            child: SizedBox(height: 1),
          ),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(3),
          // Selected swatches wear a white ink outline around the hue.
          color: selected ? kWhite : kInk,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              border: Border(
                top: BorderSide(color: pixelLighten(color, 0.3), width: 2),
                left: BorderSide(color: pixelLighten(color, 0.3), width: 2),
                bottom: BorderSide(color: pixelShade(color, 0.6), width: 2),
                right: BorderSide(color: pixelShade(color, 0.6), width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ON/OFF pill button shared by the boolean game-feel switches.
class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PixelButton(
      fill: on ? kGreen : kPanelDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      onPressed: onTap,
      label: Text(on ? 'ON' : 'OFF', style: pixelText(10, kWhite)),
    );
  }
}

/// Multi-value pill button (hit flash cycles FULL → DIM → OFF).
class _CycleButton extends StatelessWidget {
  const _CycleButton({
    required this.values,
    required this.value,
    required this.colorOf,
    required this.onTap,
  });

  final List<String> values;
  final String value;
  final Color Function(String) colorOf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PixelButton(
      fill: colorOf(value),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      onPressed: onTap,
      label: Text(value, style: pixelText(9, kWhite)),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.title,
    required this.hint,
    required this.trailing,
  });

  final String title;
  final String hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kPanelFace,
        border: pixelBevel(1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: pixelText(9, kWhite)),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54, height: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}
