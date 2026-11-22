import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';

/// All Supabase access for TJ Pro News Studio. Pattern copied from
/// Magic Box's SupabaseService (itself copied from TJ Earn): every
/// network call is bounded by a hard timeout so a stalled network
/// surfaces an error instead of hanging the UI.
///
/// SECURITY (same rule as Magic Box / TJ Earn): the app only ever
/// *reads* the balance and *asks* Edge Functions to change it. There
/// is deliberately no code here that writes coins to the ledger table
/// directly. Coin grants and spends happen only inside Edge Functions
/// (service role) — see supabase/functions/tjpro-*.
///
/// Auth: Google sign-in (see auth_service.dart) + email + password
/// login / register. Anonymous sign-in is NOT automatic: coins must
/// belong to a real account. Anonymous sessions exist ONLY as the
/// pre-link step — created just before a Google sign-in or an email
/// register, so the same user.id (and its guest coins) survives the
/// link. Enable BOTH "Anonymous sign-ins" AND "Enable Manual Linking"
/// in the Supabase dashboard (Auth -> Providers) or linking cannot
/// work. "Confirm email" is OFF in this project (verified for Magic
/// Box 15 Nov 2026), so email registration signs the user in at once.
///
/// ADMIN CHECK: [isAdmin] is the ONLY admin check and it is
/// server-side — the `tjpro-is-admin` Edge Function reads the logged
/// in user's email and compares it against the admin list that lives
/// in the function itself. The client NEVER decides admin status from
/// a local email list. [adminEmails] below exists ONLY so the login
/// screen can DISPLAY which accounts are admins; it grants nothing.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static bool _initialized = false;

  /// Admin emails — DISPLAY ONLY (login screen card). Access
  /// decisions are made server-side by the tjpro-* Edge Functions.
  /// Changing who is an admin means redeploying those functions.
  static const List<String> adminEmails = <String>[
    'mithubhattijani@gmail.com',
    'ghulamjillani019@gmail.com',
    'jaanirecords2@gmail.com',
  ];

  /// Current user, or null when Supabase never initialized / no
  /// session. Guarded: `Supabase.instance.client` throws before
  /// `Supabase.initialize()` has run, and the login gate must never
  /// crash on that (offline / unconfigured build).
  static User? get currentUser {
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// True when the current session belongs to a logged-in
  /// (non-anonymous) user.
  static bool get hasSignedInSession {
    final user = currentUser;
    return user != null && !user.isAnonymous;
  }

  /// True when the current session is an anonymous user (guest coins,
  /// or the pre-link step before Google sign-in / email register).
  static bool get hasAnonymousSession {
    final user = currentUser;
    return user != null && user.isAnonymous;
  }

  /// Bounded network guard (Magic Box / TJ Earn pattern): 25s default.
  static Future<T> _guard<T>(Future<T> Function() call,
      {int seconds = 25}) {
    return call().timeout(
      Duration(seconds: seconds),
      onTimeout: () => throw TimeoutException('Supabase request timed out'),
    );
  }

  static Future<FunctionResponse> _invoke(
    String functionName, {
    Map<String, dynamic>? body,
    HttpMethod method = HttpMethod.post,
  }) {
    return _guard(
      () => client.functions.invoke(
        functionName,
        body: body,
        method: method,
      ),
    );
  }

  /// Initialize Supabase ONLY — no session is created here. A
  /// persisted session is restored automatically by the SDK. Returns
  /// true when Supabase initialized. Never throws: false means
  /// local-only mode (coins stay on-device) and the login gate stays
  /// up. Requires a SUPABASE_ANON_KEY at build time (see
  /// [AppConfig.supabaseAnonKey]).
  static Future<bool> init() async {
    if (_initialized) return true;
    if (AppConfig.supabaseUrl.isEmpty ||
        AppConfig.supabaseAnonKey.isEmpty) {
      return false;
    }
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Supabase init timed out'),
      );
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True once [init] has run successfully this launch (Supabase SDK
  /// usable).
  static bool get isInitialized => _initialized;

  static bool get isReady => _initialized && currentUser != null;

  /// Create an anonymous session ONLY as the pre-link step before a
  /// Google sign-in / email register, or so a guest can earn coins
  /// before logging in. Returns true when an anonymous user now
  /// exists. Never throws.
  static Future<bool> ensureAnonymousSession() async {
    if (!_initialized) return false;
    try {
      final current = client.auth.currentUser;
      if (current != null) return current.isAnonymous;
      await client.auth.signInAnonymously().timeout(
            const Duration(seconds: 15),
          );
      return client.auth.currentUser?.isAnonymous == true;
    } catch (_) {
      return false;
    }
  }

  /// Link the Google identity (native ID token) onto the CURRENT user.
  /// The user keeps the same user.id — this is how a guest's coins
  /// survive the move to Google. Requires "Enable Manual Linking" in
  /// the Supabase dashboard. Throws [AuthException] when the identity
  /// is already linked to another user.
  static Future<AuthResponse> linkGoogleIdentity({
    required String idToken,
    String? accessToken,
  }) {
    return _guard(
      () => client.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      ),
    );
  }

  /// Sign in with a Google ID token (fresh Google-owned user, or the
  /// user that already owns this Google identity). Used when there is
  /// no anonymous user to link, or when linking reports the identity
  /// already belongs to another user.
  static Future<AuthResponse> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) {
    return _guard(
      () => client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      ),
    );
  }

  /// Email + password login. Signs into the existing email account.
  /// Throws [AuthException] on wrong credentials ("Invalid login
  /// credentials").
  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _guard(
      () => client.auth.signInWithPassword(
        email: email,
        password: password,
      ),
    );
  }

  /// Email + password register. Creates a fresh account — used only
  /// when there is NO session at all. When an anonymous user exists,
  /// [convertAnonymousToEmail] is the register path instead, so its
  /// coins survive. "Confirm email" is OFF in this project, so
  /// registration signs the user in at once. Throws [AuthException]
  /// when the email is already registered.
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _guard(
      () => client.auth.signUp(email: email, password: password),
    );
  }

  /// Convert the CURRENT anonymous user into a permanent email
  /// account (same user.id — guest coins survive). This is the
  /// register path when the app already has an anonymous session.
  /// Throws [AuthException] when the email is already registered to
  /// another user.
  static Future<UserResponse> convertAnonymousToEmail({
    required String email,
    required String password,
  }) {
    return _guard(
      () => client.auth.updateUser(
        UserAttributes(email: email, password: password),
      ),
    );
  }

  /// Send a password-reset email. Throws [AuthException] on failure.
  static Future<void> resetPasswordForEmail(String email) {
    return _guard(() => client.auth.resetPasswordForEmail(email));
  }

  /// Sign out of Supabase (clears the persisted session).
  static Future<void> signOut() async {
    try {
      await _guard(() => client.auth.signOut());
    } catch (_) {
      // Sign-out is best-effort; a failed call still leaves the local
      // session cleared by the SDK in most cases.
    }
  }

  // ------------------------------------------------------------------
  // Coin ledger — Edge Functions (server is the source of truth)
  // ------------------------------------------------------------------

  /// Server balance (SUM of the caller's ledger rows). Returns null
  /// when the function is not deployed / unreachable — the caller
  /// keeps the local balance.
  static Future<int?> getBalance() async {
    if (!isReady) return null;
    try {
      final res = await _invoke('tjpro-get-balance');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map && data['balance_coins'] is int) {
        return data['balance_coins'] as int;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Server-side admin check. Returns true ONLY when the
  /// `tjpro-is-admin` function says the logged-in user's email is an
  /// admin. Returns null when the function is unreachable — the caller
  /// must then treat the user as NOT admin (fail closed).
  static Future<bool?> checkIsAdmin() async {
    if (!isReady) return null;
    try {
      final res = await _invoke('tjpro-is-admin');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map && data['is_admin'] is bool) {
        return data['is_admin'] as bool;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Claim the daily 50 free coins (server-side, once per day).
  /// Returns the granted amount, or null when not available.
  static Future<int?> claimDailyCoins() async {
    if (!isReady) return null;
    try {
      final res = await _invoke('tjpro-daily-coins');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return data['coins'] as int? ?? 0;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Claim 50 coins for completing ONE Unity rewarded ad
  /// (server-side). Call ONLY after the ad completed fully. Returns
  /// the granted amount, or null when not available (e.g. daily cap
  /// of 20 ads reached — the function answers 409 then).
  static Future<int?> claimAdReward() async {
    if (!isReady) return null;
    try {
      final res = await _invoke('tjpro-claim-ad-reward');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return data['coins'] as int? ?? 0;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Claim Share & Earn referral rewards (server-side). Calls the
  /// `tjpro_claim_referral_rewards` Postgres RPC (security definer,
  /// see supabase-followups/referral-sql.sql): it atomically flips
  /// this user's qualified + unclaimed referral events to claimed
  /// and inserts the +100 ledger rows, so claim-once is enforced by
  /// the database, not the client. Returns the RPC's jsonb result
  /// ({ok, coins, count}), or null when the function does not exist
  /// yet / is unreachable — the caller (ReferralService) then falls
  /// back to a conditional table claim. Never throws.
  static Future<Map<String, dynamic>?> claimReferralRewardsRpc() async {
    if (!isReady) return null;
    try {
      final res = await _guard(
        () => client.rpc('tjpro_claim_referral_rewards'),
      );
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Spend coins (server-side validation). The server re-checks the
  /// ledger balance and only then inserts a negative entry; admins
  /// are exempt server-side (no debit, still `ok: true`). Returns the
  /// new server balance, or null when the spend was rejected
  /// (insufficient balance, function unreachable, ...). Pass a stable
  /// [idempotencyKey] per purchase so a retry never double-spends.
  static Future<SpendResult> spendCoins(
    int amount, {
    required String reason,
    String? idempotencyKey,
  }) async {
    if (!isReady) {
      return const SpendResult(ok: false, error: 'not_signed_in');
    }
    try {
      final Map<String, dynamic> body = <String, dynamic>{
        'amount_coins': amount,
        'reason': reason,
      };
      final String? key = idempotencyKey;
      if (key != null) body['idempotency_key'] = key;
      final res = await _invoke('tjpro-spend-coins', body: body);
      if (res.status != 200) {
        final data = res.data;
        final String error = data is Map && data['error'] is String
            ? data['error'] as String
            : 'server_error';
        return SpendResult(ok: false, error: error);
      }
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return SpendResult(
          ok: true,
          balance: data['balance'] as int?,
          adminFree: data['admin'] == true,
        );
      }
      return const SpendResult(ok: false, error: 'server_error');
    } catch (_) {
      return const SpendResult(ok: false, error: 'network_error');
    }
  }

  /// Recent ledger entries for the coins history screen. Returns an
  /// empty list when the function is not deployed / unreachable.
  static Future<List<Map<String, dynamic>>> getHistory({
    int limit = 50,
  }) async {
    if (!isReady) return <Map<String, dynamic>>[];
    try {
      final res = await _invoke('tjpro-history', body: {'limit': limit});
      if (res.status != 200) return <Map<String, dynamic>>[];
      final data = res.data;
      if (data is Map && data['entries'] is List) {
        return (data['entries'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}

/// Outcome of [SupabaseService.spendCoins].
class SpendResult {
  const SpendResult({required this.ok, this.balance, this.error, this.adminFree = false});

  /// True when the server accepted the spend (or waived it for an admin).
  final bool ok;

  /// New server balance after the spend (null when unknown).
  final int? balance;

  /// Machine-readable failure reason when [ok] is false
  /// (e.g. `insufficient_balance`, `not_signed_in`, `network_error`).
  final String? error;

  /// True when the spend was waived because the user is an admin
  /// (server-side decision — no coins were debited).
  final bool adminFree;
}
