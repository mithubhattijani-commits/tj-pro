/// MOTION GRAPHICS STUDIO — pricing, entitlement, ownership
/// (Build M1, v1.11.0).
///
/// PRICES ARE REMOTE (user order 2026-11-25, fix-list point
/// #20): the owner must be able to reprice anything without a
/// build. Every Motion template reads its price from the remote
/// config's `prices` map under the key `motion_price_<id>`:
///
///   - key absent        -> the template's TIER DEFAULT
///                          (FREE = 0; PRO = [MotionPricing
///                          .proTierDefaultCoins] = 50 coins for
///                          non-Pro users, included for Pro;
///                          COINS = the template's listed
///                          [MotionTemplate.coinPrice]).
///   - a number          -> that many coins (0 = free).
///   - the string "pro"  -> Pro-only: no coin unlock at all.
///   - the string "ad"   -> unlock by watching a rewarded ad.
///
/// The read is FAIL-SOFT by construction: no config, an offline
/// phone, or a malformed value all fall back to the tier
/// default, so a config typo can never lock (or free) the whole
/// Gallery by accident. This is the same `prices` map the
/// central PricingService (point #20) owns — Motion only reads
/// its own `motion_price_*` keys from it.
///
/// Entitlement itself uses only EXISTING machinery: Pro state
/// from [ProService], coin spends through [CoinService] (in
/// `motion_unlock.dart`), ownership in a local set —
/// [MotionOwnership] — following the Online Store's pattern.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../services/pricing_service.dart';
import '../services/remote_config_service.dart';
import 'motion_templates.dart';

/// How a template is priced right now (after remote override).
enum MotionPriceKind {
  /// No charge of any kind.
  free,

  /// Unlockable with [MotionPrice.coins] coins (one-time;
  /// Pro templates are additionally included for Pro users).
  coins,

  /// Pro members only — coins cannot buy it.
  proOnly,

  /// Unlock by watching one rewarded ad (one-time, then owned).
  adUnlock,
}

class MotionPrice {
  const MotionPrice(this.kind, this.coins);

  final MotionPriceKind kind;

  /// Coin amount when [kind] is [MotionPriceKind.coins].
  final int coins;
}

/// Resolves [MotionTemplate] prices from the remote `prices`
/// map (see the file header for the exact convention).
class MotionPricing {
  MotionPricing._();

  /// The PRO tier's default non-Pro unlock price (plan §6).
  static const int proTierDefaultCoins = 50;

  /// The remote-config key for [templateId] — the same string
  /// the central registry exposes as
  /// [PricingService.keyMotionTemplate].
  static String keyFor(String templateId) =>
      PricingService.keyMotionTemplate(templateId);

  /// The tier default — what a template costs when remote
  /// config says nothing about it.
  static MotionPrice tierDefault(MotionTemplate t) {
    switch (t.tier) {
      case MotionTier.free:
        return const MotionPrice(MotionPriceKind.free, 0);
      case MotionTier.pro:
        return const MotionPrice(
          MotionPriceKind.coins,
          proTierDefaultCoins,
        );
      case MotionTier.coins:
        return MotionPrice(MotionPriceKind.coins, t.coinPrice);
    }
  }

  /// The effective price: the remote value for
  /// `motion_price_<id>` in [prices] wins when the key EXISTS
  /// (parsed by the central [PriceSpec.parse] — the one parser
  /// for the whole pricing system, so Motion can never drift
  /// from it; a malformed value parses to FREE there, the
  /// system-wide typo rule). An ABSENT key falls back to
  /// [tierDefault] — Motion's one deliberate difference from
  /// the system-wide "absent = free" rule, registered in
  /// [PricingService.keyMotionTemplate]: a template's designed
  /// tier is its price until the owner says otherwise. Pure +
  /// injectable so the convention is unit-testable without a
  /// network.
  static MotionPrice resolve(
    MotionTemplate t, {
    Map<String, dynamic> prices = const {},
  }) {
    final key = keyFor(t.id);
    if (!prices.containsKey(key)) return tierDefault(t);
    final spec = PriceSpec.parse(prices[key]);
    switch (spec.kind) {
      case PriceKind.free:
        return const MotionPrice(MotionPriceKind.free, 0);
      case PriceKind.coins:
        return MotionPrice(MotionPriceKind.coins, spec.coins);
      case PriceKind.pro:
        return const MotionPrice(MotionPriceKind.proOnly, 0);
      case PriceKind.ad:
        return const MotionPrice(MotionPriceKind.adUnlock, 0);
    }
  }

