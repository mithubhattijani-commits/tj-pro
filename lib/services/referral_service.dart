import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'coin_service.dart';
import 'supabase_service.dart';
import 'unity_ads_service.dart';

/// Share & Earn — referral system (user spec, 22 Nov 2026).
///
/// Mechanics (exact):
/// - Every user gets a persistent referral code, registered
///   server-side in `tjpro_referral_codes` against their Supabase
///   user.id. Because a guest's anonymous id SURVIVES Google/email
///   linking (see [AuthService]), a code earned as a guest stays the
///   same code after login.
/// - The share link carries the code INSIDE it:
///   `https://nigraantv.xyz/apps/tj-pro?ref=<CODE>` — the new user
///   enters NOTHING manually.
/// - Capture channels (no manual entry), in the order tried:
///   (a) deep link — the `tj_pro/referral` MethodChannel fed by
///       MainActivity (launch intent + onNewIntent): the https App
///       Link and the `tjpro://ref/<CODE>` scheme, both declared in
///       AndroidManifest.xml;
///   (b) clipboard — read ONCE, on the very first launch only, when
///       it contains a ref link/code (the share text a friend pasted
///       into a browser lands here when they copy it before install);
///   (c) Play Install Referrer — READY TO ADD, not wired: the Dart
///       side already calls `getInstallReferrer` on the channel and
///       treats notImplemented as "no referrer"; the native snippet
///       + gradle line live in the v1.3.0 completion report and in
///       MainActivity.kt's referral-channel comment.
///   A manual code field exists ONLY as a last-resort fallback in
///   the Share & Earn screen.
/// - Attribution: first captured code wins. On first sync the code is
///   resolved to its owner and ONE row is inserted in
///   `tjpro_referral_events` (unique on referred_user_id — one event
///   per new user, ever). Self-referral is rejected (owner == me).
/// - Qualification: the event flips to 'qualified' server-side when
///   BOTH are true for the referred user — they are LOGGED IN (a
///   non-anonymous session; the app has real Google/email login but
///   no hard gate, so a guest who watches the ad first qualifies the
///   moment they later sign in) AND they watched their FIRST ad
///   (hooked via [UnityAdsService.onAdCompleted]: a completed
///   rewarded ad or a shown interstitial).
/// - Payout: the REFERRER's app, on open, claims via the
///   `tjpro_claim_referral_rewards` RPC (see
///   supabase-followups/referral-sql.sql): it atomically flips
///   qualified+unclaimed events to claimed and writes +100 ledger
///   rows per event (type 'tjpro_referral'), so claim-once is
///   enforced server-side and the normal server-balance sync keeps
///   the coins. [CoinService.creditReferralReward] mirrors the
///   credit locally for instant UI. If the RPC is missing (SQL only
///   partially applied) the service falls back to a conditional
///   table update (claimed flip guarded by `claimed = false`) +
///   local credit.
///
/// FAIL-SOFT everywhere: every entry point is wrapped; offline, a
/// missing table, or an unconfigured build leaves the feature
/// quietly inactive and never touches startup, ads, or coin flows.
/// Requires supabase-followups/referral-sql.sql to have been run —
/// until then all server calls fail soft and nothing breaks.
class ReferralService {
  ReferralService._();

  /// Shared instance.
  static final ReferralService instance = ReferralService._();

  /// Coins the sharer receives per qualified new user.
  static const int rewardCoins = 100;

  /// Base of the share link; the code rides in `?ref=`.
  static const String shareBaseUrl = 'https://nigraantv.xyz/apps/tj-pro';

  static const String _kCode = 'tjpro_ref_code';
  static const String _kPending = 'tjpro_ref_pending_code';
  static const String _kRegisteredUid = 'tjpro_ref_registered_uid';
  static const String _kFirstAd = 'tjpro_ref_first_ad_watched';
  static const String _kClipboardChecked = 'tjpro_ref_clipboard_checked';

  static const MethodChannel _channel = MethodChannel('tj_pro/referral');

  static const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int _codeLength = 8;

  /// My referral code (null until generated/registered).
  final ValueNotifier<String?> myCode = ValueNotifier<String?>(null);

  /// People who joined through my link (server count).
  final ValueNotifier<int> joinedCount = ValueNotifier<int>(0);

  /// Referral coins already claimed by me (server count × 100).
  final ValueNotifier<int> earnedCoins = ValueNotifier<int>(0);

