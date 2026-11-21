/// Premium AI unlock gate — Unity Ads edition (one-build, defect #4).
///
/// This replaces the old AdMob `AdService` gate. The unlock rule is
/// the same one the AdMob service implemented, so behaviour does not
/// change for users:
///
/// * Session-only unlock: watching one full rewarded ad unlocks the
///   Premium AI tools until the app is closed.
/// * The gate is OPEN when ads are off entirely
///   ([AppConfig.adsEnabled] false) or when the rewarded unlock is
///   switched off ([AppConfig.rewardedAdEnabled] false) — the AI
///   tools then work without an ad, exactly as before.
///
/// The ad itself is served by [UnityAdsService] (placement
/// `BP_Rewarded_Android`). A rewarded ad only unlocks when Unity
/// reports completion. All failures are swallowed on purpose: if no
/// ad can load or show, the caller explains and the editors keep
/// working.
library;

import '../app_config.dart';
import 'unity_ads_service.dart';

class PremiumGate {
  /// True after the user earns a rewarded ad. Session only.
  static bool premiumUnlocked = false;

  /// True when AI tools may be used: already unlocked this session,
  /// or the rewarded switch is off, or ads are off entirely.
  static bool get isUnlocked =>
      premiumUnlocked ||
      !AppConfig.adsEnabled ||
      !AppConfig.rewardedAdEnabled;

  /// Shows the Unity rewarded ad. Returns true (and unlocks) only
  /// when the user watched the full ad. When the gate is already open
  /// (ads off / rewarded off) it unlocks immediately, mirroring the
  /// old AdMob behaviour. Returns false when no ad was available or
  /// the user skipped — nothing is unlocked then.
  static Future<bool> tryUnlockWithAd() async {
    if (!AppConfig.adsEnabled || !AppConfig.rewardedAdEnabled) {
      premiumUnlocked = true;
      return true;
    }
    if (premiumUnlocked) return true;
    final result = await UnityAdsService.showRewardedAd();
    if (result == UnityAdResult.completed) {
      premiumUnlocked = true;
      return true;
    }
    return false;
  }
}
