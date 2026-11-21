import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import 'supabase_service.dart';

/// Login for TJ Pro News Studio (Magic Box pattern, v1).
///
/// Two ways in, same as Magic Box:
///  * Google — one tap, native sign-in, coins tied to the Google
///    account. When the current Supabase user is anonymous (guest
///    coins), the Google identity is LINKED onto that same user, so
///    the user.id and its coins survive.
///  * Email + password — Login for an existing account, Register for
///    a new one. Register attaches the email to the anonymous user
///    when one exists, so its coins survive; Login signs into the
///    email account's own coins.
///
/// Session persistence: the Supabase SDK restores the persisted
/// session automatically on launch (call [init] once at startup).
/// [authStateChanges] lets the app react to sign-in / sign-out.
///
/// ADMIN STATUS: [isAdmin] is a [ValueNotifier] fed ONLY by the
/// server — [refreshAdminStatus] calls the `tjpro-is-admin` Edge
/// Function. It starts false and stays false when the server cannot
/// be reached (fail closed). The client NEVER decides admin status
/// from an email list; [SupabaseService.adminEmails] is display-only.
/// The coin bypass is enforced server-side in the tjpro-* functions,
/// so a modded client cannot grant itself free features by flipping
/// this flag.
class AuthService {
  static bool _googleInitialized = false;

