/// Auto captions for the video editor (CapCut-style).
///
/// Transcription is FULLY ON-DEVICE from the video's own audio track:
/// the selected (trimmed) clip's audio is extracted with FFmpeg and
/// transcribed by whisper.cpp (whisper_ggml_plus, tiny multilingual
/// model, Urdu + English) — no microphone, no quiet room, earphones
/// work fine, and no network is needed after the first download. The
/// tiny model (~75 MB) is NOT bundled with the app anymore (v2 size
/// work): it downloads once on first captions use with a real progress
/// bar, then works offline forever. If that download ever fails, the
/// plugin's own one-time model download is used instead of failing
/// outright.
///
/// Engine note: whisper_ggml_plus is the FFmpeg-free fork of
/// whisper_ggml — its core package bundles NO FFmpeg, which is what
/// keeps it compatible with this app's own full ffmpeg-kit plugin
/// (the original whisper_ggml pulled ffmpeg-kit-min and its Android
/// namespace collided with the app's ffmpeg-kit-full, failing the
/// build at manifest merge). The app already extracts 16 kHz mono WAV
/// itself, so the companion FFmpeg converter package is not needed.
/// This package's controller API has no progress callback, so
/// transcription reports a static "Transcribing…" status; and its VAD
/// is off on Android unless a VAD model path is supplied, so no VAD
/// model is bundled (long silences can occasionally hallucinate —
/// Edit-before-export is the safety net).
///
/// Timings come from whisper's segment timestamps (much more accurate
/// than the old playback-clock mic approach). Burning uses an ASS
/// subtitles file (libass shapes Urdu/Arabic script correctly). If a
/// build ever lacks the subtitles filter, the screen falls back to
/// timed drawtext — Latin scripts only, since drawtext does not shape
/// Arabic script.
///
/// Caption styles: the Default style is the long-standing look; the
/// extra presets match the reel-caption set. Pop is real ASS karaoke
/// ({\k} per word, current word green, rest white); word timing inside
/// a line is split evenly across the line's whisper window, so it is
/// approximate within a line and exact at line boundaries.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'ffmpeg_service.dart';

/// One caption line with its time window in seconds (relative to the
/// trimmed clip start, before speed scaling).
class CaptionSegment {
  CaptionSegment(this.text, this.start, this.end);
  final String text;
  final double start;
  final double end;
}

/// Caption look. `standard` is the long-standing default and stays the
/// default; the rest are opt-in presets.
enum CaptionStyle { standard, highlight, gold, clean, pop, boxed }

class CaptionService {
  /// Arabic-script range (Urdu, Arabic, Persian).
  static bool containsArabic(String text) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  static bool containsArabicInSegments(List<CaptionSegment> segments) =>
      segments.any((s) => containsArabic(s.text));

