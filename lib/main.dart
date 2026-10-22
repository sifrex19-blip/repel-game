import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is played with the phone flat on the floor — landscape only.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      home: const CameraGate(),
    );
  }
}
