/// SCRIPT ALIGNER (Build 13, v1.10.0 — fix-list point #16).
///
/// The News Studio caption engine's timing brain. The problem it
/// solves (see NS-WHISPER-WIRING-AUDIT.md): the Whisper plugin
/// exposes NO word timestamps — only segments — BUT with
/// `splitOnWord: true` its native side sets whisper.cpp's
/// `max_len = 1`, so every returned segment is ONE word with REAL
/// spoken timings. The transcript TEXT of the tiny model on Urdu
/// is phonetic and unreliable, so the transcript is never shown:
/// the project's own script (tehreer / subtitle lines, user edits
/// included) stays authoritative, and this aligner only borrows
/// the TIMINGS — it maps each script word onto the best-matching
/// timed token with a monotonic (order-preserving) alignment,
/// then fills unmatched words proportionally inside their matched
/// neighbours (the karaoke_sync filler rule, applied between real
/// anchors instead of across the whole voiceover).
///
/// Pure Dart, no I/O — fully unit-testable. The algorithm was
/// prototyped on REAL Gemini Urdu voiceovers before wiring
/// (tool-tests/build13/proto/): match rate 78–79% of script
/// words, median boundary error 0.06–0.08 s against measured
/// speech onsets (the old whole-duration estimator: 0.24–0.65 s).
library;

/// One timed token from a word-split transcription: the raw
/// recognised word + its real start/end in seconds.
class AlignedToken {
  const AlignedToken({
    required this.text,
    required this.startSec,
    required this.endSec,
  });

  final String text;
  final double startSec;
  final double endSec;
}

/// One script word after alignment: its real (or filled) timing
/// and whether a transcript token actually matched it.
class AlignedScriptWord {
  const AlignedScriptWord({
    required this.word,
    required this.startSec,
    required this.endSec,
    required this.matched,
  });

  /// The SCRIPT's word (never the transcript's spelling).
  final String word;
  final double startSec;
  final double endSec;

  /// True when a real timed token matched this word; false when
  /// the timing was proportionally filled between anchors.
  final bool matched;
}

/// The outcome of one alignment run.
class ScriptAlignment {
  const ScriptAlignment({
    required this.words,
    required this.matchedCount,
  });

  final List<AlignedScriptWord> words;

  /// How many script words matched a real token.
  final int matchedCount;

  int get totalCount => words.length;

  /// matched / total — the honest quality signal the UI shows
  /// and the accept threshold checks.
  double get matchRate =>
      totalCount == 0 ? 0 : matchedCount / totalCount;
}

/// Minimum normalised similarity for a script word and a token
/// to count as the same word (prototype-tuned on real Urdu
/// voiceovers: the tiny model's phonetic spellings usually land
/// at 0.5–1.0 for the right word).
const double kAlignMatchMin = 0.45;

/// DP skip penalties: leaving a SCRIPT word unmatched costs more
/// than skipping a stray TOKEN (the transcript inserts junk
/// tokens more often than the script has unspoken words).
const double kAlignSkipScript = -0.35;
const double kAlignSkipToken = -0.20;

/// Accept threshold: below this match rate the aligned timings
/// are NOT trusted and callers keep the estimator timings
/// (honestly labelled). Prototype runs scored 0.78–0.79.
const double kAlignAcceptRate = 0.5;

class ScriptAligner {
  ScriptAligner._();

  static const Map<String, String> _fold = {
    'ي': 'ی', // Arabic yeh → Farsi yeh
    'ك': 'ک', // Arabic kaf → Farsi kaf
    'ة': 'ت', // teh marbuta → teh
    'ؤ': 'و', // waw hamza → waw
    'إ': 'ا', // alef hamza below → alef
    'أ': 'ا', // alef hamza above → alef
    'آ': 'ا', // alef madda → alef
  };

  // Diacritics (U+064B–U+065F), superscript alef (U+0670),
  // tatweel (U+0640), ZWNJ (U+200C), ZWJ (U+200D).
  static final RegExp _stripRe = RegExp(
    '[\\u064B-\\u065F\\u0670\\u0640\\u200C\\u200D]',
  );
  static final RegExp _punctRe = RegExp(
    r'[۔،؍؎؏؛؞؟!?,.;:"'
    r"'"
    r'«»()\[\]{}—–\-…/\\|@#%^&*+=<>~`]',
  );

  /// Normalises one word for COMPARISON only (the displayed
  /// word is never changed): punctuation and diacritics are
  /// stripped, Arabic letter variants fold to the Urdu forms,
  /// Arabic-Indic / Eastern-Arabic digits become ASCII, Latin
  /// folds to lowercase.
  static String normalizeWord(String word) {
    var w = word.replaceAll(_punctRe, '');
    w = w.replaceAll(_stripRe, '');
    final buf = StringBuffer();
    for (final rune in w.runes) {
      var ch = String.fromCharCode(rune);
      if (rune >= 0x660 && rune <= 0x669) {
        ch = String.fromCharCode(0x30 + (rune - 0x660));
      } else if (rune >= 0x6F0 && rune <= 0x6F9) {
        ch = String.fromCharCode(0x30 + (rune - 0x6F0));
      } else {
        ch = _fold[ch] ?? ch;
      }
      buf.write(ch);
    }
    return buf.toString().toLowerCase().trim();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    final la = a.length, lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;
    var prev = List<int>.generate(lb + 1, (j) => j);
    for (var i = 1; i <= la; i++) {
      final cur = List<int>.filled(lb + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var best = prev[j] + 1;
        if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
        if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
        cur[j] = best;
      }
      prev = cur;
    }
    return prev[lb];
  }

