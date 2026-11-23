import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import 'auth_service.dart';
import 'remote_config_service.dart';
import 'supabase_service.dart';
import 'unity_ads_service.dart';

/// Coin economy for TJ Pro News Studio (user's numbers, 20 Nov 2026,
/// DISCOVERY-AND-PLAN.md §15).
///
/// Earn:
/// - 1 rewarded ad = 50 coins ([rewardPerAd]).
/// - Daily free coins = 50 ([dailyFreeCoins]).
/// - Max 50 rewarded ads/day = 2500 coins/day ([maxRewardedAdsPerDay]).
///
/// Spend ([CoinCosts]):
/// - One Click AI News Maker 100, voiceover 50/video, chroma key 50,
///   premium template 25, multi-platform publish 100, AI Enhance 50,
///   auto captions 25. (Export resolution is FREE since v1.2.0 — ads
///   play alongside the export instead; the legacy export* entries in
///   [CoinCosts] are retained but no longer charged by ExportScreen.)
///
/// Admins (the 3 emails in [SupabaseService.adminEmails]) pay nothing:
/// the SERVER waives the spend in `tjpro-spend-coins` and the Watch
/// Ads button is hidden for them. The client NEVER grants free
/// features on its own — [isAdmin] comes from [AuthService.isAdmin],
/// which is fed only by the server-side `tjpro-is-admin` check.
///
/// Local-first, server-wins (Magic Box pattern): the balance lives in
/// SharedPreferences so the UI always works, and every change is also
/// sent to the server ledger; [syncFromServer] replaces the local
/// balance with the server SUM when the functions are reachable. The
/// server enforces the daily ad cap and the balance on every spend —
/// a modded client cannot spend more than its ledger balance.
///
/// Usage (later phases): `await CoinService.instance.load()` once at
/// startup, then `CoinService.instance.balance` (a [ValueNotifier]) or
/// [balanceStream] for the app-bar pill, and
/// `await CoinService.instance.spend(CoinFeature.export1080p)` before
/// running a paid feature. The result tells the caller whether the
/// spend succeeded, failed for insufficient balance, or was waived
/// for an admin.
class CoinService {
  CoinService._();

  /// Shared instance.
  static final CoinService instance = CoinService._();

  /// Coins earned for one fully-watched rewarded ad.
  static const int rewardPerAd = 50;

  /// Free coins claimable once per calendar day.
  static const int dailyFreeCoins = 50;

  /// Max rewarded ads per user per day (server-enforced too).
  static const int maxRewardedAdsPerDay = 50;

  /// Max coins earnable from ads per day (50 x 50).
  static const int maxAdCoinsPerDay =
      maxRewardedAdsPerDay * rewardPerAd;

  static const String _balanceKey = 'tjpro_balance';
  static const String _dailyClaimKey = 'tjpro_daily_claimed_date';
  static const String _adsDateKey = 'tjpro_ads_date';
  static const String _adsCountKey = 'tjpro_ads_count';
  static const String _historyKey = 'tjpro_history_json_v1';

  /// Current coin balance. Updates immediately on every earn/spend.
  final ValueNotifier<int> balance = ValueNotifier<int>(0);

  /// Rewarded ads fully watched today (local counter; the server
  /// enforces the cap independently).
  final ValueNotifier<int> adsWatchedToday = ValueNotifier<int>(0);

  /// True while a load / sync / earn / spend is in flight.
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  /// Admin status — passthrough to [AuthService.isAdmin] (server-fed
  /// only). Admins pay nothing and never see the Watch Ads button.
  ValueNotifier<bool> get isAdmin => AuthService.isAdmin;

  bool get isAdminNow => AuthService.isAdmin.value;

  final StreamController<int> _balanceController =
      StreamController<int>.broadcast();

  /// Stream of balance values (emits on every change). Later phases
  /// can listen here instead of the [ValueNotifier].
  Stream<int> get balanceStream => _balanceController.stream;

