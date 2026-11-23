/// Video burn-in — burn styled ASS captions INTO an MP4 on-device
/// (Phase 5, ported from Magic Box's `video_export_service.dart`,
/// v1.0.13 — adapted: Magic Box's per-feature ad gate is NOT ported.
/// TJ Pro's unlock economy is coins only (v1.3.0 §8) and the burn-in
/// itself was never gated; it runs with no gate. The
/// rest — probe, subtitles attempt, drawtext fallback, Download
/// folder output, progress — is the same.
///
/// Attempt 1: `subtitles` filter with the styled ASS file (full
/// style: colours, karaoke, outline, position).
/// Attempt 2 (fallback): per-line `drawtext` (parses Dialogue lines
/// back out of the ASS; plain white/border, no karaoke). Urdu in the
/// fallback still cannot shape (drawtext limitation) — the ASS
/// attempt is what carries Urdu.
///
/// Quality 720p/1080p; scale `scale=<target>:-2` (vertical) or
/// `scale=-2:<target>` (horizontal); progress 0–1 from ffmpeg stats
/// via ffprobe duration; output to the phone's Download folder as
/// `<name>_captioned_<720p|1080p>.mp4`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ffmpeg_service.dart';
import 'model_pack_service.dart';
import 'onnx_image_service.dart';

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
  });

  final bool success;
  final String? outputPath;
  final String? error;

  /// True when the export was stopped via
  /// [VideoExportService.cancelCurrentExport] (Phase 0) — the UI
  /// then says "cancelled" instead of showing an ffmpeg failure.
  final bool cancelled;
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

      // Attempt 1: styled ASS burn-in (subtitles filter).
      var session = await _execute(
        burnInArgs(
          inputPath: inputVideo.path,
          assPath: assFile.path,
          outputPath: outPath,
          quality: quality,
          vertical: vertical,
        ),
        onProgress: onProgress,
        durationSeconds: size?.durationSeconds,
      );
      var rc = await session.getReturnCode();
      if (ReturnCode.isCancel(rc)) {
        // Phase 0: a user cancel must NOT fall through to the
        // drawtext retry below — the export stops here.
        return const VideoExportResult(
          success: false,
          cancelled: true,
          error: 'Export cancel kar diya gaya.',
        );
      }
      if (ReturnCode.isSuccess(rc)) {
        return VideoExportResult(success: true, outputPath: outPath);
      }
      final assLogs = await session.getAllLogsAsString() ?? '';

      // Attempt 2: drawtext fallback (one drawtext per line). The
      // style is plainer (no karaoke), but the captions still land
      // in the video instead of failing outright.
      final drawtextFilter = await buildDrawtextFilter(
        assContent: assContent,
        scale: scaleFor(quality, vertical),
        quality: quality,
        vertical: vertical,
      );
      if (drawtextFilter != null) {
        session = await _execute(
          burnInDrawtextArgs(
            inputPath: inputVideo.path,
            drawtextFilter: drawtextFilter,
            outputPath: outPath,
          ),
          onProgress: onProgress,
          durationSeconds: size?.durationSeconds,
        );
        rc = await session.getReturnCode();
        if (ReturnCode.isCancel(rc)) {
          return const VideoExportResult(
            success: false,
            cancelled: true,
            error: 'Export cancel kar diya gaya.',
          );
        }
        if (ReturnCode.isSuccess(rc)) {
          return VideoExportResult(success: true, outputPath: outPath);
        }
      }
      final logs = await session.getAllLogsAsString() ?? '';
      final tail = (assLogs.isNotEmpty ? assLogs : logs).trim();
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
    img.Image? lastMatte;
    for (var i = 0; i < frameFiles.length; i++) {
      final bytes = await frameFiles[i].readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (lastMatte == null) {
          throw Exception('Pehla frame decode nahi hua.');
        }
      } else {
        final matte =
            await OnnxImageService.instance.alphaMatte('modnet', decoded);
        if (matte != null) lastMatte = matte;
        if (lastMatte == null) {
          throw Exception('MODNet matte nahi bana (pack issue).');
        }
      }
      final toWrite = lastMatte;
      final name = 'frame_${(i + 1).toString().padLeft(4, '0')}.png';
      await File(p.join(rgbaDir.path, name))
          .writeAsBytes(img.encodePng(toWrite));
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

  static bool _rifeEnvReady = false;

  /// Flattens an OrtValue payload (typed list or nested lists) into
  /// a fresh Float32List — same tolerance as OnnxImageService.
  static Float32List _flattenFloats(Object? value) {
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
    final frames = <img.Image>[];
    for (final f in frameFiles) {
      final decoded = img.decodeImage(await f.readAsBytes());
      if (decoded == null) {
        throw Exception('Ek frame decode nahi hua.');
      }
      frames.add(decoded);
    }

    if (!_rifeEnvReady) {
      OrtEnv.instance.init();
      _rifeEnvReady = true;
    }
    final session = OrtSession.fromFile(model, OrtSessionOptions());
    try {
      final inputName = session.inputNames.first;
      var outIndex = 0;
      Future<void> writeOut(img.Image image) async {
        outIndex++;
        final name = 'frame_${outIndex.toString().padLeft(4, '0')}.png';
        await File(p.join(outDir.path, name))
            .writeAsBytes(img.encodePng(image));
      }

      await writeOut(frames.first);
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
          throw Exception('RIFE se koi output nahi aaya.');
        }
        final raw = _flattenFloats((outputs.first! as OrtValueTensor).value);
        for (final o in outputs) {
          o?.release();
        }
        if (raw.length < 3 * ph * pw) {
          throw Exception('RIFE output adhoora hai.');
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
        await writeOut(mid);
        await writeOut(b);
        onProgress?.call((i + 1) / (frames.length - 1) * 0.85);
      }
    } finally {
      session.release();
    }

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
