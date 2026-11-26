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
///   Unity Ads ONLY (one-build, defect #4). AdMob was removed from
///   the app entirely — there are no AdMob unit IDs in this file any
///   more. The Unity Game ID + placement IDs live in the UNITY ADS
///   section below; the switches in this header gate the Unity
///   formats (banner / interstitial / rewarded).
library;

class AppConfig {
  // App name shown on the home screen.
  static const String appName = 'Jaani Studio';

  // Heading shown on the home screen.
  static const String homeHeading = 'What do you want to edit?';

  // MASTER ADS SWITCH: false turns every ad off (banner, interstitial
  // and rewarded). True turns ads on, subject to the switches below.
  static const bool adsEnabled = true;

  // Banner ad on the home screen.
  static const bool bannerAdEnabled = true;

  // Full-screen ad after a video export.
  static const bool interstitialAdEnabled = true;

  // (v1.3.0 §8: the old rewarded-ad feature switch — "rewarded ad
  // that unlocks the Premium AI tools" — is REMOVED. Premium tools
  // unlock with COINS only; rewarded ads exist solely to earn coins
  // via the Coins screen's `rewarded_coins` placement below.)

  // Native ad card in the home tools feed. NOTE: the native slot
  // was an AdMob format and was removed with AdMob (defect #4) —
  // Unity has no native equivalent in this setup. The switch is
  // kept for config compatibility but no longer gates any widget.
  static const bool nativeAdEnabled = true;

  // Full-screen ad on cold start, before the home screen. NOTE:
  // app-open was an AdMob format; Unity has no app-open equivalent
  // here, so cold start no longer shows an ad (defect #4). Kept for
  // config compatibility.
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
  // possible). The heavy News Studio assets are cached in app documents
  // by AssetDownloadService (lib/services/asset_download_service.dart):
  //   - Kasheeda font (12.6 MB TTF): loaded via FontLoader from the
  //     cached file — Urdu (Nastaleeq) rendering for ribbons/tickers
  //     (FFmpeg drawtext cannot shape Urdu, so the template renderer
  //     draws PNG overlays with this font).
  //   - Nigraan intro (10s, 854x480 LANDSCAPE, 10.005s).
  // v1.3.0 (§9 parity): the intro now ALSO ships bundled
  // (assets/templates/nigraan_intro.mp4) and the font is extracted
  // from a bundled asset when one is present — the cache is filled
  // from the bundle first, the URLs below remain a remote override.
  // URLs are EMPTY until the files are hosted at release time; NEVER
  // hardcode a fake/placeholder URL here — an empty URL means "not
  // hosted yet" and the service throws a clear error instead of
  // downloading garbage. Remote config (tj-pro.json) may override
  // these with `kasheeda_font_url` / `nigraan_intro_url`.
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

  // UNITY ADS (Game ID 800418048, Android "TJ Pro" project).
  // Test mode is OFF in UnityAdsService (production). These switches
  // gate Unity ads.
  static const bool unityAdsEnabled = true;
  static const bool unityRewardedEnabled = true;
  static const bool unityInterstitialEnabled = true;
  static const String unityGameId = '800418048';
  // (v1.3.0 §8: the old unlock placement id
  // ('BP_Rewarded_Android') is REMOVED from the unlock flow — there
  // is no ad-unlock flow any more. The only rewarded placement the
  // app uses is the earn-coins one, `unityRewardedCoinsPlacementId`
  // below.)
  static const String unityInterstitialPlacementId = 'BP_Interstitial_Android';

  // Unity BANNER placement (one-build, defect #4 — the banner was
  // the one genuinely missing Unity piece). ⚠️ A banner placement
  // with this ID must be created in the Unity dashboard (TJ Pro
  // project, Game ID 800418048) — it cannot be created from code.
  // Until it exists, the banner widget receives a load failure and
  // simply stays hidden; every other ad format works regardless.
  static const String unityBannerPlacementId = 'BP_Banner_Android';

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

