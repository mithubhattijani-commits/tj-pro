// TJ Pro v1.14.0 — functional proofs for the 5 groups.
//
// G1/G2/G5 (Timeline T1/T2/T3): TimelineMath pure proofs
// (timecode, ruler steps, fit, snap thresholds, roll, slip,
// trim-to-playhead, multi-move, range-delete plan) + widget
// proofs that the new header chips, transport frame-step and
// Trim-panel sections actually DO things (state flips, mode
// sections swap, switches toggle) — never wiring scans alone
// (the TOOLS-AUDIT lesson).
// G3 (NS T4): the Maker timeline renders the ruler + zoom
// controls, clips sit on the scale, and a ruler drag SCRUBS
// (the readout and the playhead really move).
// G4 (Motion M2): copyWith semantics (including clearing
// nullable fields), the My Templates store round-trip
// (save/upsert/duplicate/delete), the Editor saving an EDITED
// scene to the store, and the Gallery's My Templates category
// opening the Editor.
// Backward compatibility: NewsProject JSON round-trip and an
// M1-era MotionScene JSON still parse unchanged.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/motion/motion_editor_screen.dart';
import 'package:tj_pro/motion/motion_gallery_screen.dart';
import 'package:tj_pro/motion/motion_my_templates.dart';
import 'package:tj_pro/motion/motion_preview_screen.dart';
import 'package:tj_pro/motion/motion_scene.dart';
import 'package:tj_pro/motion/motion_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/video/video_editor_screen.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';

