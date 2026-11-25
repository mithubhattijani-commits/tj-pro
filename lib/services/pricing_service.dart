/// Point #20 (user order, 2026-11-25) — CENTRAL REMOTE PRICING.
///
/// The owner cannot know in advance which feature should carry
/// an ad and which should cost coins, so NO price is final in
/// code any more: every chargeable tool/option has a stable key
/// and its price is read from the remote config (tj-pro.json,
/// the `prices` object — see [RemoteConfig.prices]). Changing a
/// price never needs a new build: edit the value in tj-pro.json
/// and the next config refresh (every cold start, Build 12)
/// applies it.
///
/// VALUE SEMANTICS (one place only: [PriceSpec.parse]):
/// - key ABSENT -> the caller decides: [spec] treats it as FREE;
///   migrated points use [specOr] / [charge] with their legacy
///   built-in fallback so today's behaviour is preserved until
///   the owner sets the key.
/// - a positive number (int, integral double, or numeric
///   string) -> that many COINS per use (clamped to 1..10000).
/// - 0 or a negative number -> FREE.
/// - the string "pro" -> PRO-ONLY (Pro users + admins pass;
///   everyone else is told it is a Pro feature).
/// - the string "ad" -> unlock by watching ONE rewarded ad.
/// - anything else (bool, list, map, garbage string) -> FREE.
///   A config typo can therefore never lock a feature or invent
///   a price — the worst case is the feature runs free.
///
/// Charging itself is NOT re-implemented here: coins go through
/// [CoinService.spendAmount] (server ledger, admin waiver), Pro
/// through [ProService.proActive], and the unlock ad through
/// [UnityAdsService] on the standard rewarded placement —
/// showing that placement never credits coins (crediting is
/// [CoinService.watchRewardedAd]'s separate earn path).
///
/// The full key inventory + owner instructions live in
/// ~/workspace/tj-pro-build/PRICING-KEYS.md.
library;

import 'coin_service.dart';
import 'pro_service.dart';
import 'remote_config_service.dart';
import 'unity_ads_service.dart';

/// What one `prices` value means.
enum PriceKind {
  /// No charge — the feature runs.
  free,

  /// Charge [PriceSpec.coins] coins per use.
  coins,

  /// Pro subscribers (and admins) only.
  pro,

  /// Watch one rewarded ad to unlock this use.
  ad,
}

/// A resolved price: a [kind] plus the coin amount (only
/// meaningful when [kind] is [PriceKind.coins]).
class PriceSpec {
  const PriceSpec._(this.kind, this.coins);

  final PriceKind kind;
  final int coins;

  static const PriceSpec free = PriceSpec._(PriceKind.free, 0);
  static const PriceSpec proOnly = PriceSpec._(PriceKind.pro, 0);
  static const PriceSpec adUnlock = PriceSpec._(PriceKind.ad, 0);

  factory PriceSpec.coins(int amount) =>
      PriceSpec._(PriceKind.coins, amount);

  bool get isFree => kind == PriceKind.free;

  /// Highest price a config value may set (same guard as the
  /// Build 9 AI-tool price, so a typo cannot invent a fortune).
  static const int maxCoins = 10000;

  /// Parses ONE raw `prices` value. Pure and total: every input
  /// maps to a spec, and malformed input maps to [free] — see
  /// the file header for the full semantics table.
  static PriceSpec parse(dynamic raw) {
    if (raw == null) return free;
    if (raw is int) {
      return raw > 0 ? PriceSpec.coins(_clamp(raw)) : free;
    }
    if (raw is double) {
      if (raw == raw.roundToDouble() && raw > 0) {
        return PriceSpec.coins(_clamp(raw.round()));
      }
      return free;
    }
    if (raw is String) {
      final String s = raw.trim().toLowerCase();
      if (s == 'pro') return proOnly;
      if (s == 'ad') return adUnlock;
      final int? n = int.tryParse(s);
      if (n != null) return n > 0 ? PriceSpec.coins(_clamp(n)) : free;
      return free;
    }
    return free;
  }

