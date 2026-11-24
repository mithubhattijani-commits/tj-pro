// Build 6 (v1.5.8) — persistent diagnostics + in-app splash gate.
//
// Part 2: CrashGuard now persists the last error (message +
// first stack lines + timestamp) so a phone-only failure can be
// read back from About → "Diagnostics — aakhri khata" instead of
// guessed at. These tests pin the recording (through the storage
// seam AND through real SharedPreferences), the format caps, and
// the About display.
//
// Part 3: the app opens on the SplashGate (full-screen poster)
// and swaps itself for Home after the minimum show time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/services/crash_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrashGuard persistent diagnostics', () {
    setUp(() {
      CrashGuard.resetThrottleForTest();
      CrashGuard.diagnosticsWriter = null;
      CrashGuard.lastDiagnostic.value = null;
    });

    tearDown(() {
      CrashGuard.diagnosticsWriter = null;
      CrashGuard.resetThrottleForTest();
    });

    test('report() records message + source + stack head', () async {
      String? written;
      CrashGuard.diagnosticsWriter = (text) async => written = text;
      CrashGuard.nowFn = () => DateTime(2026, 11, 24, 14, 5, 6);
      try {
        throw StateError('boom-diagnostic');
      } catch (e, s) {
        CrashGuard.report(e, s, source: 'unit-test');
      }
      expect(written, isNotNull);
      expect(written, contains('boom-diagnostic'));
      expect(written, contains('source: unit-test'));
      expect(written, contains('2026-11-24T14:05:06'));
      // The first stack lines ride along (this test's own frames).
      expect(written, contains('main'));
      expect(CrashGuard.lastDiagnostic.value, written);
    });

    test('formatDiagnostic caps stack lines and total length', () {
      final stack = StackTrace.fromString(
        List.generate(30, (i) => '#$i fake-frame-$i').join('\n'),
      );
      // Stack-line cap: with a short message, only the first
      // diagnosticsStackLines stack lines are kept.
      final text = CrashGuard.formatDiagnostic(
        StateError('short'),
        stack,
        'cap-test',
        DateTime(2026, 1, 1),
      );
      expect(text, contains('fake-frame-0'));
      expect(text, contains('fake-frame-7'));
      expect(text, isNot(contains('fake-frame-8')));
      expect(text, isNot(contains('fake-frame-20')));
      // Length cap: a pathological message is truncated to the
      // hard budget.
      final huge = CrashGuard.formatDiagnostic(
        StateError('x' * 5000),
        stack,
        'cap-test',
        DateTime(2026, 1, 1),
      );
      expect(huge.length, CrashGuard.diagnosticsMaxChars);
    });

    test('diagnostic round-trips through SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      try {
        throw StateError('persist-me');
      } catch (e, s) {
        CrashGuard.report(e, s, source: 'prefs-test');
      }
      // The storage write is fire-and-forget; give it a turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stored = await CrashGuard.loadStoredDiagnostic();
      expect(stored, isNotNull);
      expect(stored, contains('persist-me'));
      expect(stored, contains('source: prefs-test'));
    });

    test('loadStoredDiagnostic is null when nothing recorded',
        () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CrashGuard.loadStoredDiagnostic(), isNull);
    });
  });

  group('Splash gate + About diagnostics (widget)', () {
    testWidgets('app opens on the poster, then Home replaces it',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();

      // First screen: the gate with the poster, no Home yet.
      expect(find.byType(SplashGate), findsOneWidget);
      final poster = tester.widget<Image>(
        find.descendant(
          of: find.byType(SplashGate),
          matching: find.byType(Image),
        ),
      );
      expect(
        (poster.image as AssetImage).assetName,
        'assets/splash_poster.png',
      );
      expect(poster.fit, BoxFit.cover);
      expect(find.text('VIDEO EDITOR'), findsNothing);

      // After the minimum show time the gate swaps in Home.
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(find.byType(SplashGate), findsOneWidget);
      expect(find.text('VIDEO EDITOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('About shows the stored diagnostic, copyable',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        CrashGuard.diagnosticsPrefsKey:
            '[2026-11-24T14:05:06] source: FlutterError\n'
            'Null check operator used on a null value',
      });
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();

      final about = find.text('About');
      await tester.ensureVisible(about);
      await tester.pump();
      await tester.tap(about);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Diagnostics — aakhri khata'), findsOneWidget);
      final shown = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data ?? '')
          .join('\n');
      expect(shown, contains('Null check operator used on a null value'));
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('About says so when no error was ever recorded',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();

      final about = find.text('About');
      await tester.ensureVisible(about);
      await tester.pump();
      await tester.tap(about);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Abhi tak koi khata record nahi hui.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
