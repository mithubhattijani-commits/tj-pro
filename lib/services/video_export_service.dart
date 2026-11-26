/// Video burn-in — burn styled ASS captions INTO an MP4 on-device
/// (Phase 5, ported from Magic Box's `video_export_service.dart`,
/// v1.0.13 — adapted: Magic Box's per-feature ad gate is NOT ported.
/// TJ Pro's unlock economy is coins only (v1.3.0 §8) and the burn-in
/// itself was never gated; it runs with no gate. The
/// rest — probe, Download folder output, progress — is the same.
///
/// Build 10 (v1.8.0, point #7D): the attempts are now an explicit
/// fallback chain ([ExportChain]), in the user's spec order:
///   1. `hardware` — styled ASS burn-in via the MediaCodec
///      hardware encoder (skipped on LOW-tier phones, see
///      [PerformanceConfig.tryHardwareEncoder]). When the build
///      or the device lacks the encoder, ffmpeg fails fast and
///      the chain moves on — trying costs seconds, never the
///      export.
///   2. `chunked` — the same styled burn-in in short segments
///      (output-side seeking keeps the ASS timing absolute;
///      the shape was verified against a real ffmpeg before it
///      shipped), concatenated at the end. Peak memory per pass
///      is a fraction of the full-length render. Only for
///      videos at least [VideoExportService.chunkMinDurationSeconds]
///      long — below that, chunking saves nothing.
///   3. `software` — the original full-length libx264 ASS
///      burn-in (full style: colours, karaoke, outline,
///      position), byte-identical arguments to the pre-chain
///      Attempt 1.
///   4. `software-plain` — the original drawtext fallback
///      (per-line `drawtext`; plain white/border, no karaoke).
///      Urdu in this fallback still cannot shape (drawtext
///      limitation) — the ASS attempts are what carry Urdu.
/// A user cancel stops the chain immediately (never falls
/// through), exactly as before.
///
/// Quality 720p/1080p; scale `scale=<target>:-2` (vertical) or
/// `scale=-2:<target>` (horizontal); progress 0–1 from ffmpeg stats
/// via ffprobe duration; output to the phone's Download folder as
/// `<name>_captioned_<720p|1080p>.mp4`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;


import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'export_chain.dart';
import 'ffmpeg_service.dart';
import 'model_pack_service.dart';
import 'onnx_image_service.dart';
import 'onnx_isolate.dart';
import 'performance_engine.dart';

/// Burn-in quality.
enum VideoExportQuality {
  p720,
  p1080,
  p2160;

  String get label => switch (this) {
        VideoExportQuality.p720 => '720p',
        VideoExportQuality.p1080 => '1080p',
        VideoExportQuality.p2160 => '4K',
      };

  /// Target height for a horizontal video / target width for a
  /// vertical one.
  int get target => switch (this) {
        VideoExportQuality.p720 => 720,
        VideoExportQuality.p1080 => 1080,
        VideoExportQuality.p2160 => 2160,
      };
}

/// Video dimensions + duration from ffprobe.
class VideoSize {
  const VideoSize({
    required this.width,
    required this.height,
    this.durationSeconds,
  });

  final int width;
  final int height;

  /// Media duration in seconds (from MediaInformation.getDuration()),
  /// null when ffprobe did not report one.
  final double? durationSeconds;

  bool get isVertical => height > width;

  /// ASS canvas for this video: portrait 1080x1920 for vertical
  /// video, landscape 1280x720 for horizontal.
  ({int x, int y}) get assCanvas =>
      isVertical ? (x: 1080, y: 1920) : (x: 1280, y: 720);
}

/// Result of one burn-in export attempt.
class VideoExportResult {
  const VideoExportResult({
    required this.success,
    this.outputPath,
    this.error,
    this.cancelled = false,
    this.strategy,
  });

  final bool success;
  final String? outputPath;
  final String? error;

  /// True when the export was stopped via
  /// [VideoExportService.cancelCurrentExport] (Phase 0) — the UI
  /// then says "cancelled" instead of showing an ffmpeg failure.
  final bool cancelled;

  /// Build 10 (7D): which fallback-chain strategy produced the
  /// file ('hardware' / 'chunked' / 'software' /
  /// 'software-plain'); null on failure / cancel.
  final String? strategy;
}

/// One chain attempt's outcome inside [VideoExportService]:
/// success, user-cancel, or failure with the ffmpeg logs that
/// explain it.
class _BurnOutcome {
  const _BurnOutcome({required this.ok, this.cancelled = false, this.logs = ''});

  final bool ok;
  final bool cancelled;
  final String logs;
}

