import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The phone stands upright (M5): the player sees themselves in the live
  // camera band at the bottom while the battle plays above.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await AppSettings.instance.load();
  runApp(const RepelApp());
}

class RepelApp extends StatelessWidget {
  const RepelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
