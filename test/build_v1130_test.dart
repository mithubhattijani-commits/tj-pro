// TJ Pro v1.13.0 — the five change-groups' functional proofs.
//
// G1 (export ads AFTER completion): the shared count mapping;
//   plugin-call counting on the Unity channel (the pro_noads
//   harness pattern) proving showExportAds shows exactly the
//   mapped count and Pro still suppresses everything; and the
//   REAL News Studio ExportScreen driven through a FAILED
//   export, proving zero ad calls reach the plugin — with the
//   pre-v1.13.0 code this same flow called showExportAds BEFORE
//   the encode, so the plugin would have seen load+show calls.
// G2 (parity infinite-input audit, fix-list #15): the parity
//   graph's three endless logo inputs now carry shortest=1 on
//   their overlay steps + -shortest on the output (the runaway
//   was measured on host ffmpeg 8.1.2: a 2 s base + looped GS
//   input through the old graph never terminated; with the
//   bound it finishes at exactly the base duration). The sites
//   the audit found already-safe are pinned as they are.
// G3 (Home rows overflow): the full Home screen at 360dp and
//   393dp, scrolled end to end — no RenderFlex overflow may be
//   raised (before the fix, 393dp raised 18px on the Join Now
//   pill row and 41px on the Advertising WhatsApp row, and
//   360dp raised 10px on the cards' Open pill row).
// G4 (NS safe-area guides): the Maker's guides toggle paints
//   the Video Editor's StageGridPainter over the preview frame
//   and hides it again; the toggle is preview-only State, so
//   the project JSON is byte-identical with guides on or off
//   (the export renders from the project — guides cannot leak).
// G5 (VE Adjust "My Looks"): capture → persist → new-session
//   load → apply restores every value exactly; delete removes;
//   the panel section's save/apply/delete work end to end.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/app_config.dart';
import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/export_screen.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/coin_service.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/fx_pack.dart';
import 'package:tj_pro/services/pro_service.dart';
import 'package:tj_pro/services/reel_export_service.dart';
import 'package:tj_pro/services/unity_ads_service.dart';
import 'package:tj_pro/video/adjust_looks.dart';
import 'package:tj_pro/video/panels/adjust_panel.dart';
import 'package:tj_pro/video/video_editor_controller.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';

// ---------------------------------------------------------------------------
// Unity plugin mock (the pro_noads_guard_test harness, verbatim shape).
// ---------------------------------------------------------------------------

const MethodChannel _mainChannel = MethodChannel('com.rebeloid.unity_ads');
const String _mainChannelName = 'com.rebeloid.unity_ads';

final List<MethodCall> _calls = <MethodCall>[];

Future<void> _platformCallback(
  String channelName,
  String method,
  Object? arguments,
) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (ByteData? _) {},
      );
}

String _placementChannel(String placementId) =>
    'com.rebeloid.unity_ads/videoAd_$placementId';

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void _setPro({required bool active}) {
  ProService.instance.proUntil = active
      ? DateTime.now().add(const Duration(days: 1))
      : null;
  ProService.instance.isPro.value = active;
}

int _callsFor(String method, {String? placementId}) {
  return _calls.where((MethodCall c) {
    if (c.method != method) return false;
    if (placementId == null) return true;
    final Object? args = c.arguments;
    return args is Map && args['placementId'] == placementId;
  }).length;
}

int get _interstitialLoads => _callsFor(
      'load',
      placementId: AppConfig.unityInterstitialPlacementId,
    );

int get _interstitialShows => _callsFor(
      'showVideo',
      placementId: AppConfig.unityInterstitialPlacementId,
    );

void _installUnityMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_mainChannel, (MethodCall call) async {
    _calls.add(call);
    switch (call.method) {
      case 'init':
        unawaited(
          Future<void>(
            () => _platformCallback(_mainChannelName, 'initComplete', null),
          ),
        );
        return null;
      case 'load':
        final String id = (call.arguments as Map)['placementId'] as String;
        unawaited(
          Future<void>(
            () => _platformCallback(
              _placementChannel(id),
              'loadComplete',
              <String, dynamic>{'placementId': id},
            ),
          ),
        );
        return null;
      case 'showVideo':
        final String id = (call.arguments as Map)['placementId'] as String;
        unawaited(
          Future<void>(() async {
            await _platformCallback(
              _placementChannel(id),
              'showStart',
              <String, dynamic>{'placementId': id},
            );
            await _platformCallback(
              _placementChannel(id),
              'showComplete',
              <String, dynamic>{'placementId': id},
            );
          }),
        );
        return null;
    }
    return null;
  });
}

// ---------------------------------------------------------------------------
// G5 fake host: only the Adjust surface is real; everything else
// falls through noSuchMethod (never touched by capture/apply or
// by the My Looks section).
// ---------------------------------------------------------------------------

