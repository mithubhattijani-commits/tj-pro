import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import '../app_config.dart';

/// Unity Ads rewarded + interstitial + banner integration for
/// TJ Pro.
///
/// - Game ID: 800418048 (Android, "TJ Pro" project)
/// - Rewarded placement: BP_Rewarded_Android
/// - Interstitial placement: BP_Interstitial_Android
/// - Banner placement: BP_Banner_Android (see [AppConfig])
///
/// REVENUE ads only — no coin ledger, no server calls. All failures
/// are swallowed on purpose — if an ad cannot load or show, the
/// editors keep working and no ad is shown. A rewarded ad only
/// unlocks Premium when Unity actually reports completion.
///
/// Test mode is OFF (production). Unity serves test ads only while
/// [testMode] is true in development builds.
class UnityAdsService {
  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

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

  /// Fired when a full-screen ad has actually been watched: a
  /// rewarded ad completed in full, or an interstitial that was
  /// shown (completed or skipped after starting). Set ONCE by
  /// ReferralService at startup (Share & Earn "first ad watched"
  /// qualification); null in every other context, and every firing
  /// is guarded so a bad callback can never break an ad flow.
  static void Function()? onAdCompleted;

  static void _notifyAdCompleted() {
    final cb = onAdCompleted;
    if (cb == null) return;
    try {
      cb();
    } catch (_) {
      // A listener bug must never break ads.
    }
  }

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
  ///
  /// v1.3.0 (§8): rewarded ads are EARN-COINS ONLY — this preloads the
  /// coins placement (`rewarded_coins`). The old Premium-unlock
  /// placement is gone; premium tools unlock with coins.
  static Future<bool> loadRewardedAd() async {
    return loadRewardedAdForPlacement(
      AppConfig.unityRewardedCoinsPlacementId,
    );
  }

