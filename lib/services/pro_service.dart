/// TJ Pro PRO — paid subscription state (v1.4.0).
///
/// Pro is granted MANUALLY by the owner: the user pays via Easypaisa
/// / ABL (numbers come from [RemoteConfigService] so they can change
/// without a rebuild), sends the screenshot on WhatsApp, and the
/// owner inserts/updates a row in the Supabase table `tjpro_pro`
/// (user_id, pro_until, granted_by, source) from the dashboard —
/// see supabase-followups/pro-sql.sql. The app only ever READS its
/// own row (RLS: select-own only; no client writes exist).
///
/// FAIL-SOFT (the CoinService/SupabaseService pattern): Supabase not
/// initialized, not signed in, the table missing (SQL not run yet),
/// offline, or any error at all -> FREE MODE. Pro never blocks a
/// feature; it only RAISES limits via [limitFor] (the coin economy
/// is unchanged — premium tools still cost coins, Pro users just
/// get higher caps). The last server answer is cached in
/// shared_preferences so a returning Pro user is recognised offline;
/// the cache is keyed to the user id it belongs to, so an account
/// switch never leaks Pro across users.
///
/// Usage: `await ProService.instance.init()` once at startup (and
/// after sign-in), listen to [isPro] for badges, and gate caps with
/// `ProService.instance.limitFor(freeLimit, proLimit)`.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

class ProService {
  ProService._();

  /// Shared instance (the contract API).
  static final ProService instance = ProService._();

  /// Supabase table holding Pro grants (see pro-sql.sql).
  static const String table = 'tjpro_pro';

  static const String _untilKey = 'tjpro_pro_until_ms_v1';
  static const String _userKey = 'tjpro_pro_user_id_v1';

  /// True while the signed-in user's Pro grant is active. Updated by
  /// [init] / [refresh]; [proActive] is the always-current check
  /// (it re-tests the expiry against the clock on every read).
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  /// When the current Pro grant ends (null = no grant known).
  DateTime? proUntil;

  /// True when a grant exists and has not expired yet.
  bool get proActive {
    final DateTime? until = proUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// The cap a feature should use: [proLimit] for Pro users,
  /// [freeLimit] for everyone else.
  int limitFor(int freeLimit, int proLimit) =>
      proActive ? proLimit : freeLimit;

  /// Loads ONLY the cached grant from shared_preferences (no
  /// network). [init] runs this first and then refreshes from the
  /// server; main() also calls it BEFORE the ads SDK preloads its
  /// interstitial, so a returning Pro user is already recognised
  /// when the first preload decision is made (point #10: Pro = no
  /// ads). Never throws; any failure leaves free mode.
  Future<void> loadCachedGrant() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      final int ms = prefs.getInt(_untilKey) ?? 0;
      final String cachedUser = prefs.getString(_userKey) ?? '';
      final String? currentId = SupabaseService.currentUser?.id;
      // The cache only counts for the user it was cached under; a
      // signed-in different user starts from free until refreshed.
      if (ms > 0 && (currentId == null || cachedUser == currentId)) {
        proUntil = DateTime.fromMillisecondsSinceEpoch(ms);
      } else if (currentId != null && cachedUser != currentId) {
        proUntil = null;
      }
      _syncNotifier();
    } catch (_) {
      // Cache unreadable -> free mode until a refresh succeeds.
    }
  }

  /// Loads the cached grant, then refreshes from the server.
  /// Never throws; any failure leaves the cache (or free mode).
  Future<void> init() async {
    await loadCachedGrant();
    await refresh();
  }

  /// Re-reads the signed-in user's row from `tjpro_pro` and updates
  /// the state + cache. Absent table / no row / any error keeps the
  /// current state (fail-soft — a missing table means free mode for
  /// a user with no cached grant, and never a crash).
  Future<void> refresh() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final Map<String, dynamic>? row = await SupabaseService.client
          .from(table)
          .select('pro_until')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      DateTime? until;
      if (row != null) {
        final dynamic raw = row['pro_until'];
        if (raw is String) until = DateTime.tryParse(raw);
      }
      proUntil = until;
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setInt(_untilKey, until?.millisecondsSinceEpoch ?? 0);
      await prefs.setString(_userKey, user.id);
      _syncNotifier();
    } catch (_) {
      // Fail-soft: keep the cached state exactly as-is.
    }
  }

  void _syncNotifier() {
    final bool active = proActive;
    if (isPro.value != active) isPro.value = active;
  }
}
