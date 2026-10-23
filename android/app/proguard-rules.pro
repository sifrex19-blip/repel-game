# R8/ProGuard rules for Repel (M4).
#
# Nearly nothing is needed here — and that is deliberate:
#
#  * The ML Kit / MediaPipe / odml AARs ship their own consumer rules,
#    including the auto-generated keeps for their reflectively-loaded model
#    internals and native method names (verified inside the cached AARs).
#  * The Flutter Gradle plugin contributes the engine's keep rules.
#
# Broad rules such as `-keep class com.google.mlkit.** { *; }` were measured
# to make classes.dex ~1.7 MB LARGER (they retain the entire unreachable
# library surface), so they are intentionally not used.

# The Flutter embedding resolves the generated plugin registrant by name.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Coroutines are referenced by optional ML Kit paths only.
-dontwarn kotlinx.coroutines.**

# The pose-detection Flutter plugin depends on both ML Kit model bundles,
# but build.gradle.kts excludes `pose-detection-accurate` because the game
# only ever runs the base (lite) model — PoseDetector.kt constructs the
# accurate options only inside `else` of `options["model"] == "base"`, and
# the Dart side serializes the hard-coded PoseDetectionModel.base as the
# literal string "base" (model.name). That branch is unreachable at runtime,
# so the dangling references are never executed (ART resolves them only when
# the instruction runs). Rules below are exactly what AGP generated in
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
-dontwarn com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions$Builder