  /// Split long recognized utterances into short readable chunks
  /// (max [maxWords] words each) with proportional timing, and force
  /// non-overlapping, monotonically increasing windows.
  static List<CaptionSegment> chunkSegments(
    List<CaptionSegment> raw, {
    int maxWords = 5,
  }) {
    final out = <CaptionSegment>[];
    for (final seg in raw) {
      final words = seg.text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isEmpty) continue;
      final dur = (seg.end - seg.start).clamp(0.5, 60.0);
      if (words.length <= maxWords) {
        out.add(CaptionSegment(seg.text, seg.start, seg.end));
      } else {
        var i = 0;
        while (i < words.length) {
          final chunk = words.skip(i).take(maxWords).toList();
          final f0 = i / words.length;
          final f1 = (i + chunk.length) / words.length;
          out.add(CaptionSegment(
            chunk.join(' '),
            seg.start + dur * f0,
            seg.start + dur * f1,
          ));
          i += chunk.length;
        }
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    final fixed = <CaptionSegment>[];
    for (final s in out) {
      var start = s.start;
      var end = s.end;
      if (fixed.isNotEmpty && start < fixed.last.end) {
        start = fixed.last.end;
      }
      if (end <= start) end = start + 0.8;
      fixed.add(CaptionSegment(s.text, start, end));
    }
    return fixed;
  }

  /// ASS timestamp H:MM:SS.cc.
  static String formatAssTime(double seconds) {
    final totalCs = (seconds * 100).round().clamp(0, 1 << 31);
    final h = totalCs ~/ 360000;
    final m = (totalCs % 360000) ~/ 6000;
    final s = (totalCs % 6000) ~/ 100;
    final cs = totalCs % 100;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  static String escapeAss(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('\n', r'\N');

  static String _styleName(CaptionStyle style, bool arabic) {
    switch (style) {
      case CaptionStyle.standard:
        return arabic ? 'Urdu' : 'Default';
      case CaptionStyle.highlight:
        return arabic ? 'HighlightUrdu' : 'Highlight';
      case CaptionStyle.gold:
        return arabic ? 'GoldUrdu' : 'Gold';
      case CaptionStyle.clean:
        return arabic ? 'CleanUrdu' : 'Clean';
      case CaptionStyle.pop:
        return arabic ? 'PopUrdu' : 'Pop';
      case CaptionStyle.boxed:
        return arabic ? 'BoxedUrdu' : 'Boxed';
    }
  }

  /// ASS style line fields (AABBGGRR colours, following the same byte
  /// conventions as the long-standing Default style).
  static String _styleLine({
    required String name,
    required String font,
    required int size,
    required String primary,
    required String secondary,
    required String outlineColour,
    required String back,
    required int bold,
    required int borderStyle,
    required int outline,
    required int marginV,
  }) =>
      'Style: $name,$font,$size,$primary,$secondary,$outlineColour,'
      '$back,$bold,0,0,0,100,100,0,0,$borderStyle,$outline,0,2,40,40,$marginV,1';

  /// Karaoke line for the Pop style: {\k} per word, durations split
  /// evenly across the line's whisper window (approximate within a
  /// line, exact at line boundaries).
  static String _karaokeLine(CaptionSegment s) {
    final words = s.text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return escapeAss(s.text);
    final dur = (s.end - s.start).clamp(0.2, 60.0);
    final per = (dur / words.length * 100).round().clamp(1, 6000);
    final buf = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      if (i > 0) buf.write(' ');
      buf.write('{\\k$per}${escapeAss(words[i])}');
    }
    return buf.toString();
  }

  /// Full ASS document. Latin lines use Roboto; Arabic-script lines use
  /// Noto Naskh Arabic so Urdu renders shaped, not disconnected.
  /// [style] defaults to the long-standing look; other presets only
  /// change colours/weight (and karaoke tags for Pop).
  static String buildAss({
    required List<CaptionSegment> segments,
    required bool portrait,
    CaptionStyle style = CaptionStyle.standard,
  }) {
    final w = portrait ? 720 : 1280;
    final h = portrait ? 1280 : 720;
    final size = portrait ? 44 : 36;
    final marginV = portrait ? 90 : 60;
    // (primary, secondary, outlineColour, back, bold, borderStyle, outline)
    final String primary;
    final String secondary;
    final String outlineColour;
    final String back;
    final int bold;
    final int borderStyle;
    final int outline;
    switch (style) {
      case CaptionStyle.standard:
        primary = '&H00FFFFFF';
        secondary = '&H000000FF';
        outlineColour = '&HFF000000';
        back = '&H80000000';
        bold = -1;
        borderStyle = 1;
        outline = 2;
      case CaptionStyle.highlight:
        // Black text on an opaque yellow box.
        primary = '&H00000000';
        secondary = '&H000000FF';
        outlineColour = '&HFF000000';
        back = '&H0000FFFF';
        bold = -1;
        borderStyle = 3;
        outline = 0;
      case CaptionStyle.gold:
        primary = '&H0037AFD4';
        secondary = '&H000000FF';
        outlineColour = '&HFF000000';
        back = '&H80000000';
        bold = -1;
        borderStyle = 1;
        outline = 2;
      case CaptionStyle.clean:
        // Same colours as Default but regular weight (no bold) and no
        // keyword colouring (ASS lines are single-colour anyway).
        primary = '&H00FFFFFF';
        secondary = '&H000000FF';
        outlineColour = '&HFF000000';
        back = '&H80000000';
        bold = 0;
        borderStyle = 1;
        outline = 2;
      case CaptionStyle.pop:
        // Karaoke: sung word green, unsung words white.
        primary = '&H0070EC3A';
        secondary = '&H00FFFFFF';
        outlineColour = '&HFF000000';
        back = '&H80000000';
        bold = -1;
        borderStyle = 1;
        outline = 2;
      case CaptionStyle.boxed:
        // TikTok/meme look: white bold text on an opaque black box.
        primary = '&H00FFFFFF';
        secondary = '&H00FFFFFF';
        outlineColour = '&HFF000000';
        back = '&H00000000';
        bold = -1;
        borderStyle = 3;
        outline = 0;
    }
    final buf = StringBuffer();
    buf.writeln('[Script Info]');
    buf.writeln('ScriptType: v4.00+');
    buf.writeln('PlayResX: $w');
    buf.writeln('PlayResY: $h');
    buf.writeln('WrapStyle: 2');
    buf.writeln();
    buf.writeln('[V4+ Styles]');
    buf.writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
      'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
      'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
      'Alignment, MarginL, MarginR, MarginV, Encoding',
    );
    buf.writeln(_styleLine(
      name: _styleName(style, false),
      font: 'Roboto',
      size: size,
      primary: primary,
      secondary: secondary,
      outlineColour: outlineColour,
      back: back,
      bold: bold,
      borderStyle: borderStyle,
      outline: outline,
      marginV: marginV,
    ));
    buf.writeln(_styleLine(
      name: _styleName(style, true),
      font: 'Noto Naskh Arabic',
      size: size + 4,
      primary: primary,
      secondary: secondary,
      outlineColour: outlineColour,
      back: back,
      bold: bold,
      borderStyle: borderStyle,
      outline: outline,
      marginV: marginV,
    ));
    buf.writeln();
    buf.writeln('[Events]');
    buf.writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
      'Effect, Text',
    );
    for (final s in segments) {
      final styleName = _styleName(style, containsArabic(s.text));
      final text =
          style == CaptionStyle.pop ? _karaokeLine(s) : escapeAss(s.text);
      buf.writeln(
        'Dialogue: 0,${formatAssTime(s.start)},${formatAssTime(s.end)},'
        '$styleName,,0,0,0,,$text',
      );
    }
    return buf.toString();
  }