class VideoExportService {
  /// Read the video stream size (+ duration) with ffprobe. Null
  /// when the file cannot be probed — callers then fall back to the
  /// landscape canvas / horizontal scale.
  static Future<VideoSize?> probeVideoSize(File video) async {
    try {
      final session = await FFprobeKit.getMediaInformation(video.path);
      final info = session.getMediaInformation();
      final duration = double.tryParse(info?.getDuration() ?? '');
      final streams = info?.getStreams();
      if (streams == null) return null;
      for (final s in streams) {
        if (s.getType() == 'video') {
          final w = s.getWidth();
          final h = s.getHeight();
          if (w != null && h != null && w > 0 && h > 0) {
            return VideoSize(
              width: w,
              height: h,
              durationSeconds: duration,
            );
          }
        }
      }
    } catch (_) {
      // Probe failure: caller falls back to landscape.
    }
    return null;
  }

  /// Scale filter for [quality]: vertical video scales by width,
  /// horizontal by height.
  static String scaleFor(VideoExportQuality quality, bool vertical) =>
      vertical
          ? 'scale=${quality.target}:-2'
          : 'scale=-2:${quality.target}';

  /// Escape a file path for use inside an ffmpeg filter argument:
  /// backslash, colon and single-quote all need escaping.
  static String escapeFilterPath(String path) => path
      .replaceAll(r'\', r'\\')
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'");

  /// Attempt-1 ffmpeg arguments: styled ASS burn-in.
  /// Pure builder (no ffmpeg run) — unit-tested, and the filter
  /// graph it builds is what Phase 7's reel export reuses.
  static List<String> burnInArgs({
    required String inputPath,
    required String assPath,
    required String outputPath,
    required VideoExportQuality quality,
    required bool vertical,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-vf',
      '${scaleFor(quality, vertical)},subtitles=${escapeFilterPath(assPath)}',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }

  /// Attempt-2 ffmpeg arguments: drawtext fallback with a
  /// pre-built [drawtextFilter] (see [buildDrawtextFilter]).
  static List<String> burnInDrawtextArgs({
    required String inputPath,
    required String drawtextFilter,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-vf',
      drawtextFilter,
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }

  /// Videos shorter than this never take the chain's chunked
  /// attempt — segmenting them saves no memory worth having.
  static const double chunkMinDurationSeconds = 60;

  /// Bitrate ladder (kbps) for the hardware attempt — the
  /// MediaCodec encoder takes a target bitrate, not CRF. Same
  /// YouTube-recommended ladder [ExportSettings] uses.
  static int hardwareBitrateKbpsFor(VideoExportQuality quality) =>
      switch (quality) {
        VideoExportQuality.p720 => 2500,
        VideoExportQuality.p1080 => 5000,
        VideoExportQuality.p2160 => 12000,
      };

  /// Chain attempt `hardware`: styled ASS burn-in encoded by
  /// the device's MediaCodec H.264 encoder. Pure builder —
  /// unit-tested like [burnInArgs].
  static List<String> burnInHardwareArgs({
    required String inputPath,
    required String assPath,
    required String outputPath,
    required VideoExportQuality quality,
    required bool vertical,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-vf',
      '${scaleFor(quality, vertical)},subtitles=${escapeFilterPath(assPath)}',
      '-c:v',
      'h264_mediacodec',
      '-b:v',
      '${hardwareBitrateKbpsFor(quality)}k',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }

  /// Chain attempt `chunked`: ONE segment of the styled ASS
  /// burn-in. `-ss`/`-t` sit AFTER `-i` (output seeking):
  /// ffmpeg decodes from the start and drops frames before
  /// [startSeconds], so the frames reaching the subtitles
  /// filter keep their ORIGINAL timestamps and the ASS events
  /// land at the right absolute times (verified against a
  /// real ffmpeg — see BUILD10-TOOL-TESTS). Audio is
  /// re-encoded to a fixed AAC profile so every segment
  /// shares one codec configuration and the concat step can
  /// stream-copy.
  static List<String> burnInSegmentArgs({
    required String inputPath,
    required String assPath,
    required String outputPath,
    required VideoExportQuality quality,
    required bool vertical,
    required double startSeconds,
    required double lengthSeconds,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-ss',
      startSeconds.toStringAsFixed(3),
      '-t',
      lengthSeconds.toStringAsFixed(3),
      '-vf',
      '${scaleFor(quality, vertical)},subtitles=${escapeFilterPath(assPath)}',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      outputPath,
    ];
  }

  /// Chain attempt `chunked`, final step: join the segments
  /// (same codec configuration throughout) with the concat
  /// demuxer, stream copy, faststart for instant playback.
  static List<String> burnInConcatArgs({
    required String listPath,
    required String outputPath,
  }) {
    return [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listPath,
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }

  /// The FFmpeg session this service is currently running, if
  /// any (Phase 0 registry for THIS service's direct FFmpegKit
  /// calls — runs through [FfmpegService.run] register there
  /// instead). Powers [cancelCurrentExport].
  static int? _activeSessionId;

  /// Cancels the ffmpeg pass this service is currently running
  /// (Phase 0 export CANCEL path). The in-flight [exportVideo]
  /// then returns a result with `cancelled == true` instead of
  /// falling through to its drawtext retry. A no-op when idle.
  static Future<void> cancelCurrentExport() async {
    final int? sessionId = _activeSessionId;
    if (sessionId == null) return;
    try {
      await FFmpegKit.cancel(sessionId);
    } catch (_) {
      // Best-effort: a failed cancel leaves the export running,
      // which is the pre-Phase-0 behaviour — never a crash.
    }
  }

  /// Run one ffmpeg command asynchronously and wait for its
  /// completion callback. [onProgress] (0.0–1.0) fires from the
  /// statistics callback when [durationSeconds] is known.
  static Future<FFmpegSession> _execute(
    List<String> args, {
    void Function(double progress)? onProgress,
    double? durationSeconds,
  }) async {
    final done = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        if (!done.isCompleted) done.complete(session);
      },
      null,
      (stats) {
        if (onProgress != null &&
            durationSeconds != null &&
            durationSeconds > 0) {
          onProgress(
            (stats.getTime() / 1000 / durationSeconds).clamp(0.0, 1.0),
          );
        }
      },
    );
    _activeSessionId = session.getSessionId();
    try {
      return await done.future;
    } finally {
      if (_activeSessionId == session.getSessionId()) {
        _activeSessionId = null;
      }
    }
  }

  /// Burn [assContent] into [inputVideo] and write the captioned MP4
  /// to the phone's Download folder. No ad is shown (see the file
  /// header — no ad gate in TJ Pro v1). [onProgress] fires 0.0–1.0
  /// while ffmpeg runs (only when ffprobe reported a duration).
  static Future<VideoExportResult> exportVideo({
    required File inputVideo,
    required String assContent,
    required VideoExportQuality quality,
    required String baseName,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tmp = await getTemporaryDirectory();
      // Phase 0 pre-run discipline: cancel any ffmpeg session a
      // previous run left behind, and sweep stale burn-in scratch
      // files from crashed/killed runs out of the temp cache.
      await FfmpegService.prepareForNewRun();
      await FfmpegService.cleanStaleTempFiles(
        tmp,
        prefixes: const ['caption_burn_'],
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final assFile = File('${tmp.path}/caption_burn_$stamp.ass');
      await assFile.writeAsString(assContent);

      final extDir = await getExternalStorageDirectory();
      final downloads = Directory('${extDir?.path}/Download');
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      final safeBase = baseName
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
          .trim();
      final outPath =
          '${downloads.path}/${safeBase.isEmpty ? 'tj_pro' : safeBase}'
          '_captioned_${quality.label}.mp4';

      final size = await probeVideoSize(inputVideo);
      final vertical = size?.isVertical ?? false;
      final duration = size?.durationSeconds;
      final engineConfig = PerformanceEngine.instance.config.value;

      // Runs one ffmpeg attempt and folds its return code into
      // a _BurnOutcome. A user cancel surfaces as
      // `cancelled: true` and stops the whole chain (Phase 0
      // rule — a cancel never falls through to a retry).
      Future<_BurnOutcome> runAttempt(
        List<String> args, {
        double? progressDuration,
        void Function(double progress)? progress,
      }) async {
        final session = await _execute(
          args,
          onProgress: progress ?? onProgress,
          durationSeconds: progressDuration ?? duration,
        );
        final rc = await session.getReturnCode();
        if (ReturnCode.isCancel(rc)) {
          return const _BurnOutcome(ok: false, cancelled: true);
        }
        if (ReturnCode.isSuccess(rc)) {
          return const _BurnOutcome(ok: true);
        }
        return _BurnOutcome(
          ok: false,
          logs: await session.getAllLogsAsString() ?? '',
        );
      }

      final attemptLogs = <String, String>{};
      ExportAttempt<_BurnOutcome> tracked(
        String name,
        Future<_BurnOutcome> Function() body,
      ) {
        return ExportAttempt<_BurnOutcome>(
          name: name,
          run: () async {
            final outcome = await body();
            if (outcome.logs.isNotEmpty) attemptLogs[name] = outcome.logs;
            return outcome;
          },
        );
      }

      // Build 10 (7D): the fallback chain, in spec order —
      // hardware → chunked → software → software-plain. The
      // last two are the pre-chain attempts 1 and 2 with
      // byte-identical arguments.
      final attempts = <ExportAttempt<_BurnOutcome>>[
        if (engineConfig.tryHardwareEncoder)
          tracked(
            'hardware',
            () => runAttempt(
              burnInHardwareArgs(
                inputPath: inputVideo.path,
                assPath: assFile.path,
                outputPath: outPath,
                quality: quality,
                vertical: vertical,
              ),
            ),
          ),
        if (duration != null && duration >= chunkMinDurationSeconds)
          tracked(
            'chunked',
            () => _chunkedBurnIn(
              inputPath: inputVideo.path,
              assPath: assFile.path,
              outputPath: outPath,
              quality: quality,
              vertical: vertical,
              durationSeconds: duration,
              chunkSeconds: engineConfig.exportChunkSeconds,
              tmp: tmp,
              stamp: stamp,
              onProgress: onProgress,
              runAttempt: runAttempt,
            ),
          ),
        tracked(
          'software',
          () => runAttempt(
            burnInArgs(
              inputPath: inputVideo.path,
              assPath: assFile.path,
              outputPath: outPath,
              quality: quality,
              vertical: vertical,
            ),
          ),
        ),
        tracked(
          'software-plain',
          () async {
            // Drawtext fallback (one drawtext per line). The
            // style is plainer (no karaoke), but the captions
            // still land in the video instead of failing
            // outright. The filter is built lazily, only when
            // the chain actually reaches this attempt — the
            // same laziness the pre-chain code had.
            final drawtextFilter = await buildDrawtextFilter(
              assContent: assContent,
              scale: scaleFor(quality, vertical),
              quality: quality,
              vertical: vertical,
            );
            if (drawtextFilter == null) {
              return const _BurnOutcome(
                ok: false,
                logs: 'drawtext: no caption lines parsed',
              );
            }
            return runAttempt(
              burnInDrawtextArgs(
                inputPath: inputVideo.path,
                drawtextFilter: drawtextFilter,
                outputPath: outPath,
              ),
            );
          },
        ),
      ];

      final outcome = await ExportChain.run<_BurnOutcome>(
        attempts: attempts,
        isSuccess: (r) => r.ok,
        isCancelled: (r) => r.cancelled,
      );
      if (outcome.cancelled) {
        return const VideoExportResult(
          success: false,
          cancelled: true,
          error: 'Export cancelled.',
        );
      }
      if (outcome.succeeded) {
        return VideoExportResult(
          success: true,
          outputPath: outPath,
          strategy: outcome.attemptName,
        );
      }
      // Every strategy failed: the reason shown is the styled
      // (software) attempt's logs when there are any — the
      // pre-chain preference — else the last attempt's.
      final tail = (attemptLogs['software'] ??
              attemptLogs[outcome.triedAttempts.last] ??
              '')
          .trim();
      final shown = tail.length > 600
          ? tail.substring(tail.length - 600)
          : tail;
      return VideoExportResult(
        success: false,
        error: shown.isEmpty
            ? 'ffmpeg failed (no log output).'
            : 'ffmpeg failed: $shown',
      );
    } catch (e) {
      return VideoExportResult(success: false, error: e.toString());
    }
  }

  /// Chain attempt `chunked`: render the styled burn-in in
  /// [chunkSeconds]-long segments (see [burnInSegmentArgs] for
  /// why the timing stays correct), then concat them into
  /// [outputPath]. Any segment failing abandons the attempt —
  /// the chain moves on to the full-length software render.
  /// Segment files are always cleaned up; a crashed run's
  /// leftovers are swept by the `caption_burn_` stale-file
  /// pass at the start of [exportVideo].
  static Future<_BurnOutcome> _chunkedBurnIn({
    required String inputPath,
    required String assPath,
    required String outputPath,
    required VideoExportQuality quality,
    required bool vertical,
    required double durationSeconds,
    required int chunkSeconds,
    required Directory tmp,
    required int stamp,
    required void Function(double progress)? onProgress,
    required Future<_BurnOutcome> Function(
      List<String> args, {
      double? progressDuration,
      void Function(double progress)? progress,
    }) runAttempt,
  }) async {
    final count = (durationSeconds / chunkSeconds).ceil();
    final segments = <File>[];
    final listFile = File('${tmp.path}/caption_burn_seg_$stamp.txt');
    try {
      for (var i = 0; i < count; i++) {
        final start = i * chunkSeconds.toDouble();
        final length = math.min(
          chunkSeconds.toDouble(),
          durationSeconds - start,
        );
        if (length <= 0) break;
        final segPath = '${tmp.path}/caption_burn_seg_${stamp}_$i.mp4';
        final outcome = await runAttempt(
          burnInSegmentArgs(
            inputPath: inputPath,
            assPath: assPath,
            outputPath: segPath,
            quality: quality,
            vertical: vertical,
            startSeconds: start,
            lengthSeconds: length,
          ),
          progressDuration: length,
          // Segment-local progress re-mapped onto the whole
          // video: segment i covers [i/count, (i+1)/count].
          progress: onProgress == null
              ? null
              : (p) => onProgress((i + p) / count),
        );
        if (outcome.cancelled || !outcome.ok) return outcome;
        segments.add(File(segPath));
      }
      if (segments.isEmpty) {
        return const _BurnOutcome(ok: false, logs: 'chunked: no segments');
      }
      final buf = StringBuffer();
      for (final seg in segments) {
        buf.writeln("file '${seg.path.replaceAll("'", r"'\''")}'");
      }
      await listFile.writeAsString(buf.toString());
      return await runAttempt(
        burnInConcatArgs(listPath: listFile.path, outputPath: outputPath),
        progressDuration: durationSeconds,
      );
    } finally {
      for (final seg in segments) {
        try {
          await seg.delete();
        } catch (_) {
          // Swept by the next run's stale-file pass.
        }
      }
      try {
        await listFile.delete();
      } catch (_) {
        // Same sweep.
      }
    }
  }

  /// Build the drawtext fallback filter from the ASS text: parses the
  /// Dialogue lines back out of [assContent] (start/end/text) and
  /// makes one drawtext per line. Null when no lines parse.
  /// Latin scripts only in practice — drawtext does not shape Arabic
  /// script (see the file header).
  static Future<String?> buildDrawtextFilter({
    required String assContent,
    required String scale,
    required VideoExportQuality quality,
    required bool vertical,
  }) async {
    final lines = <({double start, double end, String text})>[];
    for (final raw in assContent.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('Dialogue:')) continue;
      final parts = line.substring('Dialogue:'.length).split(',');
      // Dialogue: Layer, Start, End, Style, Name, MarginL, MarginR,
      // MarginV, Effect, Text (text may itself contain commas).
      if (parts.length < 10) continue;
      final start = _assSeconds(parts[1].trim());
      final end = _assSeconds(parts[2].trim());
      final text = parts.sublist(9).join(',').trim();
      if (start == null || end == null || text.isEmpty) continue;
      final clean = text
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', ' ')
          .trim();
      if (clean.isNotEmpty) {
        lines.add((start: start, end: end, text: clean));
      }
    }
    if (lines.isEmpty) return null;

    final fontFile = await _findFontFile();
    final fontSize = vertical
        ? (quality == VideoExportQuality.p1080 ? 84 : 56)
        : (quality == VideoExportQuality.p1080 ? 72 : 48);
    final yPos = quality == VideoExportQuality.p1080 ? 'h-260' : 'h-160';
    final filters = <String>[scale];
    for (final l in lines) {
      final text = l.text
          .replaceAll(r'\', r'\\')
          .replaceAll(':', r'\:')
          .replaceAll("'", r"\'")
          .replaceAll('%', r'\%');
      final fontPart = fontFile != null
          ? "fontfile='${escapeFilterPath(fontFile)}'"
          : 'font=sans-serif';
      filters.add(
        "drawtext=text='$text':$fontPart:fontsize=$fontSize:"
        "fontcolor=white:borderw=2:bordercolor=black:"
        "x=(w-text_w)/2:y=$yPos:box=1:boxcolor=black@0.5:"
        "enable='between(t,${l.start},${l.end})'",
      );
    }
    return filters.join(',');
  }

  // ------------------------------------------------------------------
  // v1.4.0 — MODNet HQ background removal (export path)
  // ------------------------------------------------------------------

  /// HQ background removal for ONE exported video: frames are
  /// sampled at [sampleFps], each frame's alpha matte comes from
  /// the MODNet ONNX pack via [OnnxImageService.alphaMatte]
  /// ('modnet', 512×512 — the tool-test battery's PASS verdict for
  /// video matting, Apache-2.0), the matted RGBA frames are then
  /// composited over the chosen background with ffmpeg's overlay
  /// (the matte is held between sampled frames and upsampled to
  /// 30 fps — the same hold behaviour as the ML Kit path in
  /// pro_vision.dart, but with the sharper MODNet matte).
  ///
  /// Returns the composited MP4 path inside [workDir]. Throws an
  /// [Exception] with a plain message on any failure (missing pack,
  /// unprobeable input, ffmpeg failure) — callers keep the previous
  /// output and fall back to the ML Kit path.
  static Future<String> modnetRemoveBackground({
    required String input,
    required String backgroundKind,
    String? backgroundColor,
    String? backgroundImagePath,
    required Directory workDir,
    double sampleFps = 5,
    int width = 480,
    void Function(double progress)? onProgress,
    void Function(String step)? onStep,
  }) async {
    final packs = ModelPackService.instance;
    final ready = await packs.ensurePack('modnet');
    if (!ready) {
      // v1.5.0 (#27): typed reason, never a blanket internet blame.
      throw Exception(
        'MODNet model pack: '
        '${ModelPackService.describeFailure(packs.lastFailure)}',
      );
    }
    final size = await probeVideoSize(File(input));
    if (size == null) {
      throw Exception('Video ka size probe nahi hua.');
    }
    var outW = size.width;
    var outH = size.height;
    outW -= outW % 2;
    outH -= outH % 2;
    var cutW = width.clamp(2, 480);
    cutW -= cutW % 2;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final framesDir = Directory(p.join(workDir.path, 'modnet_f_$stamp'));
    final rgbaDir = Directory(p.join(workDir.path, 'modnet_r_$stamp'));
    await framesDir.create(recursive: true);
    await rgbaDir.create(recursive: true);

    onStep?.call('Frames…');
    final extract = await _execute([
      '-y',
      '-i',
      input,
      '-vf',
      'fps=$sampleFps,scale=$cutW:-2',
      p.join(framesDir.path, 'frame_%04d.png'),
    ]);
    if (!ReturnCode.isSuccess(await extract.getReturnCode())) {
      throw Exception('MODNet frame extract fail ho gaya.');
    }
    final frameFiles = framesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (frameFiles.isEmpty) {
      throw Exception('MODNet ke liye koi frame nahi mila.');
    }

    onStep?.call('Matte (MODNet)…');
    // v1.17.0 (G1, Point #37a): each frame's matte runs in a
    // background isolate — the old loop decoded, inferred and
    // PNG-encoded every frame on the UI isolate, freezing the
    // export screen for the whole matte pass. The runner returns
    // the matted frame as PNG bytes, written as-is.
    Uint8List? lastMattePng;
    for (var i = 0; i < frameFiles.length; i++) {
      final bytes = await frameFiles[i].readAsBytes();
      final mattePng = await runOnnxOpOffThread(
        op: kOnnxOpMatte,
        packId: 'modnet',
        inputBytes: bytes,
      );
      if (mattePng != null) lastMattePng = mattePng;
      if (lastMattePng == null) {
        throw Exception('MODNet matte nahi bana (pack issue).');
      }
      final name = 'frame_${(i + 1).toString().padLeft(4, '0')}.png';
      await File(p.join(rgbaDir.path, name)).writeAsBytes(lastMattePng);
      onProgress?.call((i + 1) / frameFiles.length * 0.7);
    }

    onStep?.call('Compositing…');
    final outPath = p.join(workDir.path, 'modnet_bg_$stamp.mp4');
    final args = <String>['-y', '-i', input];
    if (backgroundKind == 'image' &&
        backgroundImagePath != null &&
        backgroundImagePath.isNotEmpty) {
      args.addAll(['-loop', '1', '-framerate', '30', '-i', backgroundImagePath]);
    } else {
      var hex = (backgroundColor ?? '#000000').replaceAll('#', '');
      if (hex.length != 6) hex = '000000';
      args.addAll([
        '-f',
        'lavfi',
        '-i',
        'color=c=0x$hex:s=${outW}x$outH:r=30',
      ]);
    }
    args.addAll([
      '-framerate',
      '$sampleFps',
      '-i',
      p.join(rgbaDir.path, 'frame_%04d.png'),
      '-filter_complex',
      '[2:v]fps=30,scale=$outW:$outH:flags=lanczos,format=rgba[fg];'
          '[1:v]scale=$outW:$outH,format=yuv420p[bg];'
          '[bg][fg]overlay=0:0:format=auto,format=yuv420p[vout]',
      '-map',
      '[vout]',
      '-map',
      '0:a?',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'copy',
      '-shortest',
      '-movflags',
      '+faststart',
      outPath,
    ]);
    final composite = await _execute(
      args,
      onProgress: (v) => onProgress?.call(0.7 + v * 0.3),
      durationSeconds: size.durationSeconds,
    );
    if (!ReturnCode.isSuccess(await composite.getReturnCode())) {
      final logs = await composite.getAllLogsAsString() ?? '';
      final tail = logs.length > 400 ? logs.substring(logs.length - 400) : logs;
      throw Exception('MODNet composite fail: $tail');
    }
    onProgress?.call(1);
    return outPath;
  }

  // ------------------------------------------------------------------
  // v1.4.0 — Smooth Slow-Mo (AI): RIFE v4.6 frame interpolation
  // ------------------------------------------------------------------

  /// AI smooth slow-motion for ONE clip file: consecutive frames
  /// are extracted at 24 fps (processing scale capped at
  /// 448×256), RIFE v4.6 (the `rife_v46` pack) interpolates the
  /// midpoint frame of every pair (input tensor [1,7,H,W] =
  /// frame A + frame B + a 0.5 timestep plane — exactly the
  /// pre/post-processing verified in
  /// tool-tests/05-audio-rife/rife/run_rife.py), and the doubled
  /// frame sequence is re-encoded at the same 24 fps with the
  /// audio slowed by atempo 0.5 — so the result plays at half
  /// speed with REAL in-between frames instead of duplicated ones.
  ///
  /// Cap: clips up to ~10 s (longer input throws a plain-message
  /// [Exception]). A missing pack also throws — fail-soft at the
  /// CALLER, which keeps the original clip and shows the message.
  /// Returns the slow-mo MP4 path inside [workDir].
  static Future<String> smoothSlowMoAi({
    required String inputPath,
    required Directory workDir,
    void Function(double progress)? onProgress,
  }) async {
    final packs = ModelPackService.instance;
    final ready = await packs.ensurePack('rife_v46');
    if (!ready) {
      // v1.5.0 (#27): the pack IS hosted now (nigraantv.xyz mirror);
      // whatever went wrong, say the true typed reason.
      throw Exception(
        'Smooth Slow-Mo ka model pack (rife_v46): '
        '${ModelPackService.describeFailure(packs.lastFailure)}',
      );
    }
    final model = await packs.packFile('rife_v46', 'rife_v4.6.onnx');
    if (model == null) {
      throw Exception('Smooth Slow-Mo ka model file nahi mila.');
    }
    final size = await probeVideoSize(File(inputPath));
    if (size == null) {
      throw Exception('Clip ka size probe nahi hua.');
    }
    final dur = size.durationSeconds ?? 0;
    if (dur <= 0 || dur > 10.5) {
      throw Exception(
        'Smooth Slow-Mo sirf ~10s tak ki clip par lagta hai '
        '(ye clip ${dur.toStringAsFixed(1)}s hai).',
      );
    }
    // Processing scale: fit inside 448×256, even dimensions.
    var sw = size.width > 448 ? 448 : size.width;
    var sh = (size.height * sw / size.width).round();
    if (sh > 256) {
      sh = 256;
      sw = (size.width * sh / size.height).round();
    }
    sw -= sw % 2;
    sh -= sh % 2;
    if (sw < 2 || sh < 2) {
      throw Exception('Clip bohat chhota hai slow-mo ke liye.');
    }
    // RIFE wants multiples of 32 — pad by edge replication.
    final pw = ((sw + 31) ~/ 32) * 32;
    final ph = ((sh + 31) ~/ 32) * 32;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final framesDir = Directory(p.join(workDir.path, 'rife_f_$stamp'));
    final outDir = Directory(p.join(workDir.path, 'rife_o_$stamp'));
    await framesDir.create(recursive: true);
    await outDir.create(recursive: true);

    const fps = 24;
    final extract = await _execute([
      '-y',
      '-i',
      inputPath,
      '-vf',
      'fps=$fps,scale=$sw:$sh',
      p.join(framesDir.path, 'frame_%04d.png'),
    ]);
    if (!ReturnCode.isSuccess(await extract.getReturnCode())) {
      throw Exception('Slow-mo frame extract fail ho gaya.');
    }
    final frameFiles = framesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (frameFiles.length < 2) {
      throw Exception('Slow-mo ke liye kam az kam 2 frames chahiye.');
    }
    // v1.17.0 (G1, Point #37a): the interpolation loop —
    // decode every frame, build a 7-plane tensor per pair,
    // run the synchronous ONNX session, encode two PNGs per
    // pair — used to run entirely on the calling (UI) isolate:
    // minutes of UI block on a 10 s clip, the same ANR class
    // as the BG-remove freeze. It now runs in ONE background
    // isolate (file paths cross, frames never do). FFmpeg
    // extraction/encode stay here — FFmpegKit is a platform
    // channel and cannot run in a background isolate.
    onProgress?.call(0.05);
    final String? rifeError = await compute(
      rifeInterpolateIsolateJob,
      <dynamic>[framesDir.path, outDir.path, model.path, pw, ph, sw, sh],
    );
    if (rifeError != null) {
      throw Exception(rifeError);
    }
    onProgress?.call(0.85);

    var outW = size.width;
    var outH = size.height;
    outW -= outW % 2;
    outH -= outH % 2;
    final outPath = p.join(workDir.path, 'slowmo_$stamp.mp4');
    final encode = await _execute(
      [
        '-y',
        '-framerate',
        '$fps',
        '-i',
        p.join(outDir.path, 'frame_%04d.png'),
        '-i',
        inputPath,
        '-filter_complex',
        '[0:v]scale=$outW:$outH:flags=lanczos,format=yuv420p[v];'
            '[1:a]atempo=0.5[a]',
        '-map',
        '[v]',
        '-map',
        '[a]',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '23',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        outPath,
      ],
      onProgress: (v) => onProgress?.call(0.85 + v * 0.15),
      durationSeconds: dur * 2,
    );
    if (!ReturnCode.isSuccess(await encode.getReturnCode())) {
      // No audio track (or atempo failed): re-encode video-only.
      final silent = await _execute([
        '-y',
        '-framerate',
        '$fps',
        '-i',
        p.join(outDir.path, 'frame_%04d.png'),
        '-vf',
        'scale=$outW:$outH:flags=lanczos,format=yuv420p',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '23',
        '-movflags',
        '+faststart',
        outPath,
      ]);
      if (!ReturnCode.isSuccess(await silent.getReturnCode())) {
        throw Exception('Slow-mo encode fail ho gaya.');
      }
    }
    onProgress?.call(1);
    return outPath;
  }

  static double? _assSeconds(String stamp) {
    // H:MM:SS.cc
    final parts = stamp.split(':');
    if (parts.length != 3) return null;
    final h = double.tryParse(parts[0]);
    final m = double.tryParse(parts[1]);
    final s = double.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return h * 3600 + m * 60 + s;
  }

  /// Best system font for drawtext on Android (Urdu-capable first).
  /// Null when none of the known paths exists — the caller then uses
  /// fontconfig's sans-serif instead.
  static Future<String?> _findFontFile() async {
    const candidates = [
      '/system/fonts/NotoNaskhArabic-Regular.ttf',
      '/system/fonts/NotoNastaliqUrdu-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
      '/system/fonts/Roboto-Regular.ttf',
    ];
    for (final path in candidates) {
      try {
        if (await File(path).exists()) return path;
      } catch (_) {}
    }
    return null;
  }
}


/// v1.17.0 (G1): the RIFE interpolation loop as a background
/// isolate job. Args: [framesDirPath, outDirPath, modelPath,
/// pw, ph, sw, sh] (padded + display sizes). Returns null on
/// success or the user-facing error line on failure — the same
/// messages the on-thread loop threw. Pure Dart + FFI + file
/// I/O only; the caller ([VideoExportService.smoothSlowMoAi])
/// owns the FFmpeg steps before and after.
String? rifeInterpolateIsolateJob(List<dynamic> args) {
  final framesDir = Directory(args[0] as String);
  final outDir = Directory(args[1] as String);
  final model = File(args[2] as String);
  final pw = args[3] as int;
  final ph = args[4] as int;
  final sw = args[5] as int;
  final sh = args[6] as int;
  try {
    final frameFiles = framesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (frameFiles.length < 2) {
      return 'Slow-mo ke liye kam az kam 2 frames chahiye.';
    }
    final frames = <img.Image>[];
    for (final f in frameFiles) {
      final decoded = img.decodeImage(f.readAsBytesSync());
      if (decoded == null) {
        return 'Ek frame decode nahi hua.';
      }
      frames.add(decoded);
    }
    OrtEnv.instance.init();
    final session = OrtSession.fromFile(model, OrtSessionOptions());
    try {
      final inputName = session.inputNames.first;
      var outIndex = 0;
      void writeOut(img.Image image) {
        outIndex++;
        final name = 'frame_${outIndex.toString().padLeft(4, '0')}.png';
        File(p.join(outDir.path, name)).writeAsBytesSync(img.encodePng(image));
      }

      writeOut(frames.first);
      for (var i = 0; i < frames.length - 1; i++) {
        final a = frames[i];
        final b = frames[i + 1];
        // Input [1,7,H,W]: A RGB, B RGB, timestep plane 0.5 —
        // channels in 0..1 (run_rife.py).
        final data = Float32List(7 * ph * pw);
        for (var y = 0; y < ph; y++) {
          final cy = y < sh ? y : sh - 1;
          for (var x = 0; x < pw; x++) {
            final cx = x < sw ? x : sw - 1;
            final idx = y * pw + x;
            final pa = a.getPixel(cx, cy);
            final pb = b.getPixel(cx, cy);
            data[idx] = pa.r.toDouble() / 255;
            data[ph * pw + idx] = pa.g.toDouble() / 255;
            data[2 * ph * pw + idx] = pa.b.toDouble() / 255;
            data[3 * ph * pw + idx] = pb.r.toDouble() / 255;
            data[4 * ph * pw + idx] = pb.g.toDouble() / 255;
            data[5 * ph * pw + idx] = pb.b.toDouble() / 255;
            data[6 * ph * pw + idx] = 0.5;
          }
        }
        final tensor = OrtValueTensor.createTensorWithDataList(
          data,
          [1, 7, ph, pw],
        );
        final outputs = session.run(OrtRunOptions(), {inputName: tensor});
        tensor.release();
        if (outputs.isEmpty || outputs.first == null) {
          for (final o in outputs) {
            o?.release();
          }
          return 'RIFE se koi output nahi aaya.';
        }
        final raw = _rifeFlattenFloats(
          (outputs.first! as OrtValueTensor).value,
        );
        for (final o in outputs) {
          o?.release();
        }
        if (raw.length < 3 * ph * pw) {
          return 'RIFE output adhoora hai.';
        }
        final mid = img.Image(width: sw, height: sh, numChannels: 3);
        for (var y = 0; y < sh; y++) {
          for (var x = 0; x < sw; x++) {
            final idx = y * pw + x;
            int ch(int plane) =>
                (raw[plane * ph * pw + idx].clamp(0.0, 1.0) * 255).round();
            mid.setPixelRgb(x, y, ch(0), ch(1), ch(2));
          }
        }
        writeOut(mid);
        writeOut(b);
      }
    } finally {
      session.release();
    }
    return null;
  } catch (e) {
    return 'Smooth Slow-Mo fail ho gaya: $e';
  }
}

/// Flattens an OrtValue payload (typed list or nested lists)
/// into a fresh Float32List — the isolate job's own copy of
/// the tolerance the on-thread loop had.
Float32List _rifeFlattenFloats(Object? value) {
  if (value is Float32List) return Float32List.fromList(value);
  if (value is Float64List) return Float32List.fromList(value);
  if (value is List) {
    final buf = <double>[];
    void walk(Object? e) {
      if (e is List) {
        for (final s in e) {
          walk(s);
        }
      } else if (e is num) {
        buf.add(e.toDouble());
      }
    }

    walk(value);
    return Float32List.fromList(buf);
  }
  return Float32List(0);
}
