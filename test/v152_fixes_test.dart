// v1.5.2 fix-round tests: template/ribbon coherence (#57,
// #62b, #63b), both-ticker editing (#65), Voice panel TTS
// completeness (#61), Logo/Reporter findability (#68), Coins
// earning button + honest prices (#66), Home de-duplication
// (#54) and the Watch Ads balance card (#55).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/coins_screen.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/project_handoff.dart';
import 'package:tj_pro/news/widgets/studio_pickers.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_v152';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_v152_tmp';
      }
      return null;
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens a Maker tool panel. The bottom zone shows the tool
/// line XOR the open panel (editors' pattern), so an already
/// open panel is closed via its check button first, and the
/// tool line is dragged until the tool is built.
Future<void> _openTool(WidgetTester tester, String id) async {
  final done = find.byKey(const Key('makerPanelDone'));
  if (done.evaluate().isNotEmpty) {
    await tester.tap(done);
    await _frames(tester);
  }
  final target = find.byKey(Key('makerTool-$id'));
  for (var i = 0; i < 10; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.tap(target);
  await _frames(tester);
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    SharedPreferences.setMockInitialValues({});
    Directory('/tmp/tj_pro_v152').createSync(recursive: true);
    Directory('/tmp/tj_pro_v152_tmp').createSync(recursive: true);
  });

  group('englishTickerText (#65)', () {
    test('JSON round-trip; old JSON defaults to empty', () {
      final project = NewsProject.create()
        ..englishTickerText = 'BREAKING: heavy rain in Karachi';
      final restored = NewsProject.fromJson(project.toJson());
      expect(restored.englishTickerText, 'BREAKING: heavy rain in Karachi');

      final legacy = NewsProject.create().toJson()
        ..remove('englishTickerText');
      expect(NewsProject.fromJson(legacy).englishTickerText, '');
    });

    test('effectivePresetFor applies it to the English ribbon', () {
      final preset = ChannelPreset.nigraanTv();
      final project = NewsProject.create()
        ..englishTickerText = 'EN ticker from the project';
      final effective = effectivePresetFor(project: project, preset: preset);
      expect(effective.englishRibbon.text, 'EN ticker from the project');
      // The saved preset itself is untouched (copy semantics).
      expect(preset.englishRibbon.text, isNot('EN ticker from the project'));
    });
  });

  group('templateDisplayLabel (#57/#62b/#63b)', () {
    test('one derivation for kind + variant', () {
      expect(
        templateDisplayLabel(templateKind: 'nigraanFinal', isFinal3: true),
        'Final 3-Ribbon',
      );
      expect(
        templateDisplayLabel(templateKind: 'nigraanFinal', isFinal3: false),
        'Classic 2-Ribbon',
      );
      expect(
        templateDisplayLabel(
          templateKind: 'breaking',
          isFinal3: true,
          breakingVariantLabel: 'Red Banner',
        ),
        'Breaking • Red Banner',
      );
      expect(
        templateDisplayLabel(templateKind: 'classic', isFinal3: false),
        'Classic',
      );
    });
  });

  group('News Maker coherence (widget)', () {
    Future<void> pumpMaker(
      WidgetTester tester, {
      required ChannelPreset preset,
      required NewsProject project,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: preset,
            initialProject: project,
          ),
        ),
      );
      await _frames(tester);
    }

    testWidgets(
        'a Classic-variant project is labelled Classic 2-Ribbon, '
        'and picking the Final card flips header + variant together',
        (tester) async {
      final preset = ChannelPreset.nigraanTv()
        ..finalVariant = kFinalVariantClassic2;
      final project = NewsProject.create()..templateKind = 'nigraanFinal';
      await pumpMaker(tester, preset: preset, project: project);

      // Header tells the truth (the v1.5.1 bug showed
      // 'Final 3-Ribbon' here while rendering Classic colours).
      // The header line is "<preset> preset • <label>".
      expect(find.textContaining('Classic 2-Ribbon'), findsWidgets);

      await _openTool(tester, 'template');
      // The Classic card is the selected one in the rail
      // (designCard marks selection with a gold check + border).
      expect(
        find.descendant(
          of: find.byKey(const Key('templateCard-classic2')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('templateCard-final3')));
      await _frames(tester);
      expect(preset.finalVariant, kFinalVariant3);
      expect(find.textContaining('Final 3-Ribbon'), findsWidgets);
    });

    testWidgets('Ticker panel edits BOTH tickers (#65)',
        (tester) async {
      final project = NewsProject.create();
      await pumpMaker(
        tester,
        preset: ChannelPreset.nigraanTv(),
        project: project,
      );
      await _openTool(tester, 'ticker');
      expect(find.byKey(const Key('tickerField')), findsOneWidget);
      expect(
        find.byKey(const Key('englishTickerField')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('englishTickerField')),
        'BREAKING: rain in Karachi',
      );
      // The field saves through the 500ms debounce timer.
      await tester.pump(const Duration(milliseconds: 700));
      expect(project.englishTickerText, 'BREAKING: rain in Karachi');
    });

    testWidgets('Voice panel is a complete TTS place (#61)',
        (tester) async {
      await pumpMaker(
        tester,
        preset: ChannelPreset.nigraanTv(),
        project: NewsProject.create(),
      );
      await _openTool(tester, 'voice');
      expect(find.byKey(const Key('voiceTehreerField')), findsOneWidget);
      expect(find.byKey(const Key('voiceBuildButton')), findsOneWidget);
      expect(find.byKey(const Key('voiceChoice-Aoede')), findsOneWidget);
    });

    testWidgets('Audio "Text se Audio" lands on the Voice panel (#56)',
        (tester) async {
      await pumpMaker(
        tester,
        preset: ChannelPreset.nigraanTv(),
        project: NewsProject.create(),
      );
      await _openTool(tester, 'audio');
      await tester.tap(find.text('Text se Audio'));
      await _frames(tester);
      // Same working flow — the Voice panel with its build button.
      expect(find.byKey(const Key('voiceBuildButton')), findsOneWidget);
    });

    testWidgets('Logo replace + Reporter name are surfaced (#68)',
        (tester) async {
      await pumpMaker(
        tester,
        preset: ChannelPreset.nigraanTv(),
        project: NewsProject.create(),
      );
      await _openTool(tester, 'logo');
      expect(find.byKey(const Key('logoPickButton')), findsOneWidget);

      await _openTool(tester, 'reporter');
      expect(find.byKey(const Key('reporterNameField')), findsOneWidget);
    });

    testWidgets('no bottom info card anymore (#64)', (tester) async {
      await pumpMaker(
        tester,
        preset: ChannelPreset.nigraanTv(),
        project: NewsProject.create(),
      );
      expect(find.textContaining('Channel preset'), findsNothing);
      expect(find.byKey(const Key('makerSummaryCard')), findsNothing);
    });
  });

  group('Coins screen (#66)', () {
    testWidgets('Watch Ads button visible + prices are honest',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CoinsScreen()),
      );
      await _frames(tester);
      expect(find.byKey(const Key('coinsWatchAdButton')), findsOneWidget);
      expect(find.text('Watch Ads, Earn Coins  •  +50 coins'),
          findsOneWidget);
      // Export carries NO coin price anymore.
      expect(find.text('Export 1080p'), findsOneWidget);
      expect(find.text('200 coins'), findsNothing);
      expect(find.text('100 coins'), findsOneWidget); // One Click only
      expect(find.text('FREE • ads ke sath'), findsNWidgets(2));
    });
  });

  group('Home (#54/#55)', () {
    testWidgets('MORE list gone; Watch Ads card carries the balance',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      await _frames(tester);
      expect(find.text('MORE'), findsNothing);
      expect(find.text('Watch Ads'), findsOneWidget);
      expect(find.textContaining('Balance:'), findsWidgets);
      expect(find.text('Invite'), findsOneWidget);
      // The Updates/About row sits below the fold — scroll to it.
      for (var i = 0; i < 8; i++) {
        if (find.text('Updates').evaluate().isNotEmpty) break;
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -300),
        );
        await _frames(tester);
      }
      // Exactly ONE updates entry (it lived in the deleted list).
      expect(find.text('Updates'), findsOneWidget);
    });
  });
}