  // TJ PRO PRO (v1.4.0) — paid Pro subscription (owner's prices,
  // 22 Nov 2026): Weekly Rs 200, 15-day Rs 500, Monthly Rs 1000,
  // paid manually via Easypaisa / ABL bank (both in Ghulam Jillani's
  // name); JazzCash is added later (empty number = not offered yet).
  // Payment is verified by the owner from the user's screenshot and
  // Pro is granted server-side in the `tjpro_pro` table — see
  // lib/services/pro_service.dart and lib/news/pro_screen.dart.
  // REMOTE-CONFIG OVERRIDE: the payment fields below must be
  // changeable without a build — RemoteConfigService (tj-pro.json)
  // maps `pro_easypaisa_number` / `pro_easypaisa_title` /
  // `pro_abl_account` / `pro_abl_title` / `pro_jazzcash_number` onto
  // them when present.
  static const String proEasypaisaNumber = '03090808180';
  static const String proEasypaisaTitle = 'Ghulam Jillani';
  static const String proAblAccount = '11200010103371080010';
  static const String proAblTitle = 'Ghulam Jillani';

  /// JazzCash number for Pro payments — EMPTY for now (JazzCash is
  /// added later); the Pro screen shows a JazzCash line ONLY when
  /// this is non-empty (via remote config).
  static const String proJazzcashNumber = '';

  /// Pro package prices in rupees (owner's numbers, 22 Nov 2026).
  static const int proWeeklyRs = 200;
  static const int proHalfMonthRs = 500;
  static const int proMonthlyRs = 1000;

