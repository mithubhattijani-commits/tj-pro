// Build 12 (v1.9.0) — the News Studio round + banner fix.
//
//   #11 RemoteConfigService refreshes on EVERY cold start;
//       HeroBannerCache revalidates under the same URL and
//       only replaces on a byte difference.
//   #12 Logo CUBE engine: shared geometry (visible-face
//       rules, painter's order), continuous full-turn angle,
//       and real generated cube frames (pixel-different at
//       0° / 90° / 180°, alpha corners).
//   #13 Logo VIDEO: border-colour detection (pure sampler),
//       preset/template field round-trips, unkeyed-video
//       overlay command.
//   #9a Store audio in the Maker's Audio panel (seeded owned
//       item: playable row + select writes the project).
//   #14 Voice music toggle + pad switch, dynamic caption
//       chips, logo source toggle, visual font chips, and
//       the responsive sweep: every Maker panel at
//       360×640 / 393×852 / 430×932 with zero render errors.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/hero_banner_cache.dart';
import 'package:tj_pro/services/logo_cube.dart';
import 'package:tj_pro/services/logo_key_service.dart';
import 'package:tj_pro/services/logo_loop_service.dart';
import 'package:tj_pro/services/reel_export_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/store_service.dart';

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

void _mockSecureStorageFreshCache() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      if (call.method == 'read') {
        final args = call.arguments;
        final key = args is Map ? args['key']?.toString() : null;
        if (key == 'tjpro_remote_config_json_v1') return '{}';
        if (key == 'tjpro_remote_config_time_v1') {
          // A FRESH cache (seconds old) — the pre-Build-12 code
          // would NOT refresh here; Build 12 must.
          return DateTime.now().millisecondsSinceEpoch.toString();
        }
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

Future<void> _openTool(WidgetTester tester, String id) async {
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
  // The tool line is a horizontal ListView: a tool can exist
  // in the tree (cache extent) while still off-viewport —
  // a tap at its centre would miss. Scroll it fully in
  // first. (Found by the Build 12 voice-panel test: the
  // button existed, the tap landed off-screen, no panel
  // ever opened.)
  await tester.ensureVisible(target);
  await _frames(tester);
  await tester.tap(target);
  await _frames(tester);
}

/// A tiny real PNG with a coloured square (a decodable logo).
Future<File> _makeLogoPng(Directory dir) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 128, 128),
    ui.Paint()..color = const ui.Color(0xFF2266CC),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(16, 16, 40, 40),
    ui.Paint()..color = const ui.Color(0xFFFFCC00),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 128);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/logo.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

Future<ui.Image> _decode(File f) async {
  final codec = await ui.instantiateImageCodec(await f.readAsBytes());
  return (await codec.getNextFrame()).image;
}

int _alphaAt(ui.Image img, Uint8List rgba, int x, int y) =>
    rgba[(y * img.width + x) * 4 + 3];

