import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _kDebugOverlay = 'dbg_overlay';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      debugOverlay = prefs.getBool(_kDebugOverlay) ?? debugOverlay;
    } catch (_) {
      // Unreadable storage: keep defaults rather than crash the app.
    }
  }

  Future<void> setDebugOverlay(bool value) async {
    if (value == debugOverlay) return;
    debugOverlay = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDebugOverlay, value);
    } catch (_) {}
  }
}
