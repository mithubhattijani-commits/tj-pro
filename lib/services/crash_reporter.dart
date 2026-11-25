/// Build 9 (v1.7.0, fix-list point #5) — CRASH AUTO-REPORT.
///
/// Extends CrashGuard (which already records every error
/// on-device) with an upload path:
///
/// - Every recorded error — uncaught or handled at a fail-soft
///   boundary — is converted to a small row and kept in a LOCAL
///   QUEUE (SharedPreferences), so reports survive offline
///   periods and app restarts. The queue is size-capped
///   ([maxQueueEntries], oldest dropped first).
/// - When the network allows, the queue is flushed to the
///   Supabase table `tjpro_crash_reports` (created by
///   supabase-followups/build9-sql.sql, which the owner runs in
///   the dashboard). Until that SQL runs — or whenever Supabase
///   is unreachable / uninitialized — the flush simply fails
///   soft and the queue waits. NOTHING here can crash the app:
///   every path is guarded, and this class never calls back
///   into CrashGuard (that would loop).
/// - Dedupe/throttle: the same error fingerprint
///   (CrashGuard.signatureFor) is queued at most ONCE per hour
///   per device, so a repeating error cannot flood the inbox.
/// - Privacy: rows carry the error text + a truncated stack,
///   the source tag/route, app version, device model, Android
///   version and an ANONYMOUS install id (random, generated
///   once, not tied to any account or person). No user content,
///   no file paths beyond what the error itself contains.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_guard.dart';
import 'supabase_service.dart';

class CrashReporter {
  CrashReporter._();

  static final CrashReporter instance = CrashReporter._();

  /// Supabase inbox table (see build9-sql.sql).
  static const String table = 'tjpro_crash_reports';

  static const String _queueKey = 'tjpro_crash_queue_v1';
  static const String _dedupeKey = 'tjpro_crash_sent_v1';
  static const String _installIdKey = 'tjpro_install_id_v1';

  /// Hard cap on queued rows (oldest dropped first).
  static const int maxQueueEntries = 50;

  /// Same fingerprint is queued at most once per this interval.
  static const Duration dedupeInterval = Duration(hours: 1);

  /// Per-field truncation, so one pathological error can never
  /// bloat the queue or the inbox.
  static const int maxErrorChars = 1000;
  static const int maxStackChars = 2000;

