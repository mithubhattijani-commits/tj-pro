plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tjpro.app"
    // v2: rtmp_streaming 2.1.1 requires compileSdk 37+ (its AAR
    // metadata enforces it at checkReleaseAarMetadata); Flutter's
    // default (36) fails the build. targetSdk is fixed at 36 below;
    // only the compile SDK is raised, no runtime behavior change.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // TJ Pro day-1 signing key. The CI workflow decodes the
    // KEYSTORE_BASE64 secret into android/app/tjpro.keystore and passes
    // the passwords via environment variables. The keystore file itself is
    // never committed to the repo (see .gitignore). Without it, builds fall
    // back to the standard debug key (local development only) - never ship
    // a build signed with a different key, or installed users would need
    // to uninstall before updating.
    val tjproKeystoreFile = file("tjpro.keystore")
    if (tjproKeystoreFile.exists()) {
        signingConfigs.create("tjpro") {
            storeFile = tjproKeystoreFile
            storePassword = System.getenv("KEYSTORE_STORE_PASSWORD")
            keyAlias = "tjpro"
            keyPassword = System.getenv("KEYSTORE_KEY_PASSWORD")
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tjpro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // whisper_ggml (on-device captions) requires minSdk 24.
        minSdk = 24
        // TJ Pro fixed: targetSdk 36 (do not change without a new release plan).
        targetSdk = 36
        // APP SIZE (user order 20 Nov 2026): all three ABIs, for the
        // SPLIT-PER-ABI build — the CI workflow builds one APK per ABI
        // (armeabi-v7a, arm64-v8a, x86_64), so each APK still carries
        // only ONE ABI's native libs and stays small, while older
        // armeabi-v7a phones and x86_64 devices (emulators/tablets)
        // are covered too. This REPLACES the old arm64-only rule
        // (3 Nov 2026) — arm64-only saved size by dropping devices;
        // split-per-ABI saves size per APK instead.
        // NOTE: do NOT add an ndk abiFilters block here — Gradle
        // forbids ndk abiFilters together with splits abi filters,
        // and `flutter build apk --split-per-abi` sets the splits
        // itself ("Conflicting configuration" build error).
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            if (tjproKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("tjpro")
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // TJ Pro: same stable day-1 key as debug, so updates never
            // force a reinstall. Falls back to the debug key only when
            // the tjpro keystore file is absent (local dev only).
            if (tjproKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("tjpro")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            // TJ Pro: NO shrinking, NO compression - an uncompressed build
            // is mandatory (a compressed build previously crashed on the
            // user's phone). R8 / resource shrinking stay OFF.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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



