import 'dart:async';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import '../app_config.dart';

/// Unity Ads rewarded + interstitial integration for TJ Pro.
///
/// - Game ID: 800418048 (Android, "TJ Pro" project)
/// - Rewarded placement: BP_Rewarded_Android
/// - Interstitial placement: BP_Interstitial_Android
///
/// REVENUE ads only — no coin ledger, no server calls. Mirrors the
/// AdMob [AdService] pattern: all failures are swallowed on purpose —
/// if an ad cannot load or show, the editors keep working and no ad
/// is shown. A rewarded ad only unlocks Premium when Unity actually
/// reports completion.
///
/// Test mode is ON for development. Flip [testMode] to false for
/// production builds.
class UnityAdsService {
  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = true;

  /// Minimum seconds between interstitial shows (frequency capping).
  static const int interstitialMinIntervalSec = 120;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;

  /// Whether the SDK initialized successfully.
  static bool get isInitialized => _initialized;

  /// Whether init was attempted and failed (UI can explain why the
  /// rewarded option is unavailable).
  static bool get initFailed => _initFailed;

  static DateTime? _lastInterstitialShown;

  /// Initialize the Unity Ads SDK. Safe to call once at app startup;
  /// subsequent calls are no-ops. Never throws, never blocks startup
  /// for more than ~10s.
  static Future<void> init() async {
    if (_initialized || _initFailed || _initStarted) return;
    _initStarted = true;
    if (!AppConfig.unityAdsEnabled) return;
    try {
      final completer = Completer<void>();
      UnityAds.init(
        gameId: AppConfig.unityGameId,
        testMode: testMode,
        onComplete: () {
          _initialized = true;
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (error, message) {
          _initFailed = true;
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    } catch (_) {
      _initFailed = true;
    }
    // Preload both placements in the background (never blocks).
    if (_initialized) {
      unawaited(loadRewardedAd());
      unawaited(loadInterstitialAd());
    }
  }

  // ------------------------------------------------------------------
  // Rewarded video
  // ------------------------------------------------------------------

  /// Load the rewarded video ad. Called at init and automatically
  /// after each show so the next ad is ready.
  static Future<bool> loadRewardedAd() async {
    if (!_initialized || !AppConfig.unityRewardedEnabled) return false;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: AppConfig.unityRewardedPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Show the rewarded video ad.
  ///
  /// Returns [UnityAdResult.completed] when the user watched the full
  /// ad (caller unlocks Premium), [UnityAdResult.skipped] when they
  /// skipped early, [UnityAdResult.failed] on error.
  static Future<UnityAdResult> showRewardedAd() async {
    if (!_initialized || !AppConfig.unityRewardedEnabled) {
      return UnityAdResult.failed;
    }
    try {
      final completer = Completer<UnityAdResult>();
      UnityAds.showVideoAd(
        placementId: AppConfig.unityRewardedPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.skipped);
          }
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.completed);
          }
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.failed);
          }
        },
      );
      final result = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => UnityAdResult.failed,
      );
      // Preload the next ad in the background.
      unawaited(loadRewardedAd());
      return result;
    } catch (_) {
      return UnityAdResult.failed;
    }
  }

  // ------------------------------------------------------------------
  // Interstitial
  // ------------------------------------------------------------------

  /// Load the interstitial ad. Called at init and automatically after
  /// each show so the next ad is ready.
  static Future<bool> loadInterstitialAd() async {
    if (!_initialized || !AppConfig.unityInterstitialEnabled) return false;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: AppConfig.unityInterstitialPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Shows the interstitial if one is ready AND the frequency cap
  /// allows it (at least [interstitialMinIntervalSec] since the last
  /// show). Returns true when an ad was shown. Never throws.
  static Future<bool> showInterstitialAd() async {
    if (!_initialized || !AppConfig.unityInterstitialEnabled) return false;
    final last = _lastInterstitialShown;
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inSeconds;
      if (elapsed < interstitialMinIntervalSec) return false;
    }
    try {
      final completer = Completer<bool>();
      UnityAds.showVideoAd(
        placementId: AppConfig.unityInterstitialPlacementId,
        onStart: (placementId) {
          _lastInterstitialShown = DateTime.now();
        },
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      final shown = await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
      // Preload the next ad in the background.
      unawaited(loadInterstitialAd());
      return shown;
    } catch (_) {
      return false;
    }
  }
}

/// Outcome of showing a Unity rewarded ad.
enum UnityAdResult {
  /// User watched the full ad — caller unlocks the reward.
  completed,

  /// User skipped before the end — no reward.
  skipped,

  /// Ad failed to load or show — no reward, show retry.
  failed,
}
