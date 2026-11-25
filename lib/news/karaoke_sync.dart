/// Karaoke sync — precise subtitle timing against the REAL voiceover
/// WAV (Phase 5).
///
/// Phase 4's `splitSubtitles` (see `lib/news/news_analysis.dart`)
/// estimated each line's duration from its word count at 2.5
/// words/second — a guess that drifts from the voice actually
/// spoken. This file replaces the guess once a voiceover exists:
///
///   - The lines are the same word-wrapped lines as `splitSubtitles`
///     (same `maxCharsPerLine`), so an edit to the tehreer re-syncs
///     to the same lines.
///   - The TOTAL duration is the voiceover WAV's real duration
///     ([wavDurationSeconds] in `lib/news/news_project.dart`) — the
///     lines together span exactly that long, no more, no less.
///   - Each line's share of the total is proportional to its
///     character count (speech runs at roughly constant chars/second,
///     and chars track spoken length better than word count for Urdu,
///     where one word can be very long). A 0.6s floor per line keeps
///     very short lines readable when the total allows it.
///   - Each word's timing inside its line is proportional to its
///     character length (longer words take longer to say) — strictly
///     better than the even split, and exact at line boundaries.
///   - Lines are contiguous, monotonic and non-overlapping; the last
///     line ends exactly at the voiceover duration (float drift is
///     absorbed there, never spread).
///
/// This is line-level + word-level timing derived from the ACTUAL
/// audio length. On its own it is NOT per-word Whisper alignment —
/// the honest statement for estimator output is "timings derived
/// from the real WAV duration", and the screens say exactly that.
/// Build 13 (point #16) adds the REAL path alongside it: the
/// voiceover is transcribed with word-split Whisper and the
/// script is aligned onto those real timings by
/// `script_aligner.dart` — see [resyncWithAlignedTimings] below
/// and `caption_alignment.dart` for the orchestration. The
/// project records which path produced its timings
/// (NewsProject.captionTimingSource) and the UI labels them
/// accordingly.
library;

import 'news_analysis.dart';
import 'script_aligner.dart';

/// Minimum readable duration of one subtitle line, when the total
/// voiceover length allows every line to have it.
const double karaokeMinLineSeconds = 0.6;

/// Splits [text] into subtitle lines synced to a voiceover of
/// [voiceoverDurationSec] seconds (the real WAV duration).
///
/// Returns [] when the text is empty or the duration is not positive
/// (callers then keep the Phase 4 estimate instead of showing
/// nothing). Every returned line carries per-word timings
/// ([SubtitleLine.words]) and an empty `translation` (dual-language
/// text is the user's own input, added in the Caption Studio).
List<SubtitleLine> syncSubtitlesToVoiceover(
  String text,
  double voiceoverDurationSec, {
  int maxCharsPerLine = 42,
}) {
  if (text.trim().isEmpty || voiceoverDurationSec <= 0) return [];
  // Same wrapping as splitSubtitles, so the lines match.
  final estimated = splitSubtitles(text, maxCharsPerLine: maxCharsPerLine);
  if (estimated.isEmpty) return [];
  return _retimeLines(
    estimated.map((l) => l.text).toList(),
    estimated.map((l) => l.translation).toList(),
    voiceoverDurationSec,
  );
}

/// Re-times already-existing lines (e.g. the user edited a line's
/// text in the AI News Maker) to a voiceover of
/// [voiceoverDurationSec] seconds, keeping each line's `translation`
/// and re-deriving its word timings from the new text. Lines keep
/// their order; empty lines are dropped.
List<SubtitleLine> resyncExistingLines(
  List<SubtitleLine> lines,
  double voiceoverDurationSec,
) {
  final texts = <String>[];
  final translations = <String>[];
  for (final line in lines) {
    if (line.text.trim().isEmpty) continue;
    texts.add(line.text);
    translations.add(line.translation);
  }
  if (texts.isEmpty || voiceoverDurationSec <= 0) return [];
  return _retimeLines(texts, translations, voiceoverDurationSec);
}

/// Core allocation: [texts] share [totalSeconds] proportionally to
/// their character counts, with the per-line floor when affordable,
/// and per-word timings proportional to word length inside each line.
List<SubtitleLine> _retimeLines(
  List<String> texts,
  List<String> translations,
  double totalSeconds,
) {
  final weights = texts.map((t) => t.trim().length.clamp(1, 1 << 20)).toList();
  final totalWeight = weights.fold<int>(0, (a, b) => a + b);
  var durations = List<double>.generate(
    texts.length,
    (i) => totalSeconds * weights[i] / totalWeight,
  );
  // Floor: every line gets at least 0.6s when the total allows it,
  // paid for out of the lines above the floor (proportional to their
  // surplus), so the total stays exact.
  final floorTotal = karaokeMinLineSeconds * texts.length;
  if (totalSeconds >= floorTotal) {
    var deficit = 0.0;
    for (var i = 0; i < durations.length; i++) {
      if (durations[i] < karaokeMinLineSeconds) {
        deficit += karaokeMinLineSeconds - durations[i];
        durations[i] = karaokeMinLineSeconds;
      }
    }
    if (deficit > 0) {
      var surplus = 0.0;
      for (final d in durations) {
        if (d > karaokeMinLineSeconds) surplus += d - karaokeMinLineSeconds;
      }
      if (surplus > 0) {
        for (var i = 0; i < durations.length; i++) {
          if (durations[i] > karaokeMinLineSeconds) {
            durations[i] -=
                deficit * (durations[i] - karaokeMinLineSeconds) / surplus;
          }
        }
      }
    }
  }
  final out = <SubtitleLine>[];
  var t = 0.0;
  for (var i = 0; i < texts.length; i++) {
    final start = t;
    var end = t + durations[i];
    // Last line ends exactly at the voiceover duration (absorbs any
    // float drift from the proportional split).
    if (i == texts.length - 1) end = totalSeconds;
    if (end <= start) end = start + 0.1;
    out.add(
      SubtitleLine(
        text: texts[i],
        startSec: start,
        endSec: end,
        words: _wordTimings(texts[i], start, end),
        translation: i < translations.length ? translations[i] : '',
      ),
    );
    t = end;
  }
  return out;
}

