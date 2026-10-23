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