void _mockPathProvider(String dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir;
      if (call.method == 'getTemporaryDirectory') return '${dir}_tmp';
      return null;
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('G1 TimelineMath — timecode / ruler / fit / snap', () {
    test('formatTimecode renders H:MM:SS:FF with a floored frame', () {
      expect(TimelineMath.formatTimecode(0, 30), '0:00:00:00');
      expect(TimelineMath.formatTimecode(61.5, 30), '0:01:01:15');
      expect(TimelineMath.formatTimecode(3661, 25), '1:01:01:00');
      // 0.999s at 30fps is frame 29, never a rounded-up second.
      expect(TimelineMath.formatTimecode(0.999, 30), '0:00:00:29');
      // A dead fps falls back to 30 instead of dividing by zero.
      expect(TimelineMath.formatTimecode(1.5, 0), '0:00:01:15');
    });

    test('rulerStepSec keeps labels at least ~56px apart', () {
      expect(TimelineMath.rulerStepSec(120), 0.5);
      expect(TimelineMath.rulerStepSec(42), 2);
      expect(TimelineMath.rulerStepSec(12), 5);
      expect(TimelineMath.rulerStepSec(8), 10);
    });

    test('pxPerSecToFit fits and clamps to the zoom range', () {
      expect(TimelineMath.pxPerSecToFit(totalSec: 10, widthPx: 420), 42);
      expect(TimelineMath.pxPerSecToFit(totalSec: 100, widthPx: 400), 12);
      expect(TimelineMath.pxPerSecToFit(totalSec: 1, widthPx: 400), 120);
      expect(TimelineMath.pxPerSecToFit(totalSec: 0, widthPx: 400), 42);
    });

    test('snapThreshold: off is 0, strength scales both bases', () {
      expect(
        TimelineMath.snapThreshold(on: false, strength: 1, forTrim: false),
        0,
      );
      expect(
        TimelineMath.snapThreshold(on: true, strength: 1, forTrim: false),
        0.15,
      );
      expect(
        TimelineMath.snapThreshold(on: true, strength: 1, forTrim: true),
        0.08,
      );
      expect(
        TimelineMath.snapThreshold(on: true, strength: 0, forTrim: false),
        0.075,
      );
      expect(
        TimelineMath.snapThreshold(on: true, strength: 2, forTrim: true),
        0.16,
      );
    });
  });

  group('G2 TimelineMath — roll / slip / trim-to-playhead', () {
    test('rollEdit moves the boundary, total length invariant', () {
      final r = TimelineMath.rollEdit(
        aTrimStart: 0,
        aEffEnd: 8,
        aFull: 10,
        bTrimStart: 0,
        bEffEnd: 5,
        delta: 1,
      );
      expect(r, isNotNull);
      expect(r!.aEnd, 9);
      expect(r.bStart, 1);
      // (9-0) + (5-1) == (8-0) + (5-0) == 13.
      expect((r.aEnd - 0) + (5 - r.bStart), 13);
    });

    test('rollEdit clamps at the A file end', () {
      final r = TimelineMath.rollEdit(
        aTrimStart: 0,
        aEffEnd: 8,
        aFull: 10,
        bTrimStart: 0,
        bEffEnd: 5,
        delta: 5,
      );
      expect(r!.delta, 2);
      expect(r.aEnd, 10);
      expect(r.bStart, 2);
    });

    test('rollEdit is null when B cannot give (already at file start)',
        () {
      expect(
        TimelineMath.rollEdit(
          aTrimStart: 0,
          aEffEnd: 8,
          aFull: 10,
          bTrimStart: 0,
          bEffEnd: 5,
          delta: -3,
        ),
        isNull,
      );
    });

    test('rollEdit negative move takes from A into B', () {
      final r = TimelineMath.rollEdit(
        aTrimStart: 0,
        aEffEnd: 8,
        aFull: 10,
        bTrimStart: 2,
        bEffEnd: 7,
        delta: -3,
      );
      expect(r!.delta, -2);
      expect(r.aEnd, 6);
      expect(r.bStart, 0);
    });

    test('slipEdit slides the window, length unchanged', () {
      final r = TimelineMath.slipEdit(
        trimStart: 2,
        effEnd: 6,
        full: 10,
        delta: 1,
      );
      expect(r!.start, 3);
      expect(r.end, 7);
      expect(r.end - r.start, 4);
    });

    test('slipEdit clamps to both file bounds', () {
      expect(
        TimelineMath.slipEdit(trimStart: 2, effEnd: 6, full: 10, delta: 10)!
            .delta,
        4,
      );
      expect(
        TimelineMath.slipEdit(trimStart: 2, effEnd: 6, full: 10, delta: -10)!
            .delta,
        -2,
      );
    });

    test('slipEdit is null when the window spans the whole file', () {
      expect(
        TimelineMath.slipEdit(trimStart: 0, effEnd: 10, full: 10, delta: 1),
        isNull,
      );
    });

    test('trimStartToPlayhead lands the start on the playhead', () {
      expect(
        TimelineMath.trimStartToPlayhead(
          clipStartSec: 5,
          playheadSec: 7,
          trimStart: 1,
          effEnd: 9,
        ),
        3,
      );
      // Playhead outside the clip: no trim.
      expect(
        TimelineMath.trimStartToPlayhead(
          clipStartSec: 5,
          playheadSec: 4,
          trimStart: 1,
          effEnd: 9,
        ),
        isNull,
      );
      // Too close to the end: the min tail is protected.
      expect(
        TimelineMath.trimStartToPlayhead(
          clipStartSec: 5,
          playheadSec: 12.9,
          trimStart: 1,
          effEnd: 9,
        ),
        8.7,
      );
    });

    test('trimEndToPlayhead lands the end on the playhead', () {
      expect(
        TimelineMath.trimEndToPlayhead(
          clipStartSec: 5,
          playheadSec: 7,
          trimStart: 1,
          effEnd: 9,
        ),
        3,
      );
      expect(
        TimelineMath.trimEndToPlayhead(
          clipStartSec: 5,
          playheadSec: 20,
          trimStart: 1,
          effEnd: 9,
        ),
        isNull,
      );
      // Too close to the start: clamps to trimStart + minClipSec.
      expect(
        TimelineMath.trimEndToPlayhead(
          clipStartSec: 5,
          playheadSec: 5.2,
          trimStart: 1,
          effEnd: 9,
        ),
        1.3,
      );
    });
  });

  group('G5 TimelineMath — multi-move + range delete plan', () {
    test('multiMoveOrder moves a selected block as one', () {
      expect(
        TimelineMath.multiMoveOrder(count: 5, selected: {1, 2}, direction: 1),
        [0, 3, 1, 2, 4],
      );
      expect(
        TimelineMath.multiMoveOrder(
            count: 5, selected: {1, 2}, direction: -1),
        [1, 2, 0, 3, 4],
      );
    });

    test('multiMoveOrder: edges stay, sparse selections each move', () {
      expect(
        TimelineMath.multiMoveOrder(count: 5, selected: {0}, direction: -1),
        [0, 1, 2, 3, 4],
      );
      expect(
        TimelineMath.multiMoveOrder(count: 5, selected: {4}, direction: 1),
        [0, 1, 2, 3, 4],
      );
      expect(
        TimelineMath.multiMoveOrder(count: 5, selected: {0, 2}, direction: 1),
        [1, 0, 3, 2, 4],
      );
      expect(
        TimelineMath.multiMoveOrder(count: 5, selected: {}, direction: 1),
        [0, 1, 2, 3, 4],
      );
    });

    test('rangeDeletePlan trims the two edge clips, keeps the rest', () {
      final plan = TimelineMath.rangeDeletePlan(
        clipStarts: [0, 5, 10],
        effDurations: [5, 5, 5],
        trimStarts: [0, 0, 0],
        rangeIn: 2,
        rangeOut: 7,
      );
      expect(plan[0].kind, RangeActionKind.trimRight);
      expect(plan[0].effEnd, 2);
      expect(plan[1].kind, RangeActionKind.trimLeft);
      expect(plan[1].trimStart, 2);
      expect(plan[2].kind, RangeActionKind.keep);
    });

    test('rangeDeletePlan removes fully covered clips', () {
      final plan = TimelineMath.rangeDeletePlan(
        clipStarts: [0, 5, 10],
        effDurations: [5, 5, 5],
        trimStarts: [0, 0, 0],
        rangeIn: 0,
        rangeOut: 15,
      );
      expect(plan.map((a) => a.kind), [
        RangeActionKind.remove,
        RangeActionKind.remove,
        RangeActionKind.remove,
      ]);
    });

    test('rangeDeletePlan splits a clip the range punches through', () {
      final plan = TimelineMath.rangeDeletePlan(
        clipStarts: [0, 5, 10],
        effDurations: [5, 5, 5],
        trimStarts: [0, 0, 0],
        rangeIn: 6,
        rangeOut: 9,
      );
      expect(plan[1].kind, RangeActionKind.split);
      expect(plan[1].effEnd, 1); // left piece ends at file 1
      expect(plan[1].trimStart, 4); // right piece starts at file 4
    });

    test('rangeDeletePlan collapses a sliver into a one-sided trim', () {
      final plan = TimelineMath.rangeDeletePlan(
        clipStarts: [0],
        effDurations: [5],
        trimStarts: [0],
        rangeIn: 2,
        rangeOut: 4.97, // right survivor would be 0.03s — a sliver
      );
      expect(plan[0].kind, RangeActionKind.trimRight);
      expect(plan[0].effEnd, 2);
    });
  });

  group('Backward compatibility', () {
    test('NewsProject JSON round-trip is unchanged by T4', () {
      final p = NewsProject.create()..setClipPaths(['/a/1.mp4', '/a/2.mp4']);
      p.clipTrims[0] = const ClipTrim(startSec: 5, endSec: 12);
      final back = NewsProject.fromJson(p.toJson());
      expect(back.clipPaths, ['/a/1.mp4', '/a/2.mp4']);
      expect(back.trimAt(0).startSec, 5);
      expect(back.trimAt(0).endSec, 12);
    });

    test('an M1-era MotionScene JSON still parses', () {
      final scene = MotionScene.fromJson({
        'w': 1280,
        'h': 720,
        'duration': 4,
        'bg': 0xFF050914,
        'layers': [
          {
            'id': 't1',
            'type': 'text',
            'x': 640,
            'y': 360,
            'text': 'Salam',
            'fontSize': 64,
          },
        ],
      });
      expect(scene, isNotNull);
      expect(scene!.layers.single.text, 'Salam');
    });
  });

  group('G4 Motion — copyWith + My Templates store', () {
    test('layer copyWith changes, keeps, and CLEARS fields', () {
      const layer = MotionLayer(
        id: 't',
        type: MotionLayerType.text,
        x: 100,
        y: 200,
        text: 'Purana',
        fontFamily: 'Amiri',
        end: 3,
      );
      final edited = layer.copyWith(text: 'Naya');
      expect(edited.text, 'Naya');
      expect(edited.fontFamily, 'Amiri'); // untouched
      final cleared = layer.copyWith(fontFamily: null, end: null);
      expect(cleared.fontFamily, isNull);
      expect(cleared.end, isNull);
      expect(cleared.text, 'Purana'); // untouched
    });

    test('scene copyWith + JSON round-trip keeps the edits', () {
      final scene = MotionTemplates.kineticHeadline.scene.copyWith(
        durationSec: 9,
        bgColor2: null,
      );
      expect(scene.durationSec, 9);
      final back = MotionScene.fromJson(scene.toJson());
      expect(back, isNotNull);
      expect(back!.durationSec, 9);
      expect(back.layers.length, scene.layers.length);
      expect(back.layers.first.id, scene.layers.first.id);
    });

    test('store: save → load → upsert → duplicate → delete', () async {
      SharedPreferences.setMockInitialValues({});
      final rec = MotionMyTemplate(
        id: 'my-test-1',
        name: 'Pehla',
        category: 'titles',
        baseTemplateId: 'kinetic_headline',
        scene: MotionTemplates.kineticHeadline.scene,
        imagePaths: const {},
        savedAtMs: 1,
      );
      var items = await MotionMyTemplates.save(rec);
      expect(items.length, 1);
      items = await MotionMyTemplates.load();
      expect(items.single.name, 'Pehla');
      expect(items.single.scene.layers.length,
          MotionTemplates.kineticHeadline.scene.layers.length);
      // Upsert by id replaces, never duplicates.
      items = await MotionMyTemplates.save(
          rec.copyWith(name: 'Badla Hua'));
      expect(items.length, 1);
      expect(items.single.name, 'Badla Hua');
      // A second id coexists; delete removes only its own.
      await MotionMyTemplates.save(rec.copyWith(name: 'Dusra'));
      items = await MotionMyTemplates.save(
        MotionMyTemplate(
          id: 'my-test-2',
          name: 'Dusra',
          category: 'titles',
          baseTemplateId: null,
          scene: rec.scene,
          imagePaths: const {},
          savedAtMs: 2,
        ),
      );
      expect(items.length, 2);
      items = await MotionMyTemplates.delete('my-test-1');
      expect(items.length, 1);
      expect(items.single.id, 'my-test-2');
    });
  });

  group('G1/G2/G5 Video Editor widget proofs', () {
    setUpAll(() {
      _mockPathProvider('/tmp/tj_pro_v1140');
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpEditor(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: VideoEditorScreen()));
      await _frames(tester);
      expect(tester.takeException(), isNull);
    }

    testWidgets('header chips flip real state; frame step is honest',
        (tester) async {
      await pumpEditor(tester, const Size(393, 852));
      expect(find.byKey(const Key('tlSnapToggle')), findsOneWidget);
      expect(find.byKey(const Key('tlTcToggle')), findsOneWidget);
      expect(find.byKey(const Key('tlMultiToggle')), findsOneWidget);
      expect(find.byKey(const Key('tlZoomFit')), findsOneWidget);
      // No clips: frame-step buttons exist but are disabled.
      final back = tester.widget<IconButton>(
          find.byKey(const Key('tpFrameBack')));
      expect(back.onPressed, isNull);
      // Timecode toggle changes the transport readout format.
      expect(find.text('0:00:00:00 / 0:00:00:00'), findsNothing);
      await tester.tap(find.byKey(const Key('tlTcToggle')));
      await _frames(tester);
      expect(find.text('0:00:00:00 / 0:00:00:00'), findsOneWidget);
      // Multi toggle shows and hides the batch action bar.
      expect(find.byKey(const Key('tlMultiBar')), findsNothing);
      await tester.tap(find.byKey(const Key('tlMultiToggle')));
      await _frames(tester);
      expect(find.byKey(const Key('tlMultiBar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tlMultiToggle')));
      await _frames(tester);
      expect(find.byKey(const Key('tlMultiBar')), findsNothing);
      // Snap + fit taps are safe with an empty timeline.
      await tester.tap(find.byKey(const Key('tlSnapToggle')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('tlZoomFit')));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Trim panel: mode chips swap the mode controls',
        (tester) async {
      await pumpEditor(tester, const Size(393, 852));
      // Open the Precut tool (its panel embeds the Trim panel).
      final target = find.text('Precut');
      for (var i = 0; i < 14 && target.evaluate().isEmpty; i++) {
        for (final rail in find.byType(ListView).evaluate()) {
          await tester.drag(find.byWidget(rail.widget), const Offset(-240, 0));
        }
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(target, findsWidgets);
      await tester.tap(target.first);
      await _frames(tester);
      // v1.15.0 G2 (Point #29): the Trim body now DRILLS — its
      // sections are chips in one line and only the chosen
      // section shows. The mode controls live in the 'Trim mode'
      // section, so select it first.
      Future<void> tapSection(String title) async {
        final chip = find.text(title);
        await tester.ensureVisible(chip);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(chip);
        await _frames(tester);
      }

      await tapSection('Trim mode');
      expect(find.byKey(const Key('trimModeRoll')), findsOneWidget);
      // Default mode = Trim: trim-to-playhead visible, roll not.
      expect(find.byKey(const Key('trimToPlayheadStart')), findsOneWidget);
      expect(find.byKey(const Key('rollNudgeBack')), findsNothing);
      // Tap the chip's InkWell itself (the KeyedSubtree wrapper's
      // centre can sit outside the viewport before scrolling),
      // and let ensureVisible's scroll animation actually run.
      Future<void> tapChip(Key key) async {
        await tester.ensureVisible(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.descendant(
            of: find.byKey(key), matching: find.byType(InkWell)));
        await _frames(tester);
      }

      await tapChip(const Key('trimModeRoll'));
      expect(find.byKey(const Key('rollNudgeBack')), findsOneWidget);
      expect(find.byKey(const Key('trimToPlayheadStart')), findsNothing);
      await tapChip(const Key('trimModeSlip'));
      await _frames(tester);
      expect(find.byKey(const Key('slipNudgeBack')), findsOneWidget);
      // Timeline settings live in their own drill section now:
      // snap switch starts ON.
      await tapSection('Timeline');
      await tester.ensureVisible(find.byKey(const Key('tlSnapSwitch')));
      final snap = tester.widget<Switch>(
          find.byKey(const Key('tlSnapSwitch')));
      expect(snap.value, isTrue);
      // Range buttons render (their own section); In is disabled
      // while there are no clips.
      await tapSection('Range (In / Out)');
      await tester.ensureVisible(find.byKey(const Key('rangeSetIn')));
      final inBtn = tester.widget<TextButton>(
          find.byKey(const Key('rangeSetIn')));
      expect(inBtn.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('G3 News Studio timeline widget proofs', () {
    late Directory tmp;
    late File logoFile;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('tjpro_v1140_ns');
      _mockPathProvider(tmp.path);
      logoFile = File('${tmp.path}/logo.png');
      await logoFile.writeAsBytes(
        <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
          0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
          0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
          0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00,
          0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
          0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ],
      );
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpMaker(WidgetTester tester, NewsProject project) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final preset = ChannelPreset.nigraanTv()..logoPath = logoFile.path;
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
              initialPreset: preset, initialProject: project),
        ),
      );
      await _frames(tester);
      expect(tester.takeException(), isNull);
    }

    testWidgets('ruler + zoom render; ruler drag scrubs the playhead',
        (tester) async {
      // Two unprobed clips: the scale uses the nominal 3s each,
      // so the ruler exists and positions are computable.
      final project = NewsProject.create()
        ..setClipPaths(['/x/clip1.mp4', '/x/clip2.mp4']);
      await pumpMaker(tester, project);
      expect(find.byKey(const Key('tlRuler')), findsOneWidget);
      expect(find.byKey(const Key('tlClip-0')), findsOneWidget);
      expect(find.byKey(const Key('tlClip-1')), findsOneWidget);
      expect(find.byKey(const Key('nsTlZoomIn')), findsOneWidget);
      expect(find.byKey(const Key('tlPlayhead')), findsOneWidget);
      final before = tester.getTopLeft(find.byKey(const Key('tlPlayhead')));
      // Drag on the ruler from its centre: fit pps ≈ (369-52)/6
      // ≈ 52.8, centre ≈ 3.0s in — the readout must leave 0:00.
      await tester.drag(
          find.byKey(const Key('tlRuler')), const Offset(30, 0));
      await _frames(tester);
      final timeText = tester.widget<Text>(
          find.byKey(const Key('tlTimeText')));
      expect(timeText.data, isNot(startsWith('0:00 /')));
      final after = tester.getTopLeft(find.byKey(const Key('tlPlayhead')));
      expect(after.dx, greaterThan(before.dx + 60));
      // Zoom in twice: content outgrows the viewport; a lane
      // drag scrolls it — nothing may throw.
      await tester.tap(find.byKey(const Key('nsTlZoomIn')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('nsTlZoomIn')));
      await _frames(tester);
      await tester.drag(
          find.byKey(const Key('tlClip-0')), const Offset(-120, 0));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('G4 Motion Editor + Gallery widget proofs', () {
    setUpAll(() {
      _mockPathProvider('/tmp/tj_pro_v1140');
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Editor edits a text layer and SAVE persists it',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MotionEditorScreen(
              template: MotionTemplates.kineticHeadline),
        ),
      );
      await _frames(tester);
      expect(find.byKey(const Key('motionEditorCanvas')), findsOneWidget);
      final field = find.byKey(const Key('motionTextField-line1'));
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'NAYA TEXT');
      await _frames(tester);
      await tester.tap(find.byKey(const Key('motionEditorSave')));
      await _frames(tester);
      final items = await MotionMyTemplates.load();
      expect(items.length, 1);
      expect(
        items.single.scene.layers.any((l) => l.text == 'NAYA TEXT'),
        isTrue,
        reason: 'the edited text must be inside the saved scene',
      );
      expect(find.byKey(const Key('motionEditorStatus')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Preview Edit button opens the Editor', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home:
              MotionPreviewScreen(template: MotionTemplates.kineticHeadline),
        ),
      );
      await _frames(tester);
      final btn = find.byKey(const Key('motionEditButton'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await _frames(tester);
      expect(find.byKey(const Key('motionEditorCanvas')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Gallery My Templates category opens the Editor',
        (tester) async {
      await MotionMyTemplates.save(
        MotionMyTemplate(
          id: 'my-gal-1',
          name: 'Meri Wali',
          category: 'titles',
          baseTemplateId: 'kinetic_headline',
          scene: MotionTemplates.kineticHeadline.scene,
          imagePaths: const {},
          savedAtMs: 3,
        ),
      );
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: MotionGalleryScreen()));
      await _frames(tester);
      final chip = find.byKey(const Key('motionCat-mine'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await _frames(tester);
      final card = find.byKey(const Key('motionCard-mine:my-gal-1'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await _frames(tester);
      expect(find.byKey(const Key('motionEditorCanvas')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
