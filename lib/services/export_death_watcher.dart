/// Hotfix (export-crash audit C4, reporting half): process-death
/// visibility for exports.
///
/// The export crash itself is a PROCESS death (Android LMK kill
/// or a native death inside the in-process ffmpeg encode), so
/// Dart's error funnel can never see it — tjpro_crash_reports
/// had ZERO export rows while users watched the app vanish at
/// 50–60%. This watcher closes that visibility hole:
///
/// * Both export entry points (Video Editor + News Studio)
///   call [markExportStarted] when a real export begins and
///   [markExportFinished] when it ends — success, failure or
///   cancel alike. The marker is a SharedPreferences timestamp,
///   so it survives the process.
/// * A graceful end ALWAYS clears the marker. A marker still
///   present at the next launch therefore means the previous
///   session ended mid-export without finishing — killed,
///   crashed, or swiped away during the window.
/// * At startup (CrashGuard.install) [checkOnStartup] reads
///   Android's ApplicationExitInfo for the previous process
///   death (reason + timestamp, via the existing
///   "tj_pro/updater" channel in MainActivity) and, when the
///   death belongs to the marked window, records it through
///   CrashGuard with source 'export.exit' — from where the
///   existing CrashReporter path carries it to Supabase.
///
/// Limits (honest): API < 30 has no ApplicationExitInfo, so on
/// those phones the report carries the marker evidence with
/// the reason marked unavailable. The watcher only REPORTS;
/// it does not change any export behaviour.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_guard.dart';

class ExportDeathWatcher {
  ExportDeathWatcher._();

  /// The updater channel in MainActivity.kt also answers
  /// 'getPreviousExitInfo' (it is the app's one native channel
  /// for process-level facts).
  static const MethodChannel _channel = MethodChannel('tj_pro/updater');

  /// SharedPreferences key: ms-epoch of the in-flight export's
  /// start. Absent = no export was in flight.
  static const String markerPrefsKey = 'tjpro_export_started_at_ms';

  /// Clock seam for tests.
  static DateTime Function() nowFn = DateTime.now;

  /// Test seam: replaces the platform-channel read (returns
  /// the ApplicationExitInfo map, or null when unavailable).
  static Future<Map<String, dynamic>?> Function()? exitInfoReaderForTest;

  /// Marks an export as in flight from now. Fail-soft: a
  /// storage failure simply means no marker (today's behaviour).
  static Future<void> markExportStarted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        markerPrefsKey,
        nowFn().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Never block an export over bookkeeping.
    }
  }

  /// Clears the in-flight marker (any graceful export end).
  static Future<void> markExportFinished() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(markerPrefsKey);
    } catch (_) {
      // Same fail-soft rule as the mark.
    }
  }

  /// Android ApplicationExitInfo reason constants (API 30+),
  /// named for the crash report.
  static String reasonName(int reason) => switch (reason) {
        0 => 'UNKNOWN',
        1 => 'EXIT_SELF',
        2 => 'SIGNALED',
        3 => 'LOW_MEMORY',
        4 => 'CRASH',
        5 => 'CRASH_NATIVE',
        6 => 'ANR',
        7 => 'INITIALIZATION_FAILURE',
        8 => 'PERMISSION_CHANGE',
        9 => 'EXCESSIVE_RESOURCE_USAGE',
        10 => 'USER_REQUESTED',
        11 => 'USER_STOPPED',
        12 => 'DEPENDENCY_DIED',
        13 => 'OTHER',
        14 => 'FREEZER',
        _ => 'REASON_$reason',
      };

  /// Pure decision (unit-tested): the recorded death belongs
  /// to the marked export window when its timestamp is not
  /// meaningfully BEFORE the export started. Five minutes of
  /// slack absorbs clock skew between the prefs write and the
  /// system's exit timestamp.
  static bool exitBelongsToExportWindow({
    required int exportStartedAtMs,
    required int exitTimestampMs,
  }) =>
      exitTimestampMs >=
      exportStartedAtMs - const Duration(minutes: 5).inMilliseconds;

  static Future<Map<String, dynamic>?> _readExitInfo() async {
    final override = exitInfoReaderForTest;
    if (override != null) return override();
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'getPreviousExitInfo',
      );
    } catch (_) {
      // Missing plugin (tests / non-Android) — no record.
      return null;
    }
  }

  /// The one-shot startup check. Reads and clears the marker;
  /// when the previous death belongs to the export window (or
  /// no exit record exists, e.g. API < 30 — the leftover
  /// marker is then the only evidence), records the death via
  /// CrashGuard with source 'export.exit'. Never throws.
  static Future<void> checkOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final startedAt = prefs.getInt(markerPrefsKey);
      if (startedAt == null) return;
      // One-shot: whatever the conclusion, never report twice.
      await prefs.remove(markerPrefsKey);
      final info = await _readExitInfo();
      final exitTs = (info?['timestamp'] as num?)?.toInt();
      if (info != null &&
          exitTs != null &&
          !exitBelongsToExportWindow(
            exportStartedAtMs: startedAt,
            exitTimestampMs: exitTs,
          )) {
        // The newest recorded death PREDATES this export — the
        // marker is stale (that session's exit was never
        // recorded). Not evidence of an export death; stay
        // silent.
        return;
      }
      final reason = (info?['reason'] as num?)?.toInt();
      final description = info?['description']?.toString() ?? '';
      final reasonText = reason == null
          ? 'unavailable (no exit record — pre-API 30 or history pruned)'
          : '${reasonName(reason)} ($reason)';
      final exitText = exitTs == null
          ? 'unknown'
          : DateTime.fromMillisecondsSinceEpoch(exitTs).toIso8601String();
      CrashGuard.captureHandled(
        StateError(
          'Previous process died during an export window. '
          'exitReason: $reasonText, exitAt: $exitText, '
          'exportStartedAt: '
          '${DateTime.fromMillisecondsSinceEpoch(startedAt).toIso8601String()}'
          '${description.isEmpty ? '' : ', description: $description'}',
        ),
        StackTrace.current,
        source: 'export.exit',
      );
    } catch (_) {
      // The watcher must never become a startup failure.
    }
  }

  /// Test seam: restores the production clock + channel.
  static void resetForTest() {
    nowFn = DateTime.now;
    exitInfoReaderForTest = null;
  }
}