  /// Normalised similarity 0..1 (1 = identical after folding).
  static double similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - _levenshtein(a, b) / maxLen;
  }

  /// Aligns [scriptWords] (the authoritative text, in order)
  /// onto [tokens] (real timings, in order) and returns a timing
  /// for EVERY script word inside [durationSec]. Monotonic by
  /// construction: word starts never go backwards.
  static ScriptAlignment align({
    required List<String> scriptWords,
    required List<AlignedToken> tokens,
    required double durationSec,
  }) {
    final n = scriptWords.length;
    if (n == 0) {
      return const ScriptAlignment(words: [], matchedCount: 0);
    }
    final duration = durationSec > 0 ? durationSec : 0.0;
    final usable = tokens
        .where((t) => t.text.trim().isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty || duration <= 0) {
      // No timing evidence at all: proportional fill over the
      // whole duration (== the old estimator), matched = 0 so
      // the caller rejects it via the accept threshold.
      final filled = _fill(
        scriptWords,
        List<int>.generate(n, (i) => i),
        0,
        duration,
      );
      return ScriptAlignment(words: filled, matchedCount: 0);
    }

    final sn = scriptWords.map(normalizeWord).toList(growable: false);
    final tn = usable.map((t) => normalizeWord(t.text)).toList(growable: false);
    final m = usable.length;

    // Monotonic DP (Needleman–Wunsch with skip penalties).
    const neg = -1e9;
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    final bt = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      dp[i][0] = dp[i - 1][0] + kAlignSkipScript;
      bt[i][0] = 1; // skip script
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = dp[0][j - 1] + kAlignSkipToken;
      bt[0][j] = 2; // skip token
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final s = similarity(sn[i - 1], tn[j - 1]);
        final diag = dp[i - 1][j - 1] + (s >= kAlignMatchMin ? s : neg / 2);
        final up = dp[i - 1][j] + kAlignSkipScript;
        final left = dp[i][j - 1] + kAlignSkipToken;
        var best = diag;
        var step = 0;
        if (up > best) {
          best = up;
          step = 1;
        }
        if (left > best) {
          best = left;
          step = 2;
        }
        dp[i][j] = best;
        bt[i][j] = step;
      }
    }
    final pairs = <int, int>{};
    var i = n, j = m;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && bt[i][j] == 0) {
        pairs[i - 1] = j - 1;
        i--;
        j--;
      } else if (i > 0 && (j == 0 || bt[i][j] == 1)) {
        i--;
      } else {
        j--;
      }
    }

    // Timing assignment: matched words take their token's real
    // timing; unmatched runs fill proportionally (by normalised
    // character weight) between their anchors.
    final starts = List<double>.filled(n, 0);
    final ends = List<double>.filled(n, 0);
    final matched = List<bool>.filled(n, false);
    pairs.forEach((wi, ti) {
      starts[wi] = usable[ti].startSec;
      ends[wi] = usable[ti].endSec;
      matched[wi] = true;
    });

    void fillRun(int from, int to, double t0, double t1) {
      // Inclusive [from..to]; weights by normalised length.
      var total = 0.0;
      final weights = <double>[];
      for (var k = from; k <= to; k++) {
        final w = sn[k].isEmpty ? 1.0 : sn[k].length.toDouble();
        weights.add(w);
        total += w;
      }
      var t = t0;
      var idx = 0;
      for (var k = from; k <= to; k++) {
        final span = (t1 - t0) * weights[idx] / total;
        starts[k] = t;
        ends[k] = t + span;
        t += span;
        idx++;
      }
    }

    final anchors = pairs.keys.toList()..sort();
    if (anchors.isEmpty) {
      fillRun(0, n - 1, 0, duration);
    } else {
      if (anchors.first > 0) {
        fillRun(0, anchors.first - 1, 0, usable[pairs[anchors.first]!].startSec);
      }
      for (var a = 0; a + 1 < anchors.length; a++) {
        final lo = anchors[a], hi = anchors[a + 1];
        if (hi - lo > 1) {
          fillRun(lo + 1, hi - 1, usable[pairs[lo]!].endSec,
              usable[pairs[hi]!].startSec);
        }
      }
      if (anchors.last < n - 1) {
        fillRun(anchors.last + 1, n - 1, usable[pairs[anchors.last]!].endSec,
            duration);
      }
    }

    // Final safety: clamp into [0, duration] and enforce a
    // non-decreasing start order (token timings from the engine
    // are already ordered; this guards pathological inputs).
    final words = <AlignedScriptWord>[];
    var prevStart = 0.0;
    for (var k = 0; k < n; k++) {
      var s = starts[k].clamp(0.0, duration).toDouble();
      if (s < prevStart) s = prevStart;
      var e = ends[k].clamp(s, duration).toDouble();
      if (e < s) e = s;
      words.add(AlignedScriptWord(
        word: scriptWords[k],
        startSec: s,
        endSec: e,
        matched: matched[k],
      ));
      prevStart = s;
    }
    return ScriptAlignment(words: words, matchedCount: pairs.length);
  }

  static List<AlignedScriptWord> _fill(
    List<String> scriptWords,
    List<int> idxs,
    double t0,
    double t1,
  ) {
    final norm = scriptWords.map(normalizeWord).toList(growable: false);
    var total = 0.0;
    for (final k in idxs) {
      total += norm[k].isEmpty ? 1.0 : norm[k].length.toDouble();
    }
    final out = <AlignedScriptWord>[];
    var t = t0;
    for (final k in idxs) {
      final w = norm[k].isEmpty ? 1.0 : norm[k].length.toDouble();
      final span = total <= 0 ? 0.0 : (t1 - t0) * w / total;
      out.add(AlignedScriptWord(
        word: scriptWords[k],
        startSec: t,
        endSec: t + span,
        matched: false,
      ));
      t += span;
    }
    return out;
  }
}
