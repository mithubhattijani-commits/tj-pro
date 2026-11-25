/// Build 10 (v1.8.0) — Core Engine (point #7), store audio
/// previews + compact grid (point #8 + the user's audio
/// order), and the session-recovery model (point #7F).
///
/// Groups:
///  * 7A tiers + diagnostics line
///  * 7B per-tier config + pressure step-down / restore
///  * 7C SafeOps isolation
///  * 7D export chain runner + the burn-in arg builders
///    (the chunked command SHAPE was additionally verified
///    against a real ffmpeg render — BUILD10-TOOL-TESTS)
///  * 7E cache eviction hooks
///  * store audio: sniff, cache, one-at-a-time player
///  * store grid widget: 3 columns, play button, tap-to-play
///  * 7F video-editor session encode/decode
///  * editor export step-down predicate
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/store_screen.dart';
import 'package:tj_pro/services/export_chain.dart';
import 'package:tj_pro/services/performance_engine.dart';
import 'package:tj_pro/services/photo_pipeline.dart';
import 'package:tj_pro/services/safe_ops.dart';
import 'package:tj_pro/services/store_audio_preview.dart';
import 'package:tj_pro/services/store_preview_cache.dart';
import 'package:tj_pro/services/store_service.dart';
import 'package:tj_pro/services/video_export_service.dart';
import 'package:tj_pro/video/editor_export_controller.dart';
import 'package:tj_pro/video/video_editor_recovery.dart';
import 'package:tj_pro/video/editor_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('7A — device tiers', () {
    test('tier rules (RAM-first, low-RAM flag dominates)', () {
      DeviceTier t({int? ram, int? cores, bool lowRam = false}) =>
          DeviceProfile.tierFor(
            ramMb: ram,
            cpuCores: cores,
            isLowRamDevice: lowRam,
          );
      expect(t(ram: 12288, cores: 8, lowRam: true), DeviceTier.low);
      expect(t(ram: 2048, cores: 8), DeviceTier.low);
      expect(t(ram: 3399, cores: 8), DeviceTier.low);
      expect(t(ram: 4096, cores: 8), DeviceTier.mid);
      expect(t(ram: 5600, cores: 8), DeviceTier.high); // 6 GB class
      expect(t(ram: 7600, cores: 8), DeviceTier.high); // 8 GB class
      expect(t(ram: 11400, cores: 8), DeviceTier.flagship); // 12 GB
      expect(t(ram: 11400, cores: 4), DeviceTier.high); // cores gate
      expect(t(ram: null, cores: null), DeviceTier.mid); // unknown
    });

    test('diagnostics line carries model, RAM and tier', () {
      const p = DeviceProfile(model: 'Pixel 7', ramMb: 8192, cpuCores: 8);
      expect(p.tier, DeviceTier.high);
      expect(p.diagnosticsLine, contains('Pixel 7'));
      expect(p.diagnosticsLine, contains('Tier: HIGH'));
    });
  });

  group('7B — adaptive config', () {
    tearDown(() => PerformanceEngine.resetForTest());

    test('pre-init defaults reproduce the pre-engine constants', () {
      final c = PerformanceEngine.instance.config.value;
      expect(c.tier, DeviceTier.high);
      expect(c.previewMaxWidth, 720);
      expect(c.previewMaxHeight, 1280);
      // The historical Phase 7 enlarge cap.
      expect(c.photoEnlargeMaxPixels, 40000000);
      expect(c.tryHardwareEncoder, isTrue);
    });

    test('per-tier values step down monotonically', () {
      final low = PerformanceConfig.forTier(DeviceTier.low);
      final mid = PerformanceConfig.forTier(DeviceTier.mid);
      final high = PerformanceConfig.forTier(DeviceTier.high);
      final flag = PerformanceConfig.forTier(DeviceTier.flagship);
      expect(low.tryHardwareEncoder, isFalse);
      expect(low.photoEnlargeMaxPixels, lessThan(mid.photoEnlargeMaxPixels));
      expect(
        mid.photoEnlargeMaxPixels,
        lessThan(high.photoEnlargeMaxPixels),
      );
      expect(high.photoEnlargeMaxPixels, flag.photoEnlargeMaxPixels);
      expect(
        low.previewThumbCacheWidth,
        lessThan(flag.previewThumbCacheWidth),
      );
      expect(DeviceTier.flagship.steppedDown, DeviceTier.high);
      expect(DeviceTier.high.steppedDown, DeviceTier.mid);
      expect(DeviceTier.mid.steppedDown, DeviceTier.low);
      expect(DeviceTier.low.steppedDown, DeviceTier.low);
      expect(flag.steppedDown.photoEnlargeMaxPixels,
          high.photoEnlargeMaxPixels);
    });

    test('enlargeImage honours the tier cap (default = 40 MP)', () async {
      final src = img.Image(width: 1000, height: 1000); // 1 MP
      // Default engine (HIGH): 4x of 1 MP = 16 MP < 40 MP cap.
      final full = await enlargeImage(src, scale: 4);
      expect(full.width, 4000);
      // Explicit smaller budget: scale shrinks to fit, no crash.
      final capped = await enlargeImage(
        src,
        scale: 4,
        maxOutPixelsOverride: 1000000,
      );
      expect(capped.width, 1000);
      expect(capped.width * capped.height, lessThanOrEqualTo(1000000));
    });
  });

  group('7B/7E — memory pressure step-down + restore', () {
    setUp(() => PerformanceEngine.resetForTest());
    tearDown(() => PerformanceEngine.resetForTest());

    test('pressure steps down one tier; a good re-probe restores', () async {
      final engine = PerformanceEngine.instance;
      PerformanceEngine.debugSetProfileForTest(
        const DeviceProfile(model: 'Pixel 7', ramMb: 8192, cpuCores: 8),
      );
      expect(engine.config.value.tier, DeviceTier.high);

      engine.handleMemoryPressure();
      expect(engine.underPressure, isTrue);
      expect(engine.pressureEvents, 1);
      expect(engine.config.value.tier, DeviceTier.mid);
      expect(engine.diagnosticsLine, contains('dabao'));

      PerformanceEngine.availableRamProbeForTest = () async => 4096;
      expect(await engine.recheckPressure(), isTrue);
      expect(engine.underPressure, isFalse);
      expect(engine.config.value.tier, DeviceTier.high);
    });

    test('a bad re-probe keeps the step-down', () async {
      final engine = PerformanceEngine.instance;
      PerformanceEngine.debugSetProfileForTest(
        const DeviceProfile(model: 'A14', ramMb: 4096, cpuCores: 8),
      );
      engine.handleMemoryPressure();
      expect(engine.config.value.tier, DeviceTier.low);
      PerformanceEngine.availableRamProbeForTest = () async => 128;
      expect(await engine.recheckPressure(), isFalse);
      expect(engine.underPressure, isTrue);
      expect(engine.config.value.tier, DeviceTier.low);
    });

    test('pressure at LOW stays at LOW (floor)', () {
      final engine = PerformanceEngine.instance;
      PerformanceEngine.debugSetProfileForTest(
        const DeviceProfile(model: 'Old', ramMb: 2048, cpuCores: 4),
      );
      engine.handleMemoryPressure();
      expect(engine.config.value.tier, DeviceTier.low);
    });
  });

  group('7C — SafeOps', () {
    test('success passes the value through', () async {
      final r = await SafeOps.run<int>('t', () async => 42);
      expect(r.ok, isTrue);
      expect(r.value, 42);
    });

    test('a throw becomes a failure result, never an exception', () async {
      final r = await SafeOps.run<int>('t', () async {
        throw StateError('boom');
      });
      expect(r.ok, isFalse);
      expect(r.error, contains('boom'));
      expect(await SafeOps.guard('t', () async {}), isTrue);
      expect(
        await SafeOps.guard('t', () async => throw StateError('x')),
        isFalse,
      );
    });
  });

  group('7D — export chain runner', () {
    ExportAttempt<String> attempt(
      String name,
      String result,
      List<String> log,
    ) =>
        ExportAttempt<String>(
          name: name,
          run: () async {
            log.add(name);
            return result;
          },
        );

    test('first success wins; later attempts never run', () async {
      final log = <String>[];
      final outcome = await ExportChain.run<String>(
        attempts: [
          attempt('hardware', 'fail', log),
          attempt('chunked', 'ok', log),
          attempt('software', 'ok', log),
        ],
        isSuccess: (r) => r == 'ok',
        isCancelled: (r) => r == 'cancel',
      );
      expect(outcome.succeeded, isTrue);
      expect(outcome.attemptName, 'chunked');
      expect(log, ['hardware', 'chunked']);
    });

    test('a cancel stops the chain immediately', () async {
      final log = <String>[];
      final outcome = await ExportChain.run<String>(
        attempts: [
          attempt('hardware', 'cancel', log),
          attempt('software', 'ok', log),
        ],
        isSuccess: (r) => r == 'ok',
        isCancelled: (r) => r == 'cancel',
      );
      expect(outcome.cancelled, isTrue);
      expect(outcome.succeeded, isFalse);
      expect(log, ['hardware']);
    });

    test('a throwing attempt is a failed attempt, chain continues', () async {
      final outcome = await ExportChain.run<String>(
        attempts: [
          ExportAttempt<String>(
            name: 'hardware',
            run: () async => throw StateError('encoder missing'),
          ),
          attempt('software', 'ok', <String>[]),
        ],
        isSuccess: (r) => r == 'ok',
        isCancelled: (r) => false,
      );
      expect(outcome.succeeded, isTrue);
      expect(outcome.attemptName, 'software');
      expect(outcome.triedAttempts, ['hardware', 'software']);
    });

    test('all attempts failing yields no result', () async {
      final outcome = await ExportChain.run<String>(
        attempts: [attempt('a', 'fail', <String>[])],
        isSuccess: (r) => r == 'ok',
        isCancelled: (r) => false,
      );
      expect(outcome.succeeded, isFalse);
      expect(outcome.result, isNull);
      expect(outcome.triedAttempts, ['a']);
    });
  });

  group('7D — burn-in arg builders', () {
    test('hardware attempt: MediaCodec encoder + ladder bitrate', () {
      final args = VideoExportService.burnInHardwareArgs(
        inputPath: 'in.mp4',
        assPath: 'caps.ass',
        outputPath: 'out.mp4',
        quality: VideoExportQuality.p1080,
        vertical: true,
      );
      expect(args, contains('h264_mediacodec'));
      expect(args, contains('5000k'));
      expect(args, isNot(contains('libx264')));
      expect(args, isNot(contains('-crf')));
      expect(
        VideoExportService.hardwareBitrateKbpsFor(VideoExportQuality.p720),
        2500,
      );
      expect(
        VideoExportService.hardwareBitrateKbpsFor(VideoExportQuality.p2160),
        12000,
      );
    });

    test('segment attempt: -ss/-t AFTER -i (absolute ASS timing)', () {
      final args = VideoExportService.burnInSegmentArgs(
        inputPath: 'in.mp4',
        assPath: 'caps.ass',
        outputPath: 'seg.mp4',
        quality: VideoExportQuality.p720,
        vertical: true,
        startSeconds: 30,
        lengthSeconds: 30,
      );
      final iIdx = args.indexOf('-i');
      final ssIdx = args.indexOf('-ss');
      expect(ssIdx, greaterThan(iIdx));
      expect(args[ssIdx + 1], '30.000');
      expect(args[args.indexOf('-t') + 1], '30.000');
      expect(args.join(' '), contains('subtitles='));
      // Segments re-encode audio to one shared AAC profile so
      // the concat step can stream-copy.
      expect(args, contains('aac'));
    });

    test('concat attempt: demuxer + stream copy + faststart', () {
      final args = VideoExportService.burnInConcatArgs(
        listPath: 'list.txt',
        outputPath: 'out.mp4',
      );
      expect(
        args,
        containsAllInOrder(['-f', 'concat', '-safe', '0', '-i', 'list.txt']),
      );
      expect(args, containsAllInOrder(['-c', 'copy']));
      expect(args, contains('+faststart'));
    });

    test('software attempt unchanged: libx264 + crf 23 + audio copy', () {
      final args = VideoExportService.burnInArgs(
        inputPath: 'in.mp4',
        assPath: 'caps.ass',
        outputPath: 'out.mp4',
        quality: VideoExportQuality.p720,
        vertical: false,
      );
      expect(args, containsAllInOrder(['-c:v', 'libx264']));
      expect(args, containsAllInOrder(['-crf', '23']));
      expect(args, containsAllInOrder(['-c:a', 'copy']));
    });

    test('editor step-down predicate only matches encode failures', () {
      expect(
        VideoEditorExportController.looksLikeEncodeFailure(
          Exception('FFmpeg failed (1). log'),
        ),
        isTrue,
      );
      expect(
        VideoEditorExportController.looksLikeEncodeFailure(
          Exception('Final export failed. log'),
        ),
        isTrue,
      );
      expect(
        VideoEditorExportController.looksLikeEncodeFailure(
          Exception('Out of memory: mmap failed'),
        ),
        isTrue,
      );
      expect(
        VideoEditorExportController.looksLikeEncodeFailure(
          Exception('User closed the picker'),
        ),
        isFalse,
      );
    });
  });

  group('store audio — sniff + cache', () {
    late Directory tempDir;
    final mp3Item = const StoreItem(
      id: 'song1',
      name: 'Calm Piano Loop.mp3',
      category: 'Music',
    );
    final mp3Bytes = <int>[
      0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFB,
    ];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('b10_audio_');
      StoreAudioPreviewCache.overrideDirForTest = tempDir;
      StoreAudioPreviewCache.resetForTest();
    });

    tearDown(() async {
      StoreAudioPreviewCache.downloaderForTest = null;
      StoreAudioPreviewCache.overrideDirForTest = null;
      StoreAudioPreviewCache.resetForTest();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('sniff accepts real audio headers, rejects HTML junk', () {
      expect(StoreAudioPreviewCache.looksLikeAudio(mp3Bytes, '.mp3'), isTrue);
      expect(
        StoreAudioPreviewCache.looksLikeAudio(
          const [0xFF, 0xFB, 0x90, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          '.mp3',
        ),
        isTrue,
      );
      expect(
        StoreAudioPreviewCache.looksLikeAudio(
          const [
            0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
          ],
          '.wav',
        ),
        isTrue,
      );
      expect(
        StoreAudioPreviewCache.looksLikeAudio(
          const [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0],
          '.m4a',
        ),
        isTrue,
      );
      expect(
        StoreAudioPreviewCache.looksLikeAudio(
          const [0x4F, 0x67, 0x67, 0x53, 0, 0, 0, 0, 0, 0, 0, 0],
          '.ogg',
        ),
        isTrue,
      );
      final html = utf8.encode('<html><head><title>error</title>');
      expect(StoreAudioPreviewCache.looksLikeAudio(html, '.mp3'), isFalse);
      expect(StoreAudioPreviewCache.looksLikeAudio(html, '.wav'), isFalse);
      expect(
        StoreAudioPreviewCache.looksLikeAudio(const [0x49, 0x44], '.mp3'),
        isFalse,
      );
    });

    test('fileFor downloads once, then serves cache + disk', () async {
      var downloads = 0;
      StoreAudioPreviewCache.downloaderForTest = (id) async {
        downloads++;
        return mp3Bytes;
      };
      final cache = StoreAudioPreviewCache.instance;
      final first = await cache.fileFor(mp3Item);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), mp3Bytes);
      expect(downloads, 1);
      final second = await cache.fileFor(mp3Item);
      expect(second!.path, first.path);
      expect(downloads, 1);
      // 7E: memory eviction forgets the map; the disk copy
      // re-serves without a new download.
      cache.evictMemory();
      expect(cache.cachedFileFor('song1'), isNull);
      final third = await cache.fileFor(mp3Item);
      expect(third, isNotNull);
      expect(downloads, 1);
    });

    test('junk bytes are never cached as audio', () async {
      StoreAudioPreviewCache.downloaderForTest =
          (id) async => utf8.encode('<html>drive error page</html>');
      final cache = StoreAudioPreviewCache.instance;
      expect(await cache.fileFor(mp3Item), isNull);
      expect(cache.cachedFileFor('song1'), isNull);
    });

    test('storeItemIsAudio matches the audio extensions only', () {
      StoreItem item(String name) =>
          StoreItem(id: name, name: name, category: 'Music');
      expect(storeItemIsAudio(item('a.mp3')), isTrue);
      expect(storeItemIsAudio(item('a.m4a')), isTrue);
      expect(storeItemIsAudio(item('a.wav')), isTrue);
      expect(storeItemIsAudio(item('a.ogg')), isTrue);
      expect(storeItemIsAudio(item('a.mp4')), isFalse);
      expect(storeItemIsAudio(item('a.json')), isFalse);
      expect(storeItemIsAudio(item('a.png')), isFalse);
    });
  });

  group('store audio — one-at-a-time player', () {
    late Directory tempDir;
    late File audioFile;
    final itemA = const StoreItem(
      id: 'a1',
      name: 'Rain Loop.mp3',
      category: 'Music',
    );
    final itemB = const StoreItem(
      id: 'b2',
      name: 'Piano Loop.mp3',
      category: 'Music',
    );
    final backends = <FakeAudioBackend>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('b10_player_');
      audioFile = File('${tempDir.path}/x.mp3');
      await audioFile.writeAsBytes(const [1, 2, 3]);
      backends.clear();
      StoreAudioPreviewPlayer.backendFactoryForTest = () {
        final b = FakeAudioBackend();
        backends.add(b);
        return b;
      };
      StoreAudioPreviewPlayer.fileResolverForTest = (item) async => audioFile;
    });

    tearDown(() async {
      await StoreAudioPreviewPlayer.resetForTest();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('toggle plays, pauses, resumes the same item', () async {
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      expect(player.state.value.phase, StoreAudioPhase.playing);
      expect(player.state.value.itemId, 'a1');
      expect(backends, hasLength(1));
      expect(backends.single.loadedFile!.path, audioFile.path);

      await player.toggle(itemA);
      expect(player.state.value.phase, StoreAudioPhase.paused);
      expect(backends.single.playing, isFalse);

      await player.toggle(itemA);
      expect(player.state.value.phase, StoreAudioPhase.playing);
      expect(backends, hasLength(1)); // same backend resumed
    });

    test('starting a second item stops + disposes the first', () async {
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      await player.toggle(itemB);
      expect(backends, hasLength(2));
      expect(backends[0].stopped, isTrue);
      expect(backends[0].disposed, isTrue);
      expect(player.state.value.itemId, 'b2');
      expect(player.state.value.phase, StoreAudioPhase.playing);
    });

    test('natural completion flips the item back to paused', () async {
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      backends.single.fireCompletion();
      await pumpEventQueue();
      expect(player.state.value.phase, StoreAudioPhase.paused);
    });

    test('an unresolvable file is an error state, not a crash', () async {
      StoreAudioPreviewPlayer.fileResolverForTest = (item) async => null;
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      expect(player.state.value.phase, StoreAudioPhase.error);
      expect(player.state.value.message, isNotNull);
      expect(backends, isEmpty);
    });

    test('a backend that fails to load is an error state', () async {
      StoreAudioPreviewPlayer.backendFactoryForTest =
          () => FakeAudioBackend(failLoad: true);
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      expect(player.state.value.phase, StoreAudioPhase.error);
    });

    test('stop() releases the backend and idles the player', () async {
      final player = StoreAudioPreviewPlayer.instance;
      await player.toggle(itemA);
      await player.stop();
      expect(player.state.value.phase, StoreAudioPhase.idle);
      expect(player.state.value.itemId, isNull);
      expect(backends.single.disposed, isTrue);
    });
  });

  group('7F — video editor session snapshot', () {
    test('clip map round-trip preserves every editable field', () {
      final clip = VideoClip(
        File('/media/clip one.mp4'),
        const Duration(milliseconds: 12345),
        1.777,
      );
      clip.trimStart = 1.5;
      clip.trimEnd = 9.25;
      clip.isPhoto = true;
      clip.kenBurns = false;
      clip.kbZoomIn = false;
      clip.volume = 0.4;
      clip.muted = true;
      clip.detachedAudioPath = '/media/audio.m4a';
      final back = VideoEditorSession.clipFromMap(
        VideoEditorSession.clipToMap(clip),
      )!;
      expect(back.file.path, '/media/clip one.mp4');
      expect(back.duration.inMilliseconds, 12345);
      expect(back.aspectRatio, 1.777);
      expect(back.trimStart, 1.5);
      expect(back.trimEnd, 9.25);
      expect(back.isPhoto, isTrue);
      expect(back.kenBurns, isFalse);
      expect(back.kbZoomIn, isFalse);
      expect(back.volume, 0.4);
      expect(back.muted, isTrue);
      expect(back.detachedAudioPath, '/media/audio.m4a');
    });

    test('session encode/decode round-trip + freshness window', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final session = VideoEditorSession(
        clips: [
          VideoEditorSession.clipToMap(
            VideoClip(File('/a.mp4'), const Duration(seconds: 3), 1.5),
          ),
        ],
        panel: const {'fxQuality': 2, 'text': 'hello', 'newsEnabled': true},
        selected: 0,
        savedAtMs: now,
      );
      final back = VideoEditorSession.decode(session.encode())!;
      expect(back.clips, hasLength(1));
      expect(back.panel['fxQuality'], 2);
      expect(back.panel['text'], 'hello');
      expect(back.selected, 0);
      expect(back.isFresh(DateTime.now()), isTrue);
      final stale = VideoEditorSession(
        clips: const [],
        panel: const {},
        selected: 0,
        savedAtMs: now - const Duration(days: 8).inMilliseconds,
      );
      expect(stale.isFresh(DateTime.now()), isFalse);
    });

    test('corrupt snapshots decode to null, never throw', () {
      expect(VideoEditorSession.decode('not json'), isNull);
      expect(VideoEditorSession.decode('{"clips": 42}'), isNull);
      expect(VideoEditorSession.decode('[1,2]'), isNull);
      expect(VideoEditorSession.clipFromMap(const {}), isNull);
      expect(
        VideoEditorSession.clipFromMap(const {'path': ''}),
        isNull,
      );
    });

    test('recovery store persists + clears via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      await VideoEditorRecoveryStore.save('{"v":1}');
      expect(await VideoEditorRecoveryStore.load(), '{"v":1}');
      await VideoEditorRecoveryStore.clear();
      expect(await VideoEditorRecoveryStore.load(), isNull);
    });
  });

  group('point #8 — store grid widget', () {
    late Directory tempDir;
    late File audioFile;
    final backends = <FakeAudioBackend>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('b10_grid_');
      audioFile = File('${tempDir.path}/x.mp3');
      await audioFile.writeAsBytes(const [1, 2, 3]);
      backends.clear();
      StoreAudioPreviewPlayer.backendFactoryForTest = () {
        final b = FakeAudioBackend();
        backends.add(b);
        return b;
      };
      StoreAudioPreviewPlayer.fileResolverForTest = (item) async => audioFile;
      StorePreviewCache.overrideDirForTest = tempDir;
    });

    tearDown(() async {
      await StoreAudioPreviewPlayer.resetForTest();
      StorePreviewCache.overrideDirForTest = null;
      StorePreviewCache.resetForTest();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    testWidgets('3-column compact grid; audio cards carry play; '
        'one sounds at a time', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final items = List<StoreItem>.generate(
        9,
        (i) => StoreItem(
          id: 'm$i',
          name: 'Track Number ${i + 1}.mp3',
          category: 'Music',
        ),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_store_listing_v1_Music': jsonEncode(
          items.map((e) => e.toJson()).toList(),
        ),
      });

      await tester.pumpWidget(
        const MaterialApp(home: StoreScreen(initialCategory: 'Music')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The grid is the compact 3-column delegate.
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      // All 9 seeded items are on screen at once (3 rows).
      expect(find.text('Track Number 1'), findsOneWidget);
      expect(find.text('Track Number 9'), findsOneWidget);
      // Every audio card has a play button.
      expect(find.byIcon(Icons.play_arrow), findsNWidgets(9));
      expect(tester.takeException(), isNull);

      // Tap the first card's play: it becomes the sounding one.
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(backends, hasLength(1));

      // Tap a different card's play: the first stops, the new
      // one sounds — still exactly one pause icon on screen.
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(backends, hasLength(2));
      expect(backends[0].disposed, isTrue);
      expect(tester.takeException(), isNull);

      // Flush pending background timers before teardown (the
      // store entry gate's Unity init carries a 10 s timeout).
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
    });
  });
}

/// Test double for [StoreAudioBackend]: records calls, can be
/// told to fail its load, and fires completions on demand.
class FakeAudioBackend implements StoreAudioBackend {
  FakeAudioBackend({this.failLoad = false});

  final bool failLoad;
  File? loadedFile;
  bool playing = false;
  bool stopped = false;
  bool disposed = false;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  @override
  Future<void> load(File file) async {
    if (failLoad) throw StateError('cannot decode');
    loadedFile = file;
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> stop() async {
    stopped = true;
    playing = false;
  }

  @override
  bool get isPlaying => playing;

  @override
  bool get isCompleted => false;

  @override
  Stream<void> get completions => _completions.stream;

  void fireCompletion() => _completions.add(null);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completions.close();
  }
}
