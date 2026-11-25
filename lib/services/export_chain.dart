/// Build 10 (v1.8.0) — Export fallback chain (fix-list
/// point #7D).
///
/// An export that fails is not the end: the chain tries the
/// next strategy — hardware encoder → chunked software →
/// full-length software → plain software — until one attempt
/// succeeds, the user cancels, or every strategy has had its
/// turn. Only then does the caller report failure, with the
/// last attempt's logs as the reason.
///
/// The runner is deliberately generic and dumb: each attempt
/// is a closure returning the caller's own result type, and
/// the caller says what counts as success / cancellation.
/// A thrown exception inside an attempt is recorded via
/// CrashGuard (tag `export.chain.<name>`) and treated as that
/// attempt failing — it never escapes the chain.
library;

import 'crash_guard.dart';

/// One named export strategy.
class ExportAttempt<T> {
  const ExportAttempt({required this.name, required this.run});

  /// Stable machine name ('hardware', 'chunked', 'software',
  /// 'software-plain') — surfaced in results and diagnostics.
  final String name;

  final Future<T> Function() run;
}

/// What the chain settled on.
class ChainOutcome<T> {
  const ChainOutcome({
    this.result,
    this.attemptName,
    required this.triedAttempts,
    this.cancelled = false,
  });

  /// The winning attempt's result (or the cancelling
  /// attempt's result); null when every attempt failed.
  final T? result;

  /// Name of the attempt that produced [result].
  final String? attemptName;

  /// Every attempt that ran, in order.
  final List<String> triedAttempts;

  /// True when a user cancel stopped the chain — the caller
  /// must NOT fall through to more attempts or report a
  /// failure.
  final bool cancelled;

  bool get succeeded => result != null && !cancelled;
}

class ExportChain {
  ExportChain._();

  static Future<ChainOutcome<T>> run<T>({
    required List<ExportAttempt<T>> attempts,
    required bool Function(T result) isSuccess,
    required bool Function(T result) isCancelled,
    void Function(String attemptName)? onAttemptFailed,
  }) async {
    final tried = <String>[];
    for (final attempt in attempts) {
      tried.add(attempt.name);
      final T result;
      try {
        result = await attempt.run();
      } catch (e, s) {
        CrashGuard.captureHandled(e, s, source: 'export.chain.${attempt.name}');
        onAttemptFailed?.call(attempt.name);
        continue;
      }
      if (isCancelled(result)) {
        return ChainOutcome<T>(
          result: result,
          attemptName: attempt.name,
          triedAttempts: tried,
          cancelled: true,
        );
      }
      if (isSuccess(result)) {
        return ChainOutcome<T>(
          result: result,
          attemptName: attempt.name,
          triedAttempts: tried,
        );
      }
      onAttemptFailed?.call(attempt.name);
    }
    return ChainOutcome<T>(triedAttempts: tried);
  }
}
