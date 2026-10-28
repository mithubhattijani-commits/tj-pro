# TJ Pro v2 — R8 / ProGuard keeps for the release build.
#
# The libraries below ship their own consumer rules too; this file
# covers the app-level guarantees: JNI native methods must never be
# stripped or renamed, and reflectively-registered plugin code must
# survive shrinking. Generic keeps come first so a renamed plugin
# package can never silently break a feature.

# Generic JNI keep: every native method in every class.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter embedding + engine (referenced reflectively).
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# ML Kit (on-device AI tools).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit.** { *; }

# ffmpeg-kit (video engine, JNI bridge).
-keep class com.arthenica.** { *; }

# RootEncoder (RTMP streaming engine behind rtmp_streaming, JNI).
-keep class com.pedro.** { *; }

# AdMob (Play services ads, reflective mediation).
-keep class com.google.android.gms.ads.** { *; }

# Parcelables used across plugin boundaries.
-keep class * implements android.os.Parcelable {
    *;
}

# v2: Flutter's embedding references Play Core split-install classes
# (PlayStoreDeferredComponentManager) that no sideloaded APK ships.
# R8 fails the release build on these missing classes; those code
# paths only run for Play Store deferred components, which this
# direct-download APK never uses, so suppressing the warning is safe.
-dontwarn com.google.android.play.core.**
