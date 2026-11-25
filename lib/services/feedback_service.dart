/// Build 9 (v1.7.0, fix-list point #5) — "REPORT BHEJO" backend.
///
/// One small service behind the feedback screen
/// (lib/news/feedback_screen.dart): sends the user's message —
/// which may be EMPTY, the report still goes — plus the latest
/// on-device diagnostics to the Supabase table `tjpro_feedback`
/// (created by supabase-followups/build9-sql.sql).
///
/// Fail-soft by design: when the send fails (offline, table not
/// created yet, Supabase uninitialized) it returns false and the
/// screen keeps the typed text (and the draft is persisted), so
/// a user's words are never lost to a network hiccup.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'crash_guard.dart';
import 'crash_reporter.dart';
import 'supabase_service.dart';

class FeedbackService {
  FeedbackService._();

  /// Supabase inbox table (see build9-sql.sql).
  static const String table = 'tjpro_feedback';

  /// SharedPreferences key for the unsent draft.
  static const String draftPrefsKey = 'tjpro_feedback_draft_v1';

  static const Duration _sendTimeout = Duration(seconds: 15);

  /// Cap on the attached diagnostics text (the stored record is
  /// already capped by CrashGuard; this is a second belt).
  static const int maxDiagnosticsChars = 4000;

  /// Send seam for tests: replaces the Supabase insert.
  static Future<bool> Function(Map<String, dynamic> row)? sendOverride;

  /// Builds the row for one feedback report. Pure.
  static Map<String, dynamic> buildRow({
    required String message,
    required String diagnostics,
    required DateTime when,
  }) {
    final diag = diagnostics.length > maxDiagnosticsChars
        ? diagnostics.substring(0, maxDiagnosticsChars)
        : diagnostics;
    return <String, dynamic>{
      'install_id': CrashReporter.instance.installId,
      'user_id': SupabaseService.currentUser?.id,
      'app_version': CrashGuard.appVersion,
      'route': CrashGuard.currentRoute ?? '',
      'message': message,
      'diagnostics': diag,
      'created_at': when.toUtc().toIso8601String(),
    };
  }

  /// Sends one report. Returns true only when the row was
  /// accepted. Never throws.
  static Future<bool> send({
    required String message,
    required String diagnostics,
  }) async {
    try {
      final row = buildRow(
        message: message,
        diagnostics: diagnostics,
        when: DateTime.now(),
      );
      final override = sendOverride;
      if (override != null) return await override(row);
      if (!SupabaseService.isInitialized) return false;
      await SupabaseService.client
          .from(table)
          .insert(row)
          .timeout(_sendTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The persisted unsent draft, or '' when none.
  static Future<String> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(draftPrefsKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Persists (or clears, when empty) the unsent draft.
  static Future<void> saveDraft(String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (text.isEmpty) {
        await prefs.remove(draftPrefsKey);
      } else {
        await prefs.setString(draftPrefsKey, text);
      }
    } catch (_) {
      // A lost draft is a nuisance, never a crash.
    }
  }
}
