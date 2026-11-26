// TJ Pro v1.17.0 — FUNCTIONAL tests for the five groups:
//   G1 Point #37a BG-remove ANR: the matte/composite pixel
//      semantics run off-thread; the isolate jobs fail soft
//      (null / error line) instead of hanging or throwing when
//      the model is unusable; the shared matte-alpha composite
//      keeps its proven byte semantics.
//   G2 Point #33 tool-row rule: (added below)
//   G3 Point #34 text: (added below)
//   G4 Points #35/#36 NS preview: (added below)
//   G5 Point #37b/c/d bake + pre-download: (added below)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:tj_pro/news/widgets/reporter_overlay.dart';
import 'package:tj_pro/services/onnx_isolate.dart';
import 'package:tj_pro/services/photo_pipeline.dart'
    show compositeMatteAlphaBytes;
import 'package:tj_pro/services/first_run_prep_service.dart';
import 'package:tj_pro/services/model_pack_service.dart';
import 'package:tj_pro/services/pro_editor.dart' show stabParamsForLevel;
import 'package:tj_pro/services/video_export_service.dart'
    show rifeInterpolateIsolateJob;
import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/motion/motion_editor_screen.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/element_override.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/widgets/template_media_preview.dart';
import 'package:tj_pro/motion/motion_hit_test.dart';
import 'package:tj_pro/motion/motion_scene.dart';
import 'package:tj_pro/motion/motion_templates.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/video/panels/legacy_text_panel.dart';
import 'package:tj_pro/video/video_editor_controller.dart';
import 'package:tj_pro/video/video_editor_panels.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';
import 'package:tj_pro/video/widgets/panel_controls.dart';
import 'package:tj_pro/video/video_editor_screen.dart';
import 'package:tj_pro/video/widgets/tool_rows.dart';
import 'package:tj_pro/video/video_editor_recovery.dart';

img.Image _solid(int w, int h, int r, int g, int b, {int a = 255}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, a));
  return image;
}