  /// Timed drawtext filter chain (fallback when the subtitles filter is
  /// unavailable). Returns null without a font file. Latin scripts only
  /// — drawtext does not shape Arabic script, so callers must not use
  /// this for Urdu captions. Styles do not apply here; it always uses
  /// white text with a black border.
  static String? buildDrawtextFilters({
    required List<CaptionSegment> segments,
    required String? fontFile,
    required double fontSize,
  }) {
    if (segments.isEmpty || fontFile == null) return null;
    final parts = <String>[];
    for (final s in segments) {
      parts.add(
        "drawtext=fontfile=$fontFile:text='${FfmpegService.escapeDrawText(s.text)}'"
        ':fontsize=${fontSize.round()}:fontcolor=white:borderw=3:bordercolor=black'
        ":x=(w-text_w)/2:y=h-text_h-60:enable='between(t,${s.start.toStringAsFixed(2)},${s.end.toStringAsFixed(2)})'",
      );
    }
    return parts.join(',');
  }

  /// First readable Arabic-script system font, or null. Used only for a
  /// warning: ASS picks fonts by name from /system/fonts at burn time.
  static String? findArabicFont() {
    const candidates = [
      '/system/fonts/NotoNaskhArabic-Regular.ttf',
      '/system/fonts/NotoNaskhArabicUI-Regular.ttf',
      '/system/fonts/NotoSansArabic-Regular.ttf',
      '/system/fonts/NotoSansArabicUI-Regular.ttf',
    ];
    for (final c in candidates) {
      try {
        if (File(c).existsSync()) return c;
      } catch (_) {}
    }
    return null;
  }
}

/// File-audio transcription: the video's own audio track, decoded by
/// whisper.cpp on-device. No microphone is involved at any point.
class FileCaptionEngine {
  /// Same model the CI workflow used to bundle (ggml-tiny.bin). It is
  /// downloaded once, on first captions use, with real progress, and
  /// cached at the plugin's own model path afterwards.
  static const _modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin';

