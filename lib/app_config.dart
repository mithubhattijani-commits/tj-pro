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

  // News Studio (v1): the 4th home card + News Studio tab. False hides
  // the whole News Studio surface (presets, News Maker, templates).
  static const bool newsStudioEnabled = true;

  // HELP — WhatsApp support (user order 20 Nov 2026, v1 MUST-HAVE,
  // Magic Box pattern). Tapping opens WhatsApp to this number.
  // Default is the user's number 03090808180 (wa.me/923090808180).
  // REMOTE-CONFIG OVERRIDE: the number must be changeable without a
  // build — RemoteConfigService (lib/services/remote_config_service.dart,
  // fetches https://nigraantv.xyz/apps/config/tj-pro.json) should map a
  // `support_whatsapp` key onto this value when present, falling back to
  // this default. The Help button itself lives on the login screen +
  // home/settings "For Help" row (login/coins track + home phases) and
  // must use [supportWhatsAppLink] / [waLinkFor], never a hardcoded URL
  // (main.dart still has two hardcoded wa.me links — switch them to this
  // value when the Help button lands).
  static const String supportWhatsAppNumber = '03090808180';

  /// wa.me link for the default support number.
  static String get supportWhatsAppLink =>
      waLinkFor(supportWhatsAppNumber);

  /// Builds a wa.me chat link from a Pakistani mobile number:
  /// '03090808180' -> 'https://wa.me/923090808180'. Numbers already in
  /// international form ('923090808180' / '+923090808180') pass through.
  static String waLinkFor(String number) {
    var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '92${digits.substring(1)}';
    }
    return 'https://wa.me/$digits';
  }

  // ADVERTISING BANNER — dedicated "Advertise" page (user order 20 Nov
  // 2026, v1 MUST-HAVE, Magic Box v3 pattern). CORRECTED ORDER: the
  // banner lives on ONE dedicated Advertise page — NOT two home slots
  // (the earlier "upar + neeche" home note is SUPERSEDED, do not build
  // it). The page shows the banner image + a WhatsApp contact button
  // (help/booking — see [supportWhatsAppLink]).
  //   - Image rendering: BoxFit.contain — any size/aspect auto-fits,
  //     fully visible, NEVER cropped (letterbox/padding OK, crop NAHI).
  //   - Paid-banner flow: 200 coins / 2 hours; a banner goes live ONLY
  //     after verification (auto-checks + owner approval in the admin
  //     panel; reject = refund; report button on the banner). The admin
  //     panel controls banners.
  //   - The Advertise page UI + the paid flow land in later phases
  //     (screens + login/coins track); this config is the ready-to-use
  //     value they read.
  // REMOTE-CONFIG OVERRIDE: all four values must be changeable without
  // a build — RemoteConfigService (tj-pro.json) should map
  // `advertising_banner_enabled` / `advertising_banner_image_url` /
  // `advertising_banner_price_coins` /
  // `advertising_banner_duration_hours` onto these when present.
  static const bool advertisingBannerEnabled = true;

  /// Banner image URL for the Advertise page (empty = no banner booked).
  /// Bundled default is the existing house banner asset; a booked paid
  /// banner replaces it via remote config.
  static const String advertisingBannerImageUrl =
      'assets/jaani_ad_banner.jpg';

  /// Paid-banner price: 200 coins per slot.
  static const int advertisingBannerPriceCoins = 200;

  /// Paid-banner slot length in hours: 2.
  static const int advertisingBannerDurationHours = 2;

  // ON-DEMAND ASSETS (user order 20 Nov 2026: keep the app as small as
  // possible). The heavy News Studio assets are NOT bundled — they are
  // downloaded on first use and cached in app documents by
  // AssetDownloadService (lib/services/asset_download_service.dart):
  //   - Kasheeda font (12.6 MB TTF): loaded via FontLoader from the
  //     cached file — Urdu (Nastaleeq) rendering for ribbons/tickers
  //     (FFmpeg drawtext cannot shape Urdu, so the template renderer
  //     draws PNG overlays with this font).
  //   - Nigraan intro (10s, 854x480 LANDSCAPE, 10.005s): portrait export
  //     needs scale/crop (scale to 720 wide + centre-crop to 720x1280).
  // URLs are EMPTY until the files are hosted at release time (the parent
  // agent hosts them); NEVER hardcode a fake/placeholder URL here — an
  // empty URL means "not hosted yet" and the service throws a clear
  // error instead of downloading garbage. Remote config (tj-pro.json)
  // may override these with `kasheeda_font_url` / `nigraan_intro_url`.
  static const String kasheedaFontUrl = '';
  static const String nigraanIntroUrl = '';

  /// Pre-rendered rotating-logo loop (`logo-rotating-alpha.mov`,
  /// ProRes 4444 with alpha, 91 MB — NEVER bundled, on-demand only).
  /// Empty until hosted at release time, same rule as the intro URL
  /// above: an empty URL means "not hosted yet" and the reel export
  /// falls back to a generated rotating loop (see
  /// `lib/services/logo_loop_service.dart`) instead of downloading
  /// garbage. Remote config may override with `logo_mov_url`.
  static const String logoMovUrl = '';

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

  // UNITY ADS (Game ID 800418048, Android "TJ Pro" project).
  // Test mode is ON in UnityAdsService — flip testMode to false for
  // production. These switches gate Unity ads independently of AdMob.
  static const bool unityAdsEnabled = true;
  static const bool unityRewardedEnabled = true;
  static const bool unityInterstitialEnabled = true;
  static const String unityGameId = '800418048';
  static const String unityRewardedPlacementId = 'BP_Rewarded_Android';
  static const String unityInterstitialPlacementId = 'BP_Interstitial_Android';

  // NEWS STUDIO — LOGIN + COINS (v1, Magic Box pattern).
  //
  // Supabase (shared "tj-earn" project znyaxxkhhopdqrvxhxmb). The URL
  // is public; the anon key is a PUBLIC Supabase key but must be
  // supplied at build time — NEVER paste a real key into this file:
  //   flutter build apk --debug \
  //     --dart-define=SUPABASE_ANON_KEY=<key from the GitHub secret>
  // With no key the app runs in local-only mode: coins stay on-device
  // and the server ledger sync is skipped.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://znyaxxkhhopdqrvxhxmb.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Google Sign-In — Web OAuth client ID (the `serverClientId`).
  ///
  /// A TJ Pro OAuth client (package com.tjpro.app) must be created in
  /// Google Cloud and this value replaced with its Web client ID
  /// (or passed as --dart-define=GOOGLE_SERVER_CLIENT_ID=...).
  /// NEVER copy another app's client ID: the Android OAuth client is
  /// tied to the package name, so Magic Box's ID cannot work here.
  /// Until this is set, Google sign-in reports "not set up yet".
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: 'REPLACE_ME_GOOGLE_WEB_CLIENT_ID',
  );

  // Unity rewarded placement that pays COINS (News Studio earning).
  // Remote config (tj-pro.json
  // `unity_rewarded_coins_placement_id`) overrides this at runtime.
  // ⚠️ This placement MUST exist in the Unity dashboard (TJ Pro
  // project, Game ID 800418048) before release — it cannot be created
  // from code. Until then the Watch Ads button reports the ad as
  // unavailable.
  static const String unityRewardedCoinsPlacementId = 'rewarded_coins';

  // Backwards-compatible alias used by older code paths.
  static const bool useTestAds = true;
}