void main() {
  group('G1 — matte-alpha composite byte semantics', () {
    test('alpha channel of the matte wins, RGB is the photo\'s', () {
      // 2x1 photo: red, green. Matte alpha: 0, 128.
      final src = Uint8List.fromList([
        255, 0, 0, 255, //
        0, 255, 0, 255,
      ]);
      final matte = Uint8List.fromList([
        9, 9, 9, 0, //
        9, 9, 9, 128,
      ]);
      final out = compositeMatteAlphaBytes(src, matte);
      expect(out, [255, 0, 0, 0, 0, 255, 0, 128]);
    });

    test('alpha pinned at 255 everywhere falls back to red channel', () {
      final src = Uint8List.fromList([10, 20, 30, 255]);
      final matte = Uint8List.fromList([77, 0, 0, 255]);
      final out = compositeMatteAlphaBytes(src, matte);
      expect(out[3], 77);
      expect(out[0], 10);
    });
  });

  group('G1 — reporter cutout composite (pure)', () {
    test('cutout carries photo RGB + matte alpha at photo size', () {
      final photo = _solid(4, 2, 200, 30, 30);
      final matted = _solid(4, 2, 200, 30, 30, a: 255);
      // Left half transparent in the matte.
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          matted.setPixelRgba(x, y, 200, 30, 30, 0);
        }
      }
      final out = reporterCutoutFromMatte(photo, matted);
      expect(out.width, 4);
      expect(out.height, 2);
      expect(out.getPixel(0, 0).a, 0);
      expect(out.getPixel(3, 0).a, 255);
      expect(out.getPixel(3, 0).r, 200);
    });

    test('replace composite over a solid colour is opaque', () {
      final cutout = _solid(3, 3, 0, 0, 0, a: 0);
      final out = reporterReplaceComposite(cutout, colorArgb: 0xFF204060);
      expect(out.getPixel(1, 1).a, 255);
      expect(out.getPixel(1, 1).r, 0x20);
      expect(out.getPixel(1, 1).g, 0x40);
      expect(out.getPixel(1, 1).b, 0x60);
    });

    test('replace composite cover-fits a background photo', () {
      final cutout = _solid(4, 2, 0, 0, 0, a: 0);
      final bg = _solid(2, 2, 10, 220, 10);
      final out = reporterReplaceComposite(cutout, bg: bg);
      expect(out.width, 4);
      expect(out.height, 2);
      expect(out.getPixel(0, 0).g, 220);
      expect(out.getPixel(3, 1).g, 220);
    });
  });

  group('G1 — isolate jobs fail soft, never hang or throw', () {
    test('reporter BG job with an unusable model returns null', () async {
      final photo = _solid(8, 8, 120, 120, 120);
      final bytes = img.encodePng(photo);
      final out = reporterBgIsolateJob(
        <dynamic>[bytes, '/nonexistent/model_fp16.onnx', 'remove', -1, null],
      );
      expect(out, isNull);
    });

    test('onnx image job with an unusable model returns null (all ops)',
        () async {
      final photo = _solid(8, 8, 90, 90, 90);
      final bytes = img.encodePng(photo);
      for (final op in [
        kOnnxOpMatte,
        kOnnxOpMatteBiref,
        kOnnxOpMatteCutout,
        kOnnxOpEsrgan,
        kOnnxOpBokeh,
        kOnnxOpStyle,
      ]) {
        final out = onnxImageIsolateJob(
          <dynamic>[op, '/nonexistent/model.onnx', bytes, null],
        );
        expect(out, isNull, reason: 'op $op must fail soft');
      }
    });

    test('onnx migan job without strokes returns null', () async {
      final photo = _solid(8, 8, 90, 90, 90);
      final bytes = img.encodePng(photo);
      final out = onnxImageIsolateJob(
        <dynamic>[kOnnxOpMigan, '/nonexistent/model.onnx', bytes, null],
      );
      expect(out, isNull);
    });

    test('off-thread runner with no pack on disk returns null', () async {
      final photo = _solid(8, 8, 90, 90, 90);
      final out = await runOnnxOpOffThread(
        op: kOnnxOpMatte,
        packId: 'modnet',
        inputBytes: img.encodePng(photo),
      );
      expect(out, isNull);
    });

    test('RIFE job reports the <2 frames error instead of throwing',
        () async {
      final dir = await Directory.systemTemp.createTemp('rife_test_');
      try {
        final err = rifeInterpolateIsolateJob(
          <dynamic>[dir.path, dir.path, '/nonexistent/rife.onnx', 32, 32, 32, 32],
        );
        expect(err, contains('2 frames'));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('RIFE job with frames but unusable model returns an error line',
        () async {
      final dir = await Directory.systemTemp.createTemp('rife_test2_');
      try {
        final frame = _solid(32, 32, 50, 60, 70);
        final bytes = img.encodePng(frame);
        await File('${dir.path}/frame_0001.png').writeAsBytes(bytes);
        await File('${dir.path}/frame_0002.png').writeAsBytes(bytes);
        final err = rifeInterpolateIsolateJob(
          <dynamic>[dir.path, dir.path, '/nonexistent/rife.onnx', 32, 32, 32, 32],
        );
        expect(err, isNotNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('G5 — stabilization bake model', () {
    test('level → vidstab params keep the historical mapping', () {
      expect(stabParamsForLevel(1), (3, 15));
      expect(stabParamsForLevel(2), (5, 30));
      expect(stabParamsForLevel(3), (8, 60));
    });

    test('stabBakeMatches requires path + source + level', () {
      final c = VideoClip(File('/v/a.mp4'), const Duration(seconds: 5), 1.5);
      expect(c.stabBakeMatches('/v/a.mp4', 2), isFalse);
      c.stabBakedPath = '/bakes/stab_x.mp4';
      c.stabBakedFor = '/v/a.mp4';
      c.stabBakedLevel = 2;
      expect(c.stabBakeMatches('/v/a.mp4', 2), isTrue);
      expect(c.stabBakeMatches('/v/a.mp4', 3), isFalse);
      expect(c.stabBakeMatches('/v/other.mp4', 2), isFalse);
      expect(c.stabBakeMatches('/v/a.mp4', 0), isFalse);
    });

    test('copyWithFile carries every field incl. the bake', () {
      final c = VideoClip(File('/v/a.mp4'), const Duration(seconds: 7), 1.5)
        ..trimStart = 1
        ..trimEnd = 6
        ..volume = 0.5
        ..muted = true
        ..disabled = true
        ..colorLabel = 3
        ..detachedAudioPath = '/a/det.m4a'
        ..stabBakedPath = '/bakes/s.mp4'
        ..stabBakedFor = '/v/a.mp4'
        ..stabBakedLevel = 2;
      final n = c.copyWithFile(File('/bakes/s.mp4'));
      expect(n.file.path, '/bakes/s.mp4');
      expect(n.trimStart, 1);
      expect(n.trimEnd, 6);
      expect(n.volume, 0.5);
      expect(n.muted, isTrue);
      expect(n.disabled, isTrue);
      expect(n.colorLabel, 3);
      expect(n.detachedAudioPath, '/a/det.m4a');
      expect(n.stabBakedPath, '/bakes/s.mp4');
      expect(n.stabBakedFor, '/v/a.mp4');
      expect(n.stabBakedLevel, 2);
    });

    test('session map round-trips the bake pointers', () {
      final c = VideoClip(File('/v/a.mp4'), const Duration(seconds: 7), 1.5)
        ..stabBakedPath = '/bakes/s.mp4'
        ..stabBakedFor = '/v/a.mp4'
        ..stabBakedLevel = 3;
      final back = VideoEditorSession.clipFromMap(
        VideoEditorSession.clipToMap(c),
      );
      expect(back, isNotNull);
      expect(back!.stabBakedPath, '/bakes/s.mp4');
      expect(back.stabBakedFor, '/v/a.mp4');
      expect(back.stabBakedLevel, 3);
    });
  });

  group('G5 — first-run preparation', () {
    test('item list is derived from the pack registry + assets', () {
      final items = FirstRunPrepService.items();
      final packItems = items.where((i) => i.id.startsWith('pack:')).toList();
      expect(packItems.length, ModelPackService.packs.length);
      for (final pack in ModelPackService.packs) {
        expect(
          items.any((i) => i.id == 'pack:${pack.id}'),
          isTrue,
          reason: 'pack ${pack.id} must be in the prep list',
        );
      }
      expect(items.any((i) => i.id == 'whisper'), isTrue);
      expect(items.any((i) => i.id == 'kasheeda'), isTrue);
      expect(items.any((i) => i.id == 'translate'), isTrue);
      for (final i in items) {
        expect(i.weightBytes, greaterThan(0));
        expect(i.label, isNotEmpty);
      }
    });

    test('overall progress is byte-weighted', () {
      // Two items of equal weight, one done → 0.5.
      expect(FirstRunPrepService.overallFor([1, 0], [100, 100]), 0.5);
      // Heavy item dominates: 300 done of 300+100 → 0.75.
      expect(FirstRunPrepService.overallFor([1, 0], [300, 100]), 0.75);
      // Fractions clamp.
      expect(FirstRunPrepService.overallFor([2, 0], [100, 100]), 0.5);
      expect(FirstRunPrepService.overallFor([], []), 1);
    });
  });

  // ---------------------------------------------------------------
  group('G2 — one chip line per panel (Point #33)', () {
    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return '/tmp/tj_pro_v1170';
          }
          if (call.method == 'getApplicationSupportDirectory') {
            return '/tmp/tj_pro_v1170';
          }
          if (call.method == 'getTemporaryDirectory') {
            return '/tmp/tj_pro_v1170_tmp';
          }
          return null;
        },
      );
      Directory('/tmp/tj_pro_v1170').createSync(recursive: true);
      Directory('/tmp/tj_pro_v1170_tmp').createSync(recursive: true);
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> pumpVe(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: VideoEditorScreen()));
      await frames(tester);
      expect(tester.takeException(), isNull);
    }

    Future<void> openTool(WidgetTester tester, String label) async {
      final target = find.descendant(
        of: find.byType(MainToolRow),
        matching: find.text(label),
      );
      for (var i = 0; i < 14 && target.evaluate().isEmpty; i++) {
        for (final rail in find.byType(ListView).evaluate()) {
          await tester.drag(find.byWidget(rail.widget), const Offset(-240, 0));
        }
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(target, findsWidgets, reason: 'VE tool $label not found');
      await tester.ensureVisible(target.first);
      await frames(tester);
      await tester.tap(target.first);
      await frames(tester);
    }

    testWidgets(
        'Effects: tab rail only — no second drill rail, body flat',
        (tester) async {
      await pumpVe(tester);
      await openTool(tester, 'Effect');
      // The tab rail is present with both tabs…
      final tabRow = find.byType(PanelTabRow);
      expect(tabRow, findsOneWidget);
      expect(
        find.descendant(of: tabRow, matching: find.text('Effects')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tabRow, matching: find.text('Tracking')),
        findsOneWidget,
      );
      // …and it is the ONLY chip line: no drill rail under it.
      expect(find.byKey(const Key('panelDrillDown')), findsNothing);
      // The body renders flat: the shake section + its control
      // are right there (the empty 'Effects' section is gone).
      expect(find.text('Shake effect'), findsOneWidget);
      expect(find.text('Shake intensity'), findsOneWidget);
      // Switching tabs swaps the body; still no drill rail.
      await tester.tap(
        find.descendant(of: tabRow, matching: find.text('Tracking')),
      );
      await frames(tester);
      expect(find.text('Shake effect'), findsNothing);
      expect(find.byKey(const Key('panelDrillDown')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Stabilizer panel: bake-first UI renders + selects',
        (tester) async {
      await pumpVe(tester);
      await openTool(tester, 'Stabilizer');
      expect(
        find.textContaining('renders right away'),
        findsOneWidget,
      );
      await tester.tap(find.text('Standard'));
      await frames(tester);
      // No clips: nothing to bake, so the panel reports the
      // baked state instead of offering export-time processing.
      expect(find.textContaining('assembly only'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  // ---------------------------------------------------------------
  group('G3 — VE text style (Point #34)', () {
    test('drawtext defaults are byte-identical to the old graph', () {
      final g = FfmpegService.finalFilterGraph(
        speed: 1,
        filterPreset: 'Original',
        aspect: 'Original',
        text: 'Hello',
        fontFile: '/f.ttf',
        videoHeight: 720,
      );
      expect(
        g,
        contains(
          "drawtext=fontfile=/f.ttf:text='Hello':fontsize=40:"
          'fontcolor=white:borderw=3:bordercolor=black'
          ':x=(w-text_w)/2:y=h-text_h-60',
        ),
      );
    });

    test('drawtext honours size scale, colour and the pill box', () {
      final g = FfmpegService.finalFilterGraph(
        speed: 1,
        filterPreset: 'Original',
        aspect: 'Original',
        text: 'Hello',
        fontFile: '/f.ttf',
        videoHeight: 720,
        textSizeScale: 2,
        textColorHex: 'ffd740',
        textBox: true,
      );
      expect(g, contains(':fontsize=80:fontcolor=ffd740:'));
      expect(g, contains(':box=1:boxcolor=black@0.5:boxborderw=12'));
    });

    testWidgets('Text panel: font/size/colour/background all wired',
        (tester) async {
      final host = _FakeTextHost();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LegacyTextPanel(host)),
          ),
        ),
      );
      await tester.pump();
      // The options that never showed before (Point #34b):
      // five sections (Text overlay / Font / Size / Colour /
      // Background).
      expect(
        find.descendant(
          of: find.byType(LegacyTextPanel),
          matching: find.byType(SectionTitle),
        ),
        findsNWidgets(5),
      );
      expect(find.text('Font'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Background'), findsOneWidget);
      // Font chip → state.
      await tester.tap(find.text('Jameel Noori Nastaleeq'));
      await tester.pump();
      expect(host.textFontId, 'jameel_kasheeda');
      // Colour circle → state.
      final red = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                const Color(0xFFFF5252),
      );
      expect(red, findsOneWidget);
      await tester.tap(red);
      await tester.pump();
      expect(host.textColorArgb, 0xFFFF5252);
      // Background pill → state.
      await tester.tap(find.widgetWithText(SwitchListTile, 'Background pill'));
      await tester.pump();
      expect(host.textBgPill, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stage layer: styled render, tap selects, pinch resizes',
        (tester) async {
      final host = _FakeTextHost();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                StageTextLayer(host: host, frameSize: const Size(400, 300)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final textWidget = tester.widget<Text>(find.text('Hello'));
      expect(textWidget.style?.fontSize, 22);
      expect(textWidget.style?.color, const Color(0xFFFFFFFF));
      // Tap → select + open the Text tab.
      await tester.tap(find.byKey(const Key('stageTextLayer')));
      await tester.pump();
      expect(host.stageLayer, 'text');
      expect(host.openedTool, 'text');
      expect(host.openedTab, 'text');
      // Pinch out → the size scale grows (and the value is the
      // panel slider's value too).
      final centre = tester.getCenter(find.byKey(const Key('stageTextLayer')));
      final g1 = await tester.startGesture(centre + const Offset(-18, 0));
      final g2 = await tester.startGesture(centre + const Offset(18, 0));
      await g1.moveBy(const Offset(-42, 0));
      await g2.moveBy(const Offset(42, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();
      expect(host.textSizeScale, greaterThan(1.5));
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------
  group('G3 — Motion text layers (Point #34)', () {
    MotionScene twoTextScene() => const MotionScene(
          width: 1280,
          height: 720,
          durationSec: 4,
          layers: [
            MotionLayer(
              id: 'a',
              type: MotionLayerType.text,
              x: 640,
              y: 360,
              text: 'AAAA',
              fontSize: 100,
            ),
            MotionLayer(
              id: 'b',
              type: MotionLayerType.text,
              x: 640,
              y: 360,
              text: 'BB',
              fontSize: 100,
            ),
          ],
        );

    test('hit test: topmost layer wins; background misses', () {
      final scene = twoTextScene();
      final hit = motionLayerAtPoint(
        scene: scene,
        t: 0,
        point: const Offset(640, 360),
        viewSize: const Size(1280, 720),
      );
      expect(hit?.id, 'b');
      final miss = motionLayerAtPoint(
        scene: scene,
        t: 0,
        point: const Offset(8, 8),
        viewSize: const Size(1280, 720),
      );
      expect(miss, isNull);
      // Reordered (a on top) → a wins the same point.
      final flipped = MotionScene(
        width: 1280,
        height: 720,
        durationSec: 4,
        layers: [scene.layers[1], scene.layers[0]],
      );
      final hit2 = motionLayerAtPoint(
        scene: flipped,
        t: 0,
        point: const Offset(640, 360),
        viewSize: const Size(1280, 720),
      );
      expect(hit2?.id, 'a');
    });

    testWidgets('editor: tapping the preview selects the tapped layer',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final template = MotionTemplate(
        id: 't1',
        name: 'T',
        category: 'News',
        tier: MotionTier.free,
        scene: twoTextScene(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MotionEditorScreen(template: template)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Initially layer 'a' is selected (first) — its text field.
      expect(find.byKey(const Key('motionTextField-a')), findsOneWidget);
      // Tap the canvas centre: both layers live there; the top
      // one ('b') must become the selection, with its controls.
      final canvas = find.byKey(const Key('motionEditorCanvas'));
      expect(canvas, findsOneWidget);
      await tester.tapAt(tester.getCenter(canvas));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('motionTextField-b')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  // ---------------------------------------------------------------
  group('G4 — NS preview (Points #35/#36)', () {
    test('notch follows the logo overrides (dy + scale)', () {
      final preset = ParityGeometry(
        1080,
        1920,
        variant: ParityVariant.final3,
      );
      final base = mediaLogoNotch(g: preset, scaleW: 0.5, scaleH: 0.5);
      expect(base.top, preset.logoVisible.top * 0.5);
      expect(base.left, preset.logoVisible.left * 0.5);
      final moved = ParityGeometry(
        1080,
        1920,
        variant: ParityVariant.final3,
        overrides: const {
          NewsElement.logo: ElementOverride(dy: 0.05, scale: 1.5),
        },
      );
      final notch2 = mediaLogoNotch(g: moved, scaleW: 0.5, scaleH: 0.5);
      // The old replicated math ignored dy and scale entirely:
      // the notch must move DOWN and GROW with the overrides.
      expect(notch2.top, greaterThan(base.top));
      expect(notch2.width, greaterThan(base.width));
      expect(notch2.top, moved.logoVisible.top * 0.5);
    });

    test('clip path: media covers the band but never the logo block', () {
      final path = mainAreaClipPath(
        width: 400,
        top: 0,
        bottom: 600,
        notchTop: 500,
        notchLeft: 300,
      );
      expect(path.contains(const Offset(200, 300)), isTrue);
      expect(path.contains(const Offset(350, 300)), isTrue);
      // Inside the logo notch (right, below notchTop) → clipped out.
      expect(path.contains(const Offset(350, 550)), isFalse);
    });

    test('export graph: media is the base, the logo overlays LAST', () {
      final g = ParityGeometry(1080, 1920, variant: ParityVariant.final3);
      final assets = ParityAssets(
        geometry: g,
        ribbons: [
          for (var i = 0; i < 3; i++)
            ParityRibbonAssets(bg: File('/r$i.png'), y: i * 100.0),
        ],
        capBar: File('/capbar.png'),
        capDate: File('/capdate.png'),
        topRibbon: null,
      );
      final cmd = buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assets,
        logoStillPng: '/logo.png',
        clockFontFile: null,
        exportStart: DateTime(2026, 11, 26),
      );
      // Media is input 0 — the base every overlay stacks on.
      expect(cmd.startsWith("-y -i '/in.mp4'"), isTrue);
      // Steps in graph order: the three ribbon overlays come
      // first (at the y positions the assets carry), and the
      // FINAL overlay step — the one the output maps — is the
      // logo still (its x is the geometry's logo left edge).
      final steps = cmd.split(';');
      final overlays = [
        for (final st in steps)
          if (st.contains('overlay=')) st,
      ];
      expect(overlays.length, greaterThanOrEqualTo(4));
      expect(overlays[0], contains('overlay=0:0'));
      expect(overlays[1], contains('overlay=0:100'));
      expect(overlays[2], contains('overlay=0:200'));
      final last = overlays.last;
      final outLabel =
          RegExp(r'\[(p\d+)\]').allMatches(last).last.group(1);
      expect(cmd, contains('-map "[$outLabel]"'));
      expect(last, contains('overlay=${g.logoVisible.left}'));
    });

    Future<void> pumpMaker(WidgetTester tester, NewsProject project) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const png = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
      ];
      File('/tmp/tj_pro_v1170/a.png').writeAsBytesSync(png);
      File('/tmp/tj_pro_v1170/b.png').writeAsBytesSync(png);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }

    Finder goldFrame() => find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final b = d.border;
          return b != null && b.top.color == const Color(0xFFF5C542);
        });

    testWidgets('no permanent gold frame; Elements tool shows it; '
        'tap on headline opens Tehreer', (tester) async {
      final project = NewsProject.create()
        ..clipPaths = ['/tmp/tj_pro_v1170/a.png', '/tmp/tj_pro_v1170/b.png'];
      await pumpMaker(tester, project);
      // Point #35a: the default preview is CLEAN.
      expect(goldFrame(), findsNothing);
      // Tap the headline band → its tool opens (Point #35b).
      final preview = find.byType(TemplateMediaPreview);
      expect(preview, findsOneWidget);
      final pSize = tester.getSize(preview);
      final pTopLeft = tester.getTopLeft(preview);
      final rects = finalElementRects(
        preset: ChannelPreset.nigraanTv(),
        overrides: project.elementOverrides,
        w: pSize.width,
        h: pSize.height,
      );
      final headline = rects[NewsElement.headlineText]!;
      await tester.tapAt(pTopLeft + headline.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('makerPanel-tehreer')), findsOneWidget);
      // Still no frame (Tehreer is not the Elements tool).
      expect(goldFrame(), findsNothing);
      // Open the Elements tool → the frame appears for editing.
      final dock = find.byKey(const Key('makerTool-elements'));
      for (var i = 0; i < 12 && dock.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byKey(const Key('makerToolLine')),
          const Offset(-240, 0),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(dock);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(goldFrame(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinch on the media zooms it (override scale grows)',
        (tester) async {
      final project = NewsProject.create()
        ..clipPaths = ['/tmp/tj_pro_v1170/a.png', '/tmp/tj_pro_v1170/b.png'];
      await pumpMaker(tester, project);
      final preview = find.byType(TemplateMediaPreview);
      final centre = tester.getCenter(preview) + const Offset(0, -120);
      final g1 = await tester.startGesture(centre + const Offset(-16, 0));
      final g2 = await tester.startGesture(centre + const Offset(16, 0));
      await g1.moveBy(const Offset(-46, 0));
      await g2.moveBy(const Offset(46, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();
      final scale =
          project.elementOverrides[NewsElement.media]?.scale ?? 1;
      expect(scale, greaterThan(1.2));
      expect(tester.takeException(), isNull);
    });
  });
}

/// A text host for the G3 widget tests: only the members the
/// panel and the stage layer touch are real; everything else
/// falls through noSuchMethod.
class _FakeTextHost extends VideoEditorController {
  @override
  void update(VoidCallback fn) => fn();

  @override
  BuildContext get context =>
      throw UnimplementedError('not used by these widgets');

  @override
  String text = 'Hello';

  @override
  String? stageLayer;

  String? openedTool;
  String? openedTab;

  @override
  void openToolTab(String key, String tab) {
    openedTool = key;
    openedTab = tab;
  }

  @override
  String textFontId = '';

  @override
  double textSizeScale = 1.0;

  @override
  int textColorArgb = 0xFFFFFFFF;

  @override
  bool textBgPill = false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}