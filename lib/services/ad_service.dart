/// AdMob loading and showing, kept separate from editor screens.
///
/// All failures are swallowed on purpose: if an ad cannot load (offline,
/// test environment, no ad fill), the editors keep working and no ad
/// is shown. A rewarded ad only unlocks Premium when the provider
/// actually reports the reward.
library;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_config.dart';

class AdService {
  /// True after the user earns a rewarded ad. Session only in V1.
  static bool premiumUnlocked = false;

  /// True when AI tools may be used: either unlocked, or the rewarded
  /// switch is off, or ads are off entirely.
  static bool get isPremiumUnlocked =>
      premiumUnlocked ||
      !AppConfig.adsEnabled ||
      !AppConfig.rewardedAdEnabled;

  static InterstitialAd? _interstitial;
  static RewardedAd? _rewarded;
  static AppOpenAd? _appOpen;
  static bool _initialised = false;

  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    if (!AppConfig.adsEnabled) return;
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      return;
    }
    await loadInterstitial();
    await loadRewarded();
    await loadAppOpen();
  }

  static Future<void> loadInterstitial() async {
    if (!AppConfig.adsEnabled || !AppConfig.interstitialAdEnabled) return;
    try {
      await InterstitialAd.load(
        adUnitId: AppConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitial = ad,
          onAdFailedToLoad: (_) => _interstitial = null,
        ),
      );
    } catch (_) {
      _interstitial = null;
    }
  }

  /// Shows the interstitial if one is loaded, then reloads a fresh one.
  static void showInterstitial() {
    if (!AppConfig.adsEnabled || !AppConfig.interstitialAdEnabled) return;
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        loadInterstitial();
      },
    );
    ad.show();
  }

  static Future<void> loadRewarded() async {
    if (!AppConfig.adsEnabled || !AppConfig.rewardedAdEnabled) return;
    try {
      await RewardedAd.load(
        adUnitId: AppConfig.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _rewarded = ad,
          onAdFailedToLoad: (_) => _rewarded = null,
        ),
      );
    } catch (_) {
      _rewarded = null;
    }
  }

  static Future<void> loadAppOpen() async {
    if (!AppConfig.adsEnabled || !AppConfig.appOpenAdEnabled) return;
    try {
      await AppOpenAd.load(
        adUnitId: AppConfig.appOpenAdUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) => _appOpen = ad,
          onAdFailedToLoad: (_) => _appOpen = null,
        ),
      );
    } catch (_) {
      _appOpen = null;
    }
  }

  /// Shows the cold-start app open ad if one is loaded. Returns true
  /// when an ad was shown. Never blocks: no loaded ad means no ad.
  static bool showAppOpen() {
    if (!AppConfig.adsEnabled || !AppConfig.appOpenAdEnabled) return false;
    final ad = _appOpen;
    if (ad == null) return false;
    _appOpen = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        loadAppOpen();
      },
    );
    ad.show();
    return true;
  }

  /// Shows the rewarded ad. Calls [onRewarded] only when the provider
  /// reports the reward. Returns false when no ad was available.
  static Future<bool> showRewarded() async {
    if (!AppConfig.adsEnabled || !AppConfig.rewardedAdEnabled) {
      premiumUnlocked = true;
      return true;
    }
    var ad = _rewarded;
    if (ad == null) {
      await loadRewarded();
      ad = _rewarded;
    }
    if (ad == null) return false;
    _rewarded = null;
    var rewarded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        loadRewarded();
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        rewarded = true;
        premiumUnlocked = true;
      },
    );
    return rewarded;
  }
}

