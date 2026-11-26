// Tools-fix wave (2026-11-25) — FUNCTIONAL regression tests.
//
// The audit's process lesson: wiring tests (does the button
// exist) let dead tools ship for months. These tests prove
// RESULTS instead: a split yields two clips with the expected
// durations, a teleprompter recording actually lands in the
// project, the ticker-direction VALUE reaches the generated
// ffmpeg command, PIP settings reach the export, NS trims reach
// the export's normalize arguments, the NS preview keeps its
// size with a tool open (Point #27), and wave-2's F2/F3/F4
// derivations agree with the services they mirror.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/coins_screen.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/project_handoff.dart';
import 'package:tj_pro/news/widgets/styled_caption_preview.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/fx_pack.dart';
import 'package:tj_pro/services/photo_pipeline.dart';
import 'package:tj_pro/services/pricing_service.dart';
import 'package:tj_pro/services/reel_export_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/store_service.dart';
import 'package:tj_pro/video/adjust_params.dart';
import 'package:tj_pro/video/editor_models.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';

void main() {
  group('P0-2 VE Split — the playhead decision', () {
    test('split at the strip centre yields the expected halves', () {
      final clips = [
        VideoClip(File('/a.mp4'), const Duration(seconds: 10), 1.0),
        VideoClip(File('/b.mp4'), const Duration(seconds: 20), 1.0),
      ];
      final res = resolveSplit(
        effectiveDurations: [for (final c in clips) c.effectiveDuration],
        trimStarts: [for (final c in clips) c.trimStart],
        selected: 1,
        clockInsideSelected: 0,
        centreSec: 25, // the playhead sits 15 s into clip 2
      );
      expect(res, isNotNull);
      expect(res!.index, 1);
      expect(res.atPlayhead, isTrue);
      expect(res.cutFileSec, 15);
      // Apply the screen's trim math (unchanged by the fix).
      final second = VideoClip(clips[1].file, clips[1].duration, 1.0)
        ..trimStart = res.cutFileSec
        ..trimEnd = clips[1].effectiveEnd;
      clips[1].trimEnd = res.cutFileSec;
      clips.insert(2, second);
      expect(
        [for (final c in clips) c.effectiveDuration],
        [10.0, 15.0, 5.0],
      );
    });

    test('centre over ANOTHER clip: THAT clip is cut (v1.15 G1.3)',
        () {
      // v1.15 behaviour change (user order + diagnosis): Split
      // cuts the clip UNDER the line — the selection follows the
      // line. The old code cut the stale selection by the clock
      // and could even claim "playhead par kata" falsely.
      final res = resolveSplit(
        effectiveDurations: const [10, 20],
        trimStarts: const [0, 0],
        selected: 1,
        clockInsideSelected: 8,
        centreSec: 5,
      );
      expect(res!.index, 0);
      expect(res.atPlayhead, isTrue);
      expect(res.cutFileSec, 5);
    });

    test('edge position is REFUSED — no midpoint fallback (G1.2)',
        () {
      // The old disclosed-midpoint fallback was the cascade: after
      // a split the line sits exactly on the new boundary, so each
      // extra tap halved the remainder. Now it refuses honestly.
      final res = resolveSplit(
        effectiveDurations: const [20],
        trimStarts: const [0],
        selected: 0,
        clockInsideSelected: 0.05,
      );
      expect(res!.refusal, SplitRefusal.atEdge);
    });

    test('line exactly on a boundary refuses instead of cascading',
        () {
      // Two clips; the line sits exactly on their boundary (10s).
      // indexAtSec puts it at the START of clip 2 → inside = 0 →
      // atEdge refusal. Before the fix this cut clip 2's midpoint.
      final res = resolveSplit(
        effectiveDurations: const [10, 20],
        trimStarts: const [0, 0],
        selected: 0,
        clockInsideSelected: 0,
        centreSec: 10,
      );
      expect(res!.index, 1);
      expect(res.refusal, SplitRefusal.atEdge);
    });

    test('midpoint mode cuts the SELECTED clip in half (G1.5)',
        () {
      final res = resolveSplit(
        effectiveDurations: const [10, 20],
        trimStarts: const [0, 0],
        selected: 1,
        clockInsideSelected: 3,
        centreSec: 5, // ignored in midpoint mode
        playheadMode: false,
      );
      expect(res!.index, 1);
      expect(res.atPlayhead, isFalse);
      expect(res.cutFileSec, 10);
    });

    test('a sub-0.3 s clip cannot split', () {
      final res = resolveSplit(
        effectiveDurations: const [0.2],
        trimStarts: const [0],
        selected: 0,
        clockInsideSelected: 0.1,
      );
      expect(res!.refusal, SplitRefusal.tooSmall);
    });

    test('invalid inputs return null', () {
      expect(
        resolveSplit(
          effectiveDurations: const [],
          trimStarts: const [],
          selected: 0,
          clockInsideSelected: 0,
        ),
        isNull,
      );
    });

    test('an already-trimmed clip splits inside its own window', () {
      final res = resolveSplit(
        effectiveDurations: const [10],
        trimStarts: const [30],
        selected: 0,
        clockInsideSelected: 4,
      );
      expect(res!.cutFileSec, 34);
    });
  });

  group('P0-1 teleprompter path — addClips result is applied', () {
    test('the recorded path actually grows the project', () {
      final p = NewsProject.create();
      expect(p.clipPaths, isEmpty);
      final res = p.addClips(['/recordings/teleprompter.mp4']);
      p.setClipPaths(res.clips);
      expect(res.droppedByCap, 0);
      expect(p.clipPaths, ['/recordings/teleprompter.mp4']);
      expect(p.clipTrims.length, 1);
    });

    test('the 20-clip cap drops honestly instead of pretending', () {
      final p = NewsProject.create()
        ..setClipPaths([for (var i = 0; i < 20; i++) '/c/$i.mp4']);
      final res = p.addClips(['/recordings/teleprompter.mp4']);
      expect(res.droppedByCap, 1);
      expect(res.clips.contains('/recordings/teleprompter.mp4'), isFalse);
    });
  });

  group('P0-3 NS export switches reach the export', () {
    test('Breaking Banner switch OFF wins over the template flag', () {
      // The dead switch: the user picks a breaking template
      // (project.breaking = true) then turns the banner OFF in
      // the Template panel (preset.showBreakingBanner = false).
      // The export preset must carry the SWITCH, not the flag.
      final preset = ChannelPreset.nigraanTv()..showBreakingBanner = false;
      final p = NewsProject(id: 'x', breaking: true);
      final eff = effectivePresetFor(project: p, preset: preset);
      expect(eff.showBreakingBanner, isFalse);
    });

    test('ticker direction: project value overrides the preset', () {
      final p = NewsProject(id: 'x')..tickerDirection = 'ltr';
      final eff = effectivePresetFor(
        project: p,
        preset: ChannelPreset.nigraanTv(),
      );
      expect(eff.topRibbon.direction, RibbonDirection.ltr);
      // Unset: the preset's own direction survives untouched.
      final p2 = NewsProject(id: 'y');
      final eff2 = effectivePresetFor(
        project: p2,
        preset: ChannelPreset.nigraanTv(),
      );
      expect(
        eff2.topRibbon.direction,
        ChannelPreset.nigraanTv().topRibbon.direction,
      );
    });

    test('the direction VALUE reaches the generated ffmpeg command', () {
      ParityAssets assets({required bool scrollRight}) => ParityAssets(
            geometry: ParityGeometry(1080, 1920),
            ribbons: [
              ParityRibbonAssets(
                bg: File('/tmp/bg.png'),
                y: 100,
                strip: File('/tmp/strip.png'),
                period: 200,
                scrollRight: scrollRight,
                windowW: 1000,
                chipW: 0,
              ),
            ],
            capBar: File('/tmp/bar.png'),
            capDate: File('/tmp/date.png'),
            topRibbon: null,
          );
      String cmd(bool rtl) => buildParityTemplateCommand(
            input: '/tmp/in.mp4',
            output: '/tmp/out.mp4',
            assets: assets(scrollRight: rtl),
            clockFontFile: null,
            exportStart: DateTime(2026, 1, 1),
          );
      final rtl = cmd(true);
      final ltr = cmd(false);
      // RTL strip advances (+mod), LTR retreats (−mod) — the two
      // commands must differ exactly in the motion formula.
      expect(rtl, contains('+mod(t*'));
      expect(rtl, isNot(contains('-mod(t*')));
      expect(ltr, contains('-mod(t*'));
      expect(ltr, isNot(contains('+mod(t*')));
    });

    test('PIP settings + source file reach the handoff and the pass',
        () async {
      final dir = await Directory.systemTemp.createTemp('tjpro_pip');
      final pip = File('${dir.path}/pip.mp4')..writeAsBytesSync([0]);
      final clip = File('${dir.path}/c.mp4')..writeAsBytesSync([0]);
      final preset = ChannelPreset(
        id: 't',
        name: 'T',
        pipEnabled: true,
        pipPosition: 'bottomRight',
        pipScale: 0.4,
      );
      final p = NewsProject(id: 'x')
        ..setClipPaths([clip.path])
        ..pipVideoPath = pip.path;
      final h = buildHandoff(project: p, preset: preset);
      expect(h.pipEnabled, isTrue);
      expect(h.pipPosition, PipPosition.bottomRight);
      expect(h.pipScale, 0.4);
      expect(h.pipVideoPath, pip.path);
      final cmd = ReelExportService.pipPassCommand(
        input: 'main.mp4',
        pipPath: h.pipVideoPath!,
        output: 'out.mp4',
        position: h.pipPosition,
        scale: h.pipScale,
      );
      expect(cmd, contains('iw*0.4'));
      expect(cmd, contains('W-w-24'));
      expect(cmd, contains('H-h-24'));
      // A missing source file is dropped, never exported broken.
      final p2 = NewsProject(id: 'y')
        ..setClipPaths([clip.path])
        ..pipVideoPath = '/gone/pip.mp4';
      expect(buildHandoff(project: p2, preset: preset).pipVideoPath, isNull);
    });
  });

  group('P1-3 NS trims — model, handoff, export arguments', () {
    test('trims reach the handoff and the normalize arguments', () async {
      final dir = await Directory.systemTemp.createTemp('tjpro_trim');
      final clip = File('${dir.path}/c.mp4')..writeAsBytesSync([0]);
      final p = NewsProject.create()..setClipPaths([clip.path]);
      p.clipTrims[0] = const ClipTrim(startSec: 5, endSec: 12);
      expect(p.clipEffectiveDurationAt(0, 40), 7);
      final h = buildHandoff(project: p);
      expect(h.trimAt(0).startSec, 5);
      expect(h.trimAt(0).endSec, 12);
      // The exact arguments reel_export_service passes since
      // the fix (was the hardcoded 0 / 3600).
      final cmd = FfmpegService.normalizeCommand(
        input: clip.path,
        output: 'o.mp4',
        width: 720,
        height: 1280,
        trimStart: h.trimAt(0).startSec,
        trimEnd: h.trimAt(0).endSec ?? 3600,
      );
      expect(cmd, contains('-ss 5'));
      expect(cmd, contains('-to 12'));
    });

    test('serialization: roundtrip keeps trims; old JSON loads full-range',
        () {
      final p = NewsProject.create()..setClipPaths(['/a.mp4', '/b.mp4']);
      p.clipTrims[1] = const ClipTrim(startSec: 2, endSec: 9);
      final back = NewsProject.fromJson(p.toJson());
      expect(back.trimAt(0).isFullRange, isTrue);
      expect(back.trimAt(1).startSec, 2);
      expect(back.trimAt(1).endSec, 9);
      // A pre-trim project file (no clipTrims key at all).
      final oldJson = p.toJson()..remove('clipTrims');
      final old = NewsProject.fromJson(oldJson);
      expect(old.clipTrims.length, 2);
      expect(old.trimAt(1).isFullRange, isTrue);
    });

    test('a split keeps both halves’ ranges through a reorder', () {
      final p = NewsProject.create()..setClipPaths(['/a.mp4']);
      p.clipTrims[0] = const ClipTrim(startSec: 10, endSec: 30);
      // Split at file-second 20 (the maker's split operation).
      final t = p.trimAt(0);
      p.setClipPaths(['/a.mp4', '/a.mp4']);
      p.clipTrims[0] = ClipTrim(startSec: t.startSec, endSec: 20);
      p.clipTrims[1] = ClipTrim(startSec: 20, endSec: t.endSec);
      // Reorder the halves — occurrence-based reconcile keeps
      // each half's own range with its own position.
      p.setClipPaths(['/a.mp4', '/a.mp4']);
      expect(p.trimAt(0).endSec, 20);
      expect(p.trimAt(1).startSec, 20);
    });
  });

  group('P1-1 Adjust — one derivation for preview and export', () {
    test('the export chain is byte-identical for known values', () {
      expect(adjustExtraFilterChain(const AdjustValues()), '');
      expect(
        adjustExtraFilterChain(const AdjustValues(brilliance: 50)),
        'eq=gamma=1.189:saturation=1.125',
      );
      expect(
        adjustExtraFilterChain(const AdjustValues(sharpen: 50)),
        'unsharp=5:5:1',
      );
      expect(
        adjustExtraFilterChain(const AdjustValues(grain: 50)),
        'noise=alls=20:allf=t',
      );
      expect(
        adjustExtraFilterChain(const AdjustValues(vignette: 50)),
        'vignette=angle=0.95',
      );
      expect(
        adjustExtraFilterChain(const AdjustValues(hue: 90)),
        'hue=h=90',
      );
    });

    test('the preview matrix is derived from the same params', () {
      // Neutral → identity.
      final id = adjustPreviewMatrix(const AdjustValues());
      const identity = [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
      for (var i = 0; i < 20; i++) {
        expect(id[i], closeTo(identity[i], 1e-6), reason: 'element $i');
      }
      // Hue 180°: the standard hue-rotate matrix's first element
      // (0.213 + cos·0.787 − sin·0.213 = −0.574).
      final hue = adjustPreviewMatrix(const AdjustValues(hue: 180));
      expect(hue[0], closeTo(-0.574, 0.01));
      // Blacks +100 lifts the offsets (the fitted curve's
      // intercept) and compresses the gains below 1.
      final lifted = adjustPreviewMatrix(const AdjustValues(blacks: 100));
      expect(lifted[4], greaterThan(5));
      expect(lifted[0], lessThan(1));
      // The overlay strengths come from the same derivation.
      final p = deriveAdjustParams(const AdjustValues(vignette: 50, grain: 50));
      expect(p.vignetteStrength, 0.5);
      expect(p.grainAmount, 20);
      expect(p.grainOpacity, closeTo(0.175, 1e-9));
    });
  });

  group('F2 Store — Transitions + Text Styles surface end-to-end', () {
    test('category list, discovery, pricing and extensions', () {
      expect(
        StoreConfig.categories,
        containsAll(['Transitions', 'Text Styles']),
      );
      expect(StoreService.categoryForFolderName('Transitions'), 'Transitions');
      expect(
        StoreService.categoryForFolderName(' text styles '),
        'Text Styles',
      );
      expect(StoreService.categoryForFolderName('Random Folder'), isNull);
      final svc = StoreService.instance;
      // Folder-default pricing (10), FREE-in-name still free.
      expect(
        svc.priceFor(
          const StoreItem(id: '1', name: 'zoom.mp4', category: 'Transitions'),
        ),
        10,
      );
      expect(
        svc.priceFor(
          const StoreItem(
            id: '2',
            name: 'FREE zoom.mp4',
            category: 'Transitions',
          ),
        ),
        0,
      );
      expect(svc.isSupported('Transitions', 'a.mp4'), isTrue);
      expect(svc.isSupported('Text Styles', 'a.json'), isTrue);
      expect(svc.isSupported('Text Styles', 'a.mp4'), isFalse);
    });
  });

  group('F3 Photo HSL — values reach the export pipeline', () {
    test('params carry the adjustments; neutral detection is shared', () {
      const rows = [
        [0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 1.0, 0.0],
      ];
      expect(const PhotoEditParams(hslAdjustments: rows).hasHslAdjustments,
          isTrue);
      expect(const PhotoEditParams().hasHslAdjustments, isFalse);
      expect(hslAdjustmentsAreNeutral(null), isTrue);
      expect(hslAdjustmentsAreNeutral(rows), isFalse);
    });

    test('a desaturating HSL row changes the exported pixels', () async {
      final dir = await Directory.systemTemp.createTemp('tjpro_f3');
      final src = img.fill(
        img.Image(width: 8, height: 8),
        color: img.ColorRgb8(255, 0, 0),
      );
      final srcFile = File('${dir.path}/src.png')
        ..writeAsBytesSync(img.encodePng(src));
      // Control: no HSL → the red survives untouched.
      final plainPath = '${dir.path}/plain.png';
      await exportPhotoWithLayers(
        workingFile: srcFile,
        params: const PhotoEditParams(),
        layers: const [],
        outPath: plainPath,
        keepAlpha: false,
      );
      // keepAlpha=false exports JPEG bytes (the pipeline's own
      // rule) — decode format-agnostically.
      final plain = img.decodeImage(await File(plainPath).readAsBytes())!;
      expect(plain.getPixel(0, 0).r, closeTo(255, 3));
      expect(plain.getPixel(0, 0).g, closeTo(0, 3));
      // Red range saturation × 0 → the export must come out grey.
      final hslPath = '${dir.path}/hsl.png';
      await exportPhotoWithLayers(
        workingFile: srcFile,
        params: const PhotoEditParams(hslAdjustments: [
          [0.0, 0.0, 0.0], // red: kill saturation
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 1.0, 0.0],
        ]),
        layers: const [],
        outPath: hslPath,
        keepAlpha: false,
      );
      final out = img.decodeImage(await File(hslPath).readAsBytes())!;
      final px = out.getPixel(0, 0);
      expect(px.r, closeTo(px.g, 3));
      expect(px.r, lessThan(200));
    });
  });

  group('F4 Coins screen — prices derive from PricingService', () {
    String row(List<(String, String)> rows, String label) =>
        rows.firstWhere((r) => r.$1 == label).$2;

    test('defaults match the legacy charge prices', () {
      final rows = coinsPriceRows(config: const RemoteConfig(prices: {}));
      expect(row(rows, 'One Click AI News Maker'), '100 coins');
      expect(row(rows, 'Voiceover'), '50 coins');
      expect(row(rows, 'Chroma key'), '50 coins');
      expect(row(rows, 'Premium template'), '25 coins');
      // The stale row: was hardcoded '50 coins', real charge 25.
      expect(row(rows, 'AI Enhance (Photo / Video)'), '25 coins');
    });

    test('a remote price change moves the display with the charge', () {
      const cfg = RemoteConfig(prices: {
        'price_photo_ai': 40,
        'price_ns_chroma': 0,
        'price_ns_voiceover': 'pro',
      });
      final rows = coinsPriceRows(config: cfg);
      expect(row(rows, 'AI Enhance (Photo / Video)'), '40 coins');
      expect(row(rows, 'Chroma key'), 'FREE');
      expect(row(rows, 'Voiceover'), 'Pro ke liye shamil');
      // And it equals the service's own resolution of the key.
      final spec = PricingService.specOr(
        PricingService.keyPhotoAi,
        fallbackCoins: cfg.aiToolPriceCoins,
        config: cfg,
      );
      expect(row(rows, 'AI Enhance (Photo / Video)'), '${spec.coins} coins');
    });
  });

  _makerWidgetTests();
}

