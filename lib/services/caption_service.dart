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

import 'caption_styles.dart';
import 'ffmpeg_service.dart';

/// One word with its real spoken timing — Whisper word timestamps
/// (transcribed clips) or karaoke-sync timings (voiceover lines, see
/// `lib/news/karaoke_sync.dart`). When a segment has no words,
/// callers fall back to even-split timing.
class CaptionWord {
  const CaptionWord({
    required this.word,
    required this.start,
    required this.end,
  });

  final String word;
  final double start;
  final double end;

  Map<String, dynamic> toJson() => {
        'word': word,
        'start': start,
        'end': end,
      };

  static CaptionWord fromJson(Map<String, dynamic> json) {
    return CaptionWord(
      word: (json['word'] as String?) ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One caption line with its time window in seconds (relative to the
/// trimmed clip start, before speed scaling).
class CaptionSegment {
  CaptionSegment(
    this.text,
    this.start,
    this.end, {
    List<CaptionWord>? words,
    this.translation = '',
  }) : words = words ?? [];

  final String text;
  final double start;
  final double end;

  /// Real per-word timings when known (empty = even-split fallback).
  final List<CaptionWord> words;

  /// Second-language line for dual captions (e.g. the English line
  /// under an Urdu line). Empty = no second line.
  final String translation;

  CaptionSegment copyWith({
    String? text,
    double? start,
    double? end,
    List<CaptionWord>? words,
    String? translation,
  }) {
    return CaptionSegment(
      text ?? this.text,
      start ?? this.start,
      end ?? this.end,
      words: words ?? this.words,
      translation: translation ?? this.translation,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'start': start,
        'end': end,
        'words': words.map((w) => w.toJson()).toList(),
        'translation': translation,
      };

  static CaptionSegment fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'];
    final words = <CaptionWord>[];
    if (rawWords is List) {
      for (final w in rawWords) {
        if (w is Map<String, dynamic>) {
          words.add(CaptionWord.fromJson(w));
        }
      }
    }
    return CaptionSegment(
      (json['text'] as String?) ?? '',
      (json['start'] as num?)?.toDouble() ?? 0,
      (json['end'] as num?)?.toDouble() ?? 0,
      words: words,
      translation: (json['translation'] as String?) ?? '',
    );
  }
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
        // Keep the line whole — its word timings and translation
        // stay valid.
        out.add(seg);
      } else {
        // Splitting invalidates per-word timings (they belonged to
        // the old text); the translation stays on the first chunk.
        var i = 0;
        while (i < words.length) {
          final chunk = words.skip(i).take(maxWords).toList();
          final f0 = i / words.length;
          final f1 = (i + chunk.length) / words.length;
          out.add(CaptionSegment(
            chunk.join(' '),
            seg.start + dur * f0,
            seg.start + dur * f1,
            translation: i == 0 ? seg.translation : '',
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

  // ---- Phase 5: text exports, real word timing, styled ASS ----
  //
  // Ported from Magic Box's `caption_service.dart` (v1.0.13) and
  // adapted to TJ Pro's [CaptionSegment] (which carries `words` +
  // `translation` since Phase 5). The long-standing [buildAss]
  // above is untouched — the live video editor still uses it.

  /// `MM:SS` clock label (list UI).
  static String formatClock(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// `HH:MM:SS,mmm` SRT timestamp.
  static String formatSrtTimestamp(double seconds) {
    final totalMs = (seconds * 1000).round();
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    final ms = totalMs % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  /// `HH:MM:SS.mmm` WebVTT timestamp (dot, not comma, unlike SRT).
  static String formatVttTimestamp(double seconds) =>
      formatSrtTimestamp(seconds).replaceFirst(',', '.');

  /// Builds a full SRT document from segments. [dualLanguage] adds
  /// each line's translation as a second line in the same cue.
  static String buildSrt(
    List<CaptionSegment> segments, {
    bool dualLanguage = false,
  }) {
    final buf = StringBuffer();
    var index = 0;
    for (final seg in segments) {
      if (seg.text.trim().isEmpty) continue;
      index++;
      buf.writeln(index);
      buf.writeln(
        '${formatSrtTimestamp(seg.start)} --> ${formatSrtTimestamp(seg.end)}',
      );
      buf.writeln(seg.text);
      if (dualLanguage && seg.translation.trim().isNotEmpty) {
        buf.writeln(seg.translation);
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// Builds a WebVTT document from segments (YouTube / web players).
  static String buildVtt(
    List<CaptionSegment> segments, {
    bool dualLanguage = false,
  }) {
    final buf = StringBuffer()..writeln('WEBVTT')..writeln();
    for (final seg in segments) {
      if (seg.text.trim().isEmpty) continue;
      buf.writeln(
        '${formatVttTimestamp(seg.start)} --> ${formatVttTimestamp(seg.end)}',
      );
      buf.writeln(seg.text);
      if (dualLanguage && seg.translation.trim().isNotEmpty) {
        buf.writeln(seg.translation);
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// Plain-text export: one caption line per text line, no timings.
  /// This is what the Copy button copies.
  static String buildPlainText(
    List<CaptionSegment> segments, {
    bool dualLanguage = false,
  }) {
    final lines = <String>[];
    for (final seg in segments) {
      if (seg.text.trim().isEmpty) continue;
      lines.add(seg.text);
      if (dualLanguage && seg.translation.trim().isNotEmpty) {
        lines.add(seg.translation);
      }
    }
    return lines.join('\n');
  }

  /// TXT export file contents — same as [buildPlainText].
  static String buildTxt(
    List<CaptionSegment> segments, {
    bool dualLanguage = false,
  }) =>
      buildPlainText(segments, dualLanguage: dualLanguage);

  /// Parses an SRT document back into segments (used by the
  /// translator: paste/pick an .srt file, translate it, re-export).
  /// Malformed blocks are skipped, never fatal. Timings are
  /// `HH:MM:SS,mmm` (a `.` separator is also accepted).
  static List<CaptionSegment> parseSrt(String srt) {
    final out = <CaptionSegment>[];
    final blocks = srt.replaceAll('\r\n', '\n').split('\n\n');
    for (final block in blocks) {
      final lines =
          block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.length < 2) continue;
      // First line may be the cue number — find the timing line.
      var timingIndex = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timingIndex = i;
          break;
        }
      }
      if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
      final parts = lines[timingIndex].split('-->');
      if (parts.length != 2) continue;
      final start = _parseSrtTime(parts[0].trim());
      final end = _parseSrtTime(parts[1].trim());
      if (start == null || end == null || end <= start) continue;
      final text = lines.sublist(timingIndex + 1).join('\n').trim();
      if (text.isEmpty) continue;
      out.add(CaptionSegment(text, start, end));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  static double? _parseSrtTime(String stamp) {
    final match = RegExp(r'^(\d+):(\d+):(\d+)[,.](\d+)$')
        .firstMatch(stamp.trim());
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    final s = int.tryParse(match.group(3)!);
    final ms = int.tryParse(match.group(4)!);
    if (h == null || m == null || s == null || ms == null) return null;
    return h * 3600 + m * 60 + s + ms / 1000;
  }

  // ---- real word timing with even-split fallback ----

  /// Start of word [index] in [seg] — real timing when known.
  static double wordStartOf(CaptionSegment seg, int index) {
    if (index >= 0 && index < seg.words.length) {
      return seg.words[index].start;
    }
    return StudioCaptionStyles.wordStart(
      start: seg.start,
      end: seg.end,
      text: seg.text,
      index: index,
    );
  }

  /// End of word [index] in [seg] — real timing when known.
  static double wordEndOf(CaptionSegment seg, int index) {
    if (index >= 0 && index < seg.words.length) {
      return seg.words[index].end;
    }
    return StudioCaptionStyles.wordEnd(
      start: seg.start,
      end: seg.end,
      text: seg.text,
      index: index,
    );
  }

  /// Index of the word being spoken at [positionSeconds], or -1 when
  /// outside the line. Real word timings when known, even-split
  /// otherwise.
  static int activeWordIndexOf(
    CaptionSegment seg,
    double positionSeconds,
  ) {
    if (seg.words.isNotEmpty) {
      for (var i = 0; i < seg.words.length; i++) {
        if (positionSeconds >= seg.words[i].start &&
            positionSeconds < seg.words[i].end) {
          return i;
        }
      }
      if (positionSeconds < seg.start) return -1;
      if (positionSeconds >= seg.end) return seg.words.length - 1;
      return -1;
    }
    return StudioCaptionStyles.activeWordIndex(
      start: seg.start,
      end: seg.end,
      text: seg.text,
      positionSeconds: positionSeconds,
    );
  }

  /// Builds a styled ASS document from segments + a Magic Box style
  /// ([StudioCaptionStyle]), so the captions open in CapCut / any
  /// editor that reads ASS with the chosen look (colours, size,
  /// position, bold/outline). Word-by-word styles use the REAL word
  /// timings when the segment carries them ([wordStartOf]/[wordEndOf])
  /// and even-split timing only as a fallback.
  ///
  /// - karaoke: one Dialogue per line, `{\kf}` per word (ASS karaoke
  ///   fills the sung part with SecondaryColour = highlight).
  /// - pop: one Dialogue per word (only that word on screen).
  /// - typewriter: one Dialogue per word, showing words-so-far.
  /// - flash: one plain Dialogue per line.
  ///
  /// [playResX]/[playResY] set the ASS canvas: pass 1080x1920 for a
  /// vertical (9:16) video and 1280x720 for a horizontal one — the
  /// font size scales with the canvas height. [outline]/[shadow]/
  /// [background] override the style's FX toggles when given.
  /// [dualLanguage] adds each line's translation as a second,
  /// smaller Dialogue above the main line. NOTE: the Highlight Box
  /// style's yellow word background has no ASS equivalent and is
  /// skipped here — the line still carries the style's colours.
  static String buildStyledAss(
    List<CaptionSegment> segments,
    StudioCaptionStyle style, {
    CaptionPosition position = CaptionPosition.bottom,
    CaptionSize size = CaptionSize.medium,
    int? highlightColor,
    String? fontFamily,
    int playResX = 1280,
    int playResY = 720,
    bool? outline,
    bool? shadow,
    bool? background,
    int? backgroundColor,
    bool dualLanguage = false,
  }) {
    final hl = highlightColor ?? style.highlightColor;
    // Font size scales with the canvas height (style sizes are tuned
    // for a 720p canvas) so captions keep the same relative size on
    // a 1080x1920 portrait canvas.
    final resScale = playResY / 720;
    final fontSize =
        (style.fontSizePt * StudioCaptionStyles.sizeScale(size) * resScale)
            .round();
    final dualFontSize = (fontSize * 0.7).round();
    final marginV = (40 * resScale).round();
    final dualMarginV = marginV + fontSize;
    final alignment = StudioCaptionStyles.assAlignment(position);
    final useOutline = outline ?? style.outline;
    final useShadow = shadow ?? style.shadow;
    final useBackground = background ?? (style.backgroundColor != 0);
    final back = useBackground
        ? StudioCaptionStyles.assColor(
            backgroundColor ??
                (style.backgroundColor != 0
                    ? style.backgroundColor
                    : StudioCaptionStyles.black70),
          )
        : '&H80000000';
    // Background ON = opaque box behind the line (BorderStyle 3);
    // otherwise the classic outline + shadow style (BorderStyle 1).
    final borderStyle = useBackground ? 3 : 1;
    final buf = StringBuffer();
    buf.writeln('[Script Info]');
    buf.writeln('Title: TJ Pro Captions');
    buf.writeln('ScriptType: v4.00+');
    buf.writeln('WrapStyle: 0');
    buf.writeln('ScaledBorderAndShadow: yes');
    buf.writeln('PlayResX: $playResX');
    buf.writeln('PlayResY: $playResY');
    buf.writeln();
    buf.writeln('[V4+ Styles]');
    buf.writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
      'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
      'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
      'Alignment, MarginL, MarginR, MarginV, Encoding',
    );
    buf.writeln(
      'Style: TJPro,${fontFamily ?? 'Arial'},$fontSize,'
      '${StudioCaptionStyles.assColor(style.textColor)},'
      '${StudioCaptionStyles.assColor(hl)},'
      '&H00000000,$back,${style.bold ? -1 : 0},0,0,0,100,100,0,0,'
      '$borderStyle,${useOutline ? 2 : 1},${useShadow ? 1 : 0},'
      '$alignment,10,10,$marginV,1',
    );
    if (dualLanguage) {
      buf.writeln(
        'Style: TJProDual,${fontFamily ?? 'Arial'},$dualFontSize,'
        '${StudioCaptionStyles.assColor(StudioCaptionStyles.white)},'
        '${StudioCaptionStyles.assColor(StudioCaptionStyles.white)},'
        '&H00000000,$back,${style.bold ? -1 : 0},0,0,0,100,100,0,0,'
        '$borderStyle,${useOutline ? 2 : 1},${useShadow ? 1 : 0},'
        '$alignment,10,10,$dualMarginV,1',
      );
    }
    buf.writeln();
    buf.writeln('[Events]');
    buf.writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
      'MarginV, Effect, Text',
    );
    for (final seg in segments) {
      if (seg.text.trim().isEmpty) continue;
      final words = StudioCaptionStyles.wordsOf(seg.text);
      if (words.isEmpty) continue;
      String show(String w) => style.uppercase ? w.toUpperCase() : w;
      switch (style.animation) {
        case CaptionAnimation.karaoke:
          final line = StringBuffer();
          for (var i = 0; i < words.length; i++) {
            final ws = wordStartOf(seg, i);
            final we = wordEndOf(seg, i);
            final cs = ((we - ws) * 100).round().clamp(1, 6000);
            line.write('{\\kf$cs}${escapeAss(show(words[i]))} ');
          }
          buf.writeln(
            'Dialogue: 0,${formatAssTime(seg.start)},'
            '${formatAssTime(seg.end)},TJPro,,0,0,0,,'
            '${line.toString().trimRight()}',
          );
        case CaptionAnimation.pop:
          for (var i = 0; i < words.length; i++) {
            final ws = wordStartOf(seg, i);
            final we = wordEndOf(seg, i);
            buf.writeln(
              'Dialogue: 0,${formatAssTime(ws)},${formatAssTime(we)},'
              'TJPro,,0,0,0,,${escapeAss(show(words[i]))}',
            );
          }
        case CaptionAnimation.typewriter:
          for (var i = 0; i < words.length; i++) {
            final ws = wordStartOf(seg, i);
            final we = i + 1 < words.length
                ? wordStartOf(seg, i + 1)
                : seg.end;
            final shown = words.sublist(0, i + 1).map(show).join(' ');
            buf.writeln(
              'Dialogue: 0,${formatAssTime(ws)},${formatAssTime(we)},'
              'TJPro,,0,0,0,,${escapeAss(shown)}',
            );
          }
        case CaptionAnimation.flash:
          buf.writeln(
            'Dialogue: 0,${formatAssTime(seg.start)},'
            '${formatAssTime(seg.end)},TJPro,,0,0,0,,'
            '${escapeAss(show(seg.text))}',
          );
      }
      if (dualLanguage && seg.translation.trim().isNotEmpty) {
        buf.writeln(
          'Dialogue: 0,${formatAssTime(seg.start)},'
          '${formatAssTime(seg.end)},TJProDual,,0,0,0,,'
          '${escapeAss(seg.translation)}',
        );
      }
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