/// Per-word timings inside one line: each word's share of the line
/// is proportional to its character length (a long Urdu word takes
/// longer to say than a short one). Words are contiguous and exactly
/// fill the line window.
List<SubtitleWord> _wordTimings(String text, double start, double end) {
  final words = text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return [];
  final weights = words.map((w) => w.length.clamp(1, 1 << 20)).toList();
  final totalWeight = weights.fold<int>(0, (a, b) => a + b);
  final duration = end - start;
  final out = <SubtitleWord>[];
  var t = start;
  for (var i = 0; i < words.length; i++) {
    final wordEnd =
        i == words.length - 1 ? end : t + duration * weights[i] / totalWeight;
    out.add(SubtitleWord(word: words[i], startSec: t, endSec: wordEnd));
    t = wordEnd;
  }
  return out;
}

/// Index of the word being spoken in [line] at [positionSeconds],
/// using the line's real word timings when present, even-split
/// otherwise. -1 when the position is outside the line or the line
/// has no words.
int activeWordIndexInLine(SubtitleLine line, double positionSeconds) {
  if (line.words.isNotEmpty) {
    for (var i = 0; i < line.words.length; i++) {
      if (positionSeconds >= line.words[i].startSec &&
          positionSeconds < line.words[i].endSec) {
        return i;
      }
    }
    if (positionSeconds < line.startSec) return -1;
    if (positionSeconds >= line.endSec) return line.words.length - 1;
    return -1;
  }
  final words = line.text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return -1;
  if (positionSeconds < line.startSec) return -1;
  final dur = line.endSec - line.startSec;
  if (dur <= 0) return 0;
  var i = ((positionSeconds - line.startSec) / (dur / words.length)).floor();
  if (i < 0) i = 0;
  if (i >= words.length) i = words.length - 1;
  return i;
}

/// Index of the subtitle line live at [positionSeconds], or -1 when
/// no line covers that moment.
int subtitleLineAt(List<SubtitleLine> lines, double positionSeconds) {
  for (var i = 0; i < lines.length; i++) {
    if (positionSeconds >= lines[i].startSec &&
        positionSeconds < lines[i].endSec) {
      return i;
    }
  }
  return -1;
}

/// Build 13 (point #16): re-times EXISTING lines from REAL aligned
/// word timings. [aligned] is the flat result of
/// [ScriptAligner.align] over the lines' own words, in the same
/// order (the caller builds the flat script from these very lines,
/// so the script — user edits included — stays authoritative and
/// only timings change). Line boundaries follow the first/last
/// word of each line; translations and texts are preserved
/// verbatim. Returns [] when the inputs disagree in word count
/// (the caller then keeps the old timings rather than guessing).
List<SubtitleLine> resyncWithAlignedTimings(
  List<SubtitleLine> lines,
  List<AlignedScriptWord> aligned,
  double totalDurationSec,
) {
  if (lines.isEmpty || totalDurationSec <= 0) return [];
  final counts = <int>[];
  var total = 0;
  for (final line in lines) {
    final words = line.words.isNotEmpty
        ? line.words.map((w) => w.word).toList()
        : line.text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    counts.add(words.length);
    total += words.length;
  }
  if (total != aligned.length) return [];
  final out = <SubtitleLine>[];
  var cursor = 0;
  var prevEnd = 0.0;
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final count = counts[li];
    if (count == 0) {
      out.add(SubtitleLine(
        text: line.text,
        startSec: prevEnd,
        endSec: prevEnd,
        translation: line.translation,
      ));
      continue;
    }
    final slice = aligned.sublist(cursor, cursor + count);
    cursor += count;
    var start = slice.first.startSec;
    if (start < prevEnd) start = prevEnd;
    var end = slice.last.endSec;
    if (end <= start) end = start + 0.1;
    if (end > totalDurationSec) end = totalDurationSec;
    if (start > end) start = end;
    out.add(SubtitleLine(
      text: line.text,
      startSec: start,
      endSec: end,
      words: [
        for (final w in slice)
          SubtitleWord(word: w.word, startSec: w.startSec, endSec: w.endSec),
      ],
      translation: line.translation,
    ));
    prevEnd = end;
  }
  return out;
}