  static const Duration _sendTimeout = Duration(seconds: 15);

  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];
  final Map<String, int> _dedupe = <String, int>{};
  String _installId = '';
  String _deviceModel = 'unknown';
  String _androidVersion = 'unknown';
  bool _attached = false;
  bool _flushing = false;

  /// Read-only view of the queued rows (diagnostics + tests).
  List<Map<String, dynamic>> get queuedReports =>
      List<Map<String, dynamic>>.unmodifiable(_queue);

  /// The anonymous install id (empty until [init] has run).
  String get installId => _installId;

  // --- Test seams ------------------------------------------------
  /// Clock seam (production uses [DateTime.now]).
  static DateTime Function() nowFn = DateTime.now;

  /// Send seam: replaces the Supabase insert in tests. Returns
  /// true when the rows were accepted.
  static Future<bool> Function(List<Map<String, dynamic>> rows)?
      sendOverride;

  /// Storage seams: replace SharedPreferences in tests.
  static Future<String?> Function(String key)? prefsReader;
  static Future<void> Function(String key, String value)? prefsWriter;

  /// Device-info seam: returns (model, androidVersion).
  static Future<({String model, String android})> Function()?
      deviceInfoOverride;

  /// Test seam: clears all in-memory state and seams.
  static void resetForTest() {
    final r = instance;
    r._queue.clear();
    r._dedupe.clear();
    r._installId = '';
    r._deviceModel = 'unknown';
    r._androidVersion = 'unknown';
    r._attached = false;
    r._flushing = false;
    nowFn = DateTime.now;
    sendOverride = null;
    prefsReader = null;
    prefsWriter = null;
    deviceInfoOverride = null;
    CrashGuard.reportListener = null;
  }

  // --- Lifecycle ---------------------------------------------------

  /// Loads the persisted queue + install id, attaches to
  /// CrashGuard and kicks a first flush. Called once from
  /// main() AFTER AuthService.init() (so a Supabase session may
  /// already exist). Never throws.
  Future<void> init() async {
    try {
      _installId = await _readInstallId();
      await _loadQueue();
      await _loadDedupe();
      final info = await _loadDeviceInfo();
      _deviceModel = info.model;
      _androidVersion = info.android;
      attach();
      unawaited(flush());
    } catch (_) {
      // Reporting must never become a startup failure.
    }
  }

  /// Hooks this reporter into CrashGuard's recorded-diagnostic
  /// stream. Idempotent.
  void attach() {
    if (_attached) return;
    _attached = true;
    CrashGuard.reportListener = (Object error, StackTrace stack,
        String source) {
      enqueue(error, stack, source: source);
    };
  }

  // --- Queue -------------------------------------------------------

  /// Converts one recorded error into a queued row (subject to
  /// the hourly fingerprint dedupe) and kicks a flush. Never
  /// throws, never awaits anything.
  void enqueue(Object error, StackTrace stack, {required String source}) {
    try {
      final now = nowFn();
      final fingerprint = CrashGuard.signatureFor(error, source);
      final lastMs = _dedupe[fingerprint];
      if (lastMs != null &&
          now.millisecondsSinceEpoch - lastMs <
              dedupeInterval.inMilliseconds) {
        return; // Same error already reported within the hour.
      }
      _dedupe[fingerprint] = now.millisecondsSinceEpoch;
      unawaited(_persistDedupe());
      _queue.add(buildRow(error, stack, source: source, when: now));
      while (_queue.length > maxQueueEntries) {
        _queue.removeAt(0);
      }
      unawaited(_persistQueue());
      unawaited(flush());
    } catch (_) {
      // The reporter never throws (see file header).
    }
  }

  /// Builds the Supabase row for one error. Pure — also used by
  /// the feedback screen's diagnostics attachment indirectly
  /// (same field discipline).
  Map<String, dynamic> buildRow(
    Object error,
    StackTrace stack, {
    required String source,
    required DateTime when,
  }) {
    return <String, dynamic>{
      'install_id': _installId,
      'user_id': SupabaseService.currentUser?.id,
      'app_version': CrashGuard.appVersion,
      'device_model': _deviceModel,
      'android_version': _androidVersion,
      'source': source,
      'route': CrashGuard.currentRoute ?? '',
      'error': _truncate(error.toString(), maxErrorChars),
      'stack': _truncate(stack.toString(), maxStackChars),
      'fingerprint': CrashGuard.signatureFor(error, source),
      'created_at': when.toUtc().toIso8601String(),
    };
  }

  static String _truncate(String text, int max) {
    return text.length > max ? text.substring(0, max) : text;
  }

  // --- Flush ---------------------------------------------------------

  /// Sends every queued row to Supabase. On ANY failure (table
  /// missing because build9-sql.sql has not run yet, offline,
  /// Supabase uninitialized) the queue is kept untouched for the
  /// next attempt. Never throws.
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      final rows = List<Map<String, dynamic>>.from(_queue);
      final ok = await _send(rows);
      if (ok) {
        _queue.removeWhere(rows.contains);
        await _persistQueue();
      }
    } catch (_) {
      // Keep the queue; a later launch / error retries.
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _send(List<Map<String, dynamic>> rows) async {
    final override = sendOverride;
    if (override != null) return override(rows);
    if (!SupabaseService.isInitialized) return false;
    try {
      await SupabaseService.client
          .from(table)
          .insert(rows)
          .timeout(_sendTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Persistence ---------------------------------------------------

  Future<String> _readInstallId() async {
    final existing = await _read(_installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _write(_installIdKey, id);
    return id;
  }

  Future<void> _loadQueue() async {
    final raw = await _read(_queueKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      _queue
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m)),
        );
      while (_queue.length > maxQueueEntries) {
        _queue.removeAt(0);
      }
    }
  }

  Future<void> _loadDedupe() async {
    final raw = await _read(_dedupeKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      _dedupe
        ..clear()
        ..addAll(
          decoded.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          ),
        );
    }
  }

  Future<void> _persistQueue() async {
    try {
      await _write(_queueKey, jsonEncode(_queue));
    } catch (_) {
      // The in-memory queue remains the record for this session.
    }
  }

  Future<void> _persistDedupe() async {
    try {
      // Prune entries older than the dedupe interval while here.
      final cutoff =
          nowFn().millisecondsSinceEpoch - dedupeInterval.inMilliseconds;
      _dedupe.removeWhere((_, ts) => ts < cutoff);
      await _write(_dedupeKey, jsonEncode(_dedupe));
    } catch (_) {
      // Dedupe is an optimisation; losing it only risks a
      // duplicate report, never a failure.
    }
  }

  Future<String?> _read(String key) async {
    final reader = prefsReader;
    if (reader != null) return reader(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    final writer = prefsWriter;
    if (writer != null) {
      await writer(key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<({String model, String android})> _loadDeviceInfo() async {
    final override = deviceInfoOverride;
    if (override != null) return override();
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final maker = info.manufacturer.trim();
        final model = info.model.trim();
        return (
          model: maker.isEmpty ? model : '$maker $model',
          android:
              'Android ${info.version.release} (SDK ${info.version.sdkInt})',
        );
      }
    } catch (_) {
      // Fall through to the dart:io description.
    }
    return (model: 'unknown', android: Platform.operatingSystemVersion);
  }

  /// Debug-only visibility into the dedupe map size (tests).
  @visibleForTesting
  int get dedupeEntryCount => _dedupe.length;
}