  bool _loaded = false;
  SharedPreferences? _prefs;

  /// Unity rewarded placement that pays coins. Remote config wins
  /// (tj-pro.json `unity_rewarded_coins_placement_id`); the bundled
  /// [AppConfig.unityRewardedCoinsPlacementId] ('rewarded_coins') is
  /// the fallback.
  ///
  /// ⚠️ The placement MUST exist in the Unity dashboard (TJ Pro
  /// project, Game ID 800418048) before release — it cannot be created
  /// from code. Until then [watchRewardedAd] reports the ad as
  /// unavailable.
  String get rewardedCoinsPlacementId =>
      RemoteConfigService.instance.config.rewardedCoinsPlacementId;

  /// Load the local balance + counters, then sync from the server and
  /// refresh admin status (both best-effort, never block the UI).
  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    balance.value = _prefs!.getInt(_balanceKey) ?? 0;
    adsWatchedToday.value = _adsWatchedTodayLocal();
    _loaded = true;
    unawaited(RemoteConfigService.instance.init());
    unawaited(syncFromServer());
    unawaited(AuthService.refreshAdminStatus());
  }

  Future<void> _saveBalance() async {
    await _prefs?.setInt(_balanceKey, balance.value);
  }

  void _setBalance(int value) {
    if (balance.value == value) return;
    balance.value = value;
    _balanceController.add(value);
    unawaited(_saveBalance());
  }

  /// Pull the server balance (when the functions are deployed) and use
  /// it as the source of truth. Silently does nothing when offline or
  /// when the functions are not deployed yet.
  Future<void> syncFromServer() async {
    try {
      final serverBalance = await SupabaseService.getBalance();
      if (serverBalance == null) return;
      _setBalance(serverBalance);
      await fetchHistory();
    } catch (_) {
      // Local-only mode: keep the local balance.
    }
  }

  /// Refresh admin status from the server (delegates to AuthService).
  Future<bool> refreshAdminStatus() => AuthService.refreshAdminStatus();

  bool canAffordAmount(int cost) => isAdminNow || balance.value >= cost;

  bool canAfford(CoinFeature feature) =>
      canAffordAmount(CoinCosts.costFor(feature));

  /// Rewarded ads still available today (cap minus watched).
  int get adsRemainingToday =>
      (maxRewardedAdsPerDay - adsWatchedToday.value).clamp(
        0,
        maxRewardedAdsPerDay,
      );

  bool get canWatchAd =>
      adsRemainingToday > 0 && AppConfig.unityAdsEnabled;

  /// True when today's daily coins have NOT been claimed yet.
  bool get canClaimDaily {
    final claimed = _prefs?.getString(_dailyClaimKey) ?? '';
    return claimed != _todayKey();
  }

  int _adsWatchedTodayLocal() {
    if ((_prefs?.getString(_adsDateKey) ?? '') != _todayKey()) return 0;
    return _prefs?.getInt(_adsCountKey) ?? 0;
  }

  Future<void> _recordAdWatched() async {
    final today = _todayKey();
    if ((_prefs?.getString(_adsDateKey) ?? '') != today) {
      await _prefs?.setString(_adsDateKey, today);
      await _prefs?.setInt(_adsCountKey, 1);
    } else {
      final n = (_prefs?.getInt(_adsCountKey) ?? 0) + 1;
      await _prefs?.setInt(_adsCountKey, n);
    }
    adsWatchedToday.value = _adsWatchedTodayLocal();
  }

  /// Claim the daily 50 free coins. Returns true when coins were
  /// granted (server-credited, or locally in local-only mode).
  /// Returns false when already claimed today.
  Future<bool> claimDaily() async {
    if (!canClaimDaily) return false;
    if (!SupabaseService.isInitialized) {
      // Local-only build (no anon key): credit locally.
      await _prefs?.setString(_dailyClaimKey, _todayKey());
      await _addLocal(dailyFreeCoins, reason: CoinCosts.reasonDaily);
      return true;
    }
    await AuthService.ensureGuestSession();
    final granted = await SupabaseService.claimDailyCoins();
    if (granted == null) return false;
    await _prefs?.setString(_dailyClaimKey, _todayKey());
    if (granted > 0) {
      _setBalance(balance.value + granted);
      await _appendLocalHistory(
        CoinLedgerEntry(
          amountCoins: granted,
          type: 'tjpro_daily',
          reason: CoinCosts.reasonDaily,
          createdAt: DateTime.now(),
        ),
      );
    }
    unawaited(syncFromServer());
    return true;
  }

  /// Watch ONE Unity rewarded ad and earn 50 coins on full watch.
  /// The ad runs on the coins placement ([rewardedCoinsPlacementId]).
  /// Coins are credited SERVER-side (`tjpro-claim-ad-reward`) only
  /// after the ad completes; a skip or a failed ad earns nothing.
  /// The server enforces the 50/day cap — when it answers cap
  /// reached, the local counter is set to the cap.
  Future<CoinEarnResult> watchRewardedAd() async {
    // v1.5.2 (fix #66): admins may earn too — the old admin
    // early-return (plus the Coins screen's admin-hidden button)
    // is why the owner found NO earning path anywhere. Admin
    // SPENDS stay waived (canAffordAmount); earning is open.
    if (adsRemainingToday <= 0) {
      return const CoinEarnResult(
        ok: false,
        error: 'Daily ad limit reached (50 ads/day). Come back tomorrow.',
      );
    }
    if (!AppConfig.unityAdsEnabled || !AppConfig.unityRewardedEnabled) {
      return const CoinEarnResult(
        ok: false,
        error: 'Rewarded ads are turned off right now. Please try later.',
      );
    }
    isLoading.value = true;
    try {
      await AuthService.ensureGuestSession();
      await UnityAdsService.init();
      if (!UnityAdsService.isInitialized) {
        return const CoinEarnResult(
          ok: false,
          error:
              'Could not load the ad. Check your connection and try again.',
        );
      }
      final loaded = await UnityAdsService.loadRewardedAdForPlacement(
        rewardedCoinsPlacementId,
      );
      if (!loaded) {
        return const CoinEarnResult(
          ok: false,
          error:
              'No ad is available right now. Please try again in a bit.',
        );
      }
      final result = await UnityAdsService.showRewardedAdForPlacement(
        rewardedCoinsPlacementId,
      );
      if (result != UnityAdResult.completed) {
        return CoinEarnResult(
          ok: false,
          error: result == UnityAdResult.skipped
              ? 'Ad skipped — watch the full ad to earn coins.'
              : 'The ad could not be shown. Please try again.',
        );
      }
      // Ad completed: credit server-side.
      if (!SupabaseService.isInitialized) {
        // Local-only build: credit locally.
        await _recordAdWatched();
        await _addLocal(rewardPerAd, reason: CoinCosts.reasonAdReward);
        return const CoinEarnResult(ok: true, coins: rewardPerAd);
      }
      final granted = await SupabaseService.claimAdReward();
      if (granted == null) {
        // Server refused (cap reached or unreachable): treat the
        // local counter as capped so the button stops offering ads
        // this run; the coins were NOT credited.
        adsWatchedToday.value = maxRewardedAdsPerDay;
        await _prefs?.setString(_adsDateKey, _todayKey());
        await _prefs?.setInt(_adsCountKey, maxRewardedAdsPerDay);
        return const CoinEarnResult(
          ok: false,
          error:
              'Daily ad limit reached (50 ads/day). Come back tomorrow.',
        );
      }
      await _recordAdWatched();
      _setBalance(balance.value + granted);
      await _appendLocalHistory(
        CoinLedgerEntry(
          amountCoins: granted,
          type: 'tjpro_reward',
          reason: CoinCosts.reasonAdReward,
          createdAt: DateTime.now(),
        ),
      );
      return CoinEarnResult(ok: true, coins: granted);
    } finally {
      isLoading.value = false;
    }
  }

  /// Mirror a Share & Earn referral credit LOCALLY after the claim
  /// succeeded server-side (the `tjpro_claim_referral_rewards` RPC
  /// already wrote the ledger rows — ReferralService follows with a
  /// [syncFromServer] so the server SUM stays the truth; this local
  /// mirror only makes the balance move instantly). In the RPC-
  /// missing fallback the claim was a table flip only, and this
  /// local credit is the balance until the SQL is fully applied.
  /// Never throws.
  Future<void> creditReferralReward(int coins) async {
    if (coins <= 0) return;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _setBalance(balance.value + coins);
      await _appendLocalHistory(
        CoinLedgerEntry(
          amountCoins: coins,
          type: 'tjpro_referral',
          reason: CoinCosts.reasonReferral,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // A failed local mirror never breaks the claim flow; the
      // server ledger (RPC path) still holds the coins.
    }
  }

  /// Spend coins for a feature. The server re-validates the balance
  /// and debits the ledger; admins are waived server-side (no debit,
  /// still `ok: true`). Returns a [CoinSpendResult] the caller must
  /// check BEFORE running the paid feature.
  ///
  /// In a local-only build (no Supabase anon key) the spend is
  /// debited locally. When Supabase IS configured but unreachable,
  /// the spend is refused (never a silent local debit that the server
  /// would later overwrite).
  Future<CoinSpendResult> spend(
    CoinFeature feature, {
    String? idempotencyKey,
  }) {
    return spendAmount(
      CoinCosts.costFor(feature),
      reason: CoinCosts.reasonFor(feature),
      idempotencyKey: idempotencyKey,
    );
  }

  /// Spend an arbitrary amount for [reason] (ledger reason string).
  Future<CoinSpendResult> spendAmount(
    int amount, {
    required String reason,
    String? idempotencyKey,
  }) async {
    if (amount <= 0) {
      return const CoinSpendResult(ok: false, error: 'invalid_amount');
    }
    if (!SupabaseService.isInitialized) {
      // Local-only build: debit locally.
      if (!canAffordAmount(amount)) {
        return const CoinSpendResult(
          ok: false,
          error: 'insufficient_balance',
        );
      }
      _setBalance(balance.value - amount);
      await _appendLocalHistory(
        CoinLedgerEntry(
          amountCoins: -amount,
          type: 'tjpro_spend',
          reason: reason,
          createdAt: DateTime.now(),
        ),
      );
      return CoinSpendResult(ok: true, balance: balance.value);
    }

    await AuthService.ensureGuestSession();
    if (!canAffordAmount(amount) && !isAdminNow) {
      return const CoinSpendResult(
        ok: false,
        error: 'insufficient_balance',
      );
    }
    final key = idempotencyKey ??
        'tjpro_spend:${AuthService.currentUser?.id ?? 'guest'}:'
            '${DateTime.now().millisecondsSinceEpoch}:$amount';
    final result = await SupabaseService.spendCoins(
      amount,
      reason: reason,
      idempotencyKey: key,
    );
    if (!result.ok) {
      return CoinSpendResult(ok: false, error: result.error);
    }
    if (result.balance != null) {
      _setBalance(result.balance!);
    } else if (!result.adminFree) {
      _setBalance(balance.value - amount);
    }
    await _appendLocalHistory(
      CoinLedgerEntry(
        amountCoins: result.adminFree ? 0 : -amount,
        type: 'tjpro_spend',
        reason: result.adminFree ? '$reason (admin — free)' : reason,
        createdAt: DateTime.now(),
      ),
    );
    return CoinSpendResult(
      ok: true,
      balance: balance.value,
      adminFree: result.adminFree,
    );
  }

  Future<void> _addLocal(int amount, {required String reason}) async {
    _setBalance(balance.value + amount);
    await _appendLocalHistory(
      CoinLedgerEntry(
        amountCoins: amount,
        type: 'tjpro_reward',
        reason: reason,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // History
  // ------------------------------------------------------------------

  /// Recent earn/spend history for the coins screen. Prefers the
  /// server ledger (`tjpro-history`); falls back to the on-device
  /// history cache when offline / not deployed.
  Future<List<CoinLedgerEntry>> fetchHistory({int limit = 50}) async {
    final server = await SupabaseService.getHistory(limit: limit);
    if (server.isNotEmpty) {
      final entries = server
          .map(CoinLedgerEntry.fromServerJson)
          .where((e) => e != null)
          .cast<CoinLedgerEntry>()
          .toList();
      if (entries.isNotEmpty) {
        await _saveLocalHistory(entries);
        return entries;
      }
    }
    return _loadLocalHistory();
  }

  List<CoinLedgerEntry> _loadLocalHistory() {
    try {
      final raw = _prefs?.getString(_historyKey);
      if (raw == null || raw.isEmpty) return <CoinLedgerEntry>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CoinLedgerEntry>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CoinLedgerEntry.fromJson)
          .where((e) => e != null)
          .cast<CoinLedgerEntry>()
          .toList();
    } catch (_) {
      return <CoinLedgerEntry>[];
    }
  }

  Future<void> _saveLocalHistory(List<CoinLedgerEntry> entries) async {
    try {
      final trimmed = entries.take(50).toList();
      await _prefs?.setString(
        _historyKey,
        jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // History cache is best-effort.
    }
  }

  Future<void> _appendLocalHistory(CoinLedgerEntry entry) async {
    final current = _loadLocalHistory();
    await _saveLocalHistory(<CoinLedgerEntry>[entry, ...current]);
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

/// Priced News Studio features (DISCOVERY-AND-PLAN.md §15).
enum CoinFeature {
  oneClick,
  voiceover,
  export720p,
  export1080p,
  export4k,
  chromaKey,
  premiumTemplate,
  multiPlatformPublish,
  aiEnhance,
  autoCaptions,
}

/// Coin prices + ledger reason strings. Admins pay none of these —
/// the server waives the spend (see [CoinService.spend]).
class CoinCosts {
  static const int oneClick = 100;
  static const int voiceover = 50;
  static const int export720p = 50;
  static const int export1080p = 100;
  static const int export4k = 200;
  static const int chromaKey = 50;
  static const int premiumTemplate = 25;
  static const int multiPlatformPublish = 100;
  static const int aiEnhance = 50;
  static const int autoCaptions = 25;

  /// Ledger reason recorded for a rewarded-ad credit.
  static const String reasonAdReward = 'rewarded_ad';

  /// Ledger reason recorded for the daily free claim.
  static const String reasonDaily = 'daily_free';

  /// Ledger reason recorded for a Share & Earn referral credit
  /// (server ledger rows written by the claim RPC use the same
  /// reason family: type 'tjpro_referral').
  static const String reasonReferral = 'referral_reward';

  static int costFor(CoinFeature feature) {
    switch (feature) {
      case CoinFeature.oneClick:
        return oneClick;
      case CoinFeature.voiceover:
        return voiceover;
      case CoinFeature.export720p:
        return export720p;
      case CoinFeature.export1080p:
        return export1080p;
      case CoinFeature.export4k:
        return export4k;
      case CoinFeature.chromaKey:
        return chromaKey;
      case CoinFeature.premiumTemplate:
        return premiumTemplate;
      case CoinFeature.multiPlatformPublish:
        return multiPlatformPublish;
      case CoinFeature.aiEnhance:
        return aiEnhance;
      case CoinFeature.autoCaptions:
        return autoCaptions;
    }
  }

  /// Ledger reason string for a feature spend.
  static String reasonFor(CoinFeature feature) {
    switch (feature) {
      case CoinFeature.oneClick:
        return 'one_click_ai_news_maker';
      case CoinFeature.voiceover:
        return 'voiceover';
      case CoinFeature.export720p:
        return 'export_720p';
      case CoinFeature.export1080p:
        return 'export_1080p';
      case CoinFeature.export4k:
        return 'export_4k';
      case CoinFeature.chromaKey:
        return 'chroma_key';
      case CoinFeature.premiumTemplate:
        return 'premium_template';
      case CoinFeature.multiPlatformPublish:
        return 'multi_platform_publish';
      case CoinFeature.aiEnhance:
        return 'ai_enhance';
      case CoinFeature.autoCaptions:
        return 'auto_captions';
    }
  }

  /// Short user-facing label for a feature (cost badges).
  static String labelFor(CoinFeature feature) {
    switch (feature) {
      case CoinFeature.oneClick:
        return 'One Click AI News Maker';
      case CoinFeature.voiceover:
        return 'Voiceover';
      case CoinFeature.export720p:
        return 'Export 720p';
      case CoinFeature.export1080p:
        return 'Export 1080p';
      case CoinFeature.export4k:
        return 'Export 4K';
      case CoinFeature.chromaKey:
        return 'Chroma key';
      case CoinFeature.premiumTemplate:
        return 'Premium template';
      case CoinFeature.multiPlatformPublish:
        return 'Multi-platform publish';
      case CoinFeature.aiEnhance:
        return 'AI Enhance';
      case CoinFeature.autoCaptions:
        return 'Auto captions';
    }
  }
}

/// One earn/spend ledger entry (coins screen history).
class CoinLedgerEntry {
  const CoinLedgerEntry({
    required this.amountCoins,
    required this.type,
    required this.reason,
    required this.createdAt,
  });

  final int amountCoins;
  final String type;
  final String reason;
  final DateTime createdAt;

  bool get isEarn => amountCoins > 0;

  static CoinLedgerEntry? fromServerJson(Map<String, dynamic> json) {
    try {
      final amount = json['amount_coins'];
      final created = json['created_at'];
      if (amount is! int || created is! String) return null;
      return CoinLedgerEntry(
        amountCoins: amount,
        type: (json['type'] ?? '').toString(),
        reason: (json['ref_id'] ?? json['reason'] ?? '').toString(),
        createdAt: DateTime.parse(created),
      );
    } catch (_) {
      return null;
    }
  }

  static CoinLedgerEntry? fromJson(Map<String, dynamic> json) {
    try {
      final amount = json['amount_coins'];
      final created = json['created_at'];
      if (amount is! int || created is! String) return null;
      return CoinLedgerEntry(
        amountCoins: amount,
        type: (json['type'] ?? '').toString(),
        reason: (json['reason'] ?? '').toString(),
        createdAt: DateTime.parse(created),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'amount_coins': amountCoins,
      'type': type,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Outcome of [CoinService.spend] / [CoinService.spendAmount].
class CoinSpendResult {
  const CoinSpendResult({required this.ok, this.balance, this.error, this.adminFree = false});

  /// True when the spend succeeded (or was waived for an admin).
  final bool ok;

  /// Balance after the spend (null when unknown).
  final int? balance;

  /// Machine-readable failure reason when [ok] is false
  /// (`insufficient_balance`, `not_signed_in`, `network_error`, ...).
  final String? error;

  /// True when the server waived the spend because the user is an
  /// admin (no coins were debited).
  final bool adminFree;
}

/// Outcome of [CoinService.watchRewardedAd].
class CoinEarnResult {
  const CoinEarnResult({required this.ok, this.coins = 0, this.error});

  /// True when coins were credited.
  final bool ok;

  /// Coins credited (0 when [ok] is false).
  final int coins;

  /// User-facing failure message (null when [ok] is true).
  final String? error;
}
