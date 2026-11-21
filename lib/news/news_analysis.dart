/// News analysis — pure Dart, zero quota (Phase 4).
///
/// The tehreer IS the transcript, so the One Click AI News Maker can
/// do its text steps with rules only — no Gemini call, no network:
///
///   1. Topic extraction — Urdu stopword removal + frequency +
///      proper-noun bonus (capitalised Latin words), per §13 of
///      DISCOVERY-AND-PLAN.md. Proper nouns in Urdu have no case, so
///      Urdu topics rank on frequency + early occurrence only.
///   2. Headline — extractive: the strongest first line, editable.
///   3. Summary — extractive: the first two lines, editable.
///   4. Subtitles — tehreer split into timed subtitle lines (BASIC
///      split now: word-count timing. Precise karaoke sync against
///      the real voiceover audio is Phase 5 — this file never claims
///      the timings are audio-synced.)
///
/// SEO helpers live here too (hashtag rules, caption builder, X cut):
/// hashtags are English/Roman ONLY — an Arabic-script tag is never
/// valid, and nothing here invents a tag. Suggestions come only from
/// the live trends endpoint (see lib/news/trends_service.dart); an
/// empty suggestion is correct, an invented one is a bug.
library;

/// Common Urdu function words — removed before topic extraction, so
/// only content words (places, people, actions) rank as topics.
const Set<String> urduStopwords = <String>{
  'کا',
  'کی',
  'کے',
  'میں',
  'نے',
  'سے',
  'کو',
  'ہے',
  'ہیں',
  'ہوں',
  'ہو',
  'تھا',
  'تھی',
  'تھے',
  'اور',
  'یا',
  'پر',
  'تک',
  'بھی',
  'یہ',
  'وہ',
  'جو',
  'جس',
  'اس',
  'ان',
  'ایک',
  'تو',
  'ہی',
  'نہ',
  'نہیں',
  'جب',
  'پھر',
  'اب',
  'آج',
  'کل',
  'کیا',
  'کیسے',
  'کہ',
  'بعد',
  'پہلے',
  'ساتھ',
  'بغیر',
  'طرف',
  'لیے',
  'پاس',
  'اندر',
  'باہر',
  'اوپر',
  'نیچے',
  'درمیان',
  'خلاف',
  'مطابق',
  'دوران',
  'قبل',
  'اگر',
  'مگر',
  'لیکن',
  'کیونکہ',
  'تاکہ',
  'جبکہ',
  'یعنی',
  'مثلا',
  'مثلاً',
  'وغیرہ',
  'صاحب',
  'جناب',
  'خبر',
  'خبریں',
};

/// Common English function words + generic news words that add no
/// topic signal.
const Set<String> englishStopwords = <String>{
  'the',
  'a',
  'an',
  'and',
  'or',
  'of',
  'to',
  'in',
  'on',
  'for',
  'with',
  'is',
  'are',
  'was',
  'were',
  'has',
  'have',
  'had',
  'by',
  'at',
  'from',
  'as',
  'it',
  'its',
  'this',
  'that',
  'these',
  'those',
  'he',
  'she',
  'they',
  'we',
  'you',
  'i',
  'not',
  'no',
  'but',
  'if',
  'then',
  'than',
  'so',
  'such',
  'more',
  'most',
  'news',
};

bool _isArabicScript(String token) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(token);

bool _isStopword(String token) {
  if (_isArabicScript(token)) return urduStopwords.contains(token);
  return englishStopwords.contains(token.toLowerCase());
}

