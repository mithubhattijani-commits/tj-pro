// Phase 9 unit + widget tests: export settings (quality / fps /
// bitrate / audio / aspect), size-estimate formula, ffmpeg command
// threading (real values, not labels), poster PNG render (decoded
// dimensions), autosave round-trip + project recovery, 20-clip cap,
// export failure naming the failed step, cancel, and the Export
// screen (settings change the estimate for real; a no-clip export
// fails with a Retry button).
//
// On-device limits (honest): no real ffmpeg run happens here — the
// VM has no device. What IS verified: every command string the
// export builds, the size formula, the PNG renders, the JSON
// round-trips and the screen wiring. Actual 4K timing / ExoPlayer
// playback need a real device (Phase 10).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/export_screen.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/project_handoff.dart';
import 'package:tj_pro/news/widgets/draft_recovery_card.dart';
import 'package:tj_pro/services/coin_service.dart';
import 'package:tj_pro/services/export_settings.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/poster_export_service.dart';
import 'package:tj_pro/services/project_recovery.dart';
import 'package:tj_pro/services/reel_export_service.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase9_test';
      }
      return null;
    },
  );
}

bool _isPng(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

Future<(int, int)> _pngDims(File file) async {
  final bytes = await file.readAsBytes();
  expect(_isPng(bytes), isTrue);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final dims = (frame.image.width, frame.image.height);
  frame.image.dispose();
  return dims;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _mockPathProvider();
    final dir = Directory('/tmp/tj_pro_phase9_test');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  group('ExportSettings — defaults + dims', () {
    test('quality labels + default bitrates per quality', () {
      expect(const ExportSettings().qualityLabel, '720p');
      expect(const ExportSettings(quality: 1).qualityLabel, '1080p');
      expect(const ExportSettings(quality: 2).qualityLabel, '4K');
      expect(ExportSettings.defaultVideoBitrateKbps(0), 2500);
      expect(ExportSettings.defaultVideoBitrateKbps(1), 5000);
      expect(ExportSettings.defaultVideoBitrateKbps(2), 12000);
      expect(ExportSettings.defaultAudioBitrateKbps, 128);
    });

    test('dims follow aspect + quality (same table as ffmpeg)', () {
      expect(const ExportSettings().dims, (720, 1280));
      expect(const ExportSettings(quality: 1).dims, (1080, 1920));
      expect(const ExportSettings(quality: 2).dims, (2160, 3840));
      expect(
        const ExportSettings(quality: 1, aspect: '16:9').dims,
        (1920, 1080),
      );
      expect(
        const ExportSettings(quality: 2, aspect: '1:1').dims,
        (2160, 2160),
      );
    });

    test('validation names the bad field', () {
      expect(const ExportSettings().isValid, isTrue);
      expect(
        const ExportSettings(fps: 25).error,
        contains('FPS'),
      );
      expect(
        const ExportSettings(videoBitrateKbps: 100).error,
        contains('Video bitrate'),
      );
      expect(
        const ExportSettings(audioBitrateKbps: 999).error,
        contains('Audio bitrate'),
      );
      expect(
        const ExportSettings(aspect: '4:3').error,
        contains('Aspect'),
      );
      expect(const ExportSettings(quality: 3).error, contains('Quality'));
    });
  });

  group('ExportSettings — size estimate formula', () {
    test('60s 720p default: duration x (2500+128) kbps / 8 + 1%', () {
      // 60 * 2628 * 1000 / 8 = 19,710,000 bytes; x1.01 = 19,907,100.
      expect(
        const ExportSettings().estimatedSizeBytes(60),
        19907100,
      );
      expect(
        const ExportSettings().estimatedSizeLabel(60),
        '19.0 MB',
      );
    });

    test('60s 4K default uses the 12 Mbps ladder', () {
      // 60 * 12128 * 1000 / 8 = 90,960,000; x1.01 = 91,869,600.
      expect(
        const ExportSettings(quality: 2).estimatedSizeBytes(60),
        91869600,
      );
    });

    test('explicit bitrates override the defaults', () {
      // 60 * 5192 * 1000 / 8 = 38,940,000; x1.01 = 39,329,400.
      expect(
        const ExportSettings(
          videoBitrateKbps: 5000,
          audioBitrateKbps: 192,
        ).estimatedSizeBytes(60),
        39329400,
      );
    });

    test('unknown duration = no estimate, never a made-up number', () {
      expect(const ExportSettings().estimatedSizeBytes(null), isNull);
      expect(const ExportSettings().estimatedSizeBytes(0), isNull);
      expect(const ExportSettings().estimatedSizeBytes(-5), isNull);
      expect(const ExportSettings().estimatedSizeLabel(null), isNull);
    });

    test('formatBytes units', () {
      expect(ExportSettings.formatBytes(320), '320 B');
      expect(ExportSettings.formatBytes(870400), '850 KB');
      expect(ExportSettings.formatBytes(19907100), '19.0 MB');
    });
  });

  group('FFmpeg commands — real settings, defaults unchanged', () {
    test('normalizeCommand default is exactly the Phase 7 command', () {
      final cmd = FfmpegService.normalizeCommand(
        input: '/tmp/in.mp4',
        trimStart: 0,
        trimEnd: 10,
        width: 720,
        height: 1280,
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains('fps=30,format=yuv420p'));
      expect(cmd, contains('-c:v libx264 -preset veryfast -crf 23'));
      expect(cmd, contains('-c:a aac -ar 48000 -ac 2'));
      expect(cmd, isNot(contains('-b:v')));
      // File-based flow: the command carries the PATH, no bytes.
      expect(cmd, contains("'/tmp/in.mp4'"));
      expect(cmd, contains("'/tmp/out.mp4'"));
    });

    test('normalizeCommand with settings carries fps + bitrates', () {
      final cmd = FfmpegService.normalizeCommand(
        input: '/tmp/in.mp4',
        trimStart: 0,
        trimEnd: 10,
        width: 1080,
        height: 1920,
        output: '/tmp/out.mp4',
        fps: 60,
        videoBitrateKbps: 5000,
        audioBitrateKbps: 192,
      );
      expect(cmd, contains('fps=60,format=yuv420p'));
      expect(cmd, contains('-b:v 5000k'));
      expect(cmd, contains('-maxrate 7500k'));
      expect(cmd, contains('-bufsize 10000k'));
      expect(cmd, contains('-b:a 192k'));
      expect(cmd, isNot(contains('crf 23')));
    });

    test('stillSegmentCommand + voiceoverMixCommand take settings', () {
      final still = FfmpegService.stillSegmentCommand(
        imagePath: '/tmp/card.png',
        durationSec: 3,
        width: 720,
        height: 1280,
        output: '/tmp/out.mp4',
        fps: 24,
        videoBitrateKbps: 2500,
        audioBitrateKbps: 128,
      );
      expect(still, contains('fps=24,format=yuv420p'));
      expect(still, contains('-b:v 2500k'));
      expect(still, contains('-b:a 128k'));

      final mix = FfmpegService.voiceoverMixCommand(
        input: '/tmp/in.mp4',
        voiceoverPath: '/tmp/vo.wav',
        output: '/tmp/out.mp4',
        hasClipAudio: true,
        audioBitrateKbps: 192,
      );
      expect(mix, contains('-b:a 192k'));
      final mixDefault = FfmpegService.voiceoverMixCommand(
        input: '/tmp/in.mp4',
        voiceoverPath: '/tmp/vo.wav',
        output: '/tmp/out.mp4',
        hasClipAudio: false,
      );
      expect(mixDefault, contains('-c:a aac -movflags'));
      expect(mixDefault, isNot(contains('-b:a')));
    });

    test('overlay + watermark passes take an explicit bitrate', () {
      final overlay = FfmpegService.overlayPassCommand(
        input: '/tmp/in.mp4',
        templatePngPath: '/tmp/t.png',
        output: '/tmp/out.mp4',
        videoBitrateKbps: 8000,
      );
      expect(overlay, isNotNull);
      expect(overlay!, contains('-b:v 8000k'));
      expect(overlay, isNot(contains('crf 23')));
      final overlayDefault = FfmpegService.overlayPassCommand(
        input: '/tmp/in.mp4',
        templatePngPath: '/tmp/t.png',
        output: '/tmp/out.mp4',
      );
      expect(overlayDefault!, contains('crf 23'));

      final wm = FfmpegService.watermarkOverlayCommand(
        input: '/tmp/in.mp4',
        watermarkPngPath: '/tmp/w.png',
        output: '/tmp/out.mp4',
        videoBitrateKbps: 5000,
      );
      expect(wm, contains('-b:v 5000k'));
    });
  });

  group('Poster export — real PNG, decoded dimensions', () {
    test('portrait poster is a 720x1280 PNG', () async {
      final dir =
          await Directory.systemTemp.createTemp('tj_pro_phase9_poster_');
      final project = NewsProject(
        id: 'poster-p',
        headline: 'Sheikhupura khabar',
        tickerText: 'Taza khabar',
      );
      final result = await PosterExportService.renderPoster(
        project: project,
        preset: ChannelPreset.nigraanTv(),
        size: PosterSize.portrait,
        dirOverride: dir,
      );
      expect(result.success, isTrue);
      expect(result.file, isNotNull);
      expect(await _pngDims(result.file!), (720, 1280));
    });

    test('landscape poster is a 1280x720 PNG', () async {
      final dir =
          await Directory.systemTemp.createTemp('tj_pro_phase9_poster_');
      final project = NewsProject(
        id: 'poster-l',
        headline: 'Sheikhupura khabar',
        tickerText: 'Taza khabar',
      );
      final result = await PosterExportService.renderPoster(
        project: project,
        preset: ChannelPreset.nigraanTv(),
        size: PosterSize.landscape,
        dirOverride: dir,
      );
      expect(result.success, isTrue);
      expect(result.file, isNotNull);
      expect(await _pngDims(result.file!), (1280, 720));
    });
  });

  group('Autosave round-trip + project recovery', () {
    test('edit -> save -> reload keeps the actual contents', () async {
      final project = NewsProject(
        id: 'phase9-autosave',
        tehreer: 'شیخوپورہ میں پولیس نے بڑی کارروائی کی۔',
        headline: 'Sheikhupura karwai',
        clipPaths: ['/tmp/c1.mp4', '/tmp/c2.mp4'],
        voiceoverDurationSec: 42,
        subtitles: [
          SubtitleLine(text: 'Line one', startSec: 0, endSec: 2),
          SubtitleLine(text: 'Line two', startSec: 2, endSec: 4),
        ],
      );
      await NewsProjectStore.save(project);
      final loaded = await NewsProjectStore.load('phase9-autosave');
      expect(loaded, isNotNull);
      expect(loaded!.tehreer, project.tehreer);
      expect(loaded.headline, 'Sheikhupura karwai');
      expect(loaded.clipPaths, ['/tmp/c1.mp4', '/tmp/c2.mp4']);
      expect(loaded.voiceoverDurationSec, 42);
      expect(loaded.subtitles, hasLength(2));
      expect(loaded.subtitles[1].text, 'Line two');

      final latest = await NewsProjectStore.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.id, 'phase9-autosave');
    });

    test('recovery: content draft is offered, empty project is not',
        () async {
      final draft = await NewsProjectStore.load('phase9-autosave');
      expect(isRecoverableDraft(draft), isTrue);
      final found = findRecoverableDraft(draft);
      expect(found, isNotNull);
      expect(found!.summary, contains('Sheikhupura karwai'));
      expect(found.summary, contains('2 clips'));
      expect(found.summary, contains('2 subtitles'));
      expect(found.project.id, 'phase9-autosave');

      expect(isRecoverableDraft(NewsProject(id: 'empty')), isFalse);
      expect(findRecoverableDraft(NewsProject(id: 'empty')), isNull);
      expect(isRecoverableDraft(null), isFalse);
      expect(findRecoverableDraft(null), isNull);
    });

    test('estimatedDurationSec: voiceover wins, else subtitles', () {
      expect(
        ReelExportService.estimatedDurationSec(
          NewsProject(id: 'd1', voiceoverDurationSec: 42.5),
        ),
        42.5,
      );
      expect(
        ReelExportService.estimatedDurationSec(
          NewsProject(id: 'd2', subtitles: [
            SubtitleLine(text: 'a', startSec: 0, endSec: 30),
          ]),
        ),
        30.0,
      );
      expect(
        ReelExportService.estimatedDurationSec(NewsProject(id: 'd3')),
        isNull,
      );
    });
  });

  group('20-clip cap (Phase 9 memory / long-project limit)', () {
    test('addClips caps at 20 and reports the dropped count', () {
      final project = NewsProject(id: 'cap');
      final picked =
          List<String>.generate(25, (i) => '/tmp/clip$i.mp4');
      final result = project.addClips(picked);
      expect(result.clips, hasLength(20));
      expect(result.droppedByCap, 5);
      expect(project.canAddClip, isTrue);

      final full = NewsProject(
        id: 'cap-full',
        clipPaths: List<String>.generate(20, (i) => '/tmp/c$i.mp4'),
      );
      expect(full.canAddClip, isFalse);
      final over = full.addClips(['/tmp/extra.mp4']);
      expect(over.clips, hasLength(20));
      expect(over.droppedByCap, 1);

      // Duplicates are skipped, not counted against the cap.
      final with20 = NewsProject(id: 'cap-dup', clipPaths: result.clips);
      final dup = with20.addClips(['/tmp/clip0.mp4']);
      expect(dup.clips, hasLength(20));
      expect(dup.droppedByCap, 0);
    });

    test('buildHandoff caps at 20 existing clips, counts the rest',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('tj_pro_phase9_cap_');
      final paths = <String>[];
      for (var i = 0; i < 22; i++) {
        final f = File('${dir.path}/clip$i.mp4');
        await f.writeAsString('x');
        paths.add(f.path);
      }
      final handoff = buildHandoff(
        project: NewsProject(id: 'cap-h', clipPaths: paths),
        preset: ChannelPreset.nigraanTv(),
      );
      expect(handoff.clipPaths, hasLength(20));
      expect(handoff.cappedClipCount, 2);
      expect(handoff.droppedClipPaths, isEmpty);
    });
  });

  group('Export failure + cancel name the step', () {
    test('no clips fails with failedStep = Clips tayyar karna', () async {
      final result = await ReelExportService.exportReel(
        project: NewsProject(id: 'noclips'),
        preset: ChannelPreset.nigraanTv(),
      );
      expect(result.success, isFalse);
      expect(result.failedStep, 'Clips tayyar karna');
      expect(result.error, contains('Koi clip nahi'));
    });

    test('cancel before any ffmpeg work returns the cancel result',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('tj_pro_phase9_cxl_');
      final clip = File('${dir.path}/clip.mp4');
      await clip.writeAsString('not a real video');
      final result = await ReelExportService.exportReel(
        project: NewsProject(
          id: 'cancelled',
          clipPaths: [clip.path],
        ),
        preset: ChannelPreset.nigraanTv(),
        isCancelled: () => true,
      );
      expect(result.success, isFalse);
      expect(result.failedStep, 'Export (cancel)');
      expect(result.error, contains('cancel'));
    });
  });

  group('DraftRecoveryCard widget — three real actions', () {
    testWidgets('resume / discard / dismiss callbacks fire',
        (tester) async {
      var resumed = false;
      var discarded = false;
      var dismissed = false;
      final draft = findRecoverableDraft(
        NewsProject(
          id: 'card-p',
          headline: 'Sheikhupura karwai',
          clipPaths: ['/tmp/c1.mp4'],
        ),
      )!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftRecoveryCard(
              draft: draft,
              onResume: () => resumed = true,
              onDiscard: () => discarded = true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('draftRecoveryCard')), findsOneWidget);
      expect(find.textContaining('Sheikhupura karwai'), findsOneWidget);
      expect(find.textContaining('1 clip'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resumeDraftButton')));
      expect(resumed, isTrue);
      await tester.tap(find.byKey(const Key('discardDraftButton')));
      expect(discarded, isTrue);
      await tester.tap(find.byKey(const Key('dismissDraftButton')));
      expect(dismissed, isTrue);
    });
  });

  group('ExportScreen widget — real settings + size + retry', () {
    testWidgets('shows estimate, quality switch changes it for real',
        (tester) async {
      final project = NewsProject(
        id: 'screen-p',
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
      expect(find.byKey(const Key('exportQualitySelector')), findsOneWidget);
      expect(find.byKey(const Key('exportFpsDropdown')), findsOneWidget);
      expect(
        find.byKey(const Key('exportVideoBitrateDropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exportAudioBitrateDropdown')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('exportAspectSelector')), findsOneWidget);
      // 42s @ 720p default (2500+128 kbps): 13.3 MB.
      expect(find.textContaining('13.3 MB'), findsOneWidget);

      // Quality switch BEFORE scrolling down: tapping changes the
      // estimate for real (1080p default is 5000+128 kbps: 25.9 MB).
      await tester.tap(find.text('1080p'));
      await tester.pump();
      expect(find.textContaining('25.9 MB'), findsOneWidget);
      expect(find.textContaining('1080×1920'), findsOneWidget);

      // The poster section is below the fold (lazy ListView) —
      // scroll it into view before asserting.
      await tester.scrollUntilVisible(
        find.byKey(const Key('exportPosterButton')),
        300,
      );
      await tester.pump();
      expect(find.byKey(const Key('exportPosterButton')), findsOneWidget);
    });

    testWidgets('no-clip export fails with the step named + Retry',
        (tester) async {
      final project = NewsProject(
        id: 'screen-fail',
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
      // Resolution is FREE since v1.2.0 (ads play alongside the
      // export instead); the balance seed is kept harmlessly so
      // the chroma/coins paths stay exercised elsewhere.
      CoinService.instance.balance.value = 1000;
      await tester.tap(find.byKey(const Key('startExportButton')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Build 7 (v1.5.9) repair: tapping Export now also fires
      // the alongside-export ads (v1.2.0) — UnityAdsService.init
      // waits on a 10-second SDK timeout that stays pending in
      // the fake-async zone and fails the test at teardown.
      // Advance past it; the export's own failure flow is
      // unaffected (it never waits on the ads).
      await tester.pump(const Duration(seconds: 11));
      // The failure UI is below the fold — scroll it into view.
      await tester.scrollUntilVisible(
        find.byKey(const Key('retryExportButton')),
        300,
      );
      await tester.pump();
      expect(find.textContaining('Clips tayyar karna'), findsOneWidget);
      expect(find.byKey(const Key('retryExportButton')), findsOneWidget);
      expect(find.textContaining('Koi clip nahi'), findsOneWidget);
    });

    testWidgets('unknown duration shows an honest no-estimate message',
        (tester) async {
      final project = NewsProject(
        id: 'screen-nodur',
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
      expect(
        find.textContaining('duration maloom nahi'),
        findsOneWidget,
      );
    });
  });
}