/// Widget-level proofs (P0-4 layout invariance + P1-2 captions
/// in the composed preview) — pumped with the same harness the
/// Build 13 panel tests use.
class _MakerHarness {
  static void mockChannels(String dir) {
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

  static Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  static Future<void> openTool(WidgetTester tester, String id) async {
    final target = find.byKey(Key('makerTool-$id'));
    for (var i = 0; i < 12; i++) {
      if (target.evaluate().isNotEmpty) {
        final rect = tester.getRect(target);
        if (rect.left >= 0 && rect.right <= 393) break;
      }
      await tester.drag(
        find.byKey(const Key('makerToolLine')),
        const Offset(-240, 0),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(target);
    await frames(tester);
  }
}

void _makerWidgetTests() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File logoFile;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('tjpro_tools_fix');
    _MakerHarness.mockChannels(tmp.path);
    logoFile = File('${tmp.path}/logo.png');
    await logoFile.writeAsBytes(
      <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
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
        home: NewsMakerScreen(initialPreset: preset, initialProject: project),
      ),
    );
    await _MakerHarness.frames(tester);
  }

  testWidgets('P0-4: the preview keeps its size with a tool open',
      (tester) async {
    await pumpMaker(tester, NewsProject.create());
    final zone = find.byKey(const Key('makerLowerZone'));
    expect(zone, findsOneWidget);
    final topBefore = tester.getTopLeft(zone).dy;
    final heightBefore = tester.getSize(zone).height;
    expect(find.byKey(const Key('tlPlayPause')), findsOneWidget);
    expect(find.text('PREVIEW'), findsOneWidget);

    await _MakerHarness.openTool(tester, 'media');
    expect(find.byKey(const Key('makerPanel-media')), findsOneWidget);
    // The timeline collapsed…
    expect(find.byKey(const Key('tlPlayPause')), findsNothing);
    // …the lower zone did not move or resize (so the preview
    // above it is exactly as big)…
    expect(tester.getTopLeft(zone).dy, closeTo(topBefore, 0.5));
    expect(tester.getSize(zone).height, closeTo(heightBefore, 0.5));
    // …and the composed preview is still mounted.
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P1-2: the composed preview shows the styled caption',
      (tester) async {
    final project = NewsProject.create()
      ..subtitles = [
        SubtitleLine(text: 'Caption test line', startSec: 0, endSec: 30),
      ];
    await pumpMaker(tester, project);
    expect(find.byKey(const Key('makerCaptionOverlay')), findsOneWidget);
    expect(find.byType(StyledCaptionPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
