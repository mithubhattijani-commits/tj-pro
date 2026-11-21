/// FFmpeg command builders + execution wrapper (via ffmpeg_kit_flutter_new).
///
/// All video work in V1 goes through here so the UI never touches raw
/// FFmpeg syntax. Commands are built as strings because FFmpegKit parses
/// them itself; file paths are single-quoted and escaped.
library;

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';

/// Result of one FFmpeg run.
class FfmpegResult {
  FfmpegResult(this.returnCode, this.logs);
  final int returnCode;
  final String logs;
  bool get ok => returnCode == 0;
}

/// Thin wrapper around FFmpegKit with progress reporting.
class FfmpegService {
  /// Runs [command]. [expectedMs] is the approximate output duration in
  /// milliseconds, used to turn statistics time into 0..1 progress.
  static Future<FfmpegResult> run(
    String command, {
    int? expectedMs,
    void Function(double progress)? onProgress,
  }) async {
    if (onProgress != null && expectedMs != null && expectedMs > 0) {
      FFmpegKitConfig.enableStatisticsCallback((statistics) {
        final t = statistics.getTime();
        if (t > 0) {
          onProgress((t / expectedMs).clamp(0.0, 1.0));
        }
      });
    }
    final session = await FFmpegKit.execute(command);
    final rc = await session.getReturnCode();
    final code = rc?.getValue() ?? -1;
    var output = await session.getOutput() ?? '';
    // Keep error text readable in the UI status line.
    if (output.length > 800) {
      output = output.substring(output.length - 800);
    }
    FFmpegKitConfig.disableStatistics();
    return FfmpegResult(code, output);
  }

  static void cancel() {
    FFmpegKit.cancel();
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
  static String videoFilter(String preset) {
    switch (preset) {
      case 'Warm':
        return 'colortemperature=temperature=3800:mix=0.6:pl=1';
      case 'Cool':
        return 'colortemperature=temperature=8500:mix=0.6:pl=1';
      case 'B&W':
        return 'hue=s=0';
      case 'Vivid':
        return 'eq=saturation=1.4:contrast=1.08:brightness=0.02';
      case 'Sepia':
        return 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131';
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
      default:
        return null;
    }
  }

  /// Aspect filter: scale to cover target then center-crop (empty = original).
  /// The target size follows [exportQuality]: 0 = 720p HD (fast, the
  /// long-standing default), 1 = 1080p Full HD, 2 = 2160p 4K (slow).
  static String aspectFilter(String aspect, {int exportQuality = 0}) {
    final dims = exportDims(aspect, exportQuality);
    if (dims == null) return '';
    final int w = dims.$1;
    final int h = dims.$2;
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
  }) {
    final parts = <String>[];
    if (speed != 1.0) parts.add('setpts=PTS/$speed');
    final vf = videoFilter(filterPreset);
    if (vf.isNotEmpty) parts.add(vf);
    final af = aspectFilter(aspect, exportQuality: exportQuality);
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
    return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
        '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=$fps,format=yuv420p" '
        '$videoArgs $audioArgs ${q(output)}';
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
  static String musicBedCommand({
    required String input,
    required String musicPath,
    required String output,
    required bool hasClipAudio,
    double musicVolume = 0.18,
    int? audioBitrateKbps,
  }) {
    final vol = musicVolume.clamp(0.0, 1.0).toStringAsFixed(2);
    final buf = StringBuffer();
    buf.write('-y -i ${q(input)} -stream_loop -1 -i ${q(musicPath)} ');
    if (hasClipAudio) {
      buf.write(
        '-filter_complex "[1:a]volume=$vol[bed];'
        '[0:a][bed]amix=inputs=2:duration=first:'
        'dropout_transition=0[aout]" '
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

  /// Rotating-logo overlay pass (Phase 7, see
  /// `~/workspace/tj-pro-news-maker/rotation-decision.md`): overlays
  /// the 3D-rotating logo bug on [input] at the template's logo-bug
  /// spot (see [logoBugRect]). The loop source is EITHER
  /// [movPath] — the pre-rendered `logo-rotating-alpha.mov`, ping-ponged
  /// in-graph (forward + `reverse` concat, so the 10 s truncated swing
  /// loops seamlessly) — OR [framesDir] — a directory of
  /// `frame_%02d.png` frames (a generated rotating loop for a
  /// user-replaced logo, or the default initial tile), looped with the
  /// image2 demuxer. Exactly one of the two must be given. The
  /// `perspective` filter is deliberately NOT used (rejected in the
  /// decision doc: a shear, not a true rotationY). Audio is copied.
  static String logoLoopOverlayCommand({
    required String input,
    required String output,
    required int width,
    required int height,
    required bool topRibbonEnabled,
    String? movPath,
    String? framesDir,
    int framesFps = 12,
    // Phase 9 — the export screen's real video bitrate (null = CRF 23).
    int? videoBitrateKbps,
  }) {
    assert(
      (movPath == null) != (framesDir == null),
      'logoLoopOverlayCommand needs exactly one of movPath / framesDir',
    );
    final (x, y, size) = logoBugRect(
      width: width,
      height: height,
      topRibbonEnabled: topRibbonEnabled,
    );
    final buf = StringBuffer();
    buf.write('-y ');
    if (movPath != null) {
      // Crop to the mov's opaque alpha bbox (measured 235,86,396x316
      // on the 854x480 ProRes) — the logo occupies only the centre of
      // the frame — then ping-pong forward+reverse into a seamless
      // 20 s loop, scaled to bug size.
      buf.write('-stream_loop -1 -i ${q(movPath)} ');
      buf.write('-i ${q(input)} ');
      buf.write('-filter_complex "');
      buf.write(
        '[0:v]crop=396:316:235:86,format=yuva420p,split[f][r];'
        '[r]reverse[rr];[f][rr]concat=n=2:v=1:a=0,format=yuva420p,'
        'scale=$size:-1[bug];'
        '[1:v][bug]overlay=$x:$y[vout]" ',
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
        '[1:v][bug]overlay=$x:$y[vout]" ',
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
    buf.write(
      '$videoArgs -c:a copy '
      '-movflags +faststart ${q(output)}',
    );
    return buf.toString();
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
    return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
        '-f lavfi -t $dur -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=$fps,format=yuv420p" '
        '-map 0:v -map 1:a -shortest '
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