class _FakeAdjustHost extends VideoEditorController {
  @override
  void update(VoidCallback fn) => fn();

  @override
  String proLut = '';
  @override
  bool adjAuto = false;
  @override
  double adjBrilliance = 0;
  @override
  double adjSharpen = 0;
  @override
  double adjClarity = 0;
  @override
  double adjWhites = 0;
  @override
  double adjBlacks = 0;
  @override
  double adjHue = 0;
  @override
  double adjFade = 0;
  @override
  double adjVignette = 0;
  @override
  double adjGrain = 0;
  @override
  double proBrightness = 0;
  @override
  double proContrast = 1;
  @override
  double proSaturation = 1;
  @override
  double proVibrance = 1;
  @override
  double proTemperature = 0;
  @override
  double proTint = 0;
  @override
  double proHighlights = 0;
  @override
  double proShadows = 0;
  @override
  double proExposure = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('G1 — export-ad counts (shared mapping)', () {
    test('720p → 1, 1080p → 2, 4K → 2', () {
      expect(UnityAdsService.exportAdCountForQuality(0), 1);
      expect(UnityAdsService.exportAdCountForQuality(1), 2);
      expect(UnityAdsService.exportAdCountForQuality(2), 2);
    });
  });

  group('G1 — showExportAds plugin counting', () {
    setUpAll(_installUnityMock);
    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_mainChannel, null);
      _setPro(active: false);
    });

    setUp(() {
      _setPro(active: false);
      _calls.clear();
    });

    test('count 1 shows exactly one interstitial', () async {
      await UnityAdsService.showExportAds(1);
      await _flush();
      expect(_interstitialShows, 1);
      expect(_interstitialLoads, greaterThanOrEqualTo(1));
    });

    test('count 2 shows exactly two interstitials back-to-back',
        () async {
      await UnityAdsService.showExportAds(2);
      await _flush();
      expect(_interstitialShows, 2);
    });

    test('Pro suppresses the whole sequence (zero plugin calls)',
        () async {
      _setPro(active: true);
      _calls.clear();
      await UnityAdsService.showExportAds(2);
      await _flush();
      expect(_calls, isEmpty);
    });
  });

  group('G1 — NS ExportScreen: a FAILED export shows NO ad', () {
    setUpAll(_installUnityMock);
    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_mainChannel, null);
      _setPro(active: false);
    });

    testWidgets('no-clip export fails; plugin sees no load/show',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _setPro(active: false);
      final project = NewsProject(
        id: 'v1130-fail',
        voiceoverDurationSec: 42,
        templateKind: 'nigraanFinal',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(
            project: project,
            preset: ChannelPreset.nigraanTv(),
          ),
        ),
      );
      await tester.pump();
      CoinService.instance.balance.value = 1000;
      _calls.clear();
      await tester.tap(find.byKey(const Key('startExportButton')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      // The failure UI proves the export ran and failed.
      await tester.scrollUntilVisible(
        find.byKey(const Key('retryExportButton')),
        300,
      );
      await tester.pump();
      expect(find.textContaining('Koi clip nahi'), findsOneWidget);
      // The v1.13.0 rule: no completed export → no ad, not even
      // an attempted load on the interstitial placement.
      expect(_interstitialShows, 0);
      expect(_interstitialLoads, 0);
    });
  });

  // -------------------------------------------------------------------------
  // G2 — parity infinite-input audit (fix-list #15).
  // -------------------------------------------------------------------------

  group('G2 — parity graph: endless logo inputs are bounded', () {
    ParityAssets assets() => ParityAssets(
          geometry: ParityGeometry(720, 1280),
          ribbons: const [],
          capBar: File('/tmp/capbar.png'),
          capDate: File('/tmp/capdate.png'),
          topRibbon: null,
        );

    String build({
      String? logoGsPath,
      String? logoPingPongPath,
      String? logoFramesDir,
      String? logoStillPng,
    }) =>
        buildParityTemplateCommand(
          input: '/tmp/in.mp4',
          output: '/tmp/out.mp4',
          assets: assets(),
          logoGsPath: logoGsPath,
          logoPingPongPath: logoPingPongPath,
          logoFramesDir: logoFramesDir,
          logoStillPng: logoStillPng,
          clockFontFile: null,
          exportStart: DateTime(2026, 11, 25, 12),
        );

    int shortestCount(String cmd) => 'shortest=1'.allMatches(cmd).length;

    test('GS logo: looped input, overlay bounded, output bounded', () {
      final cmd = build(logoGsPath: '/tmp/logo-gs.mp4');
      expect(cmd, contains("-stream_loop -1 -i '/tmp/logo-gs.mp4'"));
      expect(cmd, contains('[gsout]overlay='));
      expect(shortestCount(cmd), 1);
      expect(cmd, contains('-shortest'));
      expect(cmd, isNot(contains('reverse')));
    });

    test('ping-pong cycle: both overlays bounded, no reverse', () {
      final cmd = build(logoPingPongPath: '/tmp/logo-cycle.mov');
      expect(cmd, contains("-stream_loop -1 -i '/tmp/logo-cycle.mov'"));
      expect(cmd, contains('[logoa]overlay='));
      expect(cmd, contains('[logob]overlay='));
      expect(shortestCount(cmd), 2);
      expect(cmd, contains('-shortest'));
      expect(cmd, isNot(contains('reverse')));
    });

    test('frames logo: looped image2 input, overlay bounded', () {
      final cmd = build(logoFramesDir: '/tmp/frames');
      expect(cmd, contains('-stream_loop -1'));
      expect(cmd, contains('[logof]overlay='));
      expect(shortestCount(cmd), 1);
      expect(cmd, contains('-shortest'));
    });

    test('still logo: finite input, no loop at all', () {
      final cmd = build(logoStillPng: '/tmp/logo.png');
      expect(cmd, isNot(contains('-stream_loop')));
    });
  });

  group('G2 — audit pins: the already-safe infinite-input sites', () {
    test('logoLoopOverlayCommand loops are shortest-bounded', () {
      final cmd = FfmpegService.logoLoopOverlayCommand(
        input: '/tmp/in.mp4',
        output: '/tmp/out.mp4',
        width: 720,
        height: 1280,
        topRibbonEnabled: true,
        pingPongPath: '/tmp/cycle.mov',
      );
      expect(cmd, contains('-stream_loop -1'));
      expect(cmd, contains('shortest=1'));
      expect(cmd, contains('-shortest'));
      expect(cmd, isNot(contains('reverse')));
    });

    test('logo green-screen commands are -t bounded', () {
      final cmd = FfmpegService.logoGreenScreenCommand(
        framesDir: '/tmp/frames',
        output: '/tmp/out.mp4',
        durationSec: 10,
      );
      expect(cmd, contains('-stream_loop -1'));
      expect(cmd, contains('-t 10.00'));
    });

    test('music beds are duration-bounded (first / -shortest)', () {
      final withAudio = FfmpegService.musicBedCommand(
        input: '/tmp/in.mp4',
        musicPath: '/tmp/bed.mp3',
        output: '/tmp/out.mp4',
        hasClipAudio: true,
      );
      expect(withAudio, contains('duration=first'));
      final noAudio = FfmpegService.musicBedCommand(
        input: '/tmp/in.mp4',
        musicPath: '/tmp/bed.mp3',
        output: '/tmp/out.mp4',
        hasClipAudio: false,
      );
      expect(noAudio, contains('-shortest'));
    });

    test('PIP pass is output-bounded', () {
      final cmd = ReelExportService.pipPassCommand(
        input: '/tmp/in.mp4',
        pipPath: '/tmp/pip.mp4',
        position: PipPosition.bottomRight,
        scale: 0.3,
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains('-stream_loop -1'));
      expect(cmd, contains('-shortest'));
    });

    test('ping-pong CYCLE render: reverse on a FINITE input only', () {
      final cmd = FfmpegService.logoPingPongCycleCommand(
        movPath: '/tmp/logo.mov',
        output: '/tmp/cycle.mov',
        cropW: 396,
        cropH: 316,
        cropX: 235,
        cropY: 86,
      );
      // The one legitimate in-graph reverse: its input is the
      // finite .mov (no -stream_loop anywhere in the command).
      expect(cmd, contains('reverse'));
      expect(cmd, isNot(contains('-stream_loop')));
    });
  });

  // -------------------------------------------------------------------------
  // G3 — Home rows overflow-proof at 360dp + 393dp.
  // -------------------------------------------------------------------------

  group('G3 — Home: no RenderFlex overflow at phone widths', () {
    for (final size in [const Size(360, 800), const Size(393, 852)]) {
      testWidgets('clean at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at first layout, $size',
        );
        // Scroll end to end so both banners (and every card row)
        // lay out at this width.
        for (var i = 0; i < 14; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow while scrolling (step $i), $size',
          );
        }
        // Both fixed banners really rendered on this pass.
        expect(find.text('Join Now'), findsWidgets);
        expect(find.text(AppConfig.supportWhatsAppNumber), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  // -------------------------------------------------------------------------
  // G4 — NS safe-area guides.
  // -------------------------------------------------------------------------

  group('G4 — News Studio preview safe-area guides', () {
    testWidgets('toggle paints StageGridPainter; project untouched',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final project = NewsProject.create();
      final jsonBefore = jsonEncode(project.toJson());
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('nsGuidesToggle')), findsOneWidget);
      expect(find.byKey(const Key('nsSafeGuides')), findsNothing);

      await tester.tap(find.byKey(const Key('nsGuidesToggle')));
      await tester.pump();
      expect(find.byKey(const Key('nsSafeGuides')), findsOneWidget);
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('nsSafeGuides')),
          matching: find.byType(CustomPaint),
        ),
      );
      // The very painter the Video Editor stage uses — reused,
      // not a copy.
      expect(paint.painter, isA<StageGridPainter>());
      // Preview-only: the project (the export's input) is
      // byte-identical with the guides on.
      expect(jsonEncode(project.toJson()), jsonBefore);

      await tester.tap(find.byKey(const Key('nsGuidesToggle')));
      await tester.pump();
      expect(find.byKey(const Key('nsSafeGuides')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // -------------------------------------------------------------------------
  // G5 — VE Adjust "My Looks".
  // -------------------------------------------------------------------------

  group('G5 — My Looks capture/apply (pure, over the controller)', () {
    test('capture reads exactly the Adjust state; apply restores it', () {
      final host = _FakeAdjustHost()
        ..proLut = 'Warm'
        ..adjAuto = true
        ..adjBrilliance = 25
        ..adjSharpen = 40
        ..adjClarity = 15
        ..adjWhites = -10
        ..adjBlacks = 20
        ..adjHue = 45
        ..adjFade = 30
        ..adjVignette = 55
        ..adjGrain = 12
        ..proBrightness = 18
        ..proContrast = 1.2
        ..proSaturation = 0.8
        ..proVibrance = 1.4
        ..proTemperature = -22
        ..proTint = 9
        ..proHighlights = -35
        ..proShadows = 28
        ..proExposure = 0.6;

      final look = captureAdjustLook(host, 'Test Look');
      expect(look.name, 'Test Look');
      expect(look.lut, 'Warm');
      expect(look.auto, isTrue);
      expect(look.brilliance, 25);
      expect(look.hue, 45);
      expect(look.saturation, 0.8);

      // A different editor state (the "next session") gets every
      // value back, exactly.
      final other = _FakeAdjustHost();
      applyAdjustLook(other, look);
      expect(captureAdjustLook(other, 'Test Look'), look);
    });

    test('JSON round-trip is lossless; corrupt payloads are empty', () {
      final look = captureAdjustLook(
        _FakeAdjustHost()
          ..adjGrain = 33
          ..proSaturation = 1.75,
        'Round Trip',
      );
      final decoded = AdjustLooksStore.decode(
        AdjustLooksStore.encode([look]),
      );
      expect(decoded, [look]);
      expect(AdjustLooksStore.decode(null), isEmpty);
      expect(AdjustLooksStore.decode('not json'), isEmpty);
      expect(AdjustLooksStore.decode('{"x":1}'), isEmpty);
    });
  });

  group('G5 — My Looks persistence (SharedPreferences)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('save → new-session load → delete', () async {
      final look = captureAdjustLook(
        _FakeAdjustHost()
          ..adjBrilliance = 61
          ..proExposure = -0.4,
        'Session Look',
      );
      await AdjustLooksStore.add(look);
      // A fresh load (what a new app session reads) returns it.
      expect(await AdjustLooksStore.load(), [look]);
      // Saving over the same name replaces, never duplicates.
      final updated = captureAdjustLook(
        _FakeAdjustHost()..adjBrilliance = 5,
        'Session Look',
      );
      await AdjustLooksStore.add(updated);
      final after = await AdjustLooksStore.load();
      expect(after, hasLength(1));
      expect(after.single.brilliance, 5);
      // Delete removes it for good.
      await AdjustLooksStore.remove('Session Look');
      expect(await AdjustLooksStore.load(), isEmpty);
    });
  });

  group('G5 — My Looks panel section (widget)', () {
    testWidgets('save → apply → delete, end to end', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final host = _FakeAdjustHost()
        ..adjBrilliance = 42
        ..proBrightness = 17;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MyLooksSection(host)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Abhi koi saved look nahi'), findsOneWidget);

      // Save the current settings under a name.
      await tester.tap(find.byKey(const Key('myLookSaveButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('myLookNameField')),
        'Mera Look',
      );
      await tester.tap(find.byKey(const Key('myLookSaveConfirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('myLookApply_Mera Look')), findsOneWidget);
      expect(await AdjustLooksStore.load(), hasLength(1));

      // Change the editor, then apply — values come back exactly.
      host.adjBrilliance = -90;
      host.proBrightness = -45;
      await tester.tap(find.byKey(const Key('myLookApply_Mera Look')));
      await tester.pump();
      expect(host.adjBrilliance, 42);
      expect(host.proBrightness, 17);

      // Delete — the row and the stored entry both go.
      await tester.tap(find.byKey(const Key('myLookDelete_Mera Look')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('myLookApply_Mera Look')), findsNothing);
      expect(await AdjustLooksStore.load(), isEmpty);
      // Drain the snackbars' timers before teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
