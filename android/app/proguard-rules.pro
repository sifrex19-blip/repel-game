# ProGuard/R8 rules for Repel.
#
# NOTE: R8 minification is currently DISABLED in build.gradle.kts — this
# file is therefore not applied. It is kept for the day minify is re-enabled
# (which requires an on-device smoke test; see build.gradle.kts for why it
# was disabled: with zero measured dex savings, R8 deleted
# androidx.camera.camera2.Camera2Config — located at runtime only via a
# manifest meta-data string — and renamed META-INF/services files, crashing
# the app at startup).
#
# If minify is re-enabled, at minimum these are needed on top of the ML Kit
# AAR consumer rules (which ship inside the AARs and cover ML Kit's own
# reflective model loading):
#
#   # CameraX backend selected via manifest meta-data string
#   # (MetadataHolderService.DEFAULT_CONFIG_PROVIDER) — invisible to R8.
#   -keep class androidx.camera.camera2.Camera2Config { *; }
#   -keep class androidx.camera.camera2.Camera2Config$DefaultProvider { *; }
#
#   # ServiceLoader interfaces (renamed classes break META-INF/services).
#   -keep class kotlinx.coroutines.internal.MainDispatcherFactory
#   -keep class kotlinx.coroutines.CoroutineExceptionHandler
#
#   # Flutter embedding looks up the generated plugin registrant by name.
#   -keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
#
# NOTE on the ML Kit pose-detection-accurate exclusion: its two dangling
# class references in the plugin need -dontwarn rules ONLY while R8 runs:
#   -dontwarn com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
#   -dontwarn com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions$Builder
# (D8/debug tolerates them without rules — the branch is unreachable because
# the Dart side hard-codes PoseDetectionModel.base.)
