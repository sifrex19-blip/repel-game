plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sifrex.repel_game"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sifrex.repel_game"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys so `flutter run --release` and sideloaded builds
            // work without a Play signing keystore.
            signingConfig = signingConfigs.getByName("debug")

            // R8 minification is deliberately OFF — measured, not assumed:
            //   unminified classes.dex = 3,148,244 B
            //   minified   classes.dex = 3,148,412 B   (R8 saved ~0 bytes)
            // and the minified build CRASHED AT STARTUP: R8 deleted
            // androidx.camera.camera2.Camera2Config, which CameraX locates
            // only through a manifest meta-data string (Class.forName ->
            // ClassNotFoundException when the camera opens), and renamed the
            // META-INF/services files kotlinx.coroutines uses to discover its
            // main dispatcher (ServiceLoader -> IllegalStateException).
            // The app's real size lives in native libs, so re-enable this
            // only with keep rules for manifest-string/ServiceLoader
            // reflection AND a on-device smoke test.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // The pose-detection Flutter plugin depends on BOTH ML Kit model
    // bundles, but the game only ever runs the base (lite) model
    // (PoseDetectionModel.base — chosen for real-time performance). The
    // accurate bundle's only unique payload is the 6.4 MB full landmark
    // model, which would be dead weight in every install.
    configurations.all {
        exclude(group = "com.google.mlkit", module = "pose-detection-accurate")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