void main() {
  group('point #11 — RemoteConfigService refreshes every cold start',
      () {
    tearDown(() {
      RemoteConfigService.refreshOverrideForTest = null;
    });

    test('init refreshes even with a FRESH cached config', () async {
      _mockSecureStorageFreshCache();
      var refreshes = 0;
      RemoteConfigService.refreshOverrideForTest = () async {
        refreshes++;
      };
      final service = RemoteConfigService();
      await service.init();
      // init backgrounds the refresh — let it land.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(refreshes, 1);
      // A second cold start refreshes again (no 6h gate).
      await service.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(refreshes, 2);
    });
  });

  group('point #11 — HeroBannerCache revalidation', () {
    late Directory tempDir;
    late List<int> jpegA;
    late List<int> jpegB;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tj_b12_hero_');
      HeroBannerCache.overrideDirForTest = tempDir;
      HeroBannerCache.resetForTest();
      jpegA = await File('assets/hero_nigraan_banner.jpg').readAsBytes();
      jpegB = await File('assets/jaani_ad_banner.jpg').readAsBytes();
      expect(HeroBannerCache.bytesEqual(jpegA, jpegB), isFalse);
    });

    tearDown(() async {
      HeroBannerCache.downloaderForTest = null;
      HeroBannerCache.overrideDirForTest = null;
      HeroBannerCache.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('identical bytes: no rewrite, no revision bump', () async {
      HeroBannerCache.downloaderForTest = (_) async => jpegA;
      await HeroBannerCache.instance
          .warm(HeroBannerCache.slot1, 'https://x.test/b.jpg');
      final file = HeroBannerCache.instance
          .cachedFileFor(HeroBannerCache.slot1, 'https://x.test/b.jpg')!;
      final mtime = file.statSync().modified;
      final revisionBefore = HeroBannerCache.instance.revision.value;

      await HeroBannerCache.instance
          .refresh(HeroBannerCache.slot1, 'https://x.test/b.jpg');
      expect(HeroBannerCache.instance.revision.value, revisionBefore);
      expect(file.statSync().modified, mtime);
      expect(await file.readAsBytes(), jpegA);
    });

    test('different bytes under the SAME URL replace the cache',
        () async {
      var serveB = false;
      HeroBannerCache.downloaderForTest =
          (_) async => serveB ? jpegB : jpegA;
      await HeroBannerCache.instance
          .warm(HeroBannerCache.slot2, 'https://x.test/b.jpg');
      final revisionBefore = HeroBannerCache.instance.revision.value;

      serveB = true;
      await HeroBannerCache.instance
          .refresh(HeroBannerCache.slot2, 'https://x.test/b.jpg');
      expect(
        HeroBannerCache.instance.revision.value,
        revisionBefore + 1,
      );
      final file = HeroBannerCache.instance
          .cachedFileFor(HeroBannerCache.slot2, 'https://x.test/b.jpg')!;
      expect(await file.readAsBytes(), jpegB);
    });

    test('warm with a cached copy still revalidates in background',
        () async {
      var downloads = 0;
      HeroBannerCache.downloaderForTest = (_) async {
        downloads++;
        return jpegA;
      };
      await HeroBannerCache.instance
          .warm(HeroBannerCache.slotSplash, 'https://x.test/p.jpg');
      expect(downloads, 1);
      await HeroBannerCache.instance
          .warm(HeroBannerCache.slotSplash, 'https://x.test/p.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(downloads, 2);
    });
  });

  group('point #12 — cube geometry', () {
    List<LogoCubeFace> facesAt(double angle) => logoCubeFaces(
          angleY: angle,
          center: const Offset(100, 100),
          size: 160,
          textureWidth: 256,
          textureHeight: 256,
        );

    test('angle 0: front + top visible; back + bottom hidden', () {
      final faces = facesAt(0).map((f) => f.face).toSet();
      expect(faces, contains(kCubeFaceFront));
      expect(faces, contains(kCubeFaceTop));
      expect(faces, isNot(contains(kCubeFaceBack)));
      expect(faces, isNot(contains(kCubeFaceBottom)));
    });

    test('half turn: the BACK face fronts the camera', () {
      final faces = facesAt(3.14159265).map((f) => f.face).toSet();
      expect(faces, contains(kCubeFaceBack));
      expect(faces, isNot(contains(kCubeFaceFront)));
    });

    test('quarter turn: a side face fronts the camera', () {
      final faces = facesAt(3.14159265 / 2).map((f) => f.face).toSet();
      expect(faces, contains(kCubeFaceLeft));
      expect(faces, isNot(contains(kCubeFaceFront)));
    });

    test('faces are sorted far-to-near (painter order)', () {
      final faces = facesAt(0.6);
      for (var i = 1; i < faces.length; i++) {
        expect(faces[i].depth, lessThanOrEqualTo(faces[i - 1].depth));
      }
    });

    test('projection stays inside a sane box around the centre', () {
      // The projected silhouette of a unit cube at focal 3.2
      // can reach ~0.95× the edge — the bound proves the
      // projection never explodes or flips to infinity.
      for (final angle in [0.0, 0.7, 1.6, 3.1, 4.2, 5.5]) {
        for (final face in facesAt(angle)) {
          for (final c in face.corners) {
            expect((c.dx - 100).abs(), lessThan(160 * 1.05));
            expect((c.dy - 100).abs(), lessThan(160 * 1.05));
          }
        }
      }
    });

    test('front face is the brightest at angle 0', () {
      final faces = facesAt(0);
      final front = faces.firstWhere((f) => f.face == kCubeFaceFront);
      for (final f in faces) {
        expect(f.brightness, lessThanOrEqualTo(front.brightness));
      }
    });
  });

  group('point #12 — generated cube frames are real 3D', () {
    test('frames at 0° / 90° / 180° differ; corners stay alpha',
        () async {
      final dir = await Directory.systemTemp.createTemp('tj_b12_cube_');
      final logo = await _makeLogoPng(dir);
      final outDir = Directory('${dir.path}/loop');
      final frames = await LogoLoopService.generateFrames(
        logoFile: logo,
        outDir: outDir,
      );
      expect(frames.length, kLogoLoopFrameCount);

      Future<Uint8List> rgbaOf(File f) async {
        final img = await _decode(f);
        final data = await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return data!.buffer.asUint8List();
      }

      final img0 = await _decode(frames[0]);
      final rgba0 = await rgbaOf(frames[0]);
      final rgba12 = await rgbaOf(frames[12]);
      final rgba24 = await rgbaOf(frames[24]);
      // Transparent corners (the cube floats over the video).
      expect(_alphaAt(img0, rgba0, 2, 2), 0);
      expect(_alphaAt(img0, rgba0, 509, 2), 0);
      // Opaque cube body near the centre.
      expect(_alphaAt(img0, rgba0, 256, 256), greaterThan(200));
      // The three angles are three DIFFERENT pictures.
      expect(rgba0, isNot(rgba12));
      expect(rgba0, isNot(rgba24));
      expect(rgba12, isNot(rgba24));
      await dir.delete(recursive: true);
    });
  });

  group('point #13 — logo key detection (pure sampler)', () {
    Uint8List frame({
      required int borderArgb,
      bool noisyBorder = false,
      int size = 64,
    }) {
      final bytes = Uint8List(size * size * 4);
      var seed = 7;
      int nextRand() {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return seed % 256;
      }

      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final i = (y * size + x) * 4;
          final onBorder = x < 3 || y < 3 || x >= size - 3 || y >= size - 3;
          if (onBorder && !noisyBorder) {
            bytes[i] = (borderArgb >> 16) & 0xFF;
            bytes[i + 1] = (borderArgb >> 8) & 0xFF;
            bytes[i + 2] = borderArgb & 0xFF;
          } else {
            bytes[i] = nextRand();
            bytes[i + 1] = nextRand();
            bytes[i + 2] = nextRand();
          }
          bytes[i + 3] = 0xFF;
        }
      }
      return bytes;
    }

    test('a solid green border detects as that green, solidity 1',
        () {
      final sampled = LogoKeyService.sampleBorderColor(
        frame(borderArgb: 0xFF10C81C),
        64,
        64,
      );
      expect(sampled, isNotNull);
      expect(sampled!.argb, 0xFF10C81C);
      expect(sampled.solidity, greaterThan(0.99));
      expect(
        sampled.solidity,
        greaterThanOrEqualTo(LogoKeyDetection.minSolidity),
      );
    });

    test('a noisy border is NOT a solid background', () {
      final sampled = LogoKeyService.sampleBorderColor(
        frame(borderArgb: 0xFF10C81C, noisyBorder: true),
        64,
        64,
      );
      expect(sampled, isNotNull);
      expect(
        sampled!.solidity,
        lessThan(LogoKeyDetection.minSolidity),
      );
    });

    test('a solid BLUE border detects too (any colour keys)', () {
      final sampled = LogoKeyService.sampleBorderColor(
        frame(borderArgb: 0xFF0033CC),
        64,
        64,
      );
      expect(sampled!.argb, 0xFF0033CC);
      expect(LogoKeyService.keyHex(sampled.argb), '0x0033CC');
      expect(LogoKeyService.displayHex(sampled.argb), '#0033CC');
    });

    test('too-small frames are unjudgeable (null)', () {
      expect(
        LogoKeyService.sampleBorderColor(Uint8List(4 * 4 * 4), 4, 4),
        isNull,
      );
    });
  });

  group('points #12/#13 — logo fields round-trip everywhere', () {
    test('ChannelPreset JSON keeps the video logo + key state', () {
      final preset = ChannelPreset.nigraanTv()
        ..logoMediaKind = 'video'
        ..logoVideoPath = '/tmp/logo.mp4'
        ..logoVideoKeyColor = 0xFF10C81C
        ..logoKeyedFramesDir = '/tmp/keyed'
        ..logoVideoStillPath = '/tmp/still.png';
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.logoMediaKind, 'video');
      expect(restored.logoVideoPath, '/tmp/logo.mp4');
      expect(restored.logoVideoKeyColor, 0xFF10C81C);
      expect(restored.logoKeyedFramesDir, '/tmp/keyed');
      expect(restored.logoVideoStillPath, '/tmp/still.png');
      // Old JSON (keys absent) loads as the image source.
      final legacy = preset.toJson()
        ..remove('logoMediaKind')
        ..remove('logoVideoPath')
        ..remove('logoVideoKeyColor')
        ..remove('logoKeyedFramesDir')
        ..remove('logoVideoStillPath');
      final old = ChannelPreset.fromJson(legacy);
      expect(old.logoMediaKind, 'image');
      expect(old.logoVideoPath, isNull);
    });

    test('BreakingTemplate carries the fields preset ↔ template',
        () {
      final preset = ChannelPreset.nigraanTv()
        ..logoMediaKind = 'video'
        ..logoVideoPath = '/tmp/logo.mp4'
        ..logoVideoKeyColor = 0xFF0033CC
        ..logoKeyedFramesDir = '/tmp/keyed'
        ..logoVideoStillPath = '/tmp/still.png';
      final template = BreakingTemplate.fromPreset(preset);
      expect(template.logoMediaKind, 'video');
      expect(template.logoVideoPath, '/tmp/logo.mp4');
      expect(template.logoVideoKeyColor, 0xFF0033CC);

      final target = ChannelPreset.nigraanTv();
      template.applyToPreset(target);
      expect(target.logoMediaKind, 'video');
      expect(target.logoVideoPath, '/tmp/logo.mp4');
      expect(target.logoKeyedFramesDir, '/tmp/keyed');

      final restored = BreakingTemplate.fromJson(template.toJson());
      expect(restored.logoMediaKind, 'video');
      expect(restored.logoVideoStillPath, '/tmp/still.png');
    });

    test('unkeyed logo video overlays via the videoPath command',
        () {
      final cmd = FfmpegService.logoLoopOverlayCommand(
        input: '/tmp/base.mp4',
        output: '/tmp/out.mp4',
        width: 720,
        height: 1280,
        topRibbonEnabled: true,
        videoPath: '/tmp/logo video.mp4',
      );
      expect(cmd, contains("-stream_loop -1 -i '/tmp/logo video.mp4'"));
      expect(cmd, contains('overlay='));
      // The looped input is bounded to the base's duration
      // (without shortest=1 the graph never terminates).
      expect(cmd, contains(':shortest=1'));
      expect(cmd, contains('-shortest'));
      // Exactly-one-source is enforced.
      expect(
        () => FfmpegService.logoLoopOverlayCommand(
          input: '/tmp/base.mp4',
          output: '/tmp/out.mp4',
          width: 720,
          height: 1280,
          topRibbonEnabled: true,
          videoPath: '/tmp/a.mp4',
          framesDir: '/tmp/frames',
        ),
        throwsAssertionError,
      );
    });
  });

  group('points #9a/#14f — project music fields', () {
    test('store music + voice music toggle JSON round-trip', () {
      final project = NewsProject.create()
        ..storeMusicPath = '/tmp/store track.mp3'
        ..storeMusicName = 'Store Track'
        ..voiceMusicEnabled = false;
      final restored = NewsProject.fromJson(project.toJson());
      expect(restored.storeMusicPath, '/tmp/store track.mp3');
      expect(restored.storeMusicName, 'Store Track');
      expect(restored.voiceMusicEnabled, isFalse);

      // Legacy JSON: toggle defaults ON (historic behaviour).
      final legacy = NewsProject.create().toJson()
        ..remove('voiceMusicEnabled')
        ..remove('storeMusicPath')
        ..remove('storeMusicName');
      final old = NewsProject.fromJson(legacy);
      expect(old.voiceMusicEnabled, isTrue);
      expect(old.storeMusicPath, isNull);
    });

    test('copyWith can clear the store pick', () {
      final project = NewsProject.create()
        ..storeMusicPath = '/tmp/a.mp3'
        ..storeMusicName = 'A';
      final cleared = project.copyWith(clearStoreMusic: true);
      expect(cleared.storeMusicPath, isNull);
      expect(cleared.storeMusicName, isNull);
    });
  });

  group('point #14g — dynamic captions burn through the ASS engine',
      () {
    NewsProject captionedProject(String styleId) {
      return NewsProject.create()
        ..captionStyleId = styleId
        ..subtitles = [
          SubtitleLine(
            text: 'pehla dusra teesra',
            startSec: 0,
            endSec: 3,
            words: [
              SubtitleWord(word: 'pehla', startSec: 0, endSec: 1),
              SubtitleWord(word: 'dusra', startSec: 1, endSec: 2),
              SubtitleWord(word: 'teesra', startSec: 2, endSec: 3),
            ],
          ),
        ];
    }

    test('pop style: one Dialogue per word at the word timings',
        () {
      final ass = ReelExportService.styledAssForProject(
        project: captionedProject('bold_pop'),
        playResX: 1080,
        playResY: 1920,
      )!;
      final dialogues =
          ass.split('\n').where((l) => l.startsWith('Dialogue:')).toList();
      expect(dialogues.length, 3);
      expect(dialogues[0], contains('PEHLA'));
      expect(dialogues[1], contains('DUSRA'));
      expect(dialogues[2], contains('TEESRA'));
    });

    test('karaoke style: \\kf sweep carries the word durations',
        () {
      final ass = ReelExportService.styledAssForProject(
        project: captionedProject('karaoke_fill'),
        playResX: 1080,
        playResY: 1920,
      )!;
      expect(ass, contains('{\\kf100}'));
      expect(ass, contains('pehla'));
    });
  });

  group('Maker panels — Build 12 controls + responsive sweep', () {
    const tools = [
      'template',
      'media',
      'elements',
      'tehreer',
      'ticker',
      'ribbons',
      'logo',
      'reporter',
      'audio',
      'voice',
      'captions',
      'export',
    ];

    setUpAll(() {
      _mockPathProvider('/tmp/tj_pro_b12');
      Directory('/tmp/tj_pro_b12').createSync(recursive: true);
      Directory('/tmp/tj_pro_b12_tmp').createSync(recursive: true);
      // The Maker constructs an AudioRecorder whose internal
      // 'create' call has no error handler — harmless in the
      // fake-async zone (the future never completes), but the
      // seeded-audio test below flushes REAL async via
      // runAsync, which completes it as a
      // MissingPluginException. Mock the channel so create
      // simply succeeds.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (MethodCall call) async => null,
      );
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // StoreService caches the owned list in memory — drop
      // it so each test's seeded preferences are what the
      // Maker's Audio panel actually reads.
      StoreService.instance.resetOwnedCacheForTest();
    });

    Future<void> pumpMaker(
      WidgetTester tester, {
      NewsProject? project,
      Size size = const Size(393, 852),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project ?? NewsProject.create(),
          ),
        ),
      );
      await _frames(tester);
    }

    for (final size in [
      const Size(360, 640),
      const Size(393, 852),
      const Size(430, 932),
    ]) {
      testWidgets('all 12 panels render clean at ${size.width}x'
          '${size.height}', (tester) async {
        await pumpMaker(tester, size: size);
        for (final tool in tools) {
          await _openTool(tester, tool);
          expect(
            tester.takeException(),
            isNull,
            reason: 'render exception in $tool at $size',
          );
        }
      });
    }

    // NOTE: this empty-state test runs BEFORE the seeded one
    // below — StoreService caches the owned list in memory
    // for the life of the process.
    testWidgets('Audio panel without owned items offers the '
        'Store door (point #9a)', (tester) async {
      await pumpMaker(tester);
      await _openTool(tester, 'audio');
      await tester.drag(
        find.byKey(const Key('makerPanel-audio')),
        const Offset(0, -300),
      );
      await _frames(tester);
      expect(
        find.byKey(const Key('audioStoreOpenButton')),
        findsOneWidget,
      );
      // The built-in music selection lives here now too.
      expect(find.byKey(const Key('audioMusic-none')), findsOneWidget);
      expect(
        find.byKey(const Key('audioMusic-news_music_1')),
        findsOneWidget,
      );
    });

    testWidgets('Audio panel shows owned store audio; select '
        'writes the project (point #9a)', (tester) async {
      // Seed one owned Music item whose file exists.
      final musicFile = File('/tmp/tj_pro_b12/store_track.mp3')
        ..writeAsBytesSync(List<int>.filled(64, 0));
      SharedPreferences.setMockInitialValues({
        'tjpro_store_owned_v1': jsonEncode([
          {
            'id': 'store-audio-1',
            'name': 'Epic News Bed.mp3',
            'category': 'Music',
            'local_path': musicFile.path,
            'price_paid': 30,
            'owned_at': '2026-11-25T00:00:00.000',
          },
        ]),
      });
      final project = NewsProject.create();
      await pumpMaker(tester, project: project);
      // _loadStoreAudio awaits REAL file IO (ownedItems
      // checks each file exists) — fake-async pumps never
      // complete it. Flush in a real async zone, then pump
      // the setState through.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _frames(tester);
      await _openTool(tester, 'audio');
      // The store section sits below the built-in chips —
      // scroll the panel to it.
      await tester.drag(
        find.byKey(const Key('makerPanel-audio')),
        const Offset(0, -300),
      );
      await _frames(tester);
      expect(
        find.byKey(const Key('audioStorePlay-store-audio-1')),
        findsOneWidget,
      );
      final select = find.byKey(const Key('audioStoreSelect-store-audio-1'));
      expect(select, findsOneWidget);
      await tester.ensureVisible(select);
      await _frames(tester);
      await tester.tap(select);
      await _frames(tester);
      expect(project.storeMusicPath, musicFile.path);
      expect(project.storeMusicName, 'Epic News Bed');
      expect(
        find.byKey(const Key('audioMusicStatus')),
        findsOneWidget,
      );
    });

    testWidgets('Voice panel: music toggle gates the export '
        'bed; pad switch kept (point #14f)', (tester) async {
      final project = NewsProject.create();
      await pumpMaker(tester, project: project);
      await _openTool(tester, 'voice');
      await tester.drag(
        find.byKey(const Key('makerPanel-voice')),
        const Offset(0, -260),
      );
      await _frames(tester);
      final toggle = find.byKey(const Key('voiceMusicSwitch'));
      expect(toggle, findsOneWidget);
      expect(find.byKey(const Key('voicePadSwitch')), findsOneWidget);
      expect(project.voiceMusicEnabled, isTrue);
      await tester.ensureVisible(toggle);
      await _frames(tester);
      await tester.tap(toggle);
      await _frames(tester);
      expect(project.voiceMusicEnabled, isFalse);
      // The pad field is untouched by the bed toggle.
      expect(project.voiceMusic, isFalse);
    });

    testWidgets('Logo panel: source toggle swaps image ↔ video '
        '(points #12/#13)', (tester) async {
      await pumpMaker(tester);
      await _openTool(tester, 'logo');
      expect(find.byKey(const Key('logoSourceToggle')), findsOneWidget);
      expect(find.byKey(const Key('logoPickButton')), findsOneWidget);
      expect(find.byKey(const Key('logoRotateSwitch')), findsOneWidget);
      await tester.tap(find.text('Video logo'));
      await _frames(tester);
      expect(
        find.byKey(const Key('logoVideoPickButton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('logoStatusText')), findsOneWidget);
    });

    testWidgets('Captions panel: dynamic style chips write the '
        'project style (point #14g)', (tester) async {
      final project = NewsProject.create();
      await pumpMaker(tester, project: project);
      await _openTool(tester, 'captions');
      final chip = find.byKey(const Key('captionDyn-bold_pop'));
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await _frames(tester);
      await tester.tap(chip);
      await _frames(tester);
      expect(project.captionStyleId, 'bold_pop');
      expect(find.byKey(const Key('captionsButton')), findsOneWidget);
    });

    testWidgets('Media panel: ONE unified picker entry '
        '(point #14d)', (tester) async {
      await pumpMaker(tester);
      await _openTool(tester, 'media');
      expect(find.byKey(const Key('mediaAddButton')), findsOneWidget);
      // The three old buttons are NOT in the panel anymore —
      // they live in the unified sheet.
      expect(find.byKey(const Key('addClipGallery')), findsNothing);
      await tester.tap(find.byKey(const Key('mediaAddButton')));
      await _frames(tester);
      expect(find.byKey(const Key('addClipGallery')), findsOneWidget);
      expect(find.byKey(const Key('addClipFiles')), findsOneWidget);
      expect(find.byKey(const Key('addClipPhoto')), findsOneWidget);
    });

    testWidgets('Font chips render the font name IN the font '
        '(point #14e)', (tester) async {
      await pumpMaker(tester);
      await _openTool(tester, 'tehreer');
      final chip = find.byKey(const Key('fontChoice-jameel_kasheeda'));
      expect(chip, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)).first,
      );
      // The Kasheeda chip shows its Urdu name set in the
      // Kasheeda family itself.
      expect(label.data, 'جمیل نوری نستعلیق');
      expect(label.style?.fontFamily, 'JameelNooriNastaleeqKasheeda');
    });
  });
}
