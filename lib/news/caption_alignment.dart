/// CAPTION ALIGNMENT ORCHESTRATION (Build 13, v1.10.0 — point #16).
///
/// The "Asal timings" action shared by the News Maker's Captions
/// panel and the Caption Studio: transcribe the project's
/// voiceover with word-split Whisper (real per-word timings),
/// align the project's OWN subtitle words onto those timings
/// (script_aligner.dart — the script stays authoritative), and,
/// when the match rate clears the accept threshold, write the
/// real timings back into the project and stamp its timing
/// source. When anything fails or the match is too weak, the
/// project is left untouched and the outcome says so honestly —
/// the estimator timings stay, labelled as estimates.
library;

import 'dart:io';

import '../services/caption_service.dart';
import 'karaoke_sync.dart';
import 'news_project.dart';
import 'script_aligner.dart';

/// The result of one "Asal timings" run.
class CaptionAlignmentOutcome {
  const CaptionAlignmentOutcome({
    required this.applied,
    required this.message,
    this.matchRate = 0,
    this.matchedWords = 0,
    this.totalWords = 0,
  });

  /// True when real timings were written into the project.
  final bool applied;

  /// User-facing Roman-Urdu result line (honest either way).
  final String message;

  final double matchRate;
  final int matchedWords;
  final int totalWords;
}

/// The flat script the aligner works on: the subtitle lines' own
/// words, in order (a line's timed words when it has them, else
/// its text split on whitespace). Building the script FROM the
/// lines is what keeps user edits authoritative.
List<String> captionScriptWordsOf(NewsProject project) {
  final out = <String>[];
  for (final line in project.subtitles) {
    if (line.words.isNotEmpty) {
      out.addAll(line.words.map((w) => w.word));
    } else {
      out.addAll(
        line.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
      );
    }
  }
  return out;
}

/// Runs the full alignment for [project] (mutates it ONLY on
/// success). [workDir] hosts the extracted 16 kHz WAV.
Future<CaptionAlignmentOutcome> alignProjectCaptionsToVoiceover(
  NewsProject project, {
  required Directory workDir,
}) async {
  final voiceoverPath = project.voiceoverPath;
  if (voiceoverPath == null || voiceoverPath.isEmpty) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Create the voiceover first — the real timings come from it.',
    );
  }
  if (!File(voiceoverPath).existsSync()) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Voiceover file not found — create the voiceover again.',
    );
  }
  final duration = project.voiceoverDurationSec;
  if (duration == null || duration <= 0) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Voiceover length is unknown — Sync first.',
    );
  }
  if (project.subtitles.isEmpty) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Create subtitles first (from the script).',
    );
  }
  final scriptWords = captionScriptWordsOf(project);
  if (scriptWords.isEmpty) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Subtitle lines are empty — write the text first.',
    );
  }
  // Same language rule as the Caption Studio's tehreerLangOf.
  final lang =
      RegExp(r'[\u0600-\u06FF]').hasMatch(project.tehreer) ? 'ur' : 'en';
  final List<CaptionWord> timed;
  try {
    timed = await FileCaptionEngine.transcribeWords(
      audioPath: voiceoverPath,
      workDir: workDir,
      lang: lang,
    );
  } catch (e) {
    return CaptionAlignmentOutcome(
      applied: false,
      message: 'Whisper transcription failed: $e',
    );
  }
  if (timed.isEmpty) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message:
          'No word timing was found from Whisper — the estimate timings will remain.',
    );
  }
  final alignment = ScriptAligner.align(
    scriptWords: scriptWords,
    tokens: [
      for (final w in timed)
        AlignedToken(text: w.word, startSec: w.start, endSec: w.end),
    ],
    durationSec: duration,
  );
  if (alignment.matchRate < kAlignAcceptRate) {
    return CaptionAlignmentOutcome(
      applied: false,
      message:
          'The match is weak (${(alignment.matchRate * 100).round()}% words found) '
          '— the estimate timings will remain. If the voiceover is clear, try again.',
      matchRate: alignment.matchRate,
      matchedWords: alignment.matchedCount,
      totalWords: alignment.totalCount,
    );
  }
  final retimed = resyncWithAlignedTimings(
    project.subtitles,
    alignment.words,
    duration,
  );
  if (retimed.isEmpty) {
    return const CaptionAlignmentOutcome(
      applied: false,
      message: 'Timings could not be applied — the old timings are safe.',
    );
  }
  project.subtitles = retimed;
  project.captionTimingSource = 'whisper';
  project.captionAlignedHash = project.captionTimingFingerprint;
  return CaptionAlignmentOutcome(
    applied: true,
    message:
        'Real timings applied — ${alignment.matchedCount}/${alignment.totalCount} '
        'words at Whisper\'s real timing (${(alignment.matchRate * 100).round()}% match).',
    matchRate: alignment.matchRate,
    matchedWords: alignment.matchedCount,
    totalWords: alignment.totalCount,
  );
}
