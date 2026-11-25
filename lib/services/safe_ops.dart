/// Build 10 (v1.8.0) — Safe wrappers (fix-list point #7C).
///
/// One isolation pattern for risky single-item operations —
/// decoding a clip, initialising a player for one file,
/// applying one effect, restoring one saved snapshot: the
/// operation runs inside [SafeOps.run]; a failure is recorded
/// through CrashGuard with its boundary tag and handed back
/// as a [SafeResult] error, so the ONE bad item fails with a
/// clear message and the app — and every other item — keeps
/// working.
///
/// The codebase already had this discipline hand-rolled at
/// many boundaries (CrashGuard.captureHandled call sites);
/// this wrapper is the formal version new code uses, so the
/// next risky call does not have to re-invent it.
library;

import 'crash_guard.dart';

/// Outcome of a [SafeOps.run] call: exactly one of [value] /
/// [error] is meaningful — check [ok].
class SafeResult<T> {
  const SafeResult.ok(this.value) : error = null;
  const SafeResult.failure(this.error) : value = null;

  final T? value;
  final String? error;

  bool get ok => error == null;
}

class SafeOps {
  SafeOps._();

  /// Runs [op]; never throws. A failure is recorded via
  /// CrashGuard under the source tag `safe.<tag>` and returned
  /// as [SafeResult.failure] with a short message.
  static Future<SafeResult<T>> run<T>(
    String tag,
    Future<T> Function() op,
  ) async {
    try {
      return SafeResult<T>.ok(await op());
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'safe.$tag');
      return SafeResult<T>.failure(_shortError(e));
    }
  }

  /// [run] for operations with nothing to return: true when
  /// the operation completed, false when it failed (and was
  /// recorded under `safe.<tag>`).
  static Future<bool> guard(String tag, Future<void> Function() op) async {
    final result = await run<Object?>(tag, () async {
      await op();
      return null;
    });
    return result.ok;
  }

  static String _shortError(Object e) {
    final text = e.toString().trim();
    if (text.isEmpty) return 'Unknown error';
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}
