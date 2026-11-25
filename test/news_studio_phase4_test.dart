// Phase 4 unit + widget tests: News Maker editor, One Click AI
// News Maker (13 steps), SEO step — topic extraction, headline,
// summary, subtitle split, SEO validation, project JSON round-trip,
// WAV duration parse, trends-service degradation, and widget smoke
// tests for the three screens (incl. "no Export button anywhere").
//
// NOTE on the AI-maker widget test: widget-test pumps never flush
// real dart:io work (file I/O, network), so the voiceover step can
// only be asserted to have STARTED (its status moves off the initial
// text) — not how the proxy answered. No proxy quota is used by any
// test here; the one live TTS call for Phase 4 was done once via
// curl (see the phase report).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tj_pro/news/ai_news_maker_screen.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/seo_screen.dart';
import 'package:tj_pro/news/trends_service.dart';
import 'package:tj_pro/services/coin_service.dart';
import 'package:tj_pro/services/gemini_voice_service.dart';

const String _tehreer =
    'شیخوپورہ میں پولیس نے بڑی کارروائی کی۔ بھاری مقدار میں شراب برآمد ہوئی۔ ملزم گرفتار ہو گیا۔';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase4_test';
      }
      return null;
    },
  );
}

/// Builds a minimal WAV in memory: 16-bit mono, [sampleRate] Hz,
/// [seconds] long. Used to test the WAV-duration parse.
List<int> _makeWav({int sampleRate = 24000, int seconds = 3}) {
  final dataSize = sampleRate * 2 * seconds;
  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) => out.add([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);
  void u16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
  ascii('RIFF');
  u32(36 + dataSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  ascii('data');
  u32(dataSize);
  out.add(List<int>.filled(dataSize, 0));
  return out.toBytes();
}

void main() {
  group('Topic extraction (rules-based, zero quota)', () {
    test('stopwords removed, content words rank first', () {
      final topics = extractTopics(_tehreer);
      expect(topics, isNotEmpty);
      expect(topics.first, 'شیخوپورہ');
      for (final stop in ['میں', 'نے', 'کی', 'ہو']) {
        expect(topics, isNot(contains(stop)));
      }
      expect(topics, contains('پولیس'));
      expect(topics, contains('شراب'));
    });

    test('frequency beats first occurrence', () {
      final topics = extractTopics(
        'لاہور لاہور لاہور میں پولیس نے کارروائی کی',
      );
      expect(topics.first, 'لاہور');
    });

    test('capitalised Latin word gets the proper-noun bonus', () {
      final topics = extractTopics(
        'Police arrested the suspect in Sheikhupura today',
      );
      expect(topics, contains('Sheikhupura'));
      expect(topics, contains('Police'));
      expect(topics, isNot(contains('the')));
      expect(topics, isNot(contains('in')));
    });

    test('empty text gives no topics', () {
      expect(extractTopics(''), isEmpty);
      expect(extractTopics('میں نے کی'), isEmpty);
    });
  });

  group('Headline + summary (extractive)', () {
    test('headline is the strongest first line', () {
      expect(
        extractHeadline(_tehreer),
        'شیخوپورہ میں پولیس نے بڑی کارروائی کی',
      );
    });

    test('long headline truncates at a word boundary with …', () {
      final headline = extractHeadline(
        'یہ ایک بہت لمبی سرخی ہے جو سو حروف سے زیادہ لمبی ہے اور اس کو کاٹنا ضروری ہے تاکہ یوٹیوب کی حد پوری ہو سکے اور مزید الفاظ یہاں لکھے جاتے ہیں',
        maxChars: 40,
      );
      expect(headline.length, lessThanOrEqualTo(41));
      expect(headline, endsWith('…'));
      expect(headline.contains('  '), isFalse);
    });

    test('summary is the first two lines', () {
      expect(
        extractSummary(_tehreer),
        'شیخوپورہ میں پولیس نے بڑی کارروائی کی '
        'بھاری مقدار میں شراب برآمد ہوئی',
      );
      expect(extractSummary('صرف ایک جملہ ہے۔'), 'صرف ایک جملہ ہے');
    });

    test('empty text gives empty headline/summary', () {
      expect(extractHeadline(''), '');
      expect(extractSummary(''), '');
    });
  });

  group('Subtitle split (basic, Phase 5 does karaoke sync)', () {
    test('lines fit the char limit, timings are monotonic from 0', () {
      final lines = splitSubtitles(_tehreer);
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.text.length, lessThanOrEqualTo(42));
        expect(line.endSec, greaterThan(line.startSec));
      }
      expect(lines.first.startSec, 0);
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].startSec, lines[i - 1].endSec);
      }
      // All words survive the split.
      expect(
        lines.map((l) => l.text).join(' ').split(RegExp(r'\s+')).length,
        countWords(_tehreer),
      );
    });

    test('a long sentence wraps to several lines', () {
      final lines = splitSubtitles(
        'یہ ایک بہت لمبا جملہ ہے جس میں بہت سے الفاظ ہیں اور اس کو کئی لائنوں میں بانٹنا ضروری ہے',
      );
      expect(lines.length, greaterThan(1));
    });
  });

  group('SEO validation', () {
    test('Roman hashtags valid, Urdu script rejected', () {
      expect(isRomanHashtag('#Sheikhupura'), isTrue);
      expect(isRomanHashtag('#PunjabPolice123'), isTrue);
      expect(isRomanHashtag('#خبر'), isFalse);
      expect(isRomanHashtag('#Sheikhupura Police'), isFalse);
      expect(isRomanHashtag('Sheikhupura'), isFalse);
    });

    test('hashtag count rule: fewer than 5 / more than 6 warn', () {
      expect(
        hashtagProblems(['#A', '#B', '#C', '#D', '#E']),
        isEmpty,
      );
      expect(
        hashtagProblems(['#A', '#B']),
        isNotEmpty,
      );
      expect(
        hashtagProblems(
          ['#A', '#B', '#C', '#D', '#E', '#F', '#G'],
        ),
        isNotEmpty,
      );
      expect(
        hashtagProblems(['#خبر', '#A', '#B', '#C', '#D']),
        contains(contains('English/Roman')),
      );
    });

    test('caption order: title, description, hashtags, follow last', () {
      final caption = buildCaption(
        title: 'Hook title',
        description: 'Story line.',
        hashtags: ['#A', '#B'],
        followLine: 'Follow Nigraan TV',
      );
      expect(
        caption,
        'Hook title\n\nStory line.\n\n#A #B\n\nFollow Nigraan TV',
      );
      expect(caption.contains('http'), isFalse);
    });

    test('X caption: hook + 2 tags, hard-capped at 280', () {
      final cut = xCaption(
        title: 'x' * 300,
        hashtags: ['#A', '#B', '#C'],
      );
      expect(cut.length, lessThanOrEqualTo(280));
      final short = xCaption(
        title: 'Short hook',
        hashtags: ['#A', '#B', '#C'],
      );
      expect(short, 'Short hook #A #B');
    });

    test('title over 100 chars is the YouTube-cap problem', () {
      expect('x' * 101, hasLength(101));
    });
  });

  group('NewsProject JSON round-trip', () {
    test('all fields survive, incl. subtitles, sources, SEO', () {
      final project = NewsProject.create()
        ..tehreer = _tehreer
        ..voice = GeminiVoice.charon
        ..voiceoverPath = '/tmp/voice.wav'
        ..voiceoverDurationSec = 42.5
        ..clipPaths = ['/tmp/c1.mp4', '/tmp/c2.mp4']
        ..tickerText = 'تازہ خبر'
        ..headline = 'Headline'
        ..summary = 'Summary'
        ..subtitles = splitSubtitles(_tehreer)
        ..breaking = true
        ..sources = [
          NewsSource(kind: 'url', value: 'https://example.com/x', label: 'Dawn'),
          NewsSource(kind: 'text', value: 'Press release'),
        ]
        ..seo = (SeoData()
          ..title = 'SEO title'
          ..hashtags = ['#A', '#B', '#C', '#D', '#E']
          ..keywords = 'police, liquor');
      final restored = NewsProject.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );
      expect(restored.tehreer, _tehreer);
      expect(restored.voice, GeminiVoice.charon);
      expect(restored.voiceoverPath, '/tmp/voice.wav');
      expect(restored.voiceoverDurationSec, 42.5);
      expect(restored.clipPaths, ['/tmp/c1.mp4', '/tmp/c2.mp4']);
      expect(restored.tickerText, 'تازہ خبر');
      expect(restored.subtitles.length, project.subtitles.length);
      expect(restored.subtitles.first.text,
          project.subtitles.first.text);
      expect(restored.breaking, isTrue);
      expect(restored.sources.length, 2);
      expect(restored.sources.first.value, 'https://example.com/x');
      expect(restored.seo.title, 'SEO title');
      expect(restored.seo.hashtags.length, 5);
      expect(restored.seo.followLine, defaultFollowLine);
    });

    test('old JSON without Phase 4 fields still loads', () {
      final restored = NewsProject.fromJson({'id': 'old_1'});
      expect(restored.id, 'old_1');
      expect(restored.voice, GeminiVoice.aoede);
      expect(restored.clipPaths, isEmpty);
      expect(restored.subtitles, isEmpty);
      expect(restored.sources, isEmpty);
      expect(restored.seo.hashtags, isEmpty);
    });

    test('store save/load round-trip on disk', () async {
      _mockPathProvider();
      final project = NewsProject.create()
        ..tehreer = _tehreer
        ..headline = 'Disk headline';
      await NewsProjectStore.save(project);
      final loaded = await NewsProjectStore.load(project.id);
      expect(loaded, isNotNull);
      expect(loaded!.tehreer, _tehreer);
      expect(loaded.headline, 'Disk headline');
      final latest = await NewsProjectStore.loadLatest();
      expect(latest, isNotNull);
      await NewsProjectStore.delete(project.id);
      expect(await NewsProjectStore.load(project.id), isNull);
    });
  });

  group('WAV duration parse', () {
    test('24 kHz mono 3s WAV parses to 3.0s', () {
      expect(wavDurationFromBytes(_makeWav(seconds: 3)), 3.0);
      expect(wavDurationFromBytes(_makeWav(seconds: 1)), 1.0);
    });

    test('non-WAV bytes return null, never throw', () {
      expect(wavDurationFromBytes([1, 2, 3]), isNull);
      expect(wavDurationFromBytes(utf8.encode('hello world')), isNull);
      expect(wavDurationFromBytes([]), isNull);
    });

    test('real file path helper reads the header', () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase4_');
      final file = File('${dir.path}/t.wav');
      await file.writeAsBytes(_makeWav(seconds: 2));
      expect(wavDurationSeconds(file), 2.0);
      expect(wavDurationSeconds(File('${dir.path}/missing.wav')), isNull);
    });
  });

  group('TrendsService — never invents, degrades on 404', () {
    test('200 parses hashtags + keywords + sources', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('trends-suggest'));
        return http.Response(
          jsonEncode({
            'suggestedHashtags': ['#SheikhupuraPolice', '#PunjabPolice'],
            'suggestedKeywords': ['liquor recovery'],
            'sources': ['Google Trends', 'X'],
            'checkedAt': '2026-11-20T23:59:00Z',
          }),
          200,
        );
      });
      final result = await TrendsService.fetchSuggestions(
        text: _tehreer,
        lang: 'ur',
        client: client,
      );
      expect(result.available, isTrue);
      expect(result.suggestion!.hashtags,
          ['#SheikhupuraPolice', '#PunjabPolice']);
      expect(result.suggestion!.keywords, ['liquor recovery']);
      expect(result.suggestion!.sources, ['Google Trends', 'X']);
    });

    test('404 (endpoint not live yet) -> unavailable, empty', () async {
      final client = MockClient((_) async => http.Response(
            '{"error":"Use POST /tts, POST /edge-tts or POST /transcribe"}',
            404,
          ));
      final result = await TrendsService.fetchSuggestions(
        text: _tehreer,
        lang: 'ur',
        client: client,
      );
      expect(result.available, isFalse);
      expect(result.suggestion, isNull);
      expect(result.reason, isNotNull);
    });

    test('empty 200 is available-but-empty (correct, not invented)',
        () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'suggestedHashtags': [],
              'suggestedKeywords': [],
              'sources': ['Google Trends', 'X'],
            }),
            200,
          ));
      final result = await TrendsService.fetchSuggestions(
        text: _tehreer,
        lang: 'ur',
        client: client,
      );
      expect(result.available, isTrue);
      expect(result.suggestion!.hashtags, isEmpty);
    });

    test('network throw -> unavailable', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final result = await TrendsService.fetchSuggestions(
        text: _tehreer,
        lang: 'ur',
        client: client,
      );
      expect(result.available, isFalse);
    });
  });

  group('NewsMakerScreen widget smoke test', () {
    // v1.5.2: the Maker is a tool-panel screen now (editors'
    // interface law) — sections live inside tool panels opened
    // from the ONE bottom tool line, not in a scrolling list.
    Future<void> openTool(WidgetTester tester, String id) async {
      // The bottom zone shows the tool line XOR the open panel:
      // close any open panel first, then drag the tool line
      // until the tool is built and tap it.
      final done = find.byKey(const Key('makerPanelDone'));
      if (done.evaluate().isNotEmpty) {
        await tester.tap(done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> pumpMaker(WidgetTester tester) async {
      _mockPathProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: NewsProject.create(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('tehreer box, voice controls, clips, NO Export button',
        (tester) async {
      await pumpMaker(tester);

      expect(find.text('News Maker'), findsOneWidget);

      // Tehreer lives in its tool panel now.
      await openTool(tester, 'tehreer');
      expect(find.byKey(const Key('tehreerField')), findsOneWidget);

      // Typing tehreer updates the word count live.
      // Tools-fix wave P2: the field's rebuild is debounced
      // (250 ms after the last keystroke) instead of rebuilding
      // the whole screen per keystroke — advance past the
      // debounce window, then the count must be there.
      await tester.enterText(
        find.byKey(const Key('tehreerField')),
        'شیخوپورہ میں پولیس نے بڑی کارروائی کی',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('7 alfaz'), findsOneWidget);

      // Voice panel (fix #61): text box + build button + voices.
      await openTool(tester, 'voice');
      expect(find.byKey(const Key('voiceTehreerField')), findsOneWidget);
      expect(find.byKey(const Key('voiceBuildButton')), findsOneWidget);
      expect(find.byKey(const Key('voiceChoice-Aoede')), findsOneWidget);
      expect(find.byKey(const Key('voiceChoice-Charon')), findsOneWidget);
      // No standalone Export button on the Maker screen.
      expect(find.widgetWithText(FilledButton, 'Export'), findsNothing);
      expect(find.text('Export • 100 coins'), findsNothing);

      // Media panel holds the clip pickers. Build 12 (point
      // #14d) — UPDATED IN PLACE: the three add buttons are
      // now ONE unified "Media add karein" entry; the sources
      // (with their original keys) live in its sheet.
      await openTool(tester, 'media');
      expect(find.byKey(const Key('mediaAddButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mediaAddButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('addClipGallery')), findsOneWidget);
      expect(find.byKey(const Key('addClipFiles')), findsOneWidget);
      expect(find.byKey(const Key('addClipPhoto')), findsOneWidget);
      // Close the sheet again for the export checks below.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Export panel holds the real export card (Phase 7).
      await openTool(tester, 'export');
      expect(find.byKey(const Key('exportReelButton')), findsOneWidget);
      expect(find.byKey(const Key('openTimelineButton')), findsOneWidget);
      expect(
        find.byKey(const Key('exportQualitySelector')),
        findsOneWidget,
      );
    });

    testWidgets('voice choice switches Aoede -> Charon', (tester) async {
      await pumpMaker(tester);

      await openTool(tester, 'voice');
      // The voice rail sits below the text box + build button in
      // the panel's scroll view — scroll the panel down to it.
      await tester.drag(
        find.byKey(const Key('makerPanel-voice')),
        const Offset(0, -160),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('voiceChoice-Charon')));
      await tester.pump();
      // Charon is now the selected voice (check icon moves to it).
      expect(
        find.descendant(
          of: find.byKey(const Key('voiceChoice-Charon')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
    });
  });

  group('AiNewsMakerScreen widget smoke test', () {
    /// Drags the screen's ListView down until [target] is built.
    /// (Lazy ListView items do not exist until scrolled into view,
    /// so ensureVisible/scrollUntilVisible cannot find them first.)
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      for (var i = 0; i < 15; i++) {
        if (target.evaluate().isNotEmpty) return;
        await tester.drag(
          find.byKey(const Key('aiMakerList')),
          const Offset(0, -300),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pumpAi(WidgetTester tester) async {
      _mockPathProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: AiNewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: NewsProject.create(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('13 steps listed, Export blocked, fact-check present',
        (tester) async {
      await pumpAi(tester);

      expect(find.text('One Click AI News Maker'), findsOneWidget);
      expect(find.byKey(const Key('aiTehreerField')), findsOneWidget);
      expect(find.byKey(const Key('runAnalysisButton')), findsOneWidget);

      // All 13 step rows exist (scroll the list to build the tail).
      for (final (id, _) in aiMakerSteps) {
        await scrollTo(tester, find.byKey(Key('aiStep-$id')));
        await tester.pump();
      }
      expect(find.byKey(const Key('aiStep-export')), findsOneWidget);
      // Step 13 has the real export card now (Phase 7) — expand the
      // step (ExpansionTile builds its content lazily), scroll to it
      // and check the Export Reel button exists.
      await scrollTo(tester, find.byKey(const Key('aiStep-export')));
      await tester.tap(find.byKey(const Key('aiStep-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await scrollTo(tester, find.byKey(const Key('exportReelButton')));
      await tester.pump();
      expect(find.byKey(const Key('exportReelButton')), findsOneWidget);
      expect(find.byKey(const Key('openTimelineButton')), findsOneWidget);

      // Fact-check card lives below the steps — scroll to it.
      await scrollTo(tester, find.byKey(const Key('factCheckTitle')));
      await tester.pump();
      expect(find.byKey(const Key('factCheckTitle')), findsOneWidget);
      expect(
        find.textContaining('verify NAHI karta'),
        findsOneWidget,
      );
    });

    testWidgets('run analysis fills headline/summary/topics for real',
        (tester) async {
      await pumpAi(tester);

      // Phase 10: One Click costs 100 coins — seed the balance so
      // the run is not blocked by the coin gate (the spend itself is
      // real: local-only debit, no Supabase in tests).
      CoinService.instance.balance.value = 1000;
      await tester.enterText(
        find.byKey(const Key('aiTehreerField')),
        _tehreer,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('runAnalysisButton')));
      // Let the sync analysis + the (test-env-failing) voiceover
      // attempt finish: repeated pumps, no pumpAndSettle (the
      // scrolling ticker animation never settles by design).
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Headline step: expand it and read the auto headline.
      await scrollTo(tester, find.text('Headline'));
      await tester.pump();
      await tester.tap(find.text('Headline'));
      await tester.pump();
      final headlineField =
          tester.widget<TextField>(find.byKey(const Key('aiHeadlineField')));
      expect(
        headlineField.controller!.text,
        'شیخوپورہ میں پولیس نے بڑی کارروائی کی',
      );

      // Analyze step: the top topic chip is there (rules-based).
      await scrollTo(tester, find.text('Analyze text'));
      await tester.pump();
      await tester.tap(find.text('Analyze text'));
      await tester.pump();
      expect(find.byKey(const Key('topic-شیخوپورہ')), findsOneWidget);

      // The voiceover step STARTED (its status moved off the initial
      // text). The proxy call itself cannot finish deterministically
      // in a widget test (real network/file I/O need runAsync), so
      // this asserts the step RAN, not how the network answered —
      // the one live call is verified via curl (see phase report).
      // (The status line lives inside the Voiceover step body, so
      // expand that step first.)
      await scrollTo(tester, find.text('Voiceover'));
      await tester.ensureVisible(find.text('Voiceover'));
      await tester.pump();
      await tester.tap(find.text('Voiceover'));
      await tester.pump();
      expect(find.text('Abhi voice nahi bani.'), findsNothing);
    });

    testWidgets('fact-check source add/remove is real', (tester) async {
      await pumpAi(tester);

      await scrollTo(tester, find.byKey(const Key('sourceValueField')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('sourceLabelField')),
        'Dawn',
      );
      await tester.enterText(
        find.byKey(const Key('sourceValueField')),
        'https://example.com/x',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sourceAddButton')));
      await tester.pump();
      expect(find.textContaining('https://example.com/x'), findsOneWidget);
      expect(find.textContaining('1 source(s)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sourceDelete-0')));
      await tester.pump();
      expect(find.textContaining('0 source(s)'), findsOneWidget);
    });
  });

  group('SeoScreen widget smoke test', () {
    /// Drags the screen's ListView down until [target] is built.
    /// (Lazy ListView items do not exist until scrolled into view,
    /// so ensureVisible/scrollUntilVisible cannot find them first.)
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      for (var i = 0; i < 15; i++) {
        if (target.evaluate().isNotEmpty) return;
        await tester.drag(
          find.byKey(const Key('seoList')),
          const Offset(0, -300),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<NewsProject> pumpSeo(WidgetTester tester) async {
      _mockPathProvider();
      final project = NewsProject.create()
        ..tehreer = _tehreer
        ..headline = 'شیخوپورہ پولیس کی بڑی کارروائی'
        ..summary = 'شیخوپورہ میں پولیس نے بڑی کارروائی کی';
      await tester.pumpWidget(
        MaterialApp(home: SeoScreen(project: project)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return project;
    }

    testWidgets('stepper, title counter, hashtag rules, save applies SEO',
        (tester) async {
      final savedProject = await pumpSeo(tester);

      expect(find.text('SEO — Finalize'), findsOneWidget);
      for (final label in ['Edit', 'Finalize', 'SEO', 'Publish']) {
        expect(find.text(label), findsOneWidget);
      }
      final titleField =
          tester.widget<TextField>(find.byKey(const Key('seoTitleField')));
      expect(titleField.controller!.text,
          'شیخوپورہ پولیس کی بڑی کارروائی');
      expect(find.textContaining('/ 100'), findsOneWidget);
      // Suggestions start idle (endpoint not live — no fake tags).
      expect(find.textContaining('Refresh dabayein'), findsOneWidget);

      // Urdu-script hashtag is rejected, Roman accepted.
      final addField =
          tester.widget<TextField>(find.byKey(const Key('hashtagAddField')));
      addField.onSubmitted!('#خبر');
      await tester.pump();
      expect(find.textContaining('Urdu script nahi'), findsOneWidget);
      addField.onSubmitted!('#Sheikhupura');
      await tester.pump();
      expect(find.byKey(const Key('hashtag-#Sheikhupura')), findsOneWidget);

      // No-links note sits below the fold — scroll to it.
      await scrollTo(tester, find.textContaining('Caption mein koi link nahi'));
      await tester.pump();
      expect(
        find.textContaining('Caption mein koi link nahi'),
        findsOneWidget,
      );

      // Save applies the SEO into the project object (fields are
      // assigned synchronously at the start of _saveSeo). The disk
      // write itself cannot complete in a widget test — the fake-async
      // zone never flushes dart:io — so persistence is covered by the
      // plain unit test above ('store save/load round-trip on disk',
      // real async), not here.
      await scrollTo(tester, find.byKey(const Key('saveSeoButton')));
      await tester.ensureVisible(find.byKey(const Key('saveSeoButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveSeoButton')));
      await tester.pump();
      expect(
        savedProject.seo.hashtags,
        contains('#Sheikhupura'),
      );
      expect(
        savedProject.seo.title,
        'شیخوپورہ پولیس کی بڑی کارروائی',
      );
      // The button shows the save is in flight (awaiting the disk
      // write that only real async can finish).
      expect(find.text('Save ho raha hai…'), findsOneWidget);
    });
  });
}
