# TJ Pro

TJ Pro is a free, offline photo and video editor for Android,
built with Flutter. Photos and videos are processed on the phone
itself. There is no account, no cloud upload, and no server.

Package ID: `com.tjpro.app`. Version: `1.0.0+1`.

## What the app does

- Photo Editor: pick a photo, apply filters, crop, rotate, adjust
  brightness, contrast and saturation, add a text overlay, and save
  to the gallery (JPG, or PNG when a background was removed).
- AI tools (Premium, on-device): background remover, background
  blur, face beautify, and auto-enhance. In V1 these unlock with
  one rewarded ad, or work freely if the rewarded switch is off
  in the config file.
- Video Editor: pick clips, trim each clip, merge clips in order,
  add a text overlay, add music (music replaces the original
  audio), change speed, apply filters, pick an aspect ratio, and
  use a crossfade between clips. Exports save to the gallery.
- Ads (V1, test ads only): a banner on the home screen, a
  full-screen ad after a video export, and a rewarded ad for the
  Premium AI tools. Test ads earn no money. Real earnings need a
  real AdMob account and real ad unit IDs (see the config file).

## AdMob: test units only in this build

This build uses ONLY official Google test ad units (see
`lib/app_config.dart` and the AdMob app ID in
`android/app/src/main/AndroidManifest.xml`). It earns nothing yet.
Real AdMob units need a NEW AdMob app registration later (after the
AdMob account approval) — do NOT copy another app's real unit IDs
into this app.

## The one file to edit

**lib/app_config.dart** is the only file that needs editing for
normal changes: app name, home heading, ad IDs, ads on/off, and
feature on/off switches. See **EDIT-GUIDE.md** in this repository
for plain-language, step-by-step instructions for editing that file
on the GitHub website and getting a new APK from Actions, with no
local build and no code knowledge.

## Project structure (for the next person or agent picking this up)

- `lib/main.dart` — app start, home screen, Premium unlock card,
  and the banner ad slot. Home cards are shown or hidden from
  the config file.
- `lib/app_config.dart` — THE config file. Every changeable value
  lives here. Nothing else needs editing for normal changes.
- `lib/photo/photo_editor_screen.dart` — photo editor screen and
  its AI tool buttons. AI buttons are gated by the config file.
- `lib/video/video_editor_screen.dart` — video editor screen,
  trim, merge, text, music, speed, filters, aspect, crossfade,
  and the export that shows the interstitial ad afterwards.
- `lib/services/ad_service.dart` — loads and shows banner,
  interstitial and rewarded ads, and tracks the Premium unlock.
  It reads all IDs and switches from the config file.
- `lib/services/ad_config.dart` — REMOVED in the config-file
  update. Do not recreate it. Use `lib/app_config.dart` instead.
- `lib/services/ai_service.dart` — on-device ML Kit face
  detection and subject/selfie segmentation wrappers.
- `lib/services/photo_pipeline.dart` — photo filters, sliders,
  text overlay, and gallery export.
- `lib/services/ffmpeg_service.dart` — FFmpeg commands for video
  trim, normalize, join, crossfade, and final export.
- `lib/widgets/banner_ad_widget.dart` — home banner ad widget.
  It shows nothing if the ad fails to load.
- `pubspec.yaml` — Flutter dependencies, including
  `google_mobile_ads` for AdMob.
- `android/` — Android app wrapper. `android/app/src/main/
  AndroidManifest.xml` holds the AdMob app ID (currently the
  Google test app ID, matching the config file). `android/gradle/
  wrapper/gradle-wrapper.properties` must keep the public
  `services.gradle.org` Gradle URL, so the cloud build works.
  `android/local.properties` is NEVER committed: it holds local
  SDK paths and is created fresh in the cloud build.
- `.github/workflows/build-apk.yml` — GitHub Actions workflow.
  On every push to `main` it installs Flutter and Java 21,
  runs `flutter analyze`, builds a keystore-signed DEBUG APK
  (uncompressed, no shrinking), verifies it (package, label,
  version, signer fingerprint), and uploads it as
  the artifact `tj-pro-debug-apk`.
- `test/widget_test.dart` — smoke test: the home screen shows
  both editor entries.

## How the cloud build works

Every push to the `main` branch triggers the workflow above. No
local Android SDK, Flutter SDK, or Gradle install is needed on the
machine that pushes. The workflow creates `android/local.properties`
from the Flutter install it just set up, because the Android
settings file requires a `flutter.sdk` path and that file must not
be committed with local paths in it.

## Known limitations

- Video text is a single line, bottom-center, white with a black
  border. It needs a system font on the phone; if none is found,
  export runs without text and says so.
- Music replaces the original audio (no mixing yet).
- Merged clips are normalized to a common size and frame rate
  before joining. Crossfade falls back to a cut join on failure.
- Background remover works best on photos with a clear person or
  subject. Subject segmentation may download its model once via
  Google Play services on first use (free); selfie segmentation
  and face detection are fully bundled and offline.
- Auto-enhance is an automatic levels and color adjustment
  (algorithmic, not an ML model).
- Very long 4K videos export slowly on low-end phones.
- No cloud backup, no templates, no keyframes, no auto-captions.
- This is a debug APK: good for testing and direct sharing, not
  a Play Store release build (release signing is a later step).
