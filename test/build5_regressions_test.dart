// Build 5 (v1.5.7) regressions:
//
//  (ii) CrashGuard banner dedupe + throttle — the v1.5.6 phone
//       bug was ONE repeating error queueing a 4-second banner
//       per occurrence, so the banner marched across screens.
//       report() must log every error but banner at most once
//       per signature per window, never back-to-back, never
//       queued.
//  (iii) News Maker _load() fail-soft — the production entry
//       (no test seams) must reach the loaded workspace from the
//       stores alone, without an unhandled async error escaping
//       (the old unguarded _load/_refreshVoiceStatus were banner
//       sources).
//  (iv) Template & Studio absorption — the retired screen's
//       unique controls (lower third, category, interview, PIP,
//       chroma, intro/outro, full preset ribbon editors) must be
//       present AND functional in the Maker's Template/Ribbons
//       panels; the Maker stage must render the breaking/classic
//       previews by project kind; Channel Branding must be
//       reachable from the project-bar menu.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/crash_guard.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_build5';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_build5_tmp';
      }
      return null;
    },
  );
  // The News Maker state constructs an AudioRecorder at init; the
  // record plugin has no test implementation, and its async
  // create call would otherwise surface as a MissingPluginException
  // (on a phone the plugin exists — a test-environment artifact).
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );
}

String? _clipboardText;

void _mockClipboard() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = call.arguments as Map<dynamic, dynamic>?;
          _clipboardText = args?['text'] as String?;
          return null;
        case 'Clipboard.getData':
          final text = _clipboardText;
          return text == null ? null : <String, dynamic>{'text': text};
        default:
          return null;
      }
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens a News Maker tool (same dance as the overflow guard:
/// close any open panel, drag the tool line until the tool is
/// built, tap it).
Future<void> _openMakerTool(WidgetTester tester, String id) async {
  final done = find.byKey(const Key('makerPanelDone'));
  if (done.evaluate().isNotEmpty) {
    await tester.tap(done);
    await _frames(tester);
  }
  final target = find.byKey(Key('makerTool-$id'));
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsOneWidget, reason: 'maker tool $id not found');
  await tester.tap(target);
  await _frames(tester);
}

/// The open panel's vertical scrollable.
Finder _panelScrollable() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );

Future<void> _scrollPanelTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    140,
    scrollable: _panelScrollable().first,
  );
  await _frames(tester);
}

