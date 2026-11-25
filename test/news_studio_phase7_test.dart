// Phase 7 unit tests: reel export command builders (exact FFmpeg
// filter graphs), rotating-logo loop (angles + generated PNG frames),
// timeline handoff mapping, export validation + quality mapping, and
// the ReelExportCard buttons.
//
// Plain unit tests in real async (no widget pumps for the builders):
// persistence is covered with a mocked path_provider channel, like
// Phase 3/4/6. No proxy calls, no ffmpeg runs, no model downloads.
// The widget test at the end pumps only the export card directly
// (never the News Studio home — its FutureBuilder gate spins
// forever in widget tests).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/project_handoff.dart';
import 'package:tj_pro/news/widgets/reel_export_card.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/fx_pack.dart';
import 'package:tj_pro/services/logo_loop_service.dart';
import 'package:tj_pro/services/pro_editor.dart';
import 'package:tj_pro/services/reel_export_service.dart';
import 'package:tj_pro/services/video_export_service.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase7_test';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_phase7_test';
      }
      return null;
    },
  );
}

/// A 200x200 red-square PNG, written to [dir] — a stand-in logo file
/// for the frame-generation tests.
Future<File> _makeLogoPng(Directory dir) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 200, 200),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File('${dir.path}/logo.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

bool _isPng(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase7_test').createSync(recursive: true);
  });

  group('logoBugRect — template logo-bug spot per export size', () {
    test('720x1280 with ticker on: (590, 86, 110)', () {
      expect(
        FfmpegService.logoBugRect(
          width: 720,
          height: 1280,
          topRibbonEnabled: true,
        ),
        (590, 86, 110),
      );
    });

    test('720x1280 with ticker off: logo sits 16px from the top', () {
      expect(
        FfmpegService.logoBugRect(
          width: 720,
          height: 1280,
          topRibbonEnabled: false,
        ),
        (590, 16, 110),
      );
    });

    test('1080x1920 and 2160x3840 scale the same way', () {
      expect(
        FfmpegService.logoBugRect(
          width: 1080,
          height: 1920,
          topRibbonEnabled: true,
        ),
        // 1920*0.055 = 105.6 -> rounds to 106, +16 = 122.
        (895, 122, 165),
      );
      expect(
        FfmpegService.logoBugRect(
          width: 2160,
          height: 3840,
          topRibbonEnabled: true,
        ),
        (1810, 227, 330),
      );
    });
  });

  group('chromaPassCommand — preset sensitivity + background in the graph', () {
    test('colour background: exact graph, no second input', () {
      final cmd = chromaPassCommand(
        input: '/tmp/in.mp4',
        c: const ProChroma(
          color: 'green',
          similarity: 0.35,
          blend: 0.1,
          backgroundKind: 'color',
          backgroundColor: '#00FF00',
        ),
        output: '/tmp/out.mp4',
      );
      expect(
        cmd,
        "-y -i '/tmp/in.mp4' "
        '-filter_complex "[0:v]chromakey=color=0x00FF00:similarity=0.35:blend=0.1,'
        'format=yuva420p[keyed];color=c=0x00FF00[bgraw];'
        '[bgraw][keyed]scale2ref[bg][k2];[bg][k2]overlay=0:0[vout]" '
        '-map "[vout]" -map 0:a? -c:v libx264 -preset veryfast -crf 23 '
        "-c:a copy -movflags +faststart '/tmp/out.mp4'",
      );
    });

    test('image background: second input + scale2ref', () {
      final cmd = chromaPassCommand(
        input: '/tmp/in.mp4',
        c: const ProChroma(
          color: 'green',
          similarity: 0.5,
          blend: 0.2,
          backgroundKind: 'image',
          backgroundImagePath: '/tmp/bg.jpg',
        ),
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains("-i '/tmp/bg.jpg' "));
      expect(
        cmd,
        contains(
          '[0:v]chromakey=color=0x00FF00:similarity=0.5:blend=0.2,'
          'format=yuva420p[keyed];[1:v][keyed]scale2ref[bg][k2];'
          '[bg][k2]overlay=0:0[vout]',
        ),
      );
    });

    test('blue screen keys 0x0000FF', () {
      final cmd = chromaPassCommand(
        input: '/tmp/in.mp4',
        c: const ProChroma(color: 'blue'),
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains('chromakey=color=0x0000FF'));
    });
  });

  group('voiceoverMixCommand — ducked mix vs no-clip-audio', () {
    test('clip audio: duck + amix, video copied', () {
      final cmd = FfmpegService.voiceoverMixCommand(
        input: '/tmp/main.mp4',
        voiceoverPath: '/tmp/voice.wav',
        output: '/tmp/mix.mp4',
        hasClipAudio: true,
      );
      expect(
        cmd,
        "-y -i '/tmp/main.mp4' -i '/tmp/voice.wav' "
        '-filter_complex "[0:a]volume=0.35[ducked];'
        '[ducked][1:a]amix=inputs=2:duration=first:'
        'dropout_transition=0[aout]" -map 0:v -map "[aout]" '
        "-c:v copy -c:a aac -movflags +faststart '/tmp/mix.mp4'",
      );
    });

    test('no clip audio: voiceover becomes the track, no amix', () {
      final cmd = FfmpegService.voiceoverMixCommand(
        input: '/tmp/main.mp4',
        voiceoverPath: '/tmp/voice.wav',
        output: '/tmp/mix.mp4',
        hasClipAudio: false,
      );
      expect(cmd, contains('-map 0:v -map 1:a -shortest '));
      expect(cmd, isNot(contains('amix')));
      expect(cmd, contains('-c:v copy'));
    });

    test('clip volume is honoured', () {
      final cmd = FfmpegService.voiceoverMixCommand(
        input: '/tmp/main.mp4',
        voiceoverPath: '/tmp/voice.wav',
        output: '/tmp/mix.mp4',
        hasClipAudio: true,
        clipVolume: 0.2,
      );
      expect(cmd, contains('[0:a]volume=0.20[ducked]'));
    });
  });

  group('logoLoopOverlayCommand — ping-pong mov vs generated frames', () {
    test('mov source: crop + reverse + concat, bug at 590:86', () {
      final cmd = FfmpegService.logoLoopOverlayCommand(
        input: '/tmp/main.mp4',
        output: '/tmp/logo.mp4',
        width: 720,
        height: 1280,
        topRibbonEnabled: true,
        movPath: '/tmp/logo-rotating-alpha.mov',
      );
      expect(
        cmd,
        "-y -stream_loop -1 -i '/tmp/logo-rotating-alpha.mov' "
        "-i '/tmp/main.mp4' "
        '-filter_complex "[0:v]crop=396:316:235:86,format=yuva420p,'
        'split[f][r];[r]reverse[rr];[f][rr]concat=n=2:v=1:a=0,'
        'format=yuva420p,scale=110:-1[bug];'
        '[1:v][bug]overlay=590:86:shortest=1[vout]" '
        '-map "[vout]" -map 1:a? -c:v libx264 -preset veryfast -crf 23 '
        // Build 12: -shortest bounds the infinitely looped
        // logo input to the base video's duration.
        "-c:a copy -shortest -movflags +faststart '/tmp/logo.mp4'",
      );
      // No perspective filter anywhere (rejected in the decision doc).
      expect(cmd, isNot(contains('perspective')));
    });

    test('frames source: image2 loop at 12 fps', () {
      final cmd = FfmpegService.logoLoopOverlayCommand(
        input: '/tmp/main.mp4',
        output: '/tmp/logo.mp4',
        width: 720,
        height: 1280,
        topRibbonEnabled: true,
        framesDir: '/tmp/loop',
      );
      expect(
        cmd,
        "-y -framerate 12 -stream_loop -1 -i '/tmp/loop/frame_%02d.png' "
        "-i '/tmp/main.mp4' "
        '-filter_complex "[0:v]format=yuva420p,scale=110:-1[bug];'
        '[1:v][bug]overlay=590:86:shortest=1[vout]" '
        '-map "[vout]" -map 1:a? -c:v libx264 -preset veryfast -crf 23 '
        // Build 12: -shortest (see the mov case above).
        "-c:a copy -shortest -movflags +faststart '/tmp/logo.mp4'",
      );
    });

    test('needs exactly one loop source', () {
      expect(
        () => FfmpegService.logoLoopOverlayCommand(
          input: '/tmp/main.mp4',
          output: '/tmp/logo.mp4',
          width: 720,
          height: 1280,
          topRibbonEnabled: true,
        ),
        throwsAssertionError,
      );
      expect(
        () => FfmpegService.logoLoopOverlayCommand(
          input: '/tmp/main.mp4',
          output: '/tmp/logo.mp4',
          width: 720,
          height: 1280,
          topRibbonEnabled: true,
          movPath: '/tmp/a.mov',
          framesDir: '/tmp/loop',
        ),
        throwsAssertionError,
      );
    });
  });

  group('normalizeWithAudioCommand + stillSegmentCommand', () {
    test('silent-audio variant adds anullsrc + maps it', () {
      final cmd = FfmpegService.normalizeWithAudioCommand(
        input: '/tmp/intro.mp4',
        trimStart: 0,
        trimEnd: 10,
        width: 720,
        height: 1280,
        output: '/tmp/intro_norm.mp4',
        addSilentAudio: true,
      );
      expect(cmd, contains('anullsrc=channel_layout=stereo'));
      expect(cmd, contains('-map 0:v -map 1:a -shortest'));
      expect(cmd, contains('scale=720:1280'));
    });

    test('no silent audio = plain normalizeCommand', () {
      expect(
        FfmpegService.normalizeWithAudioCommand(
          input: '/tmp/a.mp4',
          trimStart: 1,
          trimEnd: 5,
          width: 720,
          height: 1280,
          output: '/tmp/b.mp4',
        ),
        FfmpegService.normalizeCommand(
          input: '/tmp/a.mp4',
          trimStart: 1,
          trimEnd: 5,
          width: 720,
          height: 1280,
          output: '/tmp/b.mp4',
        ),
      );
    });

    test('outro still: looped image + 3s + silent audio', () {
      final cmd = FfmpegService.stillSegmentCommand(
        imagePath: '/tmp/card.png',
        durationSec: 3,
        width: 720,
        height: 1280,
        output: '/tmp/outro.mp4',
      );
      expect(cmd, contains("-loop 1 -t 3.0 -i '/tmp/card.png'"));
      expect(cmd, contains('anullsrc=channel_layout=stereo'));
      expect(cmd, contains('fps=30,format=yuv420p'));
    });
  });

  // Build 12 (v1.9.0, point #12) — UPDATED IN PLACE: this
  // group used to pin the yoyo swing (±0.7 rad, never
  // mirroring). The user's order of 2026-11-25 supersedes the
  // 20 Nov swing decision — the export loop is now ONE FULL
  // 360° revolution of the 3D cube, so the group pins the
  // continuous sweep + the seamless loop point instead.
  group('logoLoopAngle — full revolution, seamless loop point', () {
    test('sweeps 0 → 2π across the loop; frame N = frame 0', () {
      expect(logoLoopAngle(0), closeTo(0, 0.001));
      expect(logoLoopAngle(24), closeTo(3.14159265, 0.001));
      expect(
        logoLoopAngle(47),
        closeTo(2 * 3.14159265 * 47 / 48, 0.01),
      );
      // The loop point: the frame AFTER the last wraps to
      // frame 0's angle (index modulo the frame count), and
      // 2π ≡ 0 in orientation, so -stream_loop never snaps.
      expect(logoLoopAngle(kLogoLoopFrameCount), closeTo(0, 0.001));
      expect(
        logoLoopAngle(kLogoLoopFrameCount),
        logoLoopAngle(0),
      );
    });

    test('monotonic increase — a continuous turn, no yoyo', () {
      var prev = -1.0;
      for (var i = 0; i < kLogoLoopFrameCount; i++) {
        final a = logoLoopAngle(i);
        expect(a, greaterThan(prev));
        expect(a, lessThan(2 * 3.14159265));
        prev = a;
      }
    });
  });

  group('logoLoopCacheKey', () {
    test('default tile keys differ per initial; same file = same key', () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase7_');
      final logo = await _makeLogoPng(dir);
      expect(
        logoLoopCacheKey(initial: 'N'),
        isNot(logoLoopCacheKey(initial: 'G')),
      );
      expect(
        logoLoopCacheKey(logoFile: logo),
        logoLoopCacheKey(logoFile: logo),
      );
    });
  });

  group('LogoLoopService.generateFrames — real PNG frames', () {
    test('default tile: 48 real 512x512 PNGs, cached on second call',
        () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase7_');
      final outDir = Directory('${dir.path}/loop_default');
      final first = await LogoLoopService.generateFrames(
        outDir: outDir,
        initial: 'N',
      );
      expect(first.length, kLogoLoopFrameCount);
      for (final f in first) {
        final bytes = await f.readAsBytes();
        expect(_isPng(bytes), isTrue);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, kLogoLoopFrameSize);
        expect(frame.image.height, kLogoLoopFrameSize);
        frame.image.dispose();
      }
      // Frame 0 (cube front face) and frame 24 (cube turned
      // 180° — back face) differ.
      final b0 = await first[0].readAsBytes();
      final b24 = await first[24].readAsBytes();
      expect(b0, isNot(b24));
      // Second call reuses the cache (same mtimes).
      final mtimesBefore =
          first.map((f) => f.statSync().modified).toList();
      final second = await LogoLoopService.generateFrames(
        outDir: outDir,
        initial: 'N',
      );
      expect(second.length, kLogoLoopFrameCount);
      for (var i = 0; i < first.length; i++) {
        expect(
          second[i].statSync().modified,
          mtimesBefore[i],
        );
      }
    });

    test('user logo file: 48 frames from the picked image', () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase7_');
      final logo = await _makeLogoPng(dir);
      final outDir = Directory('${dir.path}/loop_user');
      final frames = await LogoLoopService.generateFrames(
        logoFile: logo,
        outDir: outDir,
      );
      expect(frames.length, kLogoLoopFrameCount);
      for (final f in frames) {
        expect(_isPng(await f.readAsBytes()), isTrue);
      }
    });
  });

  group('buildHandoff — project + preset into editor data', () {
    late Directory dir;
    late File clip1;
    late File clip2;
    late File voice;
    late File galleryBg;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tj_pro_phase7_');
      clip1 = File('${dir.path}/clip1.mp4')..writeAsStringSync('x');
      clip2 = File('${dir.path}/clip2.mp4')..writeAsStringSync('x');
      voice = File('${dir.path}/voice.wav')..writeAsStringSync('x');
      galleryBg = File('${dir.path}/bg.jpg')..writeAsStringSync('x');
    });

    NewsProject project({
      List<String>? clips,
      String? voiceoverPath,
    }) {
      return NewsProject(
        id: 'p1',
        headline: 'Test headline',
        tehreer: 'Test tehreer',
        voiceoverPath: voiceoverPath,
        voiceoverDurationSec: 12,
        clipPaths: clips ?? [],
        tickerText: 'ticker text',
        subtitles: [
          SubtitleLine(text: 'Line one', startSec: 0, endSec: 2),
          SubtitleLine(
            text: 'Line two',
            startSec: 2,
            endSec: 4,
            words: [
              SubtitleWord(word: 'Line', startSec: 2, endSec: 3),
              SubtitleWord(word: 'two', startSec: 3, endSec: 4),
            ],
          ),
        ],
      );
    }

    test('existing clips kept, missing clips listed, never dropped silently',
        () {
      final h = buildHandoff(
        project: project(
          clips: [clip1.path, '/tmp/gone.mp4', clip2.path],
          voiceoverPath: voice.path,
        ),
      );
      expect(h.clipPaths, [clip1.path, clip2.path]);
      expect(h.droppedClipPaths, ['/tmp/gone.mp4']);
      expect(h.voiceoverPath, voice.path);
    });

    test('missing voiceover file = null, not a stale path', () {
      final h = buildHandoff(
        project: project(
          clips: [clip1.path],
          voiceoverPath: '/tmp/gone.wav',
        ),
      );
      expect(h.voiceoverPath, isNull);
    });

    test('captions map with words + template carries headline/ticker',
        () {
      final preset = ChannelPreset(
        id: 't',
        name: 'Test TV',
        lowerThirdTitle: 'Reporter',
        lowerThirdSubtitle: 'Lahore',
      );
      final h = buildHandoff(
        project: project(clips: [clip1.path]),
        preset: preset,
      );
      expect(h.captions.length, 2);
      expect(h.captions[1].words.length, 2);
      expect(h.captions[1].words[0].word, 'Line');
      expect(h.template.breakingHeadline, 'Test headline');
      expect(h.template.lowerTitle, 'Reporter');
      expect(h.template.lowerSubtitle, 'Lahore');
      expect(h.template.tickerText, 'ticker text');
      expect(h.templateKind, 'nigraanFinal');
    });

    test('empty project ticker falls back to the preset top ribbon', () {
      final preset = ChannelPreset(id: 't', name: 'Test TV');
      preset.topRibbon.text = 'preset ticker';
      final p = project(clips: [clip1.path]);
      final h = buildHandoff(
        project: p.copyWith(tickerText: ''),
        preset: preset,
      );
      expect(h.template.tickerText, 'preset ticker');
    });

    test('chroma on (newsroom): sensitivity + bundled asset carried', () {
      final preset = ChannelPreset(
        id: 't',
        name: 'Test TV',
        chromaEnabled: true,
        chromaBackground: ChromaBackgroundKind.newsroom,
        chromaSensitivity: 0.5,
      );
      final h = buildHandoff(
        project: project(clips: [clip1.path]),
        preset: preset,
      );
      expect(h.chroma, isNotNull);
      expect(h.chroma!.similarity, 0.5);
      expect(h.chroma!.backgroundKind, 'image');
      expect(
        h.chromaBackgroundAsset,
        'assets/backgrounds/newsroom.jpg',
      );
    });

    test('chroma on (gallery, file gone): falls back to solid colour',
        () {
      final preset = ChannelPreset(
        id: 't',
        name: 'Test TV',
        chromaEnabled: true,
        chromaBackground: ChromaBackgroundKind.gallery,
        chromaBackgroundPath: '/tmp/gone.jpg',
      );
      final h = buildHandoff(
        project: project(clips: [clip1.path]),
        preset: preset,
      );
      expect(h.chroma, isNotNull);
      expect(h.chroma!.backgroundKind, 'color');
      expect(h.chromaBackgroundAsset, isNull);
    });

    test('chroma on (gallery, file exists): file path carried', () {
      final preset = ChannelPreset(
        id: 't',
        name: 'Test TV',
        chromaEnabled: true,
        chromaBackground: ChromaBackgroundKind.gallery,
        chromaBackgroundPath: galleryBg.path,
      );
      final h = buildHandoff(
        project: project(clips: [clip1.path]),
        preset: preset,
      );
      expect(h.chroma!.backgroundKind, 'image');
      expect(h.chroma!.backgroundImagePath, galleryBg.path);
    });

    test('chroma off = null chroma; PIP settings map + scale clamps', () {
      final preset = ChannelPreset(
        id: 't',
        name: 'Test TV',
        pipEnabled: true,
        pipPosition: 'topLeft',
        pipScale: 0.9,
      );
      final h = buildHandoff(
        project: project(clips: [clip1.path]),
        preset: preset,
      );
      expect(h.chroma, isNull);
      expect(h.pipEnabled, isTrue);
      expect(h.pipPosition, PipPosition.topLeft);
      expect(h.pipScale, 0.5); // clamped to the filter's max
    });

    test('no preset: template-only handoff still works', () {
      final h = buildHandoff(project: project(clips: [clip1.path]));
      expect(h.clipPaths, [clip1.path]);
      expect(h.template.breakingHeadline, 'Test headline');
      expect(h.chroma, isNull);
      expect(h.pipEnabled, isFalse);
    });
  });

  group('effectivePresetFor — project ticker/headline on the preset', () {
    test('project ticker wins; empty ticker falls back to headline', () {
      final preset = ChannelPreset.nigraanTv();
      final withTicker = NewsProject(
        id: 'p1',
        tickerText: 'current story',
        headline: 'Headline',
      );
      expect(
        effectivePresetFor(project: withTicker, preset: preset)
            .topRibbon
            .text,
        'current story',
      );
      final noTicker = NewsProject(id: 'p2', headline: 'Headline');
      expect(
        effectivePresetFor(project: noTicker, preset: preset)
            .topRibbon
            .text,
        'Headline',
      );
    });

    test('template kind + breaking flag copy over', () {
      final preset = ChannelPreset.nigraanTv();
      final p = NewsProject(
        id: 'p1',
        templateKind: 'breaking',
        breaking: true,
      );
      final eff = effectivePresetFor(project: p, preset: preset);
      expect(eff.templateKind, 'breaking');
      expect(eff.showBreakingBanner, isTrue);
    });
  });

  group('ReelExportService — quality mapping + validation', () {
    test('qualityFor + reelDims cover 720p/1080p/4K', () {
      expect(ReelExportService.qualityFor(0), VideoExportQuality.p720);
      expect(ReelExportService.qualityFor(1), VideoExportQuality.p1080);
      expect(ReelExportService.qualityFor(2), VideoExportQuality.p2160);
      expect(ReelExportService.reelDims(0), (720, 1280));
      expect(ReelExportService.reelDims(1), (1080, 1920));
      expect(ReelExportService.reelDims(2), (2160, 3840));
    });

    test('VideoExportQuality.p2160 is 4K / 2160', () {
      expect(VideoExportQuality.p2160.label, '4K');
      expect(VideoExportQuality.p2160.target, 2160);
    });

    test('exportReel with no clips fails cleanly (no ffmpeg, no crash)',
        () async {
      final result = await ReelExportService.exportReel(
        project: NewsProject(id: 'empty'),
        preset: ChannelPreset.nigraanTv(),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('clip'));
    });

    test('exportReel with only missing clips fails cleanly too', () async {
      final result = await ReelExportService.exportReel(
        project: NewsProject(
          id: 'gone',
          clipPaths: ['/tmp/no-such-clip.mp4'],
        ),
        preset: ChannelPreset.nigraanTv(),
      );
      expect(result.success, isFalse);
      expect(result.notes, isNotEmpty);
    });

    test('introState is notHosted while no intro URL is configured',
        () async {
      expect(
        await ReelExportService.introState(),
        IntroAvailability.notHosted,
      );
    });

    test('styledAssForProject: null without subtitles, real ASS with',
        () {
      expect(
        ReelExportService.styledAssForProject(
          project: NewsProject(id: 'p1'),
          playResX: 720,
          playResY: 1280,
        ),
        isNull,
      );
      final ass = ReelExportService.styledAssForProject(
        project: NewsProject(
          id: 'p1',
          subtitles: [
            SubtitleLine(text: 'Test line', startSec: 0, endSec: 2),
          ],
        ),
        playResX: 720,
        playResY: 1280,
      );
      expect(ass, isNotNull);
      // Karaoke splits words with \kf tags, so the raw line never
      // appears contiguously — assert on the words + the timed event.
      expect(ass!, contains('Test'));
      expect(ass, contains('line'));
      expect(ass, contains('Dialogue: 0,0:00:00.00,0:00:02.00'));
      expect(ass, contains('PlayResX: 720'));
      expect(ass, contains('PlayResY: 1280'));
    });
  });

  group('ReelExportCard widget — real buttons, no placeholders', () {
    testWidgets('shows quality selector + Export + Open in Timeline',
        (tester) async {
      final project = NewsProject(
        id: 'p1',
        clipPaths: ['/tmp/clip1.mp4'],
        templateKind: 'nigraanFinal',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReelExportCard(
              project: project,
              preset: ChannelPreset.nigraanTv(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('exportQualitySelector')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('exportReelButton')), findsOneWidget);
      expect(find.byKey(const Key('openTimelineButton')), findsOneWidget);
      expect(find.text('Export Reel • 720p'), findsOneWidget);
      expect(find.textContaining('Phase 7'), findsNothing);

      // Quality switch updates the export label for real.
      await tester.tap(find.text('1080p'));
      await tester.pump();
      expect(find.text('Export Reel • 1080p'), findsOneWidget);
      await tester.tap(find.text('4K'));
      await tester.pump();
      expect(find.text('Export Reel • 4K'), findsOneWidget);
    });
  });
}
