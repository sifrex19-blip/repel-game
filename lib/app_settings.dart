import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm2/pixel_art.dart';

/// App-level preferences that are NOT gameplay progress (the campaign save
/// lives in [PlayerSave], economy.dart). One process-wide instance: the home
/// menu and the in-game overlay both bind to the same notifiers.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  /// Whether the debug overlay (FPS / ping / pose telemetry) is shown.
  /// On by default so on-device tuning works out of the box; Settings can
  /// hide it.
  bool debugOverlay = true;

  /// UI accent theme — one of [kAccents]' keys. Buttons, the PUSHUPS
  /// label and the menu tagline tint with it.
  String accentName = 'ORANGE';
  Color get accent => kAccents[accentName] ?? kOrange;

  /// Screen shake on impacts (photosensitivity-friendly off switch).
  bool screenShake = true;

  /// Enemy/base hit flash: FULL = white strobe (classic), DIM = soft
  /// lighten of the body hue, OFF = no flash at all.
  static const flashModes = ['FULL', 'DIM', 'OFF'];
  String hitFlash = 'FULL';

  /// Impact sparks, death poofs and drifting embers.
  bool particles = true;

  /// Vibration feedback on reps and button presses.
  bool haptics = true;

  /// How long a bad pose must persist before rep counting pauses
  /// (Settings → REP SENSITIVITY). STRICT reacts fastest, FORGIVING
  /// rides out detector flicker on tricky lighting/angles.
  static const repSensitivityModes = ['STRICT', 'NORMAL', 'FORGIVING'];
  String repSensitivity = 'NORMAL';

  /// The hold window the pose gate applies for the chosen sensitivity.
  Duration get gateHold => switch (repSensitivity) {
        'STRICT' => const Duration(milliseconds: 150),
        'FORGIVING' => const Duration(milliseconds: 600),
        _ => const Duration(milliseconds: 300),
      };

  static const _kDebugOverlay = 'dbg_overlay';
  static const _kAccent = 'accent';
  static const _kShake = 'shake';
  static const _kFlash = 'flash';
  static const _kParticles = 'particles';
  static const _kHaptics = 'haptics';
  static const _kSens = 'sens';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Resolve against defaults — never trust raw stored values, and never
      // inherit stale state (load() must be idempotent on the singleton).
      debugOverlay = prefs.getBool(_kDebugOverlay) ?? true;
      final accent = prefs.getString(_kAccent);
      accentName = accent != null && kAccents.containsKey(accent)
          ? accent
          : 'ORANGE';
      screenShake = prefs.getBool(_kShake) ?? true;
      final flash = prefs.getString(_kFlash);
      hitFlash =
          flash != null && flashModes.contains(flash) ? flash : 'FULL';
      particles = prefs.getBool(_kParticles) ?? true;
      haptics = prefs.getBool(_kHaptics) ?? true;
      final sens = prefs.getString(_kSens);
      repSensitivity =
          sens != null && repSensitivityModes.contains(sens) ? sens : 'NORMAL';
    } catch (_) {
      // Unreadable storage: keep defaults rather than crash the app.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDebugOverlay, debugOverlay);
      await prefs.setString(_kAccent, accentName);
      await prefs.setBool(_kShake, screenShake);
      await prefs.setString(_kFlash, hitFlash);
      await prefs.setBool(_kParticles, particles);
      await prefs.setBool(_kHaptics, haptics);
      await prefs.setString(_kSens, repSensitivity);
    } catch (_) {}
  }

  Future<void> _set(void Function() apply) async {
    apply();
    notifyListeners();
    await _persist();
  }

  Future<void> setDebugOverlay(bool value) {
    if (value == debugOverlay) return Future.value();
    return _set(() => debugOverlay = value);
  }

  Future<void> setAccent(String name) {
    if (!kAccents.containsKey(name) || name == accentName) {
      return Future.value();
    }
    return _set(() => accentName = name);
  }

  Future<void> setScreenShake(bool value) {
    if (value == screenShake) return Future.value();
    return _set(() => screenShake = value);
  }

  Future<void> setHitFlash(String mode) {
    if (!flashModes.contains(mode) || mode == hitFlash) return Future.value();
    return _set(() => hitFlash = mode);
  }

  Future<void> setParticles(bool value) {
    if (value == particles) return Future.value();
    return _set(() => particles = value);
  }

  Future<void> setHaptics(bool value) {
    if (value == haptics) return Future.value();
    return _set(() => haptics = value);
  }

  Future<void> setRepSensitivity(String mode) {
    if (!repSensitivityModes.contains(mode) || mode == repSensitivity) {
      return Future.value();
    }
    return _set(() => repSensitivity = mode);
  }
}