  /// Admin status from the SERVER (`tjpro-is-admin`). False until a
  /// successful server check says otherwise. UI may hide the Watch
  /// Ads button when this is true — but the coin bypass lives
  /// server-side, never here.
  static final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);

  /// True once the Web OAuth client ID has been supplied (see
  /// [AppConfig.googleServerClientId]). False until the TJ Pro Google
  /// Cloud OAuth client exists and the value is pasted in.
  static bool get isGoogleConfigured =>
      AppConfig.googleServerClientId.isNotEmpty &&
      AppConfig.googleServerClientId !=
          'REPLACE_ME_GOOGLE_WEB_CLIENT_ID';

  /// Current Supabase user (null when signed out / never initialized).
  static User? get currentUser => SupabaseService.currentUser;

  /// Email of the signed-in user, or null for guests / signed out.
  static String? get currentEmail => currentUser?.email;

  /// True when a real (non-anonymous) session exists.
  static bool get isSignedIn => SupabaseService.hasSignedInSession;

  /// True when the session is an anonymous guest (coins earned before
  /// login live here until the account is linked).
  static bool get isGuest => SupabaseService.hasAnonymousSession;

  /// Supabase auth state stream (sign-in / sign-out / token refresh).
  /// Guarded: returns an empty stream before Supabase initializes.
  static Stream<AuthState> get authStateChanges {
    try {
      return SupabaseService.client.auth.onAuthStateChange;
    } catch (_) {
      return const Stream<AuthState>.empty();
    }
  }

  /// One-time setup at app startup: initialize Supabase (restores the
  /// persisted session) and pre-warm Google sign-in. Never throws.
  /// Returns true when Supabase initialized.
  static Future<bool> init() async {
    final ok = await SupabaseService.init();
    if (ok && currentUser != null) {
      unawaited(refreshAdminStatus());
    }
    if (isGoogleConfigured) {
      unawaited(_ensureGoogleInitialized());
    }
    return ok;
  }

  /// Refresh [isAdmin] from the server. Returns the server answer.
  /// Never throws; on any failure the flag stays false (fail closed).
  static Future<bool> refreshAdminStatus() async {
    try {
      final admin = await SupabaseService.checkIsAdmin();
      isAdmin.value = admin == true;
      return isAdmin.value;
    } catch (_) {
      isAdmin.value = false;
      return false;
    }
  }

  /// Create an anonymous guest session so the user can earn coins
  /// before logging in. The guest user.id is preserved when the user
  /// later signs in with Google or registers with email (linking).
  /// Returns true when a guest session now exists. Never throws.
  static Future<bool> ensureGuestSession() async {
    if (!SupabaseService.isInitialized) {
      await SupabaseService.init();
    }
    return SupabaseService.ensureAnonymousSession();
  }

  /// Sign out of Supabase (and Google, best-effort). Clears [isAdmin].
  /// Never throws.
  static Future<void> signOut() async {
    isAdmin.value = false;
    try {
      await SupabaseService.signOut();
    } catch (_) {
      // Best-effort; the local session is cleared by the SDK anyway.
    }
    try {
      if (_googleInitialized) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {
      // Google sign-out is best-effort.
    }
  }

  /// Send a password-reset email. Never throws; the result carries a
  /// user-facing error message on failure.
  static Future<AuthResult> resetPassword({required String email}) async {
    if (!isValidEmail(email)) {
      return const AuthResult(
        ok: false,
        error: 'Please enter a valid email address.',
      );
    }
    if (!SupabaseService.isInitialized) {
      await SupabaseService.init();
    }
    try {
      await SupabaseService.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      return AuthResult(ok: false, error: _friendlyError(e.message));
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        error: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      return AuthResult(
        ok: false,
        error: 'Could not send the reset email ($e). Please try again.',
      );
    }
    return const AuthResult(ok: true);
  }

  /// Login with an existing email account. Never throws; the result
  /// carries a user-facing error message on failure.
  static Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!SupabaseService.isInitialized) {
      await SupabaseService.init();
    }
    try {
      await SupabaseService.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      return AuthResult(ok: false, error: _friendlyError(e.message));
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        error: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      return AuthResult(
        ok: false,
        error: 'Could not sign in ($e). Please try again.',
      );
    }
    final user = SupabaseService.currentUser;
    if (user == null || user.isAnonymous) {
      return const AuthResult(
        ok: false,
        error: 'Sign-in did not create a session. Please try again.',
      );
    }
    unawaited(refreshAdminStatus());
    return const AuthResult(ok: true);
  }

  /// Register a new email account. Never throws; the result carries a
  /// user-facing error message on failure.
  ///
  /// When the current Supabase user is anonymous, the email is
  /// attached to THAT user, so the same user.id (and guest coins)
  /// survives. When the email is already registered, the flow falls
  /// back to signing into that account with the given password — so
  /// a returning user who taps Register by mistake still gets in.
  static Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
  }) async {
    if (!SupabaseService.isInitialized) {
      await SupabaseService.init();
    }

    final current = SupabaseService.currentUser;

    // Anonymous user present: attach the email to THAT user so its
    // user.id (and coins) survives.
    if (current != null && current.isAnonymous) {
      try {
        await SupabaseService.convertAnonymousToEmail(
          email: email.trim(),
          password: password,
        );
      } on AuthException catch (e) {
        if (_isAlreadyRegistered(e.message)) {
          return signInWithEmail(email: email, password: password);
        }
        return AuthResult(ok: false, error: _friendlyError(e.message));
      } on TimeoutException {
        return const AuthResult(
          ok: false,
          error: 'Request timed out. Check your connection and try again.',
        );
      } catch (e) {
        return AuthResult(
          ok: false,
          error: 'Could not register ($e). Please try again.',
        );
      }
      final user = SupabaseService.currentUser;
      if (user == null || user.isAnonymous) {
        return const AuthResult(
          ok: false,
          error: 'Registration did not complete. Please try again.',
        );
      }
      unawaited(refreshAdminStatus());
      return const AuthResult(ok: true, registeredNew: true);
    }

    // No session at all: create the account directly.
    try {
      await SupabaseService.signUpWithEmail(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      if (_isAlreadyRegistered(e.message)) {
        return signInWithEmail(email: email, password: password);
      }
      return AuthResult(ok: false, error: _friendlyError(e.message));
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        error: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      return AuthResult(
        ok: false,
        error: 'Could not register ($e). Please try again.',
      );
    }
    final user = SupabaseService.currentUser;
    if (user == null || user.isAnonymous) {
      // signUp returned no session (e.g. the email was already
      // registered but GoTrue masked it): try signing in with the
      // same credentials instead of leaving the user stuck.
      return signInWithEmail(email: email, password: password);
    }
    unawaited(refreshAdminStatus());
    return const AuthResult(ok: true, registeredNew: true);
  }

  // ------------------------------------------------------------------
  // Google sign-in (native flow, Magic Box pattern)
  // ------------------------------------------------------------------

  /// One-time GoogleSignIn setup + silent restore of a previous Google
  /// account. Best-effort, never throws: false means Google sign-in is
  /// unavailable right now (not configured, or no Play Services).
  static Future<bool> _ensureGoogleInitialized() async {
    if (_googleInitialized) return true;
    if (!isGoogleConfigured) return false;
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleInitialized = true;
      try {
        final pending =
            GoogleSignIn.instance.attemptLightweightAuthentication();
        if (pending != null) {
          await pending.timeout(const Duration(seconds: 10));
        }
      } catch (_) {
        // No previous Google account (or offline) — the sign-in
        // button still works.
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Full interactive Google sign-in (called from the login button, so
  /// it runs inside a user gesture). Never throws; the result carries
  /// a user-facing error message on failure. On failure the caller
  /// stays on the login screen — never a crash, never a silent
  /// fallback to anonymous for coins.
  static Future<AuthResult> signInWithGoogle() async {
    if (!isGoogleConfigured) {
      return const AuthResult(
        ok: false,
        error:
            'Google sign-in is not set up yet. Please update the app when a new version is available.',
      );
    }
    if (!await _ensureGoogleInitialized()) {
      return const AuthResult(
        ok: false,
        error:
            'Could not start Google sign-in. Check your connection and that Google Play Services is available, then try again.',
      );
    }

    // A first launch that started offline never initialized Supabase:
    // retry now that the user is interacting (and likely online).
    if (!SupabaseService.isInitialized) {
      await SupabaseService.init();
    }

    GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate().timeout(
            const Duration(seconds: 120),
          );
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        error: 'Google sign-in timed out. Please try again.',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('canceled') || msg.contains('cancelled')) {
        return const AuthResult(
          ok: false,
          error:
              'Sign-in was cancelled. Tap "Continue with Google" to try again.',
        );
      }
      return AuthResult(
        ok: false,
        error: 'Google sign-in failed ($e). Please try again.',
      );
    }

    String? idToken;
    try {
      // In google_sign_in 7.x, account.authentication is a synchronous
      // getter (not a Future), so no await here.
      final googleAuth = account.authentication;
      idToken = googleAuth.idToken;
    } catch (_) {
      idToken = null;
    }
    if (idToken == null || idToken.isEmpty) {
      return const AuthResult(
        ok: false,
        error:
            'Google did not return an ID token. The app\'s Google setup is incomplete — please try again later.',
      );
    }

    // Access token (email scope): optional for signInWithIdToken /
    // linkIdentityWithIdToken, so a failure here is non-fatal — the
    // ID token alone is enough to sign in.
    final String? accessToken = await _fetchAccessToken(account);

    final current = SupabaseService.currentUser;

    // Already signed in (e.g. restored session): nothing to do.
    if (current != null && !current.isAnonymous) {
      unawaited(refreshAdminStatus());
      return const AuthResult(ok: true);
    }

    // Anonymous user present: link Google onto the SAME user so
    // user.id + guest coins live on.
    if (current != null && current.isAnonymous) {
      final linked = await _tryLink(idToken, accessToken);
      if (linked.ok) {
        unawaited(refreshAdminStatus());
        return const AuthResult(ok: true, linkedExisting: true);
      }
      if (linked.alreadyLinkedElsewhere) {
        // This Google account already owns a Supabase user: sign into
        // THAT user (its coins) instead of the anonymous one.
        return _signInWithIdToken(idToken, accessToken);
      }
      return AuthResult(ok: false, error: linked.error);
    }

    // No Supabase user at all: create the anonymous session first,
    // then link — same UID either way. If anonymous creation fails
    // (offline / not enabled), fall through to a plain Google sign-in
    // so the user is not blocked.
    final anonReady = await SupabaseService.ensureAnonymousSession();
    if (anonReady) {
      final linked = await _tryLink(idToken, accessToken);
      if (linked.ok) {
        unawaited(refreshAdminStatus());
        return const AuthResult(ok: true, linkedExisting: true);
      }
      if (linked.alreadyLinkedElsewhere) {
        return _signInWithIdToken(idToken, accessToken);
      }
      return AuthResult(ok: false, error: linked.error);
    }
    return _signInWithIdToken(idToken, accessToken);
  }

  /// Plain Google sign-in (new Google-owned user). Returns ok only
  /// when the resulting Supabase user is non-anonymous.
  static Future<AuthResult> _signInWithIdToken(
    String idToken,
    String? accessToken,
  ) async {
    try {
      await SupabaseService.signInWithGoogleIdToken(
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      return AuthResult(
        ok: false,
        error: 'Could not sign in with Google ($e). Please try again.',
      );
    }
    final user = SupabaseService.currentUser;
    if (user == null || user.isAnonymous) {
      return const AuthResult(
        ok: false,
        error: 'Google sign-in did not create a session. Please try again.',
      );
    }
    unawaited(refreshAdminStatus());
    return const AuthResult(ok: true, freshGoogleUser: true);
  }

  /// Link the Google identity onto the current (anonymous) user.
  static Future<_LinkResult> _tryLink(
    String idToken,
    String? accessToken,
  ) async {
    try {
      await SupabaseService.linkGoogleIdentity(
        idToken: idToken,
        accessToken: accessToken,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      // Supabase reports an already-registered email as "A user with
      // this email address has already been registered" — that is the
      // same already-linked-elsewhere case: the Google account already
      // owns a Supabase user, so fall back to signing into that user.
      if (msg.contains('already') &&
          (msg.contains('link') || msg.contains('register'))) {
        return const _LinkResult(
          ok: false,
          alreadyLinkedElsewhere: true,
        );
      }
      return _LinkResult(
        ok: false,
        error:
            'Could not link your Google account to this app account (${e.message}). '
            'Your coins are safe on this device — please try again later.',
      );
    } catch (e) {
      return _LinkResult(
        ok: false,
        error: 'Could not link your Google account ($e). Please try again.',
      );
    }
    final user = SupabaseService.currentUser;
    if (user == null || user.isAnonymous) {
      return const _LinkResult(
        ok: false,
        error:
            'Linking did not complete. Your coins are safe on this device — please try again.',
      );
    }
    return const _LinkResult(ok: true);
  }

  /// Best-effort access token for the `email` scope. Returns null on
  /// any failure — the ID token alone is enough to sign in.
  static Future<String?> _fetchAccessToken(
    GoogleSignInAccount account,
  ) async {
    try {
      const scopes = ['email'];
      final existing = await account.authorizationClient
          .authorizationForScopes(scopes)
          .timeout(const Duration(seconds: 15));
      if (existing != null) return existing.accessToken;
      final fresh = await account.authorizationClient
          .authorizeScopes(scopes)
          .timeout(const Duration(seconds: 60));
      return fresh.accessToken;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Minimal email shape check (used by the login screen before any
  /// network call, and by unit tests). Not a substitute for the
  /// server's own validation.
  static bool isValidEmail(String email) {
    final String value = email.trim();
    if (value.isEmpty || value.contains(' ')) return false;
    final int at = value.indexOf('@');
    if (at <= 0 || at != value.lastIndexOf('@')) return false;
    final String domain = value.substring(at + 1);
    return domain.contains('.') && !domain.startsWith('.');
  }

  static bool _isAlreadyRegistered(String message) {
    final msg = message.toLowerCase();
    return msg.contains('already') &&
        (msg.contains('register') || msg.contains('exists'));
  }

  static String _friendlyError(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password')) {
      return 'Wrong email or password. Please try again.';
    }
    if (msg.contains('password') &&
        (msg.contains('short') ||
            msg.contains('at least 6') ||
            msg.contains('characters'))) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('invalid') && msg.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('already') && msg.contains('register')) {
      return 'This email is already registered. Try logging in instead.';
    }
    if (msg.contains('too many') || msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a bit and try again.';
    }
    return 'Could not complete this ($message). Please try again.';
  }
}

/// Outcome of an [AuthService] sign-in / register / reset call.
class AuthResult {
  const AuthResult({
    required this.ok,
    this.error,
    this.linkedExisting = false,
    this.freshGoogleUser = false,
    this.registeredNew = false,
  });

  /// True when a non-anonymous Supabase session now exists.
  final bool ok;

  /// User-facing failure message (null when [ok] is true).
  final String? error;

  /// True when an existing anonymous user.id (and its guest coins)
  /// was preserved by linking Google / attaching email onto it.
  final bool linkedExisting;

  /// True when the session belongs to a Google-owned user created /
  /// signed into directly (no anonymous user was linked).
  final bool freshGoogleUser;

  /// True when a brand-new email account was just registered (as
  /// opposed to signing into an existing one).
  final bool registeredNew;
}

class _LinkResult {
  const _LinkResult({
    required this.ok,
    this.error,
    this.alreadyLinkedElsewhere = false,
  });

  final bool ok;
  final String? error;
  final bool alreadyLinkedElsewhere;
}
