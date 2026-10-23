import 'package:camera/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../app_settings.dart';
import '../m2/economy.dart';
import '../m2/game_camera.dart';
import '../m2/pixel_art.dart';
import '../m2/pixel_ui.dart';
import '../m2/level_ui.dart';
import '../m2/repel_game.dart';
import '../m2/shop_panel.dart';
import '../settings_panel.dart';
import 'pose_detector_service.dart';
import 'pose_overlay.dart';
import 'pushup_counter.dart';
import 'pushup_gate.dart';

/// Live camera preview + pose skeleton + pushup counter (M1) with the M2
/// combat game rendered transparently on top: every counted rep fires at
/// the monsters marching at your castle.
class PoseScreen extends StatefulWidget {
  const PoseScreen({
    super.key,
    required this.controller,
    required this.camera,
  });

  final CameraController controller;
  final CameraDescription camera;

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> with WidgetsBindingObserver {
  static const _orientationChannel =
      MethodChannel('repel/device_orientation');

  final _service = PoseDetectorService();
  final _counter = PushupCounter();
  final _gate = const PushupGate();
  final _game = RepelGame();

  /// Display rotation in degrees (0/90/180/270) as reported by Android's
  /// Surface.ROTATION — portrait is the natural orientation of phones.
  int _deviceDegrees = 0;

  Pose? _pose;
  DateTime? _lastPoseAt;
  double? _elbowAngle;
  Size? _imageSize; // raw (unrotated) frame size of the latest image
  /// Per-arm landmark visibility for the HUD: 0 = not seen, 1 = shaky,
  /// 2 = confident (see [_elbowAngleOf]).
  int _leftArm = 0;
  int _rightArm = 0;

  /// Latest verdict of the anti-cheat pose gate (front-view pushup check).
  PushupVerdict _verdict = PushupVerdict.noBody;
  double _inferenceFps = 0;
  int _fpsCounter = 0;
  DateTime _fpsWindow = DateTime.now();

  /// Render (UI) FPS sampled once per second from frame timings — shown by
  /// the debug overlay (Settings → Debug overlay).
  double _renderFps = 0;
  int _frameCount = 0;
  DateTime _frameWindow = DateTime.now();

  bool _showSettings = false;
  bool _showMore = false;

  /// True while the toolbar SHOP button holds the shop open mid-run
  /// (the game engine is paused behind it).
  bool _shopOpen = false;

  /// Zone toolbar height — the seam bar between game (top) and camera
  /// (bottom) that hosts SETTINGS / SHOP / MORE.
  static const _toolbarH = 40.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _readOrientation();
    _startStream();
  }

  /// Rolling render-FPS meter driven by the engine's own frame timings.
  void _onFrameTimings(List<FrameTiming> timings) {
    _frameCount += timings.length;
    final now = DateTime.now();
    final elapsed = now.difference(_frameWindow).inMilliseconds;
    if (elapsed >= 1000) {
      final fps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _frameWindow = now;
      if (mounted && AppSettings.instance.debugOverlay) {
        setState(() => _renderFps = fps);
      }
    }
  }

  /// Asks Android which way the screen is currently rotated.
  /// (iOS: falls back to portrait — revisit when building for iPhone.)
  Future<void> _readOrientation() async {
    try {
      final degrees =
          await _orientationChannel.invokeMethod<int>('getRotationDegrees');
      if (degrees != null && mounted) {
        setState(() => _deviceDegrees = degrees);
      }
    } on PlatformException {
      // Keep the last known value.
    } on MissingPluginException {
      // Non-Android platform without the channel — keep the default.
    }
  }

  Future<void> _startStream() async {
    try {
      if (!widget.controller.value.isStreamingImages) {
        await widget.controller.startImageStream(_onFrame);
      }
    } on CameraException catch (e) {
      debugPrint('Image stream start error: $e');
    }
  }

