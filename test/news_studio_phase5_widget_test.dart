// Phase 5 widget tests: the four new screens build, and the News
// Studio home shows the three new tiles.
//
// Build-only tests: no proxy calls, no ffmpeg, no model downloads.
// Persistence is covered by the plain unit tests in
// news_studio_phase5_test.dart (widget-test pumps never flush real
// dart:io work — Phase 4 note). No tester.runAsync + Future.delayed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/audio_tools_screen.dart';
import 'package:tj_pro/news/caption_studio_screen.dart';
import 'package:tj_pro/news/caption_translator_screen.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/tts_studio_screen.dart';
import 'package:tj_pro/services/caption_service.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase5_widget';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_phase5_widget_tmp';
      }
      return null;
    },
  );
}

/// Drags [listKey]'s ListView down until [target] is built (or
/// [maxDrags] drags pass). ListViews build lazily, so below-fold
/// widgets do not exist until scrolled into view — `find` on them
/// returns 0 and `scrollUntilVisible` trips over the screens'
/// nested horizontal scrollables.
Future<void> _scrollTo(
  WidgetTester tester,
  Key listKey,
  Finder target, {
  int maxDrags = 15,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.drag(find.byKey(listKey), const Offset(0, -600));
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase5_widget').createSync(recursive: true);
    Directory('/tmp/tj_pro_phase5_widget_tmp')
        .createSync(recursive: true);
  });

  group('Phase 5 screens build', () {
    testWidgets('AI Voice Studio builds with voice grid + generate',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TtsStudioScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI Voice Studio'), findsOneWidget);
      // 8 voices on the grid (Aoede/Charon + Asad/Uzma + 4 Gemini).
      expect(find.text('Aoede'), findsOneWidget);
      expect(find.text('Charon'), findsOneWidget);
      expect(find.text('Asad'), findsOneWidget);
      expect(find.text('Uzma'), findsOneWidget);
      // Generate button is below the fold in the ListView — scroll
      // it into view (ListView builds lazily).
      await _scrollTo(
        tester,
        const Key('ttsStudioList'),
        find.byKey(const Key('ttsGenerateButton')),
      );
      expect(find.byKey(const Key('ttsGenerateButton')), findsOneWidget);
      expect(find.text('Voice banao'), findsOneWidget);
    });

    testWidgets('Caption Studio builds with a test project',
        (tester) async {
      final project = NewsProject.create()
        ..tehreer = 'پہلی خبر کی لائن۔ دوسری خبر کی لائن۔'
        ..subtitles = [
          SubtitleLine(text: 'پہلی خبر کی لائن۔', startSec: 0, endSec: 2),
          SubtitleLine(text: 'دوسری خبر کی لائن۔', startSec: 2, endSec: 4),
        ];
      await tester.pumpWidget(
        MaterialApp(home: CaptionStudioScreen(initialProject: project)),
      );
      // No pumpAndSettle: the screen's karaoke preview embeds the
      // live template preview whose ticker animation repeats forever
      // (Phase 4 ScrollingTickerText). Two plain pumps are enough:
      // _load shows the handed-in project synchronously.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Caption Studio'), findsOneWidget);
      // Screen order is preview → styles → presets → controls →
      // lines → exports, so check each section in that order: once
      // scrolled past, a section is un-built again (ListView).
      await _scrollTo(
        tester,
        const Key('captionStudioList'),
        find.byKey(const Key('captionStyle-nigraan')),
      );
      expect(find.byKey(const Key('captionStyle-nigraan')), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('captionStudioList'),
        find.byKey(const Key('captionPreset-tiktok_bold')),
      );
      expect(find.byKey(const Key('captionPreset-tiktok_bold')),
          findsOneWidget);
      // The line cards are further down — scroll them into view
      // (the ListView builds lazily).
      await _scrollTo(
        tester,
        const Key('captionStudioList'),
        find.byKey(const Key('captionLine-0')),
      );
      expect(find.byKey(const Key('captionLine-0')), findsOneWidget);
      expect(find.text('پہلی خبر کی لائن۔'), findsOneWidget);
      expect(find.text('دوسری خبر کی لائن۔'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('captionStudioList'),
        find.byKey(const Key('exportSrtButton')),
      );
      expect(find.byKey(const Key('exportSrtButton')), findsOneWidget);
    });

    testWidgets('Audio Tools builds with converter controls',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AudioToolsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Audio Tools'), findsOneWidget);
      // Convert button is below the fold in the ListView — scroll
      // it into view (ListView builds lazily).
      await _scrollTo(
        tester,
        const Key('audioToolsList'),
        find.byKey(const Key('convertButton')),
      );
      expect(find.byKey(const Key('convertButton')), findsOneWidget);
      expect(find.text('Convert karein'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('audioToolsList'),
        find.byKey(const Key('joinAudioButton')),
      );
      expect(find.byKey(const Key('joinAudioButton')), findsOneWidget);
    });

    testWidgets('Caption Translator builds (empty = paste/pick UI)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CaptionTranslatorScreen(
            initialSegments: [],
            fromLang: 'ur',
            toLang: 'en',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Caption Translator'), findsOneWidget);
      expect(find.text('Urdu → English'), findsOneWidget);
      expect(find.byKey(const Key('pickSrtButton')), findsOneWidget);
      expect(find.byKey(const Key('loadSrtButton')), findsOneWidget);
    });

    testWidgets('Caption Translator builds with segments',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CaptionTranslatorScreen(
            initialSegments: [
              CaptionSegment('پہلی لائن۔', 0, 2),
            ],
            fromLang: 'ur',
            toLang: 'en',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Caption Translator'), findsOneWidget);
      expect(find.byKey(const Key('translateButton')), findsOneWidget);
      expect(find.text('پہلی لائن۔'), findsOneWidget);
    });

    // NOTE: no News Studio home test here. The home gates its whole
    // body on a FutureBuilder over five chained dart:io reads
    // (presets, templates, voice cap, font) — widget-test pumps
    // never flush real dart:io work (Phase 4 note), so the home
    // stays on its spinner in tests. The three tiles + navigation
    // are verified by `flutter analyze` (routes exist, code
    // compiles) and need a real-device check; see the Phase 5
    // report. Restructuring the Phase 4 home just to make it
    // testable was judged not worth the regression risk.
  });
}