  static int _clamp(int n) => n > maxCoins ? maxCoins : n;

  @override
  bool operator ==(Object other) =>
      other is PriceSpec && other.kind == kind && other.coins == coins;

  @override
  int get hashCode => Object.hash(kind, coins);

  @override
  String toString() => 'PriceSpec($kind, $coins)';
}

/// Key registry + resolution + the silent charge flow used by
/// the spend-style call sites (voiceover, One Click, chroma).
/// Dialog-style points (the AI tools) resolve through here too
/// but run their own confirm UI in AiToolCharge.
class PricingService {
  PricingService._();

  // --- Stable keys (NEVER rename: they live in tj-pro.json) ---

  /// Photo Editor AI tools + Video Editor on-device ML tools
  /// (background remover, motion tracking). Migrated from
  /// `ai_tool_price_coins` (default 25).
  static const String keyPhotoAi = 'price_photo_ai';

  /// Video Editor AI Caption Generator (Whisper, on-device).
  /// Migrated from `ai_tool_price_coins` (default 25).
  static const String keyVeCaptionGenerator = 'price_ve_caption_generator';

  /// Video Editor "Urdu (AI)" auto captions (Sherpa-ONNX).
  /// Migrated from `ai_tool_price_coins` (default 25).
  static const String keyVeAutoCaptions = 'price_ve_auto_captions';

  /// News Studio voiceover per NEW voice (Gemini + free TTS;
  /// cached voices stay free). Default 50 ([CoinCosts.voiceover]).
  static const String keyNsVoiceover = 'price_ns_voiceover';

  /// One Click AI News Maker, per run. Default 100
  /// ([CoinCosts.oneClick]).
  static const String keyNsOneClick = 'price_ns_one_click';

  /// News Studio export chroma-key add-on. Default 50
  /// ([CoinCosts.chromaKey]).
  static const String keyNsChroma = 'price_ns_chroma';

  /// Templates Library premium templates (the priced breaking
  /// variants). Number-only point: it scales the per-item price,
  /// so "pro"/"ad" fall back to the item price. Default 25.
  static const String keyNsPremiumTemplate = 'price_ns_premium_template';

  /// News Studio Logo Parts save (7-day save). Default 300
  /// (kLogoPartsSavePriceCoins).
  static const String keyLogoPartsSave = 'price_logo_parts_save';

  /// Hero banner booking, 1 hour. Default 100. Number-only
  /// (a booking is a purchase, not an unlock).
  static const String keyBannerBooking1h = 'price_banner_booking_1h';

  /// Hero banner booking, 2 hours. Default 200. Number-only.
  static const String keyBannerBooking2h = 'price_banner_booking_2h';

  /// Hero banner booking, 4 hours. Default 300. Number-only.
  static const String keyBannerBooking4h = 'price_banner_booking_4h';

  /// Motion Graphics Studio templates (Motion M1): one key per
  /// template, `motion_price_<templateId>`. The tier default
  /// (FREE / PRO / coins) ships in the template's own data; the
  /// config value overrides it when present.
  static String keyMotionTemplate(String templateId) =>
      'motion_price_$templateId';

  /// CoinSpendResult error for a "pro" price the user cannot
  /// pass (not Pro, not admin).
  static const String errorProRequired = 'pro_required';

  /// CoinSpendResult error for an "ad" price whose ad was not
  /// watched to completion (skipped / no fill / failed).
  static const String errorAdNotCompleted = 'ad_not_completed';

  // --- Resolution ----------------------------------------------

  /// The spec for [key] exactly as configured: an ABSENT key is
  /// FREE (the system-wide rule — a feature with no configured
  /// price can never be locked by accident).
  static PriceSpec spec(String key, {RemoteConfig? config}) {
    final RemoteConfig cfg = config ?? RemoteConfigService.instance.config;
    if (!cfg.prices.containsKey(key)) return PriceSpec.free;
    return PriceSpec.parse(cfg.prices[key]);
  }

