import 'package:flutter_test/flutter_test.dart';
import 'package:repel_game/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M5.3 settings: persisted accent theme + game-feel switches (AppSettings).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings persistence', () {
    test('load reads persisted values back', () async {
      SharedPreferences.setMockInitialValues({
        'accent': 'TEAL',
        'shake': false,
        'flash': 'DIM',
        'particles': false,
        'haptics': false,
        'dbg_overlay': false,
        'sens': 'FORGIVING',
      });
      final s = AppSettings.instance;
      await s.load();
      expect(s.accentName, 'TEAL');
      expect(s.screenShake, isFalse);
      expect(s.hitFlash, 'DIM');
      expect(s.particles, isFalse);
      expect(s.haptics, isFalse);
      expect(s.debugOverlay, isFalse);
      expect(s.repSensitivity, 'FORGIVING');
    });

    test('unknown accent and flash mode fall back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'accent': 'PLAID',
        'flash': 'STROBE',
        'sens': 'PSYCHO',
      });
      final s = AppSettings.instance;
      await s.load();
      expect(s.accentName, 'ORANGE');
      expect(s.hitFlash, 'FULL');
      expect(s.repSensitivity, 'NORMAL');
    });

    test('setters persist through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings.instance;
      await s.load();
      await s.setAccent('TEAL');
      await s.setScreenShake(false);
      await s.setHitFlash('OFF');
      await s.setHaptics(false);
      await s.setRepSensitivity('STRICT');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accent'), 'TEAL');
      expect(prefs.getBool('shake'), isFalse);
      expect(prefs.getString('flash'), 'OFF');
      expect(prefs.getBool('haptics'), isFalse);
      expect(prefs.getString('sens'), 'STRICT');
    });

    test('gate hold windows scale with the chosen sensitivity', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings.instance;
      await s.load();
      expect(s.gateHold.inMilliseconds, 300); // NORMAL default
      await s.setRepSensitivity('STRICT');
      expect(s.gateHold.inMilliseconds, 150);
      await s.setRepSensitivity('FORGIVING');
      expect(s.gateHold.inMilliseconds, 600);
    });

    test('setAccent rejects unknown names', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings.instance;
      await s.load();
      await s.setAccent('PLAID');
      expect(s.accentName, isNot('PLAID'));
    });
  });
}