  /// Load a rewarded video ad for a specific placement ID (e.g. the
  /// coins placement `rewarded_coins`).
  static Future<bool> loadRewardedAdForPlacement(String placementId) async {
    if (!_initialized || !AppConfig.unityRewardedEnabled) return false;
    try {
      final completer = Completer<bool>();
      UnityAds.load(
        placementId: placementId,
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

  /// Show the rewarded video ad (the earn-coins placement).
  ///
  /// Returns [UnityAdResult.completed] when the user watched the full
  /// ad (the caller credits coins), [UnityAdResult.skipped] when they
  /// skipped early, [UnityAdResult.failed] on error. v1.3.0 (§8):
  /// a completed rewarded ad NEVER unlocks premium tools directly —
  /// it only earns coins (see CoinService.watchRewardedAd).
  static Future<UnityAdResult> showRewardedAd() async {
    return showRewardedAdForPlacement(
      AppConfig.unityRewardedCoinsPlacementId,
    );
  }

  /// Show a rewarded video ad for a specific placement ID (e.g. the
  /// coins placement). Returns [UnityAdResult.completed] only when the
  /// user watched the full ad — the caller (CoinService) credits coins
  /// only on completion. Preloads the next ad for the same placement
  /// afterwards.
  static Future<UnityAdResult> showRewardedAdForPlacement(
    String placementId,
  ) async {
    if (!_initialized || !AppConfig.unityRewardedEnabled) {
      return UnityAdResult.failed;
    }
    try {
      final completer = Completer<UnityAdResult>();
      UnityAds.showVideoAd(
        placementId: placementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.skipped);
          }
        },
        onComplete: (placementId) {
          _notifyAdCompleted();
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
      unawaited(loadRewardedAdForPlacement(placementId));
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
          _notifyAdCompleted();
          if (!completer.isCompleted) completer.complete(true);
        },
        onComplete: (placementId) {
          _notifyAdCompleted();
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

  // ------------------------------------------------------------------
  // Export ads (v1.2.0)
  // ------------------------------------------------------------------

  static bool _exportAdsInFlight = false;

  /// Show [count] interstitial ads back-to-back alongside a video
  /// export (v1.2.0 export rule: 720p → 1 ad, 1080p / 4K → 2 ads;
  /// export resolution no longer costs coins).
  ///
  /// BEST-EFFORT ONLY: callers must fire this unawaited — the export
  /// starts immediately and never waits for, or fails because of,
  /// these ads. Every failure (SDK not initialized, offline, no fill,
  /// load/show timeout) is swallowed; when one ad closes OR fails the
  /// next one is attempted, and a failure simply ends that attempt.
  /// The regular interstitial frequency cap is bypassed here because
  /// the second ad must follow the first immediately, but each show
  /// still updates [_lastInterstitialShown] so ordinary interstitials
  /// stay capped afterwards. Re-entrant calls while a sequence is
  /// already running are ignored.
  static Future<void> showExportAds(int count) async {
    if (count <= 0 || _exportAdsInFlight) return;
    if (!AppConfig.unityAdsEnabled ||
        !AppConfig.unityInterstitialEnabled) {
      return;
    }
    _exportAdsInFlight = true;
    try {
      await init();
      if (!_initialized) return;
      for (var i = 0; i < count; i++) {
        // Sequential on purpose: the next ad is attempted only after
        // the previous one closed or failed. The result is ignored —
        // a failed ad never stops the export (which is not waiting
        // on this future anyway).
        await _showOneExportInterstitial();
      }
    } catch (_) {
      // Export ads are decoration — never surface a failure.
    } finally {
      _exportAdsInFlight = false;
    }
  }

  /// Load (bounded 15s wait via [loadInterstitialAd]) + show ONE
  /// interstitial for the export sequence, ignoring the frequency
  /// cap. Returns true when an ad was shown (completed or skipped),
  /// false on any failure. Show is bounded by a 2-minute timeout.
  /// Never throws.
  static Future<bool> _showOneExportInterstitial() async {
    if (!_initialized || !AppConfig.unityInterstitialEnabled) {
      return false;
    }
    try {
      final loaded = await loadInterstitialAd();
      if (!loaded) return false;
      final completer = Completer<bool>();
      UnityAds.showVideoAd(
        placementId: AppConfig.unityInterstitialPlacementId,
        onStart: (placementId) {
          _lastInterstitialShown = DateTime.now();
        },
        onClick: (placementId) {},
        onSkipped: (placementId) {
          _notifyAdCompleted();
          if (!completer.isCompleted) completer.complete(true);
        },
        onComplete: (placementId) {
          _notifyAdCompleted();
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Outcome of showing a Unity rewarded ad.
enum UnityAdResult {
  /// User watched the full ad — caller credits the coin reward.
  completed,

  /// User skipped before the end — no reward.
  skipped,

  /// Ad failed to load or show — no reward, show retry.
  failed,
}

/// Unity banner ad slot (one-build, defect #4) — replaces the old
/// AdMob `BannerAdWidget` in the same Home + editor slots.
///
/// Renders nothing at all until Unity reports the banner loaded, so
/// a failed or offline load never leaves a broken/empty slot on
/// screen. The banner placement (`BP_Banner_Android`) must exist in
/// the Unity dashboard (TJ Pro project, Game ID 800418048); until it
/// does, Unity reports a load failure and this widget simply stays
/// hidden — the app is fully usable either way.
class UnityBannerAdWidget extends StatefulWidget {
  const UnityBannerAdWidget({super.key});

  @override
  State<UnityBannerAdWidget> createState() => _UnityBannerAdWidgetState();
}

class _UnityBannerAdWidgetState extends State<UnityBannerAdWidget> {
  bool _loaded = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled ||
        !AppConfig.bannerAdEnabled ||
        !AppConfig.unityAdsEnabled ||
        _failed) {
      return const SizedBox.shrink();
    }
    return UnityBannerAd(
      placementId: AppConfig.unityBannerPlacementId,
      onLoad: (placementId) {
        if (mounted) setState(() => _loaded = true);
      },
      onFailed: (placementId, error, message) {
        if (mounted) {
          setState(() {
            _loaded = false;
            _failed = true;
          });
        }
      },
      onClick: (placementId) {},
      onShown: (placementId) {},
    );
  }

  /// Whether the banner actually loaded (kept for future layout use).
  bool get isLoaded => _loaded;
}
