// v1.24.0 (G2, Point #38) — the "Preparing your tools"
// screen must never show two states in one frame.
//
// The user's v1.22.0 recording showed the failure text/list
// and the progress UI alternating after Retry: overlapping
// text, doubled buttons (Retry/Continue next to a ghost of
// "Later"). Root causes (see tools_prep_screen.dart):
// unguarded re-entry into _start, the service's fake
// 'Preparation already running' failure label, and stale
// progress surviving a restart. These tests drive the screen
// through its states with a fake runner and pin the contract:
// in ANY frame, exactly one state's widgets exist.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/first_run_prep_service.dart';
import 'package:tj_pro/widgets/tools_prep_screen.dart';

Widget _harness(ToolsPrepRunner runner) {
  return MaterialApp(
    home: ToolsPrepScreen(kasheedaUrl: 'https://example.invalid/f', runner: runner),
  );
}

void _expectOnlyRunning(WidgetTester tester) {
  expect(find.byType(LinearProgressIndicator), findsOneWidget);
  expect(find.text('Later — continue in background'), findsOneWidget);
  expect(find.textContaining('Some downloads did not finish'), findsNothing);
  expect(find.text('Retry'), findsNothing);
  expect(find.text('Continue anyway'), findsNothing);
  expect(find.text('All tools are ready.'), findsNothing);
}

void _expectOnlyFailure(WidgetTester tester) {
  expect(find.textContaining('Some downloads did not finish'), findsOneWidget);
  expect(find.text('Retry'), findsOneWidget);
  expect(find.text('Continue anyway'), findsOneWidget);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  expect(find.text('Later — continue in background'), findsNothing);
  expect(find.text('All tools are ready.'), findsNothing);
}

void main() {
  testWidgets('running state shows ONLY the progress UI', (tester) async {
    final gate = Completer<List<String>>();
    await tester.pumpWidget(_harness(
      ({required kasheedaUrl, onProgress}) => gate.future,
    ));
    await tester.pump();
    _expectOnlyRunning(tester);
    expect(find.text('Starting…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    gate.complete(const []);
    await tester.pump();
  });

  testWidgets('a progress emission shows its label and percentage, '
      'still with no failure widgets anywhere', (tester) async {
    final gate = Completer<List<String>>();
    await tester.pumpWidget(_harness(
      ({required kasheedaUrl, onProgress}) {
        onProgress!(
          const PrepProgress(
            label: 'Noise reduction model (RNNoise)',
            itemFraction: 0.4,
            overall: 0.68,
          ),
        );
        return gate.future;
      },
    ));
    await tester.pump();
    _expectOnlyRunning(tester);
    expect(
      find.text('Noise reduction model (RNNoise) — 68%'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    gate.complete(const []);
    await tester.pump();
  });

  testWidgets('failure completion shows ONLY the failure UI', (tester) async {
    await tester.pumpWidget(_harness(
      ({required kasheedaUrl, onProgress}) async =>
          const ['Noise reduction model (RNNoise)'],
    ));
    await tester.pump();
    await tester.pump();
    _expectOnlyFailure(tester);
    expect(find.text('Noise reduction model (RNNoise)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retry: the failure UI leaves in the SAME transition '
      'that brings the progress UI — never both, never stale progress',
      (tester) async {
    var calls = 0;
    final retryGate = Completer<List<String>>();
    Future<List<String>> runner({
      required String kasheedaUrl,
      void Function(PrepProgress progress)? onProgress,
    }) {
      calls++;
      if (calls == 1) {
        // The first run gets far (68% on RNNoise), then fails.
        onProgress!(
          const PrepProgress(
            label: 'Noise reduction model (RNNoise)',
            itemFraction: 0.4,
            overall: 0.68,
          ),
        );
        return Future.value(const ['Noise reduction model (RNNoise)']);
      }
      return retryGate.future;
    }

    await tester.pumpWidget(_harness(runner));
    await tester.pump();
    await tester.pump();
    _expectOnlyFailure(tester);

    // Double-tap Retry inside one frame: the second tap must
    // not start a second run.
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Retry'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 2, reason: 'one Retry = one run, even double-tapped');
    _expectOnlyRunning(tester);
    // The old run's 68% must NOT flash inside the new run.
    expect(find.text('Starting…'), findsOneWidget);
    expect(find.textContaining('68%'), findsNothing);
    expect(tester.takeException(), isNull);

    retryGate.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(find.text('All tools are ready.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the service joins an in-flight run instead of '
      'answering with a fake failure', () async {
    // Two concurrent run() calls must be the SAME future —
    // the second caller waits for the real result. (The run
    // itself does real IO against empty registries/temp dirs
    // in the test environment and settles on its own.)
    final a = FirstRunPrepService.run(kasheedaUrl: 'https://example.invalid/f');
    final b = FirstRunPrepService.run(kasheedaUrl: 'https://example.invalid/f');
    expect(identical(a, b), isTrue);
    final failed = await a;
    expect(failed, isNot(contains('Preparation already running')));
  });
}