  /// Qualified referrals waiting to be claimed by me.
  final ValueNotifier<int> pendingClaimCount = ValueNotifier<int>(0);

  bool _inited = false;
  bool _syncing = false;
  SharedPreferences? _prefs;

  /// My share link (bare base URL until a code exists).
  String get shareLink {
    final code = myCode.value;
    return code == null ? shareBaseUrl : '$shareBaseUrl?ref=$code';
  }

  /// Share-sheet text: download link + the ref link (same URL — the
  /// code rides inside it).
  String get shareText =>
      'TJ Pro — free photo & video editor! Download from my link '
      'and do all the editing right in the app:\n$shareLink';

  /// True when this install was attributed to someone's code.
  bool get isAttributed =>
      _prefs?.getString(_kRegisteredUid) != null ||
      _prefs?.getString(_kPending) != null;

  /// True once this user has watched their first ad.
  bool get firstAdWatched => _prefs?.getBool(_kFirstAd) == true;

  // ------------------------------------------------------------------
  // Code parsing
  // ------------------------------------------------------------------

  /// Extract a referral code from ANY of the shapes it can arrive
  /// in: a full share link (`...?ref=CODE`), a `tjpro://ref/CODE`
  /// link, a Play referrer string (`ref=CODE&utm_...`), the whole
  /// share message pasted into the clipboard, or a bare code.
  /// Returns the normalized (uppercase) code, or null.
  static String? parseRefCode(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final embedded = RegExp(
      r'(?:ref=|tjpro://ref/)([A-Za-z0-9]{6,10})',
      caseSensitive: false,
    ).firstMatch(text);
    if (embedded != null) return embedded.group(1)!.toUpperCase();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme == 'tjpro' && uri.host == 'ref' &&
        uri.pathSegments.isNotEmpty) {
      final seg = uri.pathSegments.first.trim().toUpperCase();
      if (RegExp(r'^[A-Z0-9]{6,10}$').hasMatch(seg)) return seg;
    }
    final bare = text.toUpperCase();
    if (RegExp(r'^[A-Z0-9]{6,10}$').hasMatch(bare)) return bare;
    return null;
  }

  static String _generateCode() {
    final rnd = Random.secure();
    return List.generate(
      _codeLength,
      (_) => _codeAlphabet[rnd.nextInt(_codeAlphabet.length)],
    ).join();
  }

  // ------------------------------------------------------------------
  // Startup / capture
  // ------------------------------------------------------------------

  /// One-time startup wiring. Called (unawaited) from main() AFTER
  /// AuthService.init + CoinService.load. Never throws.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      myCode.value = _prefs!.getString(_kCode);

      // (a) Deep links: links that arrive while the app runs are
      // pushed by MainActivity; the launch link is pulled once.
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onLink') {
          captureFromText(call.arguments?.toString());
        }
        return null;
      });
      captureFromText(await _invokeChannel('getInitialLink'));
      // (c) Play Install Referrer: not implemented natively yet —
      // the call simply returns null until it is added.
      captureFromText(await _invokeChannel('getInstallReferrer'));
      // (b) Clipboard: first launch only.
      await _clipboardFallback();

      // First-ad hook (rewarded completion / shown interstitial).
      UnityAdsService.onAdCompleted = () {
        unawaited(noteAdWatched());
      };
      // Login (or any auth change) re-runs the sync: a guest who
      // watched the ad first qualifies the moment they sign in.
      AuthService.authStateChanges.listen(
        (_) => unawaited(syncWithServer()),
        onError: (_) {},
      );
      unawaited(syncWithServer());
    } catch (_) {
      // Referral must never break startup.
    }
  }

  Future<String?> _invokeChannel(String method) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } catch (_) {
      // MissingPluginException (method not implemented natively —
      // e.g. getInstallReferrer) or a dead channel: no link.
      return null;
    }
  }

  Future<void> _clipboardFallback() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (_prefs!.getBool(_kClipboardChecked) == true) return;
      // Mark FIRST so a crash mid-read never makes us read twice.
      await _prefs!.setBool(_kClipboardChecked, true);
      if (_prefs!.getString(_kPending) != null ||
          _prefs!.getString(_kRegisteredUid) != null) {
        return;
      }
      final data = await Clipboard.getData('text/plain');
      captureFromText(data?.text);
    } catch (_) {
      // Clipboard unavailable (background read limits): skip.
    }
  }

  /// Capture a referral code out of any text (link, referrer string,
  /// clipboard content). First captured code wins; my own code and
  /// post-attribution captures are ignored.
  void captureFromText(String? raw) {
    try {
      final code = parseRefCode(raw);
      if (code == null) return;
      unawaited(_capture(code));
    } catch (_) {}
  }

  Future<void> _capture(String code) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (code == myCode.value || code == _prefs!.getString(_kCode)) {
        return; // Self-referral never counts.
      }
      if (_prefs!.getString(_kPending) != null) return; // First wins.
      if (_prefs!.getString(_kRegisteredUid) != null) return;
      await _prefs!.setString(_kPending, code);
      unawaited(syncWithServer());
    } catch (_) {}
  }

  /// Last-resort manual entry (Share & Earn screen only). Accepts
  /// the code only when nothing was captured automatically.
  /// Returns true when the code was accepted as pending.
  Future<bool> applyManualCode(String raw) async {
    final code = parseRefCode(raw);
    if (code == null) return false;
    _prefs ??= await SharedPreferences.getInstance();
    if (_prefs!.getString(_kPending) != null ||
        _prefs!.getString(_kRegisteredUid) != null) {
      return false;
    }
    await _capture(code);
    await syncWithServer();
    return _prefs!.getString(_kPending) == code ||
        _prefs!.getString(_kRegisteredUid) != null;
  }

  // ------------------------------------------------------------------
  // Server sync: code, attribution, qualification, claim, stats
  // ------------------------------------------------------------------

  /// The workhorse, run at startup, on auth changes, and after a
  /// capture / first ad. Serialized; fail-soft.
  Future<void> syncWithServer() async {
    if (_syncing) return;
    _syncing = true;
    try {
      if (!SupabaseService.isInitialized) await SupabaseService.init();
      if (!SupabaseService.isInitialized) return;
      await AuthService.ensureGuestSession();
      final uid = SupabaseService.currentUser?.id;
      if (uid == null) return;
      await ensureMyCode();
      await _registerPendingEvent(uid);
      await _maybeQualify(uid);
      await claimRewards();
      await refreshStats(uid);
    } catch (_) {
      // Offline / tables not created yet: stay quietly inactive.
    } finally {
      _syncing = false;
    }
  }

  /// My persistent referral code — the server's row wins; created on
  /// first need. Offline, a locally generated code is returned (it
  /// is reconciled with the server on the next successful sync).
  Future<String?> ensureMyCode() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final saved = _prefs!.getString(_kCode);
      if (saved != null) myCode.value = saved;
      final uid = SupabaseService.currentUser?.id;
      if (!SupabaseService.isInitialized || uid == null) {
        if (saved != null) return saved;
        final local = _generateCode();
        await _saveCode(local);
        return local;
      }
      final serverCode = await _codeForUser(uid);
      if (serverCode != null) {
        await _saveCode(serverCode);
        return serverCode;
      }
      // No row yet: register (the saved local code first, so a code
      // already shared from an offline session stays valid).
      for (var attempt = 0; attempt < 5; attempt++) {
        final candidate =
            (attempt == 0 && saved != null) ? saved : _generateCode();
        try {
          await SupabaseService.client
              .from('tjpro_referral_codes')
              .insert({'code': candidate, 'user_id': uid});
          await _saveCode(candidate);
          return candidate;
        } on PostgrestException catch (e) {
          if (e.code != '23505') return saved; // Not a conflict: soft.
          final raced = await _codeForUser(uid);
          if (raced != null) {
            await _saveCode(raced);
            return raced;
          }
          // Candidate code taken by someone else: loop regenerates.
        }
      }
      return saved;
    } catch (_) {
      return myCode.value;
    }
  }

  Future<String?> _codeForUser(String uid) async {
    final rows = await SupabaseService.client
        .from('tjpro_referral_codes')
        .select('code')
        .eq('user_id', uid)
        .limit(1);
    if (rows.isEmpty) return null;
    final code = rows.first['code'];
    return code is String ? code : null;
  }

  Future<void> _saveCode(String code) async {
    myCode.value = code;
    await _prefs?.setString(_kCode, code);
  }

  /// Turn the captured pending code into the ONE server event for
  /// this user. Runs once per identity (the guest id survives
  /// linking, so this stays valid after login).
  Future<void> _registerPendingEvent(String uid) async {
    final pending = _prefs!.getString(_kPending);
    if (pending == null) return;
    if (_prefs!.getString(_kRegisteredUid) == uid) return;
    final rows = await SupabaseService.client
        .from('tjpro_referral_codes')
        .select('user_id')
        .eq('code', pending)
        .limit(1);
    if (rows.isEmpty) {
      // Unknown code — it can never resolve; drop it.
      await _prefs!.remove(_kPending);
      return;
    }
    final owner = rows.first['user_id'];
    if (owner is! String || owner == uid) {
      // Self-referral (or a malformed row): rejected.
      await _prefs!.remove(_kPending);
      return;
    }
    try {
      await SupabaseService.client.from('tjpro_referral_events').insert({
        'referrer_user_id': owner,
        'referrer_code': pending,
        'referred_user_id': uid,
        'status': 'pending',
      });
    } on PostgrestException catch (e) {
      // 23505 = an event already exists for this referred user
      // (unique constraint) — that IS the registered state.
      if (e.code != '23505') return;
    }
    await _prefs!.setString(_kRegisteredUid, uid);
  }

  /// Record that this user watched their first ad (persisted), then
  /// try to qualify. Called from the Unity ads completion hook.
  Future<void> noteAdWatched() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_kFirstAd, true);
      unawaited(syncWithServer());
    } catch (_) {}
  }

  /// Flip my event to 'qualified' once BOTH conditions hold:
  /// logged in (non-anonymous) AND first ad watched.
  Future<void> _maybeQualify(String uid) async {
    if (_prefs!.getBool(_kFirstAd) != true) return;
    if (!AuthService.isSignedIn) return; // Waits for login.
    if (_prefs!.getString(_kRegisteredUid) != uid) return;
    await SupabaseService.client
        .from('tjpro_referral_events')
        .update({
          'status': 'qualified',
          'qualified_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('referred_user_id', uid)
        .eq('status', 'pending');
  }

  /// Claim every qualified, unclaimed referral reward for MY code.
  /// Returns the coins credited (0 when none). Primary path: the
  /// `tjpro_claim_referral_rewards` RPC (atomic claim + ledger
  /// insert server-side; the balance sync then keeps the coins).
  /// Fallback (RPC missing): conditional table claim + local credit.
  Future<int> claimRewards() async {
    try {
      if (!SupabaseService.isInitialized) return 0;
      final uid = SupabaseService.currentUser?.id;
      if (uid == null) return 0;
      final rpc = await SupabaseService.claimReferralRewardsRpc();
      if (rpc != null) {
        final coins = (rpc['coins'] as num?)?.toInt() ?? 0;
        if (coins > 0) {
          await CoinService.instance.creditReferralReward(coins);
          // The RPC wrote real ledger rows, so the server SUM now
          // includes them — reconcile to the server truth.
          unawaited(CoinService.instance.syncFromServer());
          await refreshStats(uid);
        }
        return coins;
      }
      // Fallback: claim-once via the conditional update (the update
      // only matches rows still unclaimed, so two devices racing
      // cannot both credit the same event).
      final rows = await SupabaseService.client
          .from('tjpro_referral_events')
          .select('id')
          .eq('referrer_user_id', uid)
          .eq('status', 'qualified')
          .eq('claimed', false);
      var credited = 0;
      for (final row in rows) {
        final updated = await SupabaseService.client
            .from('tjpro_referral_events')
            .update({
              'claimed': true,
              'claimed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', row['id'] as Object)
            .eq('claimed', false)
            .select('id');
        if (updated.isNotEmpty) credited += rewardCoins;
      }
      if (credited > 0) {
        await CoinService.instance.creditReferralReward(credited);
        await refreshStats(uid);
      }
      return credited;
    } catch (_) {
      return 0;
    }
  }

  /// Refresh joined / earned / pending counts for the Share screen.
  Future<void> refreshStats([String? uidArg]) async {
    try {
      if (!SupabaseService.isInitialized) return;
      final uid = uidArg ?? SupabaseService.currentUser?.id;
      if (uid == null) return;
      final rows = await SupabaseService.client
          .from('tjpro_referral_events')
          .select('status, claimed')
          .eq('referrer_user_id', uid);
      joinedCount.value = rows.length;
      earnedCoins.value =
          rows.where((r) => r['claimed'] == true).length * rewardCoins;
      pendingClaimCount.value = rows
          .where((r) => r['status'] == 'qualified' && r['claimed'] != true)
          .length;
    } catch (_) {
      // Stats are display-only: keep the last values.
    }
  }
}