  /// The effective price from the LIVE remote config (the
  /// Gallery's normal path; the config itself is fail-soft —
  /// defaults have an empty `prices` map).
  static MotionPrice resolveFromConfig(MotionTemplate t) =>
      resolve(t, prices: RemoteConfigService.instance.config.prices);
}

/// What the signed-in user may do with a template right now.
enum MotionAccessKind {
  /// FREE template (or repriced to free) — usable at once.
  free,

  /// PRO template and the user is Pro — included.
  proIncluded,

  /// Bought/unlocked earlier — owned forever (local record).
  owned,

  /// Locked; [MotionAccess.coins] buys it (one-time).
  lockedCoins,

  /// Locked; Pro membership is the only way in.
  lockedProOnly,

  /// Locked; one rewarded ad unlocks it (one-time).
  lockedAd,
}

class MotionAccess {
  const MotionAccess(this.kind, {this.coins = 0});

  final MotionAccessKind kind;

  /// The coin price when [kind] is [MotionAccessKind.lockedCoins].
  final int coins;

  bool get canUse =>
      kind == MotionAccessKind.free ||
      kind == MotionAccessKind.proIncluded ||
      kind == MotionAccessKind.owned;
}

/// Combines price + Pro state + ownership into one verdict.
/// Pure + injectable (the Gallery passes the live values).
class MotionAccessResolver {
  MotionAccessResolver._();

  static MotionAccess resolve(
    MotionTemplate t, {
    required bool isPro,
    required bool owned,
    Map<String, dynamic> prices = const {},
  }) {
    if (owned) return const MotionAccess(MotionAccessKind.owned);
    final price = MotionPricing.resolve(t, prices: prices);
    switch (price.kind) {
      case MotionPriceKind.free:
        return const MotionAccess(MotionAccessKind.free);
      case MotionPriceKind.proOnly:
        return isPro
            ? const MotionAccess(MotionAccessKind.proIncluded)
            : const MotionAccess(MotionAccessKind.lockedProOnly);
      case MotionPriceKind.adUnlock:
        return const MotionAccess(MotionAccessKind.lockedAd);
      case MotionPriceKind.coins:
        // PRO-tier templates are included for Pro members even
        // though their non-Pro path is coins (the user's
        // ruling). A COINS-tier template stays a coin purchase
        // for everyone, like the Online Store.
        if (t.tier == MotionTier.pro && isPro) {
          return const MotionAccess(MotionAccessKind.proIncluded);
        }
        return MotionAccess(
          MotionAccessKind.lockedCoins,
          coins: price.coins,
        );
    }
  }
}

/// One-time unlocks, recorded locally (the Online Store's
/// ownership pattern): once unlocked — by coins or by ad — a
/// template is owned forever on this device.
class MotionOwnership {
  MotionOwnership._();

  static const String _key = 'tjpro_motion_owned_v1';

  static Set<String>? _cache;

  /// The owned template ids (cached after first load;
  /// fail-soft: any storage error reads as "owns nothing").
  static Future<Set<String>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? const <String>[];
      return _cache = list.toSet();
    } catch (_) {
      return _cache = <String>{};
    }
  }

  static Future<bool> isOwned(String templateId) async =>
      (await load()).contains(templateId);

  /// Records [templateId] as owned (persisted at once).
  static Future<void> markOwned(String templateId) async {
    final owned = await load();
    if (!owned.add(templateId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, owned.toList());
    } catch (_) {
      // The in-memory cache still holds it for this session.
    }
  }

  /// Test seam: forget the in-memory cache (storage untouched).
  static void resetCacheForTest() => _cache = null;
}
