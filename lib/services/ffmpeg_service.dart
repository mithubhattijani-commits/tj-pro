/// FFmpeg command builders + execution wrapper (via ffmpeg_kit_flutter_new).
///
/// All video work in V1 goes through here so the UI never touches raw
/// FFmpeg syntax. Commands are built as strings because FFmpegKit parses
/// them itself; file paths are single-quoted and escaped.
library;

import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

/// Result of one FFmpeg run.
class FfmpegResult {
  FfmpegResult(this.returnCode, this.logs, {this.cancelled = false});
  final int returnCode;
  final String logs;

  /// True when this run was stopped through [FfmpegService.cancel],
  /// [FfmpegService.cancelCurrent] or [FfmpegService.prepareForNewRun]
  /// (Phase 0) — callers can then say "cancelled" instead of
  /// reporting a generic ffmpeg failure.
  final bool cancelled;

  bool get ok => returnCode == 0;
}

/// Thin wrapper around FFmpegKit with progress reporting.
class FfmpegService {
  // ------------------------------------------------------------------
  // Hotfix (export-crash audit C1/C6): tier-based encode policy.
  //
  // Every command built in this file encodes with the uniform
  // token `-c:v libx264 -preset veryfast` and NO thread cap —
  // libx264 then threads across every core, each thread holding
  // its own frame queue, which is the memory profile that gets
  // the whole process LMK-killed mid-encode on weak phones.
  // [run] now rewrites that token with the CURRENT policy:
  // [encodeThreads] (0 = no cap injected) and [encodePreset].
  // The values are pushed here by PerformanceEngine whenever
  // its config changes (tier adoption + memory-pressure
  // step-down), so the policy is live: a pressure event during
  // an export lightens the NEXT stage's encode automatically.
  // ------------------------------------------------------------------

  /// libx264 thread cap applied by [run] (0 = inject nothing,
  /// the pre-engine default). Pushed by PerformanceEngine.
  static int encodeThreads = 0;

  /// libx264 preset applied by [run]. Pushed by
  /// PerformanceEngine; 'veryfast' = the historical preset.
  static String encodePreset = 'veryfast';

  /// The uniform encode token every builder in this file emits.
  static const String _x264Token = '-c:v libx264 -preset veryfast';

  /// Pure rewrite behind the encode policy (unit-tested):
  /// replaces the uniform libx264 token with the capped /
  /// re-presetted form. Commands without the token (stream
  /// copies, audio-only passes, probes) pass through untouched,
  /// and with the default policy (no cap + veryfast) every
  /// command passes through byte-identical.
  static String applyEncodePolicy(
    String command, {
    required int threads,
    required String preset,
  }) {
    if (threads <= 0 && preset == 'veryfast') return command;
    if (!command.contains(_x264Token)) return command;
    final capped = threads > 0
        ? '-c:v libx264 -threads $threads -preset $preset'
        : '-c:v libx264 -preset $preset';
    return command.replaceFirst(_x264Token, capped);
  }

  /// Session registry (Phase 0): the ids of every session currently
  /// executing through [run], in start order. Before Phase 0 there
  /// was no registry at all — a new export could not cancel a
  /// leftover session, and the only cancel was the global kill in
  /// [cancel]. Registration happens the moment a session starts;
  /// the entry is removed when its run completes.
  static final Set<int> _activeSessionIds = <int>{};

  /// Ids cancelled through this service, so the owning [run] can
  /// mark its [FfmpegResult.cancelled] even if the native cancel
  /// return code is not the canonical one on some build.
  static final Set<int> _cancelledSessionIds = <int>{};

  /// Sessions currently executing through [run] (diagnostics/tests).
  static int get activeSessionCount => _activeSessionIds.length;

  /// Runs [command]. [expectedMs] is the approximate output duration in
  /// milliseconds, used to turn statistics time into 0..1 progress.
  ///
  /// Phase 0: the run goes through `executeAsync` with a PER-SESSION
  /// statistics callback. The old code installed the callback in the
  /// GLOBAL FFmpegKitConfig slot and disabled it after every run —
  /// two overlapping runs (an export pass and a thumbnail pass)
  /// could steal or kill each other's progress stream. The session
  /// is registered in [_activeSessionIds] for its whole lifetime.
  static Future<FfmpegResult> run(
    String command, {
    int? expectedMs,
    void Function(double progress)? onProgress,
  }) async {
    // Hotfix (audit C1/C6): apply the live encode policy
    // (PerformanceEngine-pushed thread cap + preset) to every
    // libx264 encode that flows through here — both export
    // paths and every helper pass alike.
    command = applyEncodePolicy(
      command,
      threads: encodeThreads,
      preset: encodePreset,
    );
    final done = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeAsync(
      command,
      (completed) {
        if (!done.isCompleted) done.complete(completed);
      },
      null,
      (statistics) {
        if (onProgress != null && expectedMs != null && expectedMs > 0) {
          final t = statistics.getTime();
          if (t > 0) {
            onProgress((t / expectedMs).clamp(0.0, 1.0));
          }
        }
      },
    );
    final int sessionId = session.getSessionId() ?? -1;
    final bool registered = sessionId >= 0;
    if (registered) _activeSessionIds.add(sessionId);
    try {
      final completed = await done.future;
      final rc = await completed.getReturnCode();
      final code = rc?.getValue() ?? -1;
      var output = await completed.getOutput() ?? '';
      // Keep error text readable in the UI status line.
      if (output.length > 800) {
        output = output.substring(output.length - 800);
      }
      return FfmpegResult(
        code,
        output,
        cancelled: (registered && _cancelledSessionIds.contains(sessionId)) ||
            ReturnCode.isCancel(rc),
      );
    } finally {
      if (registered) {
        _activeSessionIds.remove(sessionId);
        _cancelledSessionIds.remove(sessionId);
      }
    }
  }

  /// Cancels ALL sessions currently running through [run] (the
  /// long-standing behaviour the News export screen relies on),
  /// plus a global backstop for any session started outside [run].
  static void cancel() {
    _cancelledSessionIds.addAll(_activeSessionIds);
    unawaited(FFmpegKit.cancel());
  }

  /// Cancels only the MOST RECENT session running through [run] —
  /// the in-flight export pass — leaving any other session (e.g. a
  /// thumbnail pass) alone. A no-op when nothing is running.
  static Future<void> cancelCurrent() async {
    if (_activeSessionIds.isEmpty) return;
    final int sessionId = _activeSessionIds.last;
    _cancelledSessionIds.add(sessionId);
    try {
      await FFmpegKit.cancel(sessionId);
    } catch (_) {
      // Best-effort: the mark above still makes the owning run
      // report itself cancelled when it unwinds.
    }
  }