/// Word count ("alfaz") — whitespace split, empty pieces dropped.
int countWords(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Splits [text] into sentences on `. ! ? ؟ ۔` and newlines. Empty
/// pieces are dropped; sentence terminators are kept out of the
/// returned strings (callers re-join with spaces).
List<String> splitSentences(String text) {
  final sentences = <String>[];
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if ('.!?؟۔\n'.contains(ch)) {
      final sentence = buffer.toString().trim();
      if (sentence.isNotEmpty) sentences.add(sentence);
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences;
}

/// Extracts up to [maxTopics] topic keywords from [text].
///
/// Rules-based only (zero quota): stopwords removed, tokens shorter
/// than 2 chars (Urdu) / 3 chars (Latin) dropped, pure numbers
/// dropped. Score = occurrences + 1 for a capitalised Latin token
/// (proper-noun bonus); ties break by first occurrence, so the story's
/// main place/person — usually named first — ranks first.
List<String> extractTopics(String text, {int maxTopics = 10}) {
  final tokens = text
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .toList();
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  final display = <String, String>{};
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (_isStopword(token)) continue;
    if (RegExp(r'^\d+$').hasMatch(token)) continue;
    final minLen = _isArabicScript(token) ? 2 : 3;
    if (token.length < minLen) continue;
    final key = _isArabicScript(token) ? token : token.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
    firstSeen.putIfAbsent(key, () => i);
    display.putIfAbsent(key, () => token);
    // Proper-noun bonus: a capitalised Latin word is probably a
    // name/place — count it once extra.
    if (!_isArabicScript(token) &&
        token[0] == token[0].toUpperCase() &&
        token[0] != token[0].toLowerCase()) {
      counts[key] = counts[key]! + 1;
    }
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  return ranked.take(maxTopics).map((k) => display[k]!).toList();
}

/// Extractive headline: the strongest first line (first sentence).
/// Longer than [maxChars] it is cut at the last space before the
/// limit, with '…'. Always editable by the user afterwards.
String extractHeadline(String text, {int maxChars = 100}) {
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return '';
  var headline = sentences.first.trim();
  if (headline.length <= maxChars) return headline;
  final cut = headline.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > maxChars ~/ 2) {
    headline = cut.substring(0, lastSpace);
  } else {
    headline = cut;
  }
  return '$headline…';
}

/// Extractive summary: the first [lines] sentences, joined with a
/// space. Editable by the user afterwards.
String extractSummary(String text, {int lines = 2}) {
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return '';
  return sentences.take(lines).join(' ');
}

/// One word with its spoken timing inside a subtitle line.
///
/// Filled by karaoke sync (Phase 5 — timings derived from the real
/// voiceover WAV duration, proportional to word length) or left empty
/// (callers then fall back to even-split timing). Serialised with the
/// line so a synced project stays synced after reload.
class SubtitleWord {
  SubtitleWord({
    required this.word,
    required this.startSec,
    required this.endSec,
  });

  final String word;
  final double startSec;
  final double endSec;

  Map<String, dynamic> toJson() => {
        'word': word,
        'startSec': startSec,
        'endSec': endSec,
      };

  static SubtitleWord fromJson(Map<String, dynamic> json) {
    return SubtitleWord(
      word: (json['word'] as String?) ?? '',
      startSec: (json['startSec'] as num?)?.toDouble() ?? 0,
      endSec: (json['endSec'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One subtitle line with its (estimated) timing.
class SubtitleLine {
  SubtitleLine({
    required this.text,
    required this.startSec,
    required this.endSec,
    List<SubtitleWord>? words,
    this.translation = '',
  }) : words = words ?? [];

  final String text;
  final double startSec;
  final double endSec;

  /// Per-word timings (karaoke sync, Phase 5). Empty = even-split
  /// fallback (Phase 4 estimate or a manually typed line).
  final List<SubtitleWord> words;

  /// Second-language line for dual captions (e.g. the English line
  /// under an Urdu line). Empty = no second line. Set by the
  /// translator or typed by hand in the Caption Studio.
  final String translation;

  Map<String, dynamic> toJson() => {
        'text': text,
        'startSec': startSec,
        'endSec': endSec,
        'words': words.map((w) => w.toJson()).toList(),
        'translation': translation,
      };

  static SubtitleLine fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'];
    final words = <SubtitleWord>[];
    if (rawWords is List) {
      for (final w in rawWords) {
        if (w is Map<String, dynamic>) {
          words.add(SubtitleWord.fromJson(w));
        }
      }
    }
    return SubtitleLine(
      text: (json['text'] as String?) ?? '',
      startSec: (json['startSec'] as num?)?.toDouble() ?? 0,
      endSec: (json['endSec'] as num?)?.toDouble() ?? 0,
      words: words,
      translation: (json['translation'] as String?) ?? '',
    );
  }
}

/// Splits the tehreer into timed subtitle lines — BASIC split only:
/// sentences are word-wrapped to [maxCharsPerLine] and each line's
/// duration is estimated from its word count at [wordsPerSecond]
/// (min 1s, max 8s). These timings are an estimate, NOT audio-synced:
/// once a voiceover exists, call [syncSubtitlesToVoiceover] (see
/// `lib/news/karaoke_sync.dart`) to re-time the same lines against
/// the real WAV duration.
List<SubtitleLine> splitSubtitles(
  String text, {
  int maxCharsPerLine = 42,
  double wordsPerSecond = 2.5,
}) {
  final lines = <String>[];
  for (final sentence in splitSentences(text)) {
    final words = sentence
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    var current = StringBuffer();
    for (final word in words) {
      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= maxCharsPerLine) {
        current.write(' $word');
      } else {
        lines.add(current.toString());
        current = StringBuffer(word);
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());
  }
  final result = <SubtitleLine>[];
  var t = 0.0;
  for (final line in lines) {
    final words = countWords(line);
    final duration =
        (words / wordsPerSecond).clamp(1.0, 8.0).toDouble();
    result.add(
      SubtitleLine(text: line, startSec: t, endSec: t + duration),
    );
    t += duration;
  }
  return result;
}

// ---------------------------------------------------------------------------
// SEO helpers (mockup 7 + §12).
// ---------------------------------------------------------------------------

/// A hashtag is valid only when it is English/Roman only: `#` +
/// Latin letters, digits or underscore. Urdu/Arabic script, spaces
/// and punctuation are all rejected — never suggest or accept them.
bool isRomanHashtag(String tag) =>
    RegExp(r'^#[A-Za-z0-9_]+$').hasMatch(tag.trim());

/// Problems with the hashtag list, as user-facing strings. Empty =
/// valid. 5–6 tags is the house rule (fewer/more is a warning, not a
/// rejection — the user may still save).
List<String> hashtagProblems(List<String> tags) {
  final problems = <String>[];
  for (final tag in tags) {
    final t = tag.trim();
    if (t.isEmpty) continue;
    if (!t.startsWith('#')) {
      problems.add('"$t" — # se shuru nahi hota');
    } else if (!isRomanHashtag(t)) {
      problems.add('"$t" — sirf English/Roman letters allowed');
    }
  }
  final nonEmpty = tags.where((t) => t.trim().isNotEmpty).length;
  if (nonEmpty < 5) {
    problems.add('Hashtags 5 se kam hain ($nonEmpty) — 5–6 likhein');
  } else if (nonEmpty > 6) {
    problems.add('Hashtags 6 se zyada hain ($nonEmpty) — 5–6 likhein');
  }
  return problems;
}

/// Builds the publish caption: hook title first, description,
/// hashtags, follow line last. No links ever — links live only in
/// the one comment (website + YouTube + WhatsApp channel).
String buildCaption({
  required String title,
  required String description,
  required List<String> hashtags,
  required String followLine,
}) {
  final parts = <String>[];
  if (title.trim().isNotEmpty) parts.add(title.trim());
  if (description.trim().isNotEmpty) parts.add(description.trim());
  final tags =
      hashtags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  if (tags.isNotEmpty) parts.add(tags.join(' '));
  if (followLine.trim().isNotEmpty) parts.add(followLine.trim());
  return parts.join('\n\n');
}

/// X gets a short cut: hook + at most 2 hashtags, hard-capped at
/// 280 chars (X rule — caption cut hogi, see mockup 6).
String xCaption({required String title, required List<String> hashtags}) {
  final tags =
      hashtags.map((t) => t.trim()).where((t) => t.isNotEmpty).take(2);
  var text = title.trim();
  if (tags.isNotEmpty) text = '$text ${tags.join(' ')}';
  if (text.length <= 280) return text;
  return '${text.substring(0, 277)}…';
}

/// Default follow line (last line of every caption).
const String defaultFollowLine =
    'Follow Nigraan TV for more breaking news';