  /// Makes sure the tiny model exists at the plugin's model path.
  /// Downloads to a `.part` file first and renames on success, so an
  /// interrupted download never leaves a corrupt model behind.
  /// [onModelDownloadProgress] reports 0..1 while downloading.
  static Future<void> _ensureModel({
    void Function(double progress)? onModelDownloadProgress,
  }) async {
    final controller = WhisperController();
    final modelPath = await controller.getPath(WhisperModel.tiny);
    final modelFile = File(modelPath);
    if (await modelFile.exists() && await modelFile.length() > 0) return;
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_modelUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('Model download HTTP ${response.statusCode}');
        }
        final total = response.contentLength;
        final partFile = File('$modelPath.part');
        final sink = partFile.openWrite();
        var received = 0;
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            onModelDownloadProgress?.call(received / total);
          }
        }
        await sink.close();
        if (await partFile.length() == 0) {
          throw Exception('Model download came back empty');
        }
        await partFile.rename(modelPath);
      } finally {
        client.close();
      }
    } catch (_) {
      // Own download failed: fall back to the plugin's one-time
      // download instead of failing outright.
      try {
        await controller.downloadModel(WhisperModel.tiny);
      } catch (_) {
        // Transcribe below will surface the real error.
      }
    }
  }

  /// Extract the trimmed range of [inputPath] as 16 kHz mono WAV
  /// (the format whisper expects). Timings of the result are relative
  /// to [trimStart], matching the old playback-clock convention.
  static Future<File> extractAudio({
    required String inputPath,
    required double trimStart,
    required double trimEnd,
    required Directory dir,
  }) async {
    final outPath = p.join(dir.path, 'caption_audio.wav');
    final cmd =
        '-i ${FfmpegService.q(inputPath)} -ss ${trimStart.toStringAsFixed(2)} '
        '-to ${trimEnd.toStringAsFixed(2)} -vn -ac 1 -ar 16000 -f wav '
        '${FfmpegService.q(outPath)}';
    final res = await FfmpegService.run(
      cmd,
      expectedMs: ((trimEnd - trimStart) * 1000).round(),
    );
    if (!res.ok) {
      final logs = res.logs;
      if (logs.contains('matches no streams') ||
          logs.contains('does not contain any stream') ||
          logs.contains('Stream map')) {
        throw Exception(
          'Is video me audio track nahi hai — captions ke liye awaz wali video chahiye.',
        );
      }
      throw Exception('Audio nikalne me masla: $logs');
    }
    final file = File(outPath);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception('Audio file nahi bani — dobara try karein.');
    }
    return file;
  }

  /// Transcribe [wavPath] with the tiny multilingual model.
  /// [lang] is 'ur' or 'en'. Returns whisper's phrase segments with
  /// real timestamps (no chunking here — callers chunk for display).
  /// The model is downloaded once on first use (see [_ensureModel]);
  /// [onModelDownloadProgress] reports 0..1 during that download.
  /// `convert: false` because the WAV is already 16 kHz mono (no
  /// FFmpeg conversion step, no companion package needed).
  static Future<List<CaptionSegment>> transcribeFile({
    required String wavPath,
    required String lang,
    void Function(double progress)? onModelDownloadProgress,
  }) async {
    try {
      await _ensureModel(
        onModelDownloadProgress: onModelDownloadProgress,
      );
    } catch (_) {
      // Model prep failed: transcribe below surfaces the real error.
    }
    final controller = WhisperController();
    final result = await controller.transcribe(
      model: WhisperModel.tiny,
      audioPath: wavPath,
      lang: lang,
      withTimestamps: true,
      convert: false,
      vadMode: WhisperVadMode.auto,
    );
    final out = <CaptionSegment>[];
    for (final s in result?.transcription.segments ?? []) {
      final text = s.text.trim();
      if (text.isEmpty) continue;
      final start = s.fromTs.inMilliseconds / 1000.0;
      final end = s.toTs.inMilliseconds / 1000.0;
      if (end <= start) continue;
      out.add(CaptionSegment(text, start, end));
    }
    return out;
  }
}

