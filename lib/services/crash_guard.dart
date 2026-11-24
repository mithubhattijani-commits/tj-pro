/// TJ Pro — global crash guard (Master Plan Phase 0).
///
/// Before Phase 0 the app had NO global error handling: any
/// unhandled framework or async error took the app straight down
/// with no trace and no user-facing state. This guard is the one
/// funnel for those errors:
///
/// - [install] wires `FlutterError.onError` (framework/build
///   errors) and `PlatformDispatcher.onError` (async errors that
///   escape to the platform). `main()` additionally wraps startup
///   in a guarded zone that forwards to [report].
/// - Every error is LOGGED (debugPrint + stack) and kept in
///   [lastError] — never swallowed silently (Phase 0 rule: the
///   handler surfaces, it does not hide).
/// - When the UI is up, the user sees a short snackbar via
///   [messengerKey] instead of a frozen/crashed app; build-time
///   failures render the broadcast-style fallback from
///   [errorWidgetBuilder] instead of the red error screen.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CrashGuard {
  CrashGuard._();

  /// Scaffold messenger wired into `MaterialApp`, so a caught
  /// error can surface as a snackbar from anywhere (services
  /// included), without needing a BuildContext.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Most recent caught error (diagnostics + tests).
  static final ValueNotifier<String?> lastError =
      ValueNotifier<String?>(null);

  static bool _installed = false;

  // --- Build 5 (v1.5.7): snackbar dedupe + throttle --------------
  // v1.5.6 on the user's phone: ONE repeating error (a layout
  // overflow refiring on every frame in the News Maker workspace)
  // queued a 4-second banner per occurrence, so the "Kuch ghalat
  // ho gaya" banner marched across every screen he opened for
  // minutes. report() now (a) suppresses the SAME error signature
  // inside a short window, (b) enforces a minimum gap between
  // banners, and (c) REPLACES the visible banner instead of
  // queueing another one behind it. Logging + [lastError] are
  // NEVER throttled — only the user-facing banner is.

  /// Same-signature suppression window.
  static const Duration dedupeWindow = Duration(seconds: 10);

  /// Minimum gap between two user-facing banners.
  static const Duration snackbarMinGap = Duration(seconds: 4);

  static final Map<String, DateTime> _signatureSeenAt =
      <String, DateTime>{};
  static DateTime? _lastSnackbarAt;

  /// How many banners the throttle has suppressed (diagnostics +
  /// tests — the errors themselves were still logged).
  static int suppressedBanners = 0;

  /// Clock seam for tests (production uses [DateTime.now]).
  static DateTime Function() nowFn = DateTime.now;

  /// Test seam: clears the dedupe/throttle state.
  static void resetThrottleForTest() {
    _signatureSeenAt.clear();
    _lastSnackbarAt = null;
    suppressedBanners = 0;
    nowFn = DateTime.now;
  }

  /// The dedupe signature of one report: source + runtime type +
  /// the message head (long stack-derived messages are cut so the
  /// same repeating error maps to one signature).
  static String signatureFor(Object error, String source) {
    final message = error.toString();
    final head = message.length > 120 ? message.substring(0, 120) : message;
    return '$source|${error.runtimeType}|$head';
  }

  /// Install the framework + platform error handlers and the safe
  /// error widget. Idempotent; call once from `main()` after the
  /// binding exists and before `runApp`.
  static void install() {
    if (_installed) return;
    _installed = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      report(
        details.exception,
        details.stack ?? StackTrace.empty,
        source: 'flutter',
      );
      // Keep the framework's own diagnostics (console dump in
      // debug, test binding failure in tests) exactly as before.
      previous?.call(details);
    };
    ui.PlatformDispatcher.instance.onError =
        (Object error, StackTrace stack) {
      report(error, stack, source: 'platform');
      // True = handled here; the platform must not also crash
      // the app for an error we have already surfaced.
      return true;
    };
    ErrorWidget.builder = errorWidgetBuilder;
  }

  /// The single reporting funnel: log loudly, remember, and (when
  /// the UI exists) tell the user with a snackbar. Never throws.
  static void report(
    Object error,
    StackTrace stack, {
    String source = 'app',
  }) {
    final String message = error.toString();
    debugPrint('[TJPro][$source] $message');
    debugPrintStack(stackTrace: stack, label: '[TJPro][$source]');
    lastError.value = message;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    // Dedupe + throttle (see the Build 5 note above): a repeating
    // error is logged every time but banners at most once per
    // signature per window, never back-to-back, never queued.
    final now = nowFn();
    final signature = signatureFor(error, source);
    final seenAt = _signatureSeenAt[signature];
    if (seenAt != null && now.difference(seenAt) < dedupeWindow) {
      suppressedBanners++;
      return;
    }
    final lastShown = _lastSnackbarAt;
    if (lastShown != null && now.difference(lastShown) < snackbarMinGap) {
      suppressedBanners++;
      return;
    }
    _signatureSeenAt[signature] = now;
    _lastSnackbarAt = now;
    try {
      // Replace, never queue: a stale queued banner marching
      // across later screens was the v1.5.6 symptom.
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Kuch ghalat ho gaya — app chalti rahegi, dobara '
            'koshish karke dekhein.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      // The messenger itself is gone (app shutting down) — the
      // log above is the record; reporting must never throw.
    }
  }

  /// Broadcast-style fallback for a widget that failed to build:
  /// a calm dark panel with a plain message instead of the
  /// framework's red error screen.
  static Widget errorWidgetBuilder(FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF101014),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.amber, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Is hisse mein kuch ghalat ho gaya.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