  /// Phase 0 pre-run discipline for EXPORT entry points: cancel
  /// every session a previous (possibly crashed or abandoned) run
  /// left behind, so a new export never competes with a zombie
  /// ffmpeg for CPU/RAM. Callers: the reel export, the caption
  /// burn-in export and the Video Editor export.
  static Future<void> prepareForNewRun() async {
    if (_activeSessionIds.isEmpty) return;
    _cancelledSessionIds.addAll(_activeSessionIds);
    try {
      await FFmpegKit.cancel();
    } catch (_) {
      // Same best-effort rule as [cancelCurrent].
    }
  }

  /// Best-effort cleanup of stale scratch files: entries inside
  /// [dir] whose name starts with one of [prefixes] and that were
  /// last modified before `now - maxAge` are deleted (directories
  /// recursively). Used by the export entry points to keep the
  /// temp cache from growing across crashed/killed runs. Never
  /// throws and never touches fresh files, so a live export's own
  /// intermediates are safe.
  static Future<void> cleanStaleTempFiles(
    Directory dir, {
    required List<String> prefixes,
    Duration maxAge = const Duration(hours: 6),
  }) async {
    try {
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (!prefixes.any(name.startsWith)) continue;
          final stat = await entity.stat();
          if (stat.modified.isAfter(cutoff)) continue;
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else {
            await entity.delete();
          }
        } catch (_) {
          // One stubborn entry must not stop the sweep.
        }
      }
    } catch (_) {
      // Cleanup is housekeeping — never block an export over it.
    }
  }

  /// Quote a file path for FFmpeg command strings.
  static String q(String path) => "'${path.replaceAll("'", "'\\''")}'";

  /// Escape text for the drawtext filter (single-quoted value).
  static String escapeDrawText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(':', '\\:')
        .replaceAll('%', '\\%')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('\n', ' ');
  }

  /// First readable system font for drawtext, or null if none found.
  static String? findFontFile() {
    const candidates = [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/RobotoStatic-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/NotoSans.ttf',
      '/system/fonts/RobotoFlex-Regular.ttf',
    ];
    for (final c in candidates) {
      try {
        if (File(c).existsSync()) return c;
      } catch (_) {}
    }
    return null;
  }

  /// Video filter chain for the named preset (empty = no filter).
  ///
  /// v1.3.0 (feature §6.1): [intensity] 0..1 scales the preset's
  /// strength — every parameter's deviation from neutral is scaled
  /// by it (the sepia matrix is lerped toward identity), mirroring
  /// the live preview's matrix lerp in the Colour panel. Intensity 1
  /// (the default) returns exactly the long-standing strings.
  static String videoFilter(String preset, {double intensity = 1}) {
    final i = intensity.clamp(0.0, 1.0);
    String n(double v) => v.toStringAsFixed(3);
    switch (preset) {
      case 'Warm':
        return 'colortemperature=temperature=${(6500 - (6500 - 3800) * i).round()}:mix=${n(0.6 * i)}:pl=1';
      case 'Cool':
        return 'colortemperature=temperature=${(6500 + (8500 - 6500) * i).round()}:mix=${n(0.6 * i)}:pl=1';
      case 'B&W':
        return 'hue=s=${n(1 - i)}';
      case 'Vivid':
        return 'eq=saturation=${n(1 + 0.4 * i)}:contrast=${n(1 + 0.08 * i)}:brightness=${n(0.02 * i)}';
      case 'Sepia':
        const m = [
          .393, .769, .189, 0, //
          .349, .686, .168, 0,
          .272, .534, .131, 0,
        ];
        const id = [
          1.0, 0.0, 0.0, 0, //
          0.0, 1.0, 0.0, 0,
          0.0, 0.0, 1.0, 0,
        ];
        final lerped = [
          for (var k = 0; k < m.length; k++) n(id[k] + (m[k] - id[k]) * i),
        ];
        return 'colorchannelmixer=${lerped.join(':')}';
      default:
        return '';
    }
  }

  /// Export frame size for an aspect setting and quality preset:
  /// quality 0 = 720p HD (fast), 1 = 1080p Full HD, 2 = 2160p 4K (slow).
  /// Returns null for 'Original' (no scaling).
  static (int, int)? exportDims(String aspect, int quality) {
    final int q = quality.clamp(0, 2);
    switch (aspect) {
      case '9:16':
        return q == 2
            ? (2160, 3840)
            : q == 1
                ? (1080, 1920)
                : (720, 1280);
      case '16:9':
        return q == 2
            ? (3840, 2160)
            : q == 1
                ? (1920, 1080)
                : (1280, 720);
      case '1:1':
        return q == 2
            ? (2160, 2160)
            : q == 1
                ? (1080, 1080)
                : (720, 720);
      case '4:5':
        // Build 2 (Phase 1): the Canvas panel's 4:5 ratio is real
        // end-to-end — width-driven like 9:16 (720 / 1080 / 2160).
        return q == 2
            ? (2160, 2700)
            : q == 1
                ? (1080, 1350)
                : (720, 900);
      default:
        return null;
    }
  }

  /// Aspect filter: scale to cover target then center-crop (empty = original).
  /// The target size follows [exportQuality]: 0 = 720p HD (fast, the
  /// long-standing default), 1 = 1080p Full HD, 2 = 2160p 4K (slow).
  ///
  /// v1.3.0 (feature §6.5 — canvas background fill): [canvasFill]
  /// 'color' letterboxes instead of cropping — the clip is scaled to
  /// FIT and padded with [fillColor], so nothing is cut off. 'blur'
  /// is NOT produced here (it needs a two-stream graph); callers use
  /// [blurFillPassCommand] / the blur-fill normalize variant instead
  /// and pass aspect 'Original' to this chain.
  static String aspectFilter(
    String aspect, {
    int exportQuality = 0,
    String canvasFill = 'none',
    String fillColor = 'black',
  }) {
    final dims = exportDims(aspect, exportQuality);
    if (dims == null) return '';
    final int w = dims.$1;
    final int h = dims.$2;
    if (canvasFill == 'color') {
      return 'scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=$fillColor';
    }
    return 'scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h';
  }

  /// Build the filter graph for the final pass (speed + filter + aspect +
  /// text). Returns the -vf argument value (without the -vf flag itself).
  static String finalFilterGraph({
    required double speed,
    required String filterPreset,
    required String aspect,
    String? text,
    String? fontFile,
    String? subtitlesPath,
    String? captionFilter,
    String? extraVideoFilter,
    bool textAtTop = false,
    int? videoHeight,
    int exportQuality = 0,
    // v1.3.0: filter intensity (§6.1) + canvas fill (§6.5). Defaults
    // reproduce the pre-v1.3.0 graph exactly.
    double filterIntensity = 1,
    String canvasFill = 'none',
    String fillColor = 'black',
    // Build 3 (Phase 3): the export frame rate (24/30/60). Null —
    // every pre-Build-3 caller — leaves the graph byte-identical
    // (the source rate flows through); a value appends `fps=<n>`
    // just before the final format conversion.
    int? fps,
  }) {
    final parts = <String>[];
    if (speed != 1.0) parts.add('setpts=PTS/$speed');
    final vf = videoFilter(filterPreset, intensity: filterIntensity);
    if (vf.isNotEmpty) parts.add(vf);
    final af = aspectFilter(
      aspect,
      exportQuality: exportQuality,
      canvasFill: canvasFill,
      fillColor: fillColor,
    );
    if (af.isNotEmpty) parts.add(af);
    if (text != null && text.trim().isNotEmpty && fontFile != null) {
      final h = videoHeight ?? exportDims(aspect, exportQuality)?.$2 ?? 720;
      final size = (h / 18).round().clamp(24, 72);
      // Position: bottom-center with margin, classic CapCut caption spot.
      parts.add(
        "drawtext=fontfile=$fontFile:text='${escapeDrawText(text.trim())}'"
        ":fontsize=$size:fontcolor=white:borderw=3:bordercolor=black"
        ":x=(w-text_w)/2:y=${textAtTop ? '40' : 'h-text_h-60'}",
      );
    }
    if (subtitlesPath != null) {
      parts.add("subtitles=${q(subtitlesPath)}:fontsdir='/system/fonts'");
    } else if (captionFilter != null && captionFilter.isNotEmpty) {
      parts.add(captionFilter);
    }
    if (extraVideoFilter != null && extraVideoFilter.isNotEmpty) {
      parts.add(extraVideoFilter);
    }
    if (fps != null) parts.add('fps=$fps');
    parts.add('format=yuv420p');
    return parts.join(',');
  }

  /// One-pass command for a SINGLE clip: trim + speed + filter + aspect +
  /// text + optional music (replaces original audio).
  static String singleClipCommand({
    required String input,
    required double trimStart,
    required double trimEnd,
    required double speed,
    required String filterPreset,
    required String aspect,
    String? text,
    String? fontFile,
    String? subtitlesPath,
    String? captionFilter,
    String? extraVideoFilter,
    String? audioFilter,
    bool textAtTop = false,
    String? musicPath,
    required String output,
    int exportQuality = 0,
    // v1.3.0: see [finalFilterGraph].
    double filterIntensity = 1,
    String canvasFill = 'none',
    String fillColor = 'black',
    // Build 3: see [finalFilterGraph]'s fps.
    int? fps,
  }) {
    final graph = finalFilterGraph(
      speed: speed,
      filterPreset: filterPreset,
      aspect: aspect,
      text: text,
      fontFile: fontFile,
      subtitlesPath: subtitlesPath,
      captionFilter: captionFilter,
      extraVideoFilter: extraVideoFilter,
      textAtTop: textAtTop,
      exportQuality: exportQuality,
      filterIntensity: filterIntensity,
      canvasFill: canvasFill,
      fillColor: fillColor,
      fps: fps,
    );
    final buf = StringBuffer();
    buf.write('-y -ss $trimStart -to $trimEnd -i ${q(input)} ');
    if (musicPath != null) buf.write('-i ${q(musicPath)} ');
    // PRO ramp: a labeled audio snippet ([0:a]...[aout]) cannot go
    // through -af (simple filtergraphs take no input labels), so it
    // joins the video graph in one -filter_complex. Only when no
    // music replaces the audio (the UI never combines ramp+music).
    final useComplexAudio =
        audioFilter != null && audioFilter.contains('[0:a]') && musicPath == null;
    if (useComplexAudio) {
      buf.write('-filter_complex "[0:v]$graph[vout];$audioFilter" -map "[vout]" -map "[aout]" ');
    } else {
      buf.write('-vf "$graph" ');
    // When music replaces the audio, the music keeps its normal speed and
    // -shortest trims it to the video; tempo-adjust only the original audio.
      // audioFilter (when given) replaces the atempo rule entirely.
      if (audioFilter != null) {
        buf.write('-af "$audioFilter" ');
      } else if (speed != 1.0 && musicPath == null) {
        buf.write('-af "atempo=$speed" ');
      }
      if (musicPath != null) {
        buf.write('-map 0:v:0 -map 1:a:0 -shortest ');
      }
    }
    buf.write('-c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${q(output)}');
    return buf.toString();
  }

  /// Normalize one clip: trim + scale-to-cover + center-crop to a common size
  /// + 30fps + aac audio. Used before concat/xfade so every intermediate
  /// matches.
  ///
  /// Phase 9 — [fps], [videoBitrateKbps] and [audioBitrateKbps] are
  /// the export screen's REAL settings: fps goes into the filter
  /// (`fps=<n>`), an explicit video bitrate replaces CRF 23 with
  /// `-b:v / -maxrate / -bufsize`, an explicit audio bitrate adds
  /// `-b:a`. All three default to the Phase 7 behaviour (30 fps,
  /// CRF 23, AAC with no explicit bitrate) so existing callers and
  /// tests are untouched.
  static String normalizeCommand({
    required String input,
    required double trimStart,
    required double trimEnd,
    required int width,
    required int height,
    required String output,
    int fps = 30,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    // v1.3.0 (§6.5): blur-fill framing instead of scale+crop — the
    // clip is scaled to FIT over a blurred, darkened copy of itself
    // (the reference intro treatment). Needs a two-stream graph, so
    // this variant uses -filter_complex.
    bool blurFill = false,
  }) {
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac -ar 48000 -ac 2'
        : '-c:a aac -b:a ${audioBitrateKbps}k -ar 48000 -ac 2';
    if (blurFill) {
      return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
          '-filter_complex "[0:v]split[bg][fg];'
          '[bg]scale=$width:$height:force_original_aspect_ratio=increase,'
          'crop=$width:$height,gblur=sigma=24,eq=brightness=-0.12[bgb];'
          '[fg]scale=$width:$height:force_original_aspect_ratio=decrease[fgb];'
          '[bgb][fgb]overlay=(W-w)/2:(H-h)/2,fps=$fps,format=yuv420p[vout]" '
          '-map "[vout]" -map 0:a? '
          '$videoArgs $audioArgs ${q(output)}';
    }
    return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
        '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=$fps,format=yuv420p" '
        '$videoArgs $audioArgs ${q(output)}';
  }

  /// v1.3.0 (§6.5) — blur-fill as a standalone pass over an already
  /// rendered video (the single-clip editor path, where the main
  /// pass ran with aspect 'Original'): the frame is reframed to
  /// [width]x[height] as a sharp fit over its own blurred copy.
  /// Audio is copied. Guarded by the caller like every post-pass.
  static String blurFillPassCommand({
    required String input,
    required String output,
    required int width,
    required int height,
  }) {
    return '-y -i ${q(input)} '
        '-filter_complex "[0:v]split[bg][fg];'
        '[bg]scale=$width:$height:force_original_aspect_ratio=increase,'
        'crop=$width:$height,gblur=sigma=24,eq=brightness=-0.12[bgb];'
        '[fg]scale=$width:$height:force_original_aspect_ratio=decrease[fgb];'
        '[bgb][fgb]overlay=(W-w)/2:(H-h)/2,format=yuv420p[vout]" '
        '-map "[vout]" -map 0:a? '
        '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
        '-movflags +faststart ${q(output)}';
  }

  /// v1.3.0 (§6.7) — main-clip transform pass: the clip is scaled,
  /// rotated and faded over a blurred copy of itself (never black
  /// bars). [posX]/[posY] are centre offsets as fractions of the
  /// frame (−0.5..0.5). [rotationDeg] rotates the foreground;
  /// [opacity] 0..1 fades it over the backdrop. Audio copied.
  static String transformPassCommand({
    required String input,
    required String output,
    required int width,
    required int height,
    required double scale,
    required double posX,
    required double posY,
    required double rotationDeg,
    required double opacity,
  }) {
    final s = scale.clamp(0.3, 2.5);
    final rad = (rotationDeg * 3.14159265 / 180).toStringAsFixed(4);
    final op = opacity.clamp(0.0, 1.0).toStringAsFixed(2);
    final ox = (posX * width).round();
    final oy = (posY * height).round();
    return '-y -i ${q(input)} '
        '-filter_complex "[0:v]split[bg][fgs];'
        '[bg]scale=$width:$height:force_original_aspect_ratio=increase,'
        'crop=$width:$height,gblur=sigma=24,eq=brightness=-0.18[bgb];'
        '[fgs]format=yuva420p,scale=iw*$s:ih*$s,'
        'rotate=$rad:ow=rotw(iw):oh=roth(ih):c=black@0,'
        'colorchannelmixer=aa=$op[fgv];'
        '[bgb][fgv]overlay=x=(W-w)/2+$ox:y=(H-h)/2+$oy,format=yuv420p[vout]" '
        '-map "[vout]" -map 0:a? '
        '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
        '-movflags +faststart ${q(output)}';
  }

  /// v1.3.0 (§6.1) — a still photo becomes a video clip: the photo
  /// fills [width]x[height] for [durationSec]. With [kenBurns] the
  /// frame slowly zooms (in or out — the pipeline's zoompan move);
  /// without it the photo is a static scale+crop segment. Silent
  /// stereo audio is added so concat joins match the other clips.
  static String photoClipCommand({
    required String imagePath,
    required String output,
    required int width,
    required int height,
    required double durationSec,
    bool kenBurns = false,
    bool zoomIn = true,
  }) {
    final dur = durationSec.clamp(0.5, 60.0);
    final frames = (dur * 30).round();
    final String vf;
    if (kenBurns) {
      // zoompan works on a single input frame: upscale first so the
      // zoom has pixels to move through, then pan/zoom to the frame.
      final z = zoomIn
          ? "z='min(1+0.12*on/$frames,1.12)'"
          : "z='max(1.12-0.12*on/$frames,1.0)'";
      vf = 'scale=${width * 2}:${height * 2}:force_original_aspect_ratio=increase,'
          'crop=${width * 2}:${height * 2},'
          'zoompan=$z:x=\'iw/2-(iw/zoom/2)\':y=\'ih/2-(ih/zoom/2)\''
          ':d=$frames:s=${width}x$height:fps=30,format=yuv420p';
    } else {
      vf = 'scale=$width:$height:force_original_aspect_ratio=increase,'
          'crop=$width:$height,fps=30,format=yuv420p';
    }
    return '-y -loop 1 -t $dur -i ${q(imagePath)} '
        '-f lavfi -t $dur -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "$vf" -map 0:v -map 1:a -shortest '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -ar 48000 -ac 2 '
        '${q(output)}';
  }

  /// v1.3.0 (§6.9) — piecewise-linear volume envelope expression for
  /// the `volume` filter's eval mode: [points] are (timeSec, gain)
  /// pairs sorted by time; the gain holds the first/last value
  /// outside the point range and lerps between points. Returns an
  /// FFmpeg expression string (no surrounding quotes).
  static String volumeEnvelopeExpression(
    List<(double, double)> points,
    double fallback,
  ) {
    if (points.isEmpty) return fallback.toStringAsFixed(2);
    final pts = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    String n(double v) => v.toStringAsFixed(3);
    var expr = n(pts.last.$2);
    for (var i = pts.length - 2; i >= 0; i--) {
      final (t0, v0) = pts[i];
      final (t1, v1) = pts[i + 1];
      final span = (t1 - t0).abs() < 0.001 ? 0.001 : t1 - t0;
      expr =
          'if(lt(t,${n(t1)}),${n(v0)}+(${n(v1)}-${n(v0)})*(t-${n(t0)})/${n(span)},$expr)';
    }
    return 'if(lt(t,${n(pts.first.$1)}),${n(pts.first.$2)},$expr)';
  }

  /// Concat-demuxer command for already-normalized clips (fast, no re-encode).
  static String concatCommand({
    required String listFile,
    required String output,
  }) {
    return '-y -f concat -safe 0 -i ${q(listFile)} -c copy ${q(output)}';
  }

  /// Crossfade chain for normalized clips. [durationsMs] are the trimmed
  /// durations of each clip in milliseconds. Returns null when < 2 clips.
  static String? xfadeCommand({
    required List<String> inputs,
    required List<int> durationsMs,
    required bool hasAudio,
    required String output,
  }) {
    if (inputs.length < 2) return null;
    const fadeMs = 500;
    final buf = StringBuffer();
    for (final i in inputs) {
      buf.write('-i ${q(i)} ');
    }
    buf.write('-filter_complex "');
    // Video chain.
    var prev = '[0:v]';
    var offsetMs = durationsMs[0] - fadeMs;
    for (var i = 1; i < inputs.length; i++) {
      final out = i == inputs.length - 1 ? '[vout]' : '[vx$i]';
      buf.write('$prev[$i:v]xfade=transition=fade:duration=0.5:offset=${offsetMs / 1000.0}$out;');
      prev = out;
      offsetMs += durationsMs[i] - fadeMs;
    }
    // Audio chain (only when every clip has audio; acrossfade chains
    // automatically with no offset needed).
    String audioMap = '';
    if (hasAudio) {
      var aprev = '[0:a]';
      for (var i = 1; i < inputs.length; i++) {
        final out = i == inputs.length - 1 ? '[aout]' : '[ax$i]';
        buf.write('$aprev[$i:a]acrossfade=d=0.5$out;');
        aprev = out;
      }
      audioMap = ' -map "[vout]" -map "[aout]"';
    } else {
      audioMap = ' -map "[vout]"';
    }
    buf.write('"');
    buf.write(audioMap);
    buf.write(' -c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${q(output)}');
    return buf.toString();
  }

  /// Final pass over a merged file: speed + filter + aspect + text + music.
  static String finalPassCommand({
    required String input,
    required double speed,
    required String filterPreset,
    required String aspect,
    String? text,
    String? fontFile,
    String? subtitlesPath,
    String? captionFilter,
    String? extraVideoFilter,
    String? audioFilter,
    bool textAtTop = false,
    String? musicPath,
    required String output,
    int exportQuality = 0,
    // v1.3.0: see [finalFilterGraph].
    double filterIntensity = 1,
    String canvasFill = 'none',
    String fillColor = 'black',
    // Build 3: see [finalFilterGraph]'s fps.
    int? fps,
  }) {
    final graph = finalFilterGraph(
      speed: speed,
      filterPreset: filterPreset,
      aspect: aspect,
      text: text,
      fontFile: fontFile,
      subtitlesPath: subtitlesPath,
      captionFilter: captionFilter,
      extraVideoFilter: extraVideoFilter,
      textAtTop: textAtTop,
      exportQuality: exportQuality,
      filterIntensity: filterIntensity,
      canvasFill: canvasFill,
      fillColor: fillColor,
      fps: fps,
    );
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} ');
    if (musicPath != null) buf.write('-i ${q(musicPath)} ');
    // PRO ramp: a labeled audio snippet ([0:a]...[aout]) cannot go
    // through -af (simple filtergraphs take no input labels), so it
    // joins the video graph in one -filter_complex. Only when no
    // music replaces the audio (the UI never combines ramp+music).
    final useComplexAudio =
        audioFilter != null && audioFilter.contains('[0:a]') && musicPath == null;
    if (useComplexAudio) {
      buf.write('-filter_complex "[0:v]$graph[vout];$audioFilter" -map "[vout]" -map "[aout]" ');
    } else {
      buf.write('-vf "$graph" ');
    // Same rule as singleClipCommand: music keeps normal speed.
      // audioFilter (when given) replaces the atempo rule entirely.
      if (audioFilter != null) {
        buf.write('-af "$audioFilter" ');
      } else if (speed != 1.0 && musicPath == null) {
        buf.write('-af "atempo=$speed" ');
      }
      if (musicPath != null) {
        buf.write('-map 0:v:0 -map 1:a:0 -shortest ');
      }
    }
    buf.write('-c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${q(output)}');
    return buf.toString();
  }

  /// Logo-bug geometry for the Nigraan final template (mirrors
  /// `NigraanFinalLayout.compute` in `lib/live/news_template.dart`):
  /// logo size = 15.3% of the frame width, top-right with a 20px
  /// margin, sitting under the top ticker when it is enabled.
  /// Returns (x, y, size) in output pixels.
  static (int, int, int) logoBugRect({
    required int width,
    required int height,
    required bool topRibbonEnabled,
  }) {
    final size = (width * 0.153).round();
    final x = width - size - 20;
    final y = (topRibbonEnabled ? (height * 0.055).round() : 0) + 16;
    return (x, y, size);
  }

  /// Voiceover mix pass: mixes [voiceoverPath] (the Gemini voiceover
  /// WAV) over the clip audio of [input]. The clip audio is ducked to
  /// [clipVolume] (0.35 = the voice stays clearly on top) and the mix
  /// is cut to the video length (`duration=first`). Video is copied,
  /// not re-encoded. When [hasClipAudio] is false the video has no
  /// audio track at all, so the voiceover simply becomes the audio
  /// track (`-shortest` trims it to the video).
  static String voiceoverMixCommand({
    required String input,
    required String voiceoverPath,
    required String output,
    required bool hasClipAudio,
    double clipVolume = 0.35,
    // Phase 9 — the export screen's real audio bitrate. Null = the
    // Phase 7 behaviour (AAC, no explicit bitrate).
    int? audioBitrateKbps,
  }) {
    final vol = clipVolume.clamp(0.0, 1.0).toStringAsFixed(2);
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} -i ${q(voiceoverPath)} ');
    if (hasClipAudio) {
      buf.write(
        '-filter_complex "[0:a]volume=$vol[ducked];'
        '[ducked][1:a]amix=inputs=2:duration=first:'
        'dropout_transition=0[aout]" '
        '-map 0:v -map "[aout]" ',
      );
    } else {
      buf.write('-map 0:v -map 1:a -shortest ');
    }
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac'
        : '-c:a aac -b:a ${audioBitrateKbps}k';
    buf.write(
      '-c:v copy $audioArgs -movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }

  /// Background-music bed pass (v1.2.0): loops [musicPath] (a built-in
  /// news-music MP3) quietly UNDER the existing audio of [input]. The
  /// music is cut to the video length (`duration=first` on the mix, or
  /// `-shortest` when the video has no audio of its own). Video is
  /// copied, not re-encoded. Callers treat any failure as "export
  /// without the bed" — this command never gates the export.
  /// Build 13 (point 6 — Permanent Logo): turns a directory of
  /// frame_%02d.png frames (the logo animation rendered on a
  /// solid green background) into a standalone looping MP4 —
  /// logo only, no template, no audio.
  static String logoGreenScreenCommand({
    required String framesDir,
    required String output,
    required double durationSec,
    int fps = 12,
  }) {
    final pattern = framesDir.endsWith('/')
        ? '${framesDir}frame_%02d.png'
        : '$framesDir/frame_%02d.png';
    return '-y -framerate $fps -stream_loop -1 -i ${q(pattern)} '
        '-t ${durationSec.toStringAsFixed(2)} '
        '-c:v libx264 -pix_fmt yuv420p -r 30 '
        '-movflags +faststart ${q(output)}';
  }

  /// Build 13 (point 6 — Permanent Logo, cube path): composites
  /// a transparent frame_%02d.png logo loop over a solid green
  /// canvas into a standalone MP4.
  static String logoGreenCompositeCommand({
    required String framesDir,
    required String output,
    required double durationSec,
    int size = 512,
    int fps = 12,
  }) {
    final pattern = framesDir.endsWith('/')
        ? '${framesDir}frame_%02d.png'
        : '$framesDir/frame_%02d.png';
    return '-y -f lavfi -i color=c=0x00B140:size=${size}x$size '
        '-framerate $fps -stream_loop -1 -i ${q(pattern)} '
        '-filter_complex "[0:v][1:v]overlay=0:0:format=auto[vout]" '
        '-map "[vout]" -t ${durationSec.toStringAsFixed(2)} '
        '-c:v libx264 -pix_fmt yuv420p -r 30 '
        '-movflags +faststart ${q(output)}';
  }

  static String musicBedCommand({
    required String input,
    required String musicPath,
    required String output,
    required bool hasClipAudio,
    double musicVolume = 0.18,
    int? audioBitrateKbps,
    // v1.3.0 (§9 criterion 10): optional bed fades — the Final
    // template's bed fades in 0.8 s / out 1.5 s. [durationSec] is
    // needed to place the fade-out; without it no fades are applied.
    double fadeInSec = 0,
    double fadeOutSec = 0,
    double? durationSec,
  }) {
    final vol = musicVolume.clamp(0.0, 1.0).toStringAsFixed(2);
    var bedChain = '[1:a]volume=$vol';
    if (fadeInSec > 0) {
      bedChain += ',afade=t=in:st=0:d=${fadeInSec.toStringAsFixed(2)}';
    }
    if (fadeOutSec > 0 && durationSec != null && durationSec > fadeOutSec) {
      bedChain +=
          ',afade=t=out:st=${(durationSec - fadeOutSec).toStringAsFixed(2)}:d=${fadeOutSec.toStringAsFixed(2)}';
    }
    bedChain += '[bed]';
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} -stream_loop -1 -i ${q(musicPath)} ');
    if (hasClipAudio) {
      buf.write(
        '-filter_complex "$bedChain;'
        '[0:a][bed]amix=inputs=2:duration=first:'
        'dropout_transition=0[aout]" '
        '-map 0:v -map "[aout]" ',
      );
    } else {
      buf.write(
        '-filter_complex "${bedChain.replaceAll('[bed]', '[aout]')}" '
        '-map 0:v -map "[aout]" -shortest ',
      );
    }
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac'
        : '-c:a aac -b:a ${audioBitrateKbps}k';
    buf.write(
      '-c:v copy $audioArgs -movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }

  /// v1.3.0 (§6.8 — auto-duck): mixes [musicPath] UNDER the existing
  /// audio of [input] with sidechain compression — the music dips
  /// automatically whenever the clip's own audio (voice) is loud and
  /// comes back up in the gaps, the way the reel pipeline ducks its
  /// bed by hand. The music is first gained to [musicVolume], then
  /// ducked by the original audio as the sidechain. When the input
  /// has no audio track the music simply becomes the track (no
  /// ducking possible). Video is copied, not re-encoded.
  static String musicDuckCommand({
    required String input,
    required String musicPath,
    required String output,
    required bool hasClipAudio,
    double musicVolume = 1.0,
    int? audioBitrateKbps,
    double fadeInSec = 0,
    double fadeOutSec = 0,
    double? durationSec,
  }) {
    final vol = musicVolume.clamp(0.0, 1.5).toStringAsFixed(2);
    // Build 13 (point 5): optional bed fades + output bound for
    // the News Studio bed (its fixed-level mix fades the bed in
    // and out on the Final template). All defaults reproduce
    // the pre-Build-13 command byte-for-byte, so the Video
    // Editor's call is unchanged.
    var bedChain = '[1:a]volume=$vol';
    if (fadeInSec > 0) {
      bedChain += ',afade=t=in:st=0:d=${fadeInSec.toStringAsFixed(2)}';
    }
    if (fadeOutSec > 0 && durationSec != null && durationSec > fadeOutSec) {
      bedChain +=
          ',afade=t=out:st=${(durationSec - fadeOutSec).toStringAsFixed(2)}:d=${fadeOutSec.toStringAsFixed(2)}';
    }
    bedChain += '[bedraw];';
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} -stream_loop -1 -i ${q(musicPath)} ');
    if (hasClipAudio) {
      buf.write(
        '-filter_complex "[0:a]asplit[voice][sc];'
        '$bedChain'
        '[bedraw][sc]sidechaincompress=threshold=0.02:ratio=8:attack=40:release=400[bed];'
        '[voice][bed]amix=inputs=2:duration=first:dropout_transition=0[aout]" '
        '-map 0:v -map "[aout]" ',
      );
    } else {
      buf.write(
        '-filter_complex "[1:a]volume=$vol[aout]" '
        '-map 0:v -map "[aout]" -shortest ',
      );
    }
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac'
        : '-c:a aac -b:a ${audioBitrateKbps}k';
    buf.write(
      '-c:v copy $audioArgs -movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }

  /// The alpha .mov's opaque bbox for the OVERLAY pass
  /// (measured 235,86,396x316 on the 854x480 ProRes — the logo
  /// occupies only the centre of the frame). Callers rendering
  /// an overlay ping-pong cycle pass these to
  /// [logoPingPongCycleCommand].
  static const int logoMovCropW = 396;
  static const int logoMovCropH = 316;
  static const int logoMovCropX = 235;
  static const int logoMovCropY = 86;

  /// Hotfix (export-crash audit C3): renders ONE finite
  /// ping-pong cycle of the alpha logo .mov — cropped to
  /// [cropW]×[cropH] at [cropX],[cropY], played forward then
  /// in `reverse` — into [output] (a lossless qtrle .mov, so
  /// the alpha survives byte-exact).
  ///
  /// WHY: the overlay commands used to run `reverse` INSIDE
  /// the export graph on a `-stream_loop -1` (infinite) input.
  /// `reverse` buffers its entire input before emitting one
  /// frame, so on an endless input the graph's memory grew
  /// with export progress until Android killed the process —
  /// a textbook 50–60% export death. Here the input is the
  /// FINITE .mov: `reverse` buffers one 10 s cycle, once, and
  /// the export graph afterwards only loops the small finished
  /// cycle file. Output behaviour is identical (the same
  /// forward+reverse seamless loop).
  static String logoPingPongCycleCommand({
    required String movPath,
    required String output,
    required int cropW,
    required int cropH,
    required int cropX,
    required int cropY,
  }) {
    return '-y -i ${q(movPath)} '
        '-filter_complex "[0:v]crop=$cropW:$cropH:$cropX:$cropY,'
        'format=yuva420p,split[f][r];[r]reverse[rr];'
        '[f][rr]concat=n=2:v=1:a=0,format=yuva420p[cyc]" '
        '-map "[cyc]" -c:v qtrle ${q(output)}';
  }

  /// Runs [logoPingPongCycleCommand] and returns [outputPath]
  /// on success, null on any failure (callers fall back to
  /// their generated-frames / still logo paths, exactly as
  /// they did when the mov overlay pass itself failed).
  static Future<String?> prepareLogoPingPongCycle({
    required String movPath,
    required String outputPath,
    required int cropW,
    required int cropH,
    required int cropX,
    required int cropY,
  }) async {
    try {
      final res = await run(
        logoPingPongCycleCommand(
          movPath: movPath,
          output: outputPath,
          cropW: cropW,
          cropH: cropH,
          cropX: cropX,
          cropY: cropY,
        ),
      );
      if (res.ok && await File(outputPath).exists()) return outputPath;
    } catch (_) {
      // Fall through: no cycle, the caller's fallback applies.
    }
    return null;
  }

  /// Rotating-logo overlay pass: overlays the 3D-rotating logo
  /// bug on [input] at the template's logo-bug spot (see
  /// [logoBugRect]). The loop source is EXACTLY ONE of:
  /// [pingPongPath] — a FINITE pre-rendered ping-pong cycle of
  /// the alpha .mov (see [logoPingPongCycleCommand]; hotfix
  /// C3 — the in-graph `reverse` over an infinite input is
  /// gone); [framesDir] — a directory of
  /// `frame_%02d.png` frames (Build 12: the generated rotating
  /// CUBE loop for a user-picked logo or the default tile, or
  /// the keyed frames of a logo video), looped with the image2
  /// demuxer; or [videoPath] — a logo video overlaid unkeyed
  /// (point #13 fallback). The `perspective` filter is
  /// deliberately NOT used (a shear, not a true rotation).
  /// Audio is copied.
  static String logoLoopOverlayCommand({
    required String input,
    required String output,
    required int width,
    required int height,
    required bool topRibbonEnabled,
    String? pingPongPath,
    String? framesDir,
    String? videoPath,
    int framesFps = 12,
    // Phase 9 — the export screen's real video bitrate (null = CRF 23).
    int? videoBitrateKbps,
  }) {
    assert(
      (pingPongPath != null ? 1 : 0) +
              (framesDir != null ? 1 : 0) +
              (videoPath != null ? 1 : 0) ==
          1,
      'logoLoopOverlayCommand needs exactly one of '
      'pingPongPath / framesDir / videoPath',
    );
    final (x, y, size) = logoBugRect(
      width: width,
      height: height,
      topRibbonEnabled: topRibbonEnabled,
    );
    final buf = StringBuffer();
    buf.write('-y ');
    if (videoPath != null) {
      // Build 12 (point #13 fallback): a logo VIDEO whose
      // background could NOT be keyed (no solid colour) is
      // overlaid as-is, looped — it still moves/rotates as the
      // source does; the panel tells the user it is unkeyed.
      buf.write('-stream_loop -1 -i ${q(videoPath)} ');
      buf.write('-i ${q(input)} ');
      buf.write('-filter_complex "');
      buf.write(
        '[0:v]scale=$size:-1,format=yuva420p[bug];'
        '[1:v][bug]overlay=$x:$y:shortest=1[vout]" ',
      );
      buf.write('-map "[vout]" -map 1:a? ');
    } else if (pingPongPath != null) {
      // Hotfix (audit C3): the cycle file already carries the
      // mov's opaque-alpha crop (396:316:235:86 on the 854x480
      // ProRes, baked in by logoPingPongCycleCommand) AND the
      // forward+reverse ping-pong — the graph here only scales
      // the finite cycle to bug size and loops it. NO reverse
      // in this graph, ever: on the old `-stream_loop -1` mov
      // input it buffered without bound.
      buf.write('-stream_loop -1 -i ${q(pingPongPath)} ');
      buf.write('-i ${q(input)} ');
      buf.write('-filter_complex "');
      buf.write(
        '[0:v]format=yuva420p,scale=$size:-1[bug];'
        '[1:v][bug]overlay=$x:$y:shortest=1[vout]" ',
      );
      buf.write('-map "[vout]" -map 1:a? ');
    } else {
      buf.write(
        '-framerate $framesFps -stream_loop -1 '
        '-i ${q('$framesDir/frame_%02d.png')} ',
      );
      buf.write('-i ${q(input)} ');
      buf.write('-filter_complex "');
      buf.write(
        '[0:v]format=yuva420p,scale=$size:-1[bug];'
        '[1:v][bug]overlay=$x:$y:shortest=1[vout]" ',
      );
      buf.write('-map "[vout]" -map 1:a? ');
    }
    // Phase 9 — an explicit video bitrate replaces CRF 23 (null =
    // Phase 7 behaviour).
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    // Build 12 fix: EVERY branch above loops its logo input
    // forever (-stream_loop -1). The overlay filter's
    // framesync bound (shortest=1, set in each branch) ends
    // the graph with the BASE video — measured on host
    // ffmpeg 8.1.2 without it: a 4 s base produced a 1000+ s
    // output and never finished; with it: exactly 4.0 s.
    // The output-level -shortest stays as the house-style
    // second bound (music beds, voiceover mixes use it).
    buf.write(
      '$videoArgs -c:a copy -shortest '
      '-movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }

  /// v1.5.1 (#47): the still twin of [logoLoopOverlayCommand] —
  /// a picked logo held STATIC at the same bug rect when the
  /// preset's rotation is OFF (the export honours the switch
  /// exactly like the preview).
  static String logoStillOverlayCommand({
    required String input,
    required String output,
    required int width,
    required int height,
    required bool topRibbonEnabled,
    required String logoPath,
    int? videoBitrateKbps,
  }) {
    final (x, y, size) = logoBugRect(
      width: width,
      height: height,
      topRibbonEnabled: topRibbonEnabled,
    );
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    return '-y -i ${q(input)} -i ${q(logoPath)} '
        '-filter_complex "[1:v]format=yuva420p,scale=$size:-1[bug];'
        '[0:v][bug]overlay=$x:$y[vout]" '
        '-map "[vout]" -map 0:a? '
        '$videoArgs -c:a copy '
        '-movflags +faststart ${q(output)}';
  }

  /// Normalize one segment AND guarantee it has an audio stream, so
  /// the concat demuxer can join it with the other segments: when
  /// [addSilentAudio] is true (the source has no audio — e.g. the
  /// intro, or a still-image outro card), a silent stereo track of
  /// [durationSec] is generated with `anullsrc`. When false this is
  /// exactly [normalizeCommand].
  static String normalizeWithAudioCommand({
    required String input,
    required double trimStart,
    required double trimEnd,
    required int width,
    required int height,
    required String output,
    bool addSilentAudio = false,
    // Phase 9 — passed through to [normalizeCommand] (see there).
    int fps = 30,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    // v1.3.0 (§9.9): blurred-fill framing (the Final template's
    // intro treatment) instead of scale+crop.
    bool blurFill = false,
  }) {
    if (!addSilentAudio) {
      return normalizeCommand(
        input: input,
        trimStart: trimStart,
        trimEnd: trimEnd,
        width: width,
        height: height,
        output: output,
        fps: fps,
        videoBitrateKbps: videoBitrateKbps,
        audioBitrateKbps: audioBitrateKbps,
        blurFill: blurFill,
      );
    }
    final dur = (trimEnd - trimStart).clamp(0.1, 3600.0);
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac -ar 48000 -ac 2'
        : '-c:a aac -b:a ${audioBitrateKbps}k -ar 48000 -ac 2';
    final frameChain = blurFill
        ? '-filter_complex "[0:v]split[bg][fg];'
            '[bg]scale=$width:$height:force_original_aspect_ratio=increase,'
            'crop=$width:$height,gblur=sigma=24,eq=brightness=-0.12[bgb];'
            '[fg]scale=$width:$height:force_original_aspect_ratio=decrease[fgb];'
            '[bgb][fgb]overlay=(W-w)/2:(H-h)/2,fps=$fps,format=yuv420p[vout]" '
            '-map "[vout]" -map 1:a'
        : '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=$fps,format=yuv420p" '
            '-map 0:v -map 1:a';
    return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
        '-f lavfi -t $dur -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '$frameChain -shortest '
        '$videoArgs $audioArgs ${q(output)}';
  }

  /// A still image held for [durationSec] as a video segment with a
  /// silent audio track (the 3 s outro end card, rendered from the
  /// template PNG). Same codecs/dims as [normalizeCommand] so the
  /// concat demuxer can join it with the other segments.
  static String stillSegmentCommand({
    required String imagePath,
    required double durationSec,
    required int width,
    required int height,
    required String output,
    // Phase 9 — the export screen's real fps/bitrate (see
    // [normalizeCommand]; defaults = Phase 7 behaviour).
    int fps = 30,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
  }) {
    final dur = durationSec.clamp(0.1, 3600.0);
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac -ar 48000 -ac 2'
        : '-c:a aac -b:a ${audioBitrateKbps}k -ar 48000 -ac 2';
    return '-y -loop 1 -t $dur -i ${q(imagePath)} '
        '-f lavfi -t $dur -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=$fps,format=yuv420p" '
        '-map 0:v -map 1:a -shortest '
        '$videoArgs $audioArgs ${q(output)}';
  }

  /// Second-pass overlay for the v2 news template and/or logo.
  ///
  /// [templatePngPath] is the composited 720x1280 template frame
  /// rendered by dart:ui (the same renderer the live view uses), so
  /// Urdu/Arabic shaping stays correct — FFmpeg drawtext would render
  /// it disconnected. It is scaled to the video frame with scale2ref,
  /// so every export aspect works (banner stays top, ticker bottom).
  /// [logoPath] is scaled to 160px wide and placed at [logoPosition]
  /// (topLeft/topRight/bottomLeft/bottomRight). Logo rotation is
  /// live-only; exports get a static logo. Audio is copied untouched
  /// (only video re-encodes). Returns null when neither overlay is
  /// requested, so callers can skip the pass entirely.
  static String? overlayPassCommand({
    required String input,
    String? templatePngPath,
    String? logoPath,
    String logoPosition = 'topRight',
    required String output,
    // Phase 9 — the export screen's real video bitrate (null = CRF 23).
    int? videoBitrateKbps,
  }) {
    if (templatePngPath == null && logoPath == null) return null;
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} ');
    int? logoIdx;
    int? templateIdx;
    if (logoPath != null) {
      buf.write('-i ${q(logoPath)} ');
      logoIdx = 1;
    }
    if (templatePngPath != null) {
      buf.write('-i ${q(templatePngPath)} ');
      templateIdx = logoIdx == null ? 1 : 2;
    }
    buf.write('-filter_complex "');
    var videoLabel = '[0:v]';
    if (templateIdx != null) {
      final outLabel = logoIdx != null ? '[tmp]' : '[vout]';
      buf.write(
        '$videoLabel[$templateIdx:v]scale2ref[base][ov];'
        '[base][ov]overlay=0:0$outLabel;',
      );
      videoLabel = outLabel;
    }
    if (logoIdx != null) {
      final pos = switch (logoPosition) {
        'topLeft' => 'x=16:y=16',
        'topRight' => 'x=W-w-16:y=16',
        'bottomLeft' => 'x=16:y=H-h-16',
        'bottomRight' => 'x=W-w-16:y=H-h-16',
        _ => 'x=W-w-16:y=16',
      };
      buf.write(
        '[$logoIdx:v]scale=160:-1[logo];'
        '$videoLabel[logo]overlay=$pos[vout];',
      );
      videoLabel = '[vout]';
    }
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    buf.write(
      '" -map "$videoLabel" -map 0:a? '
      '$videoArgs -c:a copy '
      '-movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }

  /// Watermark overlay pass (Phase 8, master prompt §9).
  ///
  /// [watermarkPngPath] is the full-frame transparent PNG from
  /// `renderWatermarkImage` (same frame size as [input], mark already
  /// at its corner), so the overlay is a plain 0:0 composite — no
  /// scale2ref, no position math in the filter graph. Audio is
  /// copied untouched (only video re-encodes). The caller skips this
  /// pass entirely when the preset's watermark is off.
  static String watermarkOverlayCommand({
    required String input,
    required String watermarkPngPath,
    required String output,
    // Phase 9 — the export screen's real video bitrate (null = CRF 23).
    int? videoBitrateKbps,
  }) {
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    return '-y -i ${q(input)} -i ${q(watermarkPngPath)} '
        '-filter_complex "[0:v][1:v]overlay=0:0[vout]" '
        '-map "[vout]" -map 0:a? '
        '$videoArgs -c:a copy '
        '-movflags +faststart ${q(output)}';
  }
}

