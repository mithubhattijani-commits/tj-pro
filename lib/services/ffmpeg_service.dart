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

  /// Aspect filter: scale to cover target then center-crop (empty = original).
  static String aspectFilter(String aspect) {
    switch (aspect) {
      case '9:16':
        return 'scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280';
      case '16:9':
        return 'scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720';
      case '1:1':
        return 'scale=720:720:force_original_aspect_ratio=increase,crop=720:720';
      default:
        return '';
    }
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
  }) {
    final parts = <String>[];
    if (speed != 1.0) parts.add('setpts=PTS/$speed');
    final vf = videoFilter(filterPreset);
    if (vf.isNotEmpty) parts.add(vf);
    final af = aspectFilter(aspect);
    if (af.isNotEmpty) parts.add(af);
    if (text != null && text.trim().isNotEmpty && fontFile != null) {
      final h = videoHeight ?? 720;
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
  static String normalizeCommand({
    required String input,
    required double trimStart,
    required double trimEnd,
    required int width,
    required int height,
    required String output,
  }) {
    return '-y -ss $trimStart -to $trimEnd -i ${q(input)} '
        '-vf "scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,fps=30,format=yuv420p" '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -ar 48000 -ac 2 ${q(output)}';
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
    buf.write(
      '" -map "$videoLabel" -map 0:a? '
      '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
      '-movflags +faststart ${q(output)}',
    );
    return buf.toString();
  }
}