  /// The spec for a MIGRATED point: an absent key falls back to
  /// [fallbackCoins] (the price the point charged before this
  /// system existed), so deploying the code before the config —
  /// or a phone holding an old cached config — changes nothing.
  /// Once the key exists in `prices`, its value rules (0 makes
  /// the point free, "pro"/"ad" switch its gate).
  static PriceSpec specOr(
    String key, {
    required int fallbackCoins,
    RemoteConfig? config,
  }) {
    final RemoteConfig cfg = config ?? RemoteConfigService.instance.config;
    if (!cfg.prices.containsKey(key)) {
      return fallbackCoins > 0
          ? PriceSpec.coins(fallbackCoins)
          : PriceSpec.free;
    }
    return PriceSpec.parse(cfg.prices[key]);
  }

  /// Number-only resolution for price TABLES (banner booking
  /// durations, per-item template prices): a configured number
  /// wins (0 = free), an absent key keeps [fallback], and a
  /// "pro"/"ad" value — meaningless in a table — also keeps
  /// [fallback] rather than breaking the table.
  static int coinsOr(String key, int fallback, {RemoteConfig? config}) {
    final RemoteConfig cfg = config ?? RemoteConfigService.instance.config;
    if (!cfg.prices.containsKey(key)) return fallback;
    final PriceSpec s = PriceSpec.parse(cfg.prices[key]);
    switch (s.kind) {
      case PriceKind.coins:
        return s.coins;
      case PriceKind.free:
        return 0;
      case PriceKind.pro:
      case PriceKind.ad:
        return fallback;
    }
  }

  // --- Charging --------------------------------------------------

  /// True when the current user passes a "pro" price: an active
  /// Pro grant, or an admin (admins are waived everywhere).
  static bool get passesPro =>
      CoinService.instance.isAdminNow || ProService.instance.proActive;

  /// The silent charge flow for spend-style points (no dialogs —
  /// the tap that started the action is the consent, exactly as
  /// these points behaved before this system):
  /// - free -> ok, nothing charged.
  /// - coins -> [CoinService.spendAmount] at the resolved price
  ///   (server ledger; admins waived inside CoinService).
  /// - pro -> ok for Pro/admin, else [errorProRequired].
  /// - ad -> one rewarded ad; ok only on a full watch, else
  ///   [errorAdNotCompleted].
  static Future<CoinSpendResult> charge(
    String key, {
    required String reason,
    required int fallbackCoins,
    String? idempotencyKey,
  }) async {
    final PriceSpec s = specOr(key, fallbackCoins: fallbackCoins);
    switch (s.kind) {
      case PriceKind.free:
        return const CoinSpendResult(ok: true);
      case PriceKind.coins:
        return CoinService.instance.spendAmount(
          s.coins,
          reason: reason,
          idempotencyKey: idempotencyKey,
        );
      case PriceKind.pro:
        return passesPro
            ? const CoinSpendResult(ok: true)
            : const CoinSpendResult(ok: false, error: errorProRequired);
      case PriceKind.ad:
        final bool watched = await watchUnlockAd();
        return watched
            ? const CoinSpendResult(ok: true)
            : const CoinSpendResult(
                ok: false,
                error: errorAdNotCompleted,
              );
    }
  }

  /// Shows ONE rewarded ad on the standard rewarded placement
  /// and returns true only when it was watched to completion.
  /// Never credits coins and never touches the earn counters —
  /// earning is [CoinService.watchRewardedAd]'s own path.
  /// Fail-soft: any failure (not initialized, no fill, SDK
  /// error) returns false, i.e. "not unlocked".
  static Future<bool> watchUnlockAd() async {
    try {
      await UnityAdsService.init();
      if (!UnityAdsService.isInitialized) return false;
      final String placement =
          CoinService.instance.rewardedCoinsPlacementId;
      final bool loaded =
          await UnityAdsService.loadRewardedAdForPlacement(placement);
      if (!loaded) return false;
      final UnityAdResult result =
          await UnityAdsService.showRewardedAdForPlacement(placement);
      return result == UnityAdResult.completed;
    } catch (_) {
      return false;
    }
  }
}
