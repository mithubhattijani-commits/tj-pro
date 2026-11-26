/// BUILD v1.26.0 — Motion M4 + M5.
///
/// M5: the scene⇄track converter (CHECK #8 integration note
/// traps a–e), the blank-canvas Creator (add layer, add
/// keyframe, Save → My Templates), Undo/Redo over scene
/// snapshots. M4: the keywords guard (every template id MUST
/// have a trilingual entry), the prompt matcher running on
/// the REAL catalogue, the Gallery's Smart Match behaviour
/// (score-ordered results + "Matched:" line, honest
/// suggestion fallback, never a fake AI result), Favourites
/// + Recents, and the plan §5 tier split.
///
/// The checked Gemini suites live in their own files
/// (motion_keyframes_gemini_test 65 + motion_prompt_matcher_
/// gemini_test 46); this file tests the INTEGRATION.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/motion/motion_editor_screen.dart';
import 'package:tj_pro/motion/motion_evaluator.dart';
import 'package:tj_pro/motion/motion_gallery_meta.dart';
import 'package:tj_pro/motion/motion_gallery_screen.dart';
import 'package:tj_pro/motion/motion_keyframe_convert.dart';
import 'package:tj_pro/motion/motion_keyframes.dart';
import 'package:tj_pro/motion/motion_my_templates.dart';
import 'package:tj_pro/motion/motion_prompt_matcher.dart';
import 'package:tj_pro/motion/motion_scene.dart';
import 'package:tj_pro/motion/motion_template_keywords.dart';
import 'package:tj_pro/motion/motion_templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MotionFavourites.resetCacheForTest();
    MotionRecents.resetCacheForTest();
  });

  // ── M5 converter ──────────────────────────────────────────

  group('M5 converter — scene ⇄ tracks', () {
    MotionLayer kfLayer() => MotionLayer.fromJson({
          'id': 't1',
          'type': 'text',
          'x': 640,
          'y': 360,
          'w': 800,
          'text': 'Test',
          'fontSize': 60,
          'keyframes': [
            {'t': 0.0, 'opacity': 0.0, 'easing': 'linear'},
            {
              't': 1.0,
              'x': 800.0,
              'opacity': 1.0,
              'rotation': math.pi / 2,
              'easing': 'easeOut',
            },
            {'t': 2.0, 'x': 400.0, 'scale': 2.0, 'easing': 'easeIn'},
          ],
        })!;

    test('trap (a): easing direction — scene END easing lands '
        'on the track START keyframe', () {
      final set = keyframeSetFromLayer(kfLayer());
      final opacity = set.trackFor(MotionProperty.opacity);
      expect(opacity.keyframes.map((k) => k.timeSec), [0.0, 1.0]);
      // Segment 0→1 is driven by scene kf@1.0's 'easeOut'.
      expect(opacity.keyframes[0].easing, MotionEasing.easeOut);
      // The last keyframe starts no segment: linear.
      expect(opacity.keyframes[1].easing, MotionEasing.linear);
      final x = set.trackFor(MotionProperty.positionX);
      expect(x.keyframes.map((k) => k.timeSec), [1.0, 2.0]);
      expect(x.keyframes.map((k) => k.value), [800.0, 400.0]);
      // Segment 1→2 driven by scene kf@2.0's 'easeIn'.
      expect(x.keyframes[0].easing, MotionEasing.easeIn);
    });

    test('trap (c): rotation radians ⇄ degrees', () {
      final layer = kfLayer();
      final set = keyframeSetFromLayer(layer);
      final rot = set.trackFor(MotionProperty.rotationDeg);
      expect(rot.keyframes.single.value, closeTo(90, 1e-9));
      final back = layerWithKeyframeSet(layer, set);
      final kf = back.keyframes.firstWhere((k) => k.t == 1.0);
      expect(kf.rotation, closeTo(math.pi / 2, 1e-12));
    });

    test('round-trip parity: the evaluator cannot tell the '
        'converted scene from the original', () {
      final layer = kfLayer();
      final back =
          layerWithKeyframeSet(layer, keyframeSetFromLayer(layer));
      MotionScene sceneOf(MotionLayer l) => MotionScene(
          width: 1280, height: 720, durationSec: 3, layers: [l]);
      for (final t in [
        0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5,
      ]) {
        final a = sceneStateAt(sceneOf(layer), t).single;
        final b = sceneStateAt(sceneOf(back), t).single;
        expect(b.x, closeTo(a.x, 1e-9), reason: 'x@$t');
        expect(b.y, closeTo(a.y, 1e-9), reason: 'y@$t');
        expect(b.scale, closeTo(a.scale, 1e-9), reason: 's@$t');
        expect(b.rotation, closeTo(a.rotation, 1e-9),
            reason: 'r@$t');
        expect(b.opacity, closeTo(a.opacity, 1e-9),
            reason: 'o@$t');
      }
    });

    test('trap (e): exotic scene easings flatten to the '
        'nearest enum easing', () {
      final layer = MotionLayer.fromJson({
        'id': 't2',
        'type': 'text',
        'x': 10,
        'y': 10,
        'keyframes': [
          {'t': 0.0, 'opacity': 0.0},
          {'t': 1.0, 'opacity': 1.0, 'easing': 'easeOutBack'},
        ],
      })!;
      final track =
          keyframeSetFromLayer(layer).trackFor(MotionProperty.opacity);
      expect(track.keyframes.first.easing, MotionEasing.easeOut);
    });

    test('trap (d): addKeyframeSeeded seeds the base value '
        'at the layer start', () {
      final layer = MotionLayer.fromJson({
        'id': 't3',
        'type': 'text',
        'x': 10,
        'y': 10,
        'start': 0.5,
        'opacity': 0.8,
      })!;
      var set = keyframeSetFromLayer(layer);
      expect(set.trackFor(MotionProperty.opacity).isEmpty, isTrue);
      set = addKeyframeSeeded(
          set, layer, MotionProperty.opacity, 1.5, 0.3);
      final track = set.trackFor(MotionProperty.opacity);
      expect(track.keyframes.map((k) => k.timeSec), [0.5, 1.5]);
      expect(track.keyframes.map((k) => k.value), [0.8, 0.3]);
      // A second add on the same track does NOT re-seed.
      set = addKeyframeSeeded(
          set, layer, MotionProperty.opacity, 2.5, 0.1);
      expect(
        set.trackFor(MotionProperty.opacity).keyframes.length,
        3,
      );
    });

    test('scenePropertyValueAt mirrors the evaluator', () {
      final layer = kfLayer();
      final scene = MotionScene(
          width: 1280, height: 720, durationSec: 3, layers: [layer]);
      for (final t in [0.0, 0.5, 1.0, 1.5, 2.0]) {
        final r = sceneStateAt(scene, t).single;
        expect(
          scenePropertyValueAt(layer, MotionProperty.opacity, t),
          closeTo(r.opacity, 1e-9),
          reason: 'opacity@$t',
        );
        expect(
          scenePropertyValueAt(layer, MotionProperty.positionX, t),
          closeTo(r.x, 1e-9),
          reason: 'x@$t',
        );
        expect(
          scenePropertyValueAt(
              layer, MotionProperty.rotationDeg, t),
          closeTo(r.rotation * 180 / math.pi, 1e-9),
          reason: 'rot@$t',
        );
      }
    });
  });

  // ── M4 keywords + matcher on the real catalogue ──────────

  group('M4 keywords + matcher (real catalogue)', () {
    test('GUARD: every template id has a trilingual entry', () {
      expect(kMotionTemplateKeywords.length,
          MotionTemplates.all.length);
      for (final t in MotionTemplates.all) {
        final kw = kMotionTemplateKeywords[t.id];
        expect(kw, isNotNull, reason: 'missing keywords: ${t.id}');
        expect(kw!.en, isNotEmpty, reason: t.id);
        expect(kw.roman, isNotEmpty, reason: t.id);
        expect(kw.urdu, isNotEmpty, reason: t.id);
        expect(kw.tags, isNotEmpty, reason: t.id);
      }
    });

    test('tier split follows the plan §5 table: 22/6/6', () {
      int n(MotionTier tier) =>
          MotionTemplates.all.where((t) => t.tier == tier).length;
      expect(MotionTemplates.all.length, 34);
      expect(n(MotionTier.free), 22);
      expect(n(MotionTier.pro), 6);
      expect(n(MotionTier.coins), 6);
    });

    test('prompts in all three languages find the right design',
        () {
      final cat = motionCatalogue();
      String first(String prompt) => MotionPromptMatcher.match(
              prompt: prompt, catalogue: cat)
          .first
          .templateId;
      expect(first('breaking news intro'), 'breaking_news_intro');
      expect(first('لوگو انٹرو'), 'logo_reveal');
      expect(first('naam strip'), 'naam_strip_classic');
      expect(first('election results'), 'election_results_bars');
      expect(first('countdown'), 'countdown_3_2_1');
    });

    test('no fake results: weak signal → suggestions only; '
        'gibberish → nothing', () {
      final cat = motionCatalogue();
      // 'charts' genuinely matches (the 'chart' keyword hits
      // it) — chart_bars leads the tie by catalogue order.
      expect(
        MotionPromptMatcher.match(prompt: 'charts', catalogue: cat)
            .first
            .templateId,
        'chart_bars',
      );
      // A sub-threshold signal (a saved template whose NAME
      // overlaps the prompt) yields category suggestions but
      // NO dressed-up results.
      const scene = MotionScene(
          width: 1280, height: 720, durationSec: 3, layers: []);
      final withMine = motionCatalogue(mine: const [
        MotionMyTemplate(
          id: 'm-cricket',
          name: 'My Cricket Score Board',
          category: 'points',
          baseTemplateId: null,
          scene: scene,
          imagePaths: {},
          savedAtMs: 0,
        ),
      ]);
      expect(
          MotionPromptMatcher.match(
              prompt: 'cricket', catalogue: withMine),
          isEmpty);
      expect(
        MotionPromptMatcher.suggestCategories(
            prompt: 'cricket', catalogue: withMine),
        contains('Points'),
      );
      // Pure gibberish: no matches AND no suggestions.
      expect(
          MotionPromptMatcher.match(
              prompt: 'zzz qqq nothing', catalogue: cat),
          isEmpty);
      expect(
        MotionPromptMatcher.suggestCategories(
            prompt: 'zzz qqq nothing', catalogue: cat),
        isEmpty,
      );
    });
  });

  // ── M4 favourites + recents stores ────────────────────────

  group('M4 gallery meta stores', () {
    test('favourites toggle persists both ways', () async {
      expect(await MotionFavourites.toggle('logo_reveal'), isTrue);
      expect(await MotionFavourites.isFavourite('logo_reveal'),
          isTrue);
      expect(await MotionFavourites.toggle('logo_reveal'), isFalse);
      expect(await MotionFavourites.isFavourite('logo_reveal'),
          isFalse);
    });

    test('recents: most-recent first, capped, de-duplicated',
        () async {
      for (var i = 0; i < 10; i++) {
        await MotionRecents.record('t$i');
      }
      var recent = await MotionRecents.load();
      expect(recent.length, MotionRecents.maxItems);
      expect(recent.first, 't9');
      await MotionRecents.record('t5');
      recent = await MotionRecents.load();
      expect(recent.first, 't5');
      expect(recent.where((id) => id == 't5').length, 1);
    });
  });

  // ── Gallery widget behaviour ──────────────────────────────

  group('M4 Gallery — Smart Match behaviour', () {
    Future<void> pumpGallery(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: MotionGalleryScreen()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }

    testWidgets('prompt search: score order + Matched line',
        (tester) async {
      await pumpGallery(tester);
      expect(find.byKey(const Key('motionCreateButton')),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('motionSearchField')), 'breaking');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const Key('motionMatchHint')),
          findsOneWidget);
      expect(find.textContaining('Matched:'), findsOneWidget);
      expect(
          find.byKey(const Key('motionCard-breaking_news_intro')),
          findsOneWidget);
      // logo_reveal scores 0 for 'breaking' — not dressed up
      // as a result.
      expect(find.byKey(const Key('motionCard-logo_reveal')),
          findsNothing);
    });

    testWidgets('gibberish: honest no-design panel, no chips',
        (tester) async {
      await pumpGallery(tester);
      await tester.enterText(
          find.byKey(const Key('motionSearchField')), 'zzz-no-match');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('No design found'),
          findsOneWidget);
      expect(find.byKey(const Key('motionMatchHint')),
          findsNothing);
    });

    testWidgets('weak signal: category suggestion chips',
        (tester) async {
      // A saved template whose name overlaps the prompt gives
      // the matcher a sub-threshold signal: no fake results,
      // an honest category chip instead.
      const scene = MotionScene(
          width: 1280, height: 720, durationSec: 3, layers: []);
      await MotionMyTemplates.save(const MotionMyTemplate(
        id: 'my-cricket',
        name: 'My Cricket Score Board',
        category: 'points',
        baseTemplateId: null,
        scene: scene,
        imagePaths: {},
        savedAtMs: 0,
      ));
      await pumpGallery(tester);
      await tester.enterText(
          find.byKey(const Key('motionSearchField')), 'cricket');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('No design found'),
          findsOneWidget);
      expect(find.byKey(const Key('motionSuggestChip-points')),
          findsOneWidget);
    });

    testWidgets('heart toggle → Favourites chip appears',
        (tester) async {
      await pumpGallery(tester);
      expect(find.byKey(const Key('motionCat-favourites')),
          findsNothing);
      await tester.tap(
          find.byKey(const Key('motionFav-logo_reveal')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(await MotionFavourites.isFavourite('logo_reveal'),
          isTrue);
      expect(find.byKey(const Key('motionCat-favourites')),
          findsOneWidget);
    });
  });

  // ── Editor widget behaviour ───────────────────────────────

  group('M5 Creator — blank canvas, keyframes, undo/redo', () {
    Future<void> pumpBlank(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: MotionEditorScreen.blank()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }

    Finder verticalScrollable() => find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        );

    testWidgets('undo/redo round-trips an added layer',
        (tester) async {
      await pumpBlank(tester);
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const Key('motionUndo')))
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('motionAddText')),
        200,
        scrollable: verticalScrollable(),
      );
      await tester.tap(find.byKey(const Key('motionAddText')));
      await tester.pump();
      expect(find.text('New Text'), findsWidgets);
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const Key('motionUndo')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('motionUndo')));
      await tester.pump();
      expect(find.text('New Text'), findsNothing);
      await tester.tap(find.byKey(const Key('motionRedo')));
      await tester.pump();
      expect(find.text('New Text'), findsWidgets);
    });

    testWidgets('add keyframe at playhead, then SAVE lands in '
        'My Templates with the keyframe in the scene',
        (tester) async {
      await pumpBlank(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('motionKfAdd')),
        240,
        scrollable: verticalScrollable(),
      );
      await tester.tap(find.byKey(const Key('motionKfAdd')));
      await tester.pump();
      // Playhead starts at 0 → the row for t=0 exists and the
      // keyframe is selected (delete control visible).
      expect(find.byKey(const Key('motionKfRow-0')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('motionKfDelete')),
        200,
        scrollable: verticalScrollable(),
      );
      expect(find.byKey(const Key('motionKfDelete')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('motionEditorSave')),
        240,
        scrollable: verticalScrollable(),
      );
      await tester.tap(find.byKey(const Key('motionEditorSave')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final mine = await MotionMyTemplates.load();
      expect(mine, hasLength(1));
      expect(mine.single.name, 'My Design');
      expect(mine.single.scene.layers.single.keyframes, isNotEmpty);
    });
  });
}
