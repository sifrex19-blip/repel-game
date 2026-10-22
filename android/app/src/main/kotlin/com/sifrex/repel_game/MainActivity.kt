package com.sifrex.repel_game

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "repel/device_orientation"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getRotationDegrees") {
                // Surface.ROTATION_0/90/180/270 -> 0/90/180/270 degrees.
                // Used to compensate the camera sensor orientation so pose
                // detection always sees an upright image.
                @Suppress("DEPRECATION")
                val rotation = windowManager.defaultDisplay.rotation
                result.success(rotation * 90)
            } else {
                result.notImplemented()
            }
        }
    }
}