  Future<void> _stopStream() async {
    try {
      if (widget.controller.value.isStreamingImages) {
        await widget.controller.stopImageStream();
      }
    } on CameraException catch (e) {
      debugPrint('Image stream stop error: $e');
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = _rotationForCamera();
    await _service.processCameraImage(
      image,
      InputImageRotationValue.fromRawValue(rotation) ??
          InputImageRotation.rotation0deg,
      onPose: _onPose,
    );

    // Rolling inference-FPS meter (updated roughly once per second).
    _fpsCounter++;
    final now = DateTime.now();
    final elapsed = now.difference(_fpsWindow).inMilliseconds;
    if (elapsed >= 1000) {
      _inferenceFps = _fpsCounter * 1000 / elapsed;
      _fpsCounter = 0;
      _fpsWindow = now;
      if (mounted) setState(() {});
    }
  }

  void _onPose(Pose? pose, Duration inference) {
    if (!mounted) return;
    setState(() {
      _pose = pose;
      if (pose != null) {
        _lastPoseAt = DateTime.now();
        final angle = _elbowAngleOf(pose);
        _elbowAngle = angle;
        // Cheat gate: only a body plausibly IN a front-view pushup may
        // feed the counter — waving your hands upright is rejected here.
        _verdict = _gate.evaluate(_gateSampleOf(pose));
        if (_verdict != PushupVerdict.ok) {
          _counter.interrupt(); // faked pose can't complete a half-cycle
        } else if (angle != null) {
          final reps = _counter.update(angle, _lastPoseAt!);
          if (reps != null) {
            _game.onRep(); // a counted pushup = one shot at the monsters
            HapticFeedback.mediumImpact(); // feel every rep without looking
          }
        }
      } else {
        _elbowAngle = null;
        _leftArm = 0;
        _rightArm = 0;
        _verdict = PushupVerdict.noBody;
      }
    });
  }

  /// Builds the gate's view of the body from ML Kit landmarks.
  GateSample _gateSampleOf(Pose pose) {
    GatePoint? p(PoseLandmarkType t) {
      final l = pose.landmarks[t];
      return l == null ? null : GatePoint(l.x, l.y, l.likelihood);
    }

    return GateSample(
      shoulderL: p(PoseLandmarkType.leftShoulder),
      shoulderR: p(PoseLandmarkType.rightShoulder),
      wristL: p(PoseLandmarkType.leftWrist),
      wristR: p(PoseLandmarkType.rightWrist),
      hipL: p(PoseLandmarkType.leftHip),
      hipR: p(PoseLandmarkType.rightHip),
    );
  }

  /// Toolbar SHOP: pauses the engine and holds the shop open mid-run.
  void _openShop() {
    HapticFeedback.selectionClick();
    _game.pauseEngine();
    setState(() => _shopOpen = true);
  }

  void _closeShop() {
    _game.resumeEngine();
    setState(() => _shopOpen = false);
  }

  /// Average elbow angle across whichever arms are confidently visible.
  /// Also records per-arm visibility (0 = not seen, 1 = seen but shaky,
  /// 2 = confident) for the HUD's arm indicators — wrists near the frame
  /// edge are the usual reason no angle (and therefore no rep) exists.
  double? _elbowAngleOf(Pose pose) {
    final angles = <double>[];
    _leftArm = 0;
    _rightArm = 0;
    var armIndex = 0;
    for (final (s, e, w) in [
      (
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist
      ),
      (
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist
      ),
    ]) {
      final shoulder = pose.landmarks[s];
      final elbow = pose.landmarks[e];
      final wrist = pose.landmarks[w];
      if (shoulder == null || elbow == null || wrist == null) {
        armIndex++;
        continue;
      }
      final minLikelihood = [
        shoulder.likelihood,
        elbow.likelihood,
        wrist.likelihood,
      ].reduce((a, b) => a < b ? a : b);
      // 0.4 (was 0.5): wrists are often the weakest landmark during a
      // plank and a strict cut here dropped the angle entirely.
      final state = minLikelihood >= 0.5 ? 2 : minLikelihood >= 0.4 ? 1 : 0;
      if (armIndex == 0) {
        _leftArm = state;
      } else {
        _rightArm = state;
      }
      armIndex++;
      if (state == 0) continue;
      angles.add(computeAngle(
        ax: shoulder.x,
        ay: shoulder.y,
        bx: elbow.x,
        by: elbow.y,
        cx: wrist.x,
        cy: wrist.y,
      ));
    }
    if (angles.isEmpty) return null;
    return angles.reduce((a, b) => a + b) / angles.length;
  }

  /// One-line status for the hero HUD panel.
  String _phaseLabel(GameSnapshot s) => switch (s.phase) {
        GamePhase.menu => 'LEVEL SELECT',
        GamePhase.intro => 'WAVE ${s.wave} — READY',
        GamePhase.fighting => 'FIGHT!',
        GamePhase.waveCleared => 'WAVE CLEAR — SHOP',
        GamePhase.victory => 'VICTORY!',
        GamePhase.defeat => 'DEFEAT',
      };

  Color _phaseColor(GameSnapshot s) => switch (s.phase) {
        GamePhase.fighting => kGreen,
        GamePhase.victory || GamePhase.waveCleared => kGold,
        GamePhase.defeat => kOrange,
        _ => kWhite,
      };

  /// L/R arm visibility dot for the form meter (0 missing, 1 shaky, 2 good).
  Widget _armDot(String label, int state) {
    final color = state == 2
        ? kGreen
        : state == 1
            ? kOrange
            : const Color(0xFF6B6680);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          child: Text(label, style: pixelText(7, kDimText)),
        ),
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: kInk, width: 1),
          ),
        ),
      ],
    );
  }

  /// Form-meter status: what to do right now, in the player's terms.
  /// The cheat gate outranks everything — if the body isn't plausibly in
  /// a pushup, say why (and how to fix it) before any angle coaching.
  String _formStatus() {
    if (_verdict != PushupVerdict.ok) return verdictMessage(_verdict);
    if (!_counter.isCalibrated) return 'CALIBRATING…';
    return switch (_counter.phase) {
      PushupPhase.down => 'PUSH UP!',
      PushupPhase.up => 'GO DOWN',
      PushupPhase.unknown => 'READY',
    };
  }

  Color _formStatusColor() {
    if (_verdict != PushupVerdict.ok) {
      return _verdict == PushupVerdict.noBody ? kDimText : kOrange;
    }
    if (!_counter.isCalibrated) return kOrange;
    return switch (_counter.phase) {
      PushupPhase.down => kOrange,
      PushupPhase.up => kGreen,
      PushupPhase.unknown => kWhite,
    };
  }

  /// BODY dot on the form meter: 2 = pose gate says "real pushup pose",
  /// 1 = body seen but rejected, 0 = nothing usable in frame.
  int get _bodyState => switch (_verdict) {
        PushupVerdict.ok => 2,
        PushupVerdict.noBody => 0,
        _ => 1,
      };

  /// Angle bar: 60° (bent) → 180° (straight) with the learned down/up
  /// threshold ticks — the direct answer to "why didn't that count?".
  Widget _angleBar() {
    double t(double? deg) =>
        deg == null ? 0.0 : ((deg - 60) / 120).clamp(0.0, 1.0);
    final angle = _counter.smoothedAngle ?? _elbowAngle;
    final down = _counter.downAngle;
    final up = _counter.upAngle;
    final fill = angle == null
        ? const Color(0xFF6B6680)
        : down != null && angle <= down
            ? kOrange
            : up != null && angle >= up
                ? kGreen
                : const Color(0xFF9D97B8);

    return Container(
      height: 14,
      decoration: BoxDecoration(
        color: kPanelDark,
        border: Border.all(color: kInk, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          double tickX(double? deg) => (t(deg) * w - 1).clamp(0.0, w - 3);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: t(angle) * w,
                child: ColoredBox(color: fill),
              ),
              if (down != null)
                Positioned(
                  left: tickX(down),
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: const ColoredBox(color: kOrange),
                ),
              if (up != null)
                Positioned(
                  left: tickX(up),
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: const ColoredBox(color: kGreen),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Compensates the fixed sensor orientation for how the device is held, so
  /// ML Kit sees the image upright. Front and back cameras compensate
  /// differently (mirroring) — canonical Android camera2 formulas.
  int _rotationForCamera() {
    final sensor = widget.camera.sensorOrientation;
    final device = _deviceDegrees;
    if (widget.camera.lensDirection == CameraLensDirection.front) {
      return (sensor + device) % 360;
    }
    return (sensor - device + 360) % 360;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopStream();
      _game.saveIfDirty(); // flush debounced coin/progress changes
      _game.pauseEngine();
    } else if (state == AppLifecycleState.resumed) {
      _readOrientation();
      _startStream();
      _game.resumeEngine();
    }
  }

  @override
  void didChangeMetrics() {
    // Screen rotation changes metrics — refresh the device rotation.
    _readOrientation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _stopStream();
    _game.saveIfDirty();
    _game.pauseEngine();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final rotation = _rotationForCamera();

    // Portrait M5 layout: the world fights in the top band, the live camera
    // owns everything below. Preview and skeleton share this rect exactly
    // (CameraPreview contains + centers, the mapper does the same fit).
    final camZone = cameraZoneOf(screen);

    // Landmarks are pixels of the image *after* ML Kit applied the rotation
    // we reported to it. Until the first frame, assume a portrait sensor.
    final raw = _imageSize ?? Size(screen.height, screen.width);
    final rotated = rotation % 180 == 90 ? Size(raw.height, raw.width) : raw;

    final mapper = PoseMapper(
      rotatedImageSize: rotated,
      screenSize: camZone.size,
      mirror: widget.camera.lensDirection == CameraLensDirection.front,
      origin: camZone.topLeft,
    );

    final poseAge = _lastPoseAt == null
        ? null
        : DateTime.now().difference(_lastPoseAt!);
    // Hint states: nobody in frame vs hands/arms outside the frame (the
    // usual reason the elbow angle — and therefore a rep — never exists).
    final hintNoPose = poseAge == null || poseAge.inMilliseconds > 1500;
    final hintNoArms = !hintNoPose && _elbowAngle == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) {
          final debugOn = AppSettings.instance.debugOverlay;
          return Stack(
        fit: StackFit.expand,
        children: [
          // Live camera feed — bottom band of the screen (M5): the player
          // always sees themselves while the battle plays above.
          Positioned.fromRect(
            rect: camZone,
            child: CameraPreview(widget.controller),
          ),

          // Zone toolbar: the seam between the game (top) and the camera
          // (bottom) is a bar with SETTINGS / SHOP / MORE.
          Positioned(
            left: 0,
            right: 0,
            top: camZone.top,
            child: Container(
              height: _toolbarH,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: kInk,
                border: Border(
                  top: BorderSide(color: kPanelLight, width: 1),
                  bottom: BorderSide(color: kPanelDark, width: 3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PixelButton(
                    fill: kPanelDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    onPressed: () => setState(() => _showSettings = true),
                    label: Text('SETTINGS', style: pixelText(8, kWhite)),
                  ),
                  PixelButton(
                    fill: kPanelDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    onPressed: _openShop,
                    label: Text('SHOP', style: pixelText(8, kGold)),
                  ),
                  PixelButton(
                    fill: kPanelDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    onPressed: () => setState(() => _showMore = true),
                    label: Text('MORE', style: pixelText(8, kWhite)),
                  ),
                ],
              ),
            ),
          ),

          // M1: skeleton so the player sees what the AI sees.
          CustomPaint(
            painter: PoseOverlayPainter(pose: _pose, mapper: mapper),
          ),

          // M2: combat game floating over the camera feed.
          GameWidget<RepelGame>(game: _game),

          // Hero HUD panel (top center) — level, rep count with pop, the
          // combo meter, and the current fight status. One framed pixel
          // block instead of floating labels.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<GameSnapshot>(
                valueListenable: _game.snapshot,
                builder: (context, snap, _) {
                  final combo = snap.combo;
                  final mult = comboMultiplier(combo);
                  final barColor =
                      mult >= 1.8 ? kOrange : mult >= 1.5 ? kGold : kGreen;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PixelPanel(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#${snap.levelId} ${snap.levelName.toUpperCase()}',
                            style: pixelText(7, kDimText),
                          ),
                          const SizedBox(height: 5),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              );
                              // Old number expands out, new one pops in —
                              // pixel feel.
                              return FadeTransition(
                                opacity: curved,
                                child: ScaleTransition(
                                  scale:
                                      Tween<double>(begin: 1.35, end: 1.0)
                                          .animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              '${_counter.reps}',
                              key: ValueKey(_counter.reps),
                              style: TextStyle(
                                fontFamily: kPixelFont,
                                fontSize: _counter.reps < 100 ? 44 : 30,
                                height: 1,
                                color: kWhite,
                                shadows: const [
                                  Shadow(
                                      color: kInk,
                                      offset: Offset(3, 3),
                                      blurRadius: 0),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'PUSHUPS',
                            style: TextStyle(
                              fontFamily: kPixelFont,
                              fontSize: 9,
                              color: kOrange,
                              shadows: [
                                Shadow(
                                    color: kInk,
                                    offset: Offset(1, 1),
                                    blurRadius: 0),
                              ],
                            ),
                          ),
                          const SizedBox(height: 7),
                          // Combo meter — 8 segments, colored by multiplier.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 8; i++)
                                Container(
                                  width: 7,
                                  height: 11,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 1.5),
                                  decoration: BoxDecoration(
                                    color: i < combo ? barColor : kPanelDark,
                                    border:
                                        Border.all(color: kInk, width: 1),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Label pops on every new combo step (the feel the
                          // old canvas combo had).
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 1.4, end: 1.0)
                                    .animate(CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOut)),
                                child: child,
                              ),
                            ),
                            child: Text(
                              combo >= 2
                                  ? 'COMBO ${mult.toStringAsFixed(1)}X'
                                  : 'COMBO --',
                              key: ValueKey(combo),
                              style:
                                  pixelText(7, combo >= 2 ? barColor : kDimText),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _phaseLabel(snap),
                            style: pixelText(7, _phaseColor(snap)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Pushup form meter — just below the zone toolbar, always
          // visible: body-gate verdict, arm visibility, live elbow angle,
          // and where the down/up thresholds sit, so you can SEE why a rep
          // did or didn't count.
          Positioned(
            left: 0,
            right: 0,
            top: camZone.top + _toolbarH + 6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PixelPanel(
                  face: const Color(0xCC0D0B14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _armDot('B', _bodyState),
                          const SizedBox(width: 8),
                          _armDot('L', _leftArm),
                          const SizedBox(width: 8),
                          _armDot('R', _rightArm),
                          const SizedBox(width: 12),
                          Text(
                            '${_elbowAngle?.toStringAsFixed(0) ?? '--'}°',
                            style: pixelText(10, kWhite),
                          ),
                          const Spacer(),
                          Text(
                            _formStatus(),
                            style: pixelText(8, _formStatusColor()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _angleBar(),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            _counter.isCalibrated
                                ? 'DOWN ${_counter.downAngle!.toStringAsFixed(0)}°'
                                : 'DO 2 FULL PUSHUPS TO CALIBRATE',
                            style: pixelText(
                                7,
                                _counter.isCalibrated
                                    ? kOrange
                                    : kDimText),
                          ),
                          const Spacer(),
                          if (_counter.isCalibrated)
                            Text(
                              'UP ${_counter.upAngle!.toStringAsFixed(0)}°',
                              style: pixelText(7, kGreen),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Debug cluster (bottom left of the camera band) — one pixel panel
          // with all telemetry, behind Settings → Debug overlay.
          if (debugOn)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PixelPanel(
                    face: const Color(0xCC0D0B14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              color: poseAge != null &&
                                      poseAge.inMilliseconds < 1500
                                  ? kGreen
                                  : const Color(0xFF6B6680),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'M1 ${_inferenceFps.toStringAsFixed(0)} FPS '
                              '${_service.lastInference.inMilliseconds} MS',
                              style: pixelText(7, kWhite),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UI ${_renderFps.toStringAsFixed(0)} FPS · PING --',
                          style: pixelText(7, kWhite),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'GATE ${_verdict.name.toUpperCase()}',
                          style: pixelText(7, kDimText),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_counter.phase.name.toUpperCase()} · CAL '
                          '${_counter.isCalibrated ? "${_counter.downAngle!.toStringAsFixed(0)}/${_counter.upAngle!.toStringAsFixed(0)}°" : "--"}',
                          style: pixelText(7, kDimText),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'R$rotation° S${widget.camera.sensorOrientation}°'
                          ' F${_imageSize?.width.toInt() ?? "?"}'
                          '×${_imageSize?.height.toInt() ?? "?"}',
                          style: pixelText(7, kDimText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Position hint (over the camera band, where the player looks) —
          // pixel styled; adapts: nobody in frame vs hands out of frame.
          if (hintNoPose || hintNoArms)
            Positioned.fromRect(
              rect: camZone,
              child: Center(
                child: PixelPanel(
                  face: const Color(0xCC0D0B14),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hintNoPose ? 'STEP BACK' : 'HANDS OUT OF FRAME',
                        style: pixelText(11, kOrange, shadow: 2),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        hintNoPose
                            ? 'LET THE CAMERA SEE YOUR WHOLE BODY'
                            : 'MOVE BACK OR LOWER THE PHONE',
                        textAlign: TextAlign.center,
                        style: pixelText(7, kWhite),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // M4: level select / victory overlays — each hides itself unless
          // its phase is active, so they never overlap the shop.
          MenuPanel(game: _game),
          VictoryPanel(game: _game),

          // M3: between-waves shop / defeat screen — topmost layer so it
          // covers the HUD while the player rests and shops. forceShow:
          // the toolbar SHOP button holds it open mid-run (engine paused).
          ShopPanel(
            game: _game,
            forceShow: _shopOpen,
            onClose: _closeShop,
          ),

          // MORE popup: reset the counter / exit to menu.
          if (_showMore) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showMore = false),
                child: Container(color: const Color(0x730D0B14)),
              ),
            ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // taps inside don't fall through to close
                child: PixelPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('MORE', style: pixelText(10, kWhite)),
                      const SizedBox(height: 12),
                      PixelButton(
                        fill: kPanelDark,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _counter.reset();
                            _showMore = false;
                          });
                        },
                        label:
                            Text('RESET COUNTER', style: pixelText(8, kWhite)),
                      ),
                      const SizedBox(height: 8),
                      PixelButton(
                        fill: kPanelDark,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _game.toMenu();
                            _showMore = false;
                          });
                        },
                        label:
                            Text('EXIT TO MENU', style: pixelText(8, kOrange)),
                      ),
                      const SizedBox(height: 8),
                      PixelButton(
                        fill: kPanelDark,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        onPressed: () => setState(() => _showMore = false),
                        label: Text('CLOSE', style: pixelText(8, kDimText)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Settings (debug overlay switches) — above everything so the
          // gear works even while a panel is open.
          if (_showSettings)
            SettingsPanel(
              onClose: () => setState(() => _showSettings = false),
              renderFps: _renderFps,
              inferenceFps: _inferenceFps,
              inferenceMs: _service.lastInference.inMilliseconds,
            ),
        ],
          );
        },
      ),
    );
  }
}