  // MODEL PACKS (v1.4.0) — every AI model is a DOWNLOADABLE pack,
  // never bundled in the APK (same rule as the Kasheeda font above).
  // ModelPackService (lib/services/model_pack_service.dart) owns the
  // pack registry (pack id -> file names + expected sizes); this map
  // owns ONLY the download URLs, keyed '<packId>/<fileName>'.
  // Hugging Face `resolve` URLs serve the exact tested files (see
  // ~/workspace/tj-pro-build/V140-TOOL-TESTS.md for the verified
  // sizes/licences). A pack/file with NO entry here is simply not
  // hosted yet — ModelPackService fails soft (returns false) instead
  // of downloading garbage:
  //   - dfn3 (v1.5.0): upstream ships ONLY a release tar.gz, so the
  //     four files were extracted from the tested tarball and are
  //     mirrored on nigraantv.xyz (apps/models/) — the URLs below.
  //     NOTE: the pack is downloadable, but the DFN3 DSP pipeline
  //     is still NOT ported (see AudioEnhanceService's header);
  //     nothing in the app claims DFN3 until that port is verified.
  //   - rife_v46 (v1.5.0): the tested ONNX is mirrored on
  //     nigraantv.xyz (apps/models/rife_v4.6.onnx) — URL below.
  static const Map<String, String> modelPackUrls = <String, String>{
    // Shruti Urdu sherpa-onnx pack (Apache-2.0) — Urdu auto captions.
    'shruti_ur/preprocess.onnx':
        'https://huggingface.co/udgamlabs/Shruti-ONNX/resolve/main/ur/sherpa-onnx/preprocess.onnx',
    'shruti_ur/encode.onnx':
        'https://huggingface.co/udgamlabs/Shruti-ONNX/resolve/main/ur/sherpa-onnx/encode.onnx',
    'shruti_ur/uncached_decode.onnx':
        'https://huggingface.co/udgamlabs/Shruti-ONNX/resolve/main/ur/sherpa-onnx/uncached_decode.onnx',
    'shruti_ur/cached_decode.onnx':
        'https://huggingface.co/udgamlabs/Shruti-ONNX/resolve/main/ur/sherpa-onnx/cached_decode.onnx',
    'shruti_ur/tokens.txt':
        'https://huggingface.co/udgamlabs/Shruti-ONNX/resolve/main/ur/sherpa-onnx/tokens.txt',
    // MI-GAN (MIT) — photo object remove, 512x512 pipeline.
    'migan/migan_pipeline_v2.onnx':
        'https://huggingface.co/andraniksargsyan/migan/resolve/main/migan_pipeline_v2.onnx',
    // BiRefNet_lite fp16 (MIT) — photo BG matte, fixed 1024x1024.
    'birefnet_fp16/model_fp16.onnx':
        'https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/main/onnx/model_fp16.onnx',
    // Real-ESRGAN general-x4v3 (BSD-3) — photo enhance.
    'esrgan/realesr-general-x4v3.onnx':
        'https://huggingface.co/CoderViking/realesr-general-x4v3-onnx/resolve/main/realesr-general-x4v3.onnx',
    // Depth Anything V2 Small int8 (Apache-2.0) — depth/bokeh.
    'depth_v2_small/model_int8.onnx':
        'https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model_int8.onnx',
    // MODNet (Apache-2.0) — portrait matte, 512x512.
    'modnet/model.onnx':
        'https://huggingface.co/Xenova/modnet/resolve/main/onnx/model.onnx',
    // Fast-neural-style (ONNX Model Zoo, Apache-2.0) — "Artistic
    // Styles". Candy is BANNED (eye artifact) and has no pack.
    // v1.5.0 (#27 root cause): these MUST use media.githubusercontent
    // .com — raw.githubusercontent.com serves a 132-byte Git LFS
    // POINTER file for these .onnx binaries, not the model itself;
    // the download "succeeded" and the size sanity then rejected it,
    // which v1.4.0 misreported as an internet problem. The media
    // host serves the real 6,728,029-byte files (verified live).
    'fns_udnie/udnie-9.onnx':
        'https://media.githubusercontent.com/media/onnx/models/main/validated/vision/style_transfer/fast_neural_style/model/udnie-9.onnx',
    'fns_mosaic/mosaic-9.onnx':
        'https://media.githubusercontent.com/media/onnx/models/main/validated/vision/style_transfer/fast_neural_style/model/mosaic-9.onnx',
    'fns_rain/rain-princess-9.onnx':
        'https://media.githubusercontent.com/media/onnx/models/main/validated/vision/style_transfer/fast_neural_style/model/rain-princess-9.onnx',
    // RIFE v4.6 (MIT) — export-time slow-mo interpolation, mirrored
    // on the Nigraan site (verified live: 200, 21,297,017 bytes).
    'rife_v46/rife_v4.6.onnx':
        'https://nigraantv.xyz/apps/models/rife_v4.6.onnx',
    // DeepFilterNet3 (MIT/Apache-2.0) — the four files extracted
    // from the tested upstream tarball and mirrored on the Nigraan
    // site. Downloadable from v1.5.0; the DSP port is still pending
    // verification (AudioEnhanceService keeps its ffmpeg chain and
    // never claims this pack).
    'dfn3/enc.onnx': 'https://nigraantv.xyz/apps/models/enc.onnx',
    'dfn3/erb_dec.onnx':
        'https://nigraantv.xyz/apps/models/erb_dec.onnx',
    'dfn3/df_dec.onnx':
        'https://nigraantv.xyz/apps/models/df_dec.onnx',
    'dfn3/config.ini': 'https://nigraantv.xyz/apps/models/config.ini',
    // RNNoise model for ffmpeg's arnndn filter (official xiph models
    // mirrored by GregorR/rnnoise-models for exactly this filter):
    // cb.rnnn = the general-purpose speech model (conjoined-burgers).
    'rnnoise_models/cb.rnnn':
        'https://raw.githubusercontent.com/GregorR/rnnoise-models/master/conjoined-burgers-2018-08-28/cb.rnnn',
  };
}


