import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'm2/pixel_art.dart';
import 'm2/pixel_ui.dart';

/// Pixel-styled settings overlay: debug switches live here (M5), not on the
/// game HUD itself — the HUD only appears when the debug overlay is enabled.
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  builder: (context, _) {
                    final debugOn = settings.debugOverlay;
                    return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RowCard(
                        title: 'DEBUG OVERLAY',
                        hint: 'FPS, ping and pose telemetry on screen',
                        trailing: PixelButton(
                          fill: debugOn ? kGreen : kPanelDark,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          onPressed: () =>
                              settings.setDebugOverlay(!debugOn),
                          label: Text(
                            debugOn ? 'ON' : 'OFF',
                            style: pixelText(10, kWhite),
                          ),
                        ),
                      ),
                      if (debugOn) ...[
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
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double? v) => v == null ? '--' : v.toStringAsFixed(0);
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