void main() {
  group('CrashGuard banner dedupe + throttle', () {
    var clock = DateTime(2026, 11, 24, 12);

    setUp(() {
      CrashGuard.resetThrottleForTest();
      clock = DateTime(2026, 11, 24, 12);
      CrashGuard.nowFn = () => clock;
    });

    tearDown(() {
      CrashGuard.resetThrottleForTest();
    });

    test('signature is stable per source+type+message head', () {
      final a = CrashGuard.signatureFor(StateError('boom'), 'app');
      final b = CrashGuard.signatureFor(StateError('boom'), 'app');
      final c = CrashGuard.signatureFor(StateError('bang'), 'app');
      expect(a, b);
      expect(a, isNot(c));
    });

    testWidgets('same error banners once per window; a different '
        'error inside the min gap is also held back', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: CrashGuard.messengerKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pump();

      CrashGuard.report(StateError('overflow'), StackTrace.empty);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(CrashGuard.lastError.value, contains('overflow'));

      // Same signature 1s later: logged, but NO second banner and
      // no queued banner behind the first.
      clock = clock.add(const Duration(seconds: 1));
      CrashGuard.report(StateError('overflow'), StackTrace.empty);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(CrashGuard.suppressedBanners, 1);

      // A DIFFERENT error 1s after that is still inside the min
      // gap — held back too (no banner pile-up).
      clock = clock.add(const Duration(seconds: 1));
      CrashGuard.report(ArgumentError('other'), StackTrace.empty);
      await tester.pump();
      expect(CrashGuard.suppressedBanners, 2);
      expect(CrashGuard.lastError.value, contains('other'));

      // After the dedupe window the same error may banner again —
      // and it REPLACES (still exactly one SnackBar, not a queue).
      clock = clock.add(const Duration(seconds: 11));
      CrashGuard.report(StateError('overflow'), StackTrace.empty);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(CrashGuard.suppressedBanners, 2);

      // Let the banner expire so no timer is pending at teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    });
  });

  group('News Maker production load (fail-soft)', () {
    setUpAll(() {
      _mockPathProvider();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('loads the workspace from the stores with no '
        'unhandled error', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // runAsync: _load reads the stores with real dart:io, which
      // never completes inside the fake-async zone.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(home: NewsMakerScreen()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 900));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const Key('makerToolLine')),
        findsOneWidget,
        reason: 'workspace tool line should be built after _load',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Template & Studio absorption (Build 5)', () {
    setUpAll(() {
      _mockPathProvider();
      _mockClipboard();
      SharedPreferences.setMockInitialValues({});
    });

    Future<ChannelPreset> pumpMaker(
      WidgetTester tester, {
      NewsProject? project,
    }) async {
      final preset = ChannelPreset.nigraanTv();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: preset,
            initialProject: project ?? NewsProject.create(),
          ),
        ),
      );
      await _frames(tester);
      expect(tester.takeException(), isNull);
      return preset;
    }

    testWidgets('Template panel carries the absorbed controls, '
        'and they edit the preset', (tester) async {
      final preset = await pumpMaker(tester);
      await _openMakerTool(tester, 'template');

      // Preset selector shows the working preset's name.
      expect(find.text('${preset.name} preset'), findsOneWidget);
      // Kasheeda font status line.
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('kasheedaStatus')),
      );
      expect(find.byKey(const Key('kasheedaStatus')), findsOneWidget);

      // Lower third: typing edits the preset field.
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioLowerTitleField')),
      );
      await tester.enterText(
        find.byKey(const Key('studioLowerTitleField')),
        'Jaani Bhatti',
      );
      await _frames(tester);
      expect(preset.lowerThirdTitle, 'Jaani Bhatti');

      // Category field edits the preset.
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioCategoryField')),
      );
      await tester.enterText(
        find.byKey(const Key('studioCategoryField')),
        'POLITICS',
      );
      await _frames(tester);
      expect(preset.categoryLabel, 'POLITICS');

      // Interview plate: name edits the preset.
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioInterviewNameField')),
      );
      await tester.enterText(
        find.byKey(const Key('studioInterviewNameField')),
        'Mehman Khan',
      );
      await _frames(tester);
      expect(preset.interviewName, 'Mehman Khan');

      // PIP: switch on reveals the scale slider; both edit.
      final pipBefore = preset.pipEnabled;
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioPipSwitch')),
      );
      await tester.tap(find.byKey(const Key('studioPipSwitch')));
      await _frames(tester);
      expect(preset.pipEnabled, !pipBefore);
      if (preset.pipEnabled) {
        expect(
          find.byKey(const Key('studioPipScaleSlider')),
          findsOneWidget,
        );
      }

      // Chroma: switch on reveals the background chips.
      final chromaBefore = preset.chromaEnabled;
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioChromaSwitch')),
      );
      await tester.tap(find.byKey(const Key('studioChromaSwitch')));
      await _frames(tester);
      expect(preset.chromaEnabled, !chromaBefore);
      if (preset.chromaEnabled) {
        expect(
          find.byKey(const Key('studioChromaBg-newsroom')),
          findsOneWidget,
        );
      }

      // Intro/Outro: the switch edits the preset.
      final introBefore = preset.showIntro;
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('studioIntroSwitch')),
      );
      await tester.tap(find.byKey(const Key('studioIntroSwitch')));
      await _frames(tester);
      expect(preset.showIntro, !introBefore);

      // Flush the autosave debounce so no timer is pending.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ribbons panel carries the full preset ribbon '
        'editors, and they edit the preset', (tester) async {
      final preset = await pumpMaker(tester);
      await _openMakerTool(tester, 'ribbons');

      await _scrollPanelTo(
        tester,
        find.byKey(const Key('ribbonText-top')),
      );
      await tester.enterText(
        find.byKey(const Key('ribbonText-top')),
        'نئی ٹکر تحریر',
      );
      await _frames(tester);
      expect(preset.topRibbon.text, 'نئی ٹکر تحریر');

      // The Urdu ribbon's on/off switch edits the preset.
      final enabledBefore = preset.urduRibbon.enabled;
      await _scrollPanelTo(
        tester,
        find.byKey(const Key('ribbonEnabled-urdu')),
      );
      await tester.tap(find.byKey(const Key('ribbonEnabled-urdu')));
      await _frames(tester);
      expect(preset.urduRibbon.enabled, !enabledBefore);

      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ticker paste fills the project ticker field',
        (tester) async {
      await pumpMaker(tester);
      await _openMakerTool(tester, 'ticker');
      _clipboardText = 'پیسٹ شدہ ٹکر';
      await tester.tap(find.byKey(const Key('pasteTickerButton')));
      await _frames(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('tickerField')))
            .controller
            ?.text,
        'پیسٹ شدہ ٹکر',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stage renders breaking + classic previews by '
        'project kind', (tester) async {
      await pumpMaker(
        tester,
        project: NewsProject.create()..templateKind = 'breaking',
      );
      expect(
        find.byKey(const Key('makerBreakingPreview')),
        findsOneWidget,
      );
      // A same-type pumpWidget would reuse the Maker's State —
      // clear the tree first so the classic project really loads.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await _frames(tester);
      await pumpMaker(
        tester,
        project: NewsProject.create()..templateKind = 'classic',
      );
      expect(
        find.byKey(const Key('makerClassicPreview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Channel Branding opens from the project-bar menu',
        (tester) async {
      await pumpMaker(tester);
      await tester.tap(find.byKey(const Key('makerMoreMenu')));
      await _frames(tester);
      await tester.tap(find.text('Channel Branding'));
      await _frames(tester);
      await _frames(tester);
      expect(find.byKey(const Key('brandingNameField')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Export panel carries the template frame (poster) '
        'export at the one export door', (tester) async {
      await pumpMaker(tester);
      await _openMakerTool(tester, 'export');
      expect(find.byKey(const Key('seoButton')), findsOneWidget);
      expect(
        find.byKey(const Key('templateFrameExportButton')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
