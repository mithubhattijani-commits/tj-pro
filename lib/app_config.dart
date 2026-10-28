/// TJ Pro — THE ONE CONFIG FILE.
///
/// This is the only file Jaani ever needs to edit. Everything changeable
/// lives here: the app name, the home heading, every ad unit ID, every
/// ads switch, and every feature switch. No other file needs to change.
///
/// HOW TO EDIT (no coding, no local build):
///   1. Open the file lib/app_config.dart on the GitHub website.
///   2. Change ONLY the values on the right of the = sign.
///   3. Keep true/false in small letters, and keep ad IDs inside quotes.
///   4. Save it as a commit on GitHub, then open the Actions tab and
///      wait for the "Build APK" run to finish green. Download the new
///      APK from that run. The full steps are in EDIT-GUIDE.md.
///
/// ADS:
///   The ad IDs below are GOOGLE TEST units (all five formats + test
///   app ID). Test ads earn nothing. Real AdMob units need a NEW AdMob
///   app registration later (after the AdMob account approval); only
///   then replace the test IDs below with the real ones.
library;

class AppConfig {
  // App name shown on the home screen.
  static const String appName = 'TJ Pro';

  // Heading shown on the home screen.
  static const String homeHeading = 'What do you want to edit?';

  // MASTER ADS SWITCH: false turns every ad off (banner, interstitial
  // and rewarded). True turns ads on, subject to the switches below.
  static const bool adsEnabled = true;

  // Banner ad on the home screen.
  static const bool bannerAdEnabled = true;

  // Full-screen ad after a video export.
  static const bool interstitialAdEnabled = true;

  // Rewarded ad that unlocks the Premium AI tools. If this is false,
  // the AI tools work without watching an ad.
  static const bool rewardedAdEnabled = true;

  // Native ad card in the home tools feed.
  static const bool nativeAdEnabled = true;

  // Full-screen ad on cold start, before the home screen.
  static const bool appOpenAdEnabled = true;

  // FEATURE SWITCHES: false hides that feature from the app.
  static const bool photoEditorEnabled = true;
  static const bool videoEditorEnabled = true;
  static const bool aiToolsEnabled = true;
  static const bool liveStudioEnabled = true;
  static const bool musicOverlayEnabled = true;
  static const bool crossfadeEnabled = true;

  // AdMob IDs (GOOGLE TEST units, all five formats).
  static const String appId = 'ca-app-pub-3940256099942544~3347511713';
  static const String bannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String nativeAdUnitId =
      'ca-app-pub-3940256099942544/2247696110';
  static const String appOpenAdUnitId =
      'ca-app-pub-3940256099942544/9257395921';

  // Backwards-compatible alias used by older code paths.
  static const bool useTestAds = true;
}


