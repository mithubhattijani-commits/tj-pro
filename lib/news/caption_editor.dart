/// Caption line editing — pure Dart (Phase 5, ported from Magic
/// Box's caption screens: `_editSegment`, `_splitSelected`,
/// `_mergeSelected`, `_shiftAll`, `_nudgeSelected`, `_addManualLine`,
/// `_pushUndo`/`_undo`/`_redo`).
///
/// Operates on [SubtitleLine]s (see `lib/news/news_analysis.dart`).
/// Every mutation snapshots the list first, so undo/redo are full
/// list restores. Lines are treated as immutable values: an edit
/// replaces the line object, never mutates it in place.
///
/// Word timings: editing a line's text invalidates its per-word
/// timings (they were derived from the old text), so edited / split /
/// merged lines lose their `words` and fall back to even-split timing
/// until the project is re-synced against its voiceover
/// (`resyncExistingLines` in `lib/news/karaoke_sync.dart`).
/// Translations survive edits (they are the user's own second line).
library;

import 'news_analysis.dart';

List<SubtitleLine> copyCaptionLines(List<SubtitleLine> lines) =>
    lines
        .map(
          (l) => SubtitleLine(
            text: l.text,
            startSec: l.startSec,
            endSec: l.endSec,
            words: List<SubtitleWord>.from(l.words),
            translation: l.translation,
          ),
        )
        .toList();

/// Mutable editor over a caption line list, with undo/redo.
class CaptionEditor {
  CaptionEditor(List<SubtitleLine> initial)
      : _lines = copyCaptionLines(initial);

  List<SubtitleLine> _lines;
  final List<List<SubtitleLine>> _undoStack = [];
  final List<List<SubtitleLine>> _redoStack = [];

  List<SubtitleLine> get lines => List<SubtitleLine>.unmodifiable(_lines);
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushUndo() {
    _undoStack.add(copyCaptionLines(_lines));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Takes one undo snapshot WITHOUT changing anything — the screen
  /// calls this once when the user starts typing in a line field, so
  /// a whole typing session is ONE undo step instead of one per
  /// keystroke.
  void beginEdit() => _pushUndo();

  /// Replaces line [index]'s text without taking an undo snapshot
  /// (pair with [beginEdit]). Same rules as [editLine].
  bool setLineText(int index, String newText) {
    if (index < 0 || index >= _lines.length) return false;
    if (newText.trim().isEmpty) return false;
    final old = _lines[index];
    _lines[index] = SubtitleLine(
      text: newText.trim(),
      startSec: old.startSec,
      endSec: old.endSec,
      translation: old.translation,
    );
    return true;
  }

  /// Sets the second-language line without an undo snapshot (pair
  /// with [beginEdit]).
  bool setTranslationText(int index, String translation) {
    if (index < 0 || index >= _lines.length) return false;
    final old = _lines[index];
    _lines[index] = SubtitleLine(
      text: old.text,
      startSec: old.startSec,
      endSec: old.endSec,
      words: List<SubtitleWord>.from(old.words),
      translation: translation.trim(),
    );
    return true;
  }

  bool undo() {
    if (!canUndo) return false;
    _redoStack.add(copyCaptionLines(_lines));
    _lines = _undoStack.removeLast();
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _undoStack.add(copyCaptionLines(_lines));
    _lines = _redoStack.removeLast();
    return true;
  }

  /// Replaces line [index]'s text (same time window). Word timings
  /// are dropped (see the file header); the translation is kept.
  /// Returns false when the index or the new text is invalid.
  bool editLine(int index, String newText) {
    if (index < 0 || index >= _lines.length) return false;
    if (newText.trim().isEmpty) return false;
    _pushUndo();
    final old = _lines[index];
    _lines[index] = SubtitleLine(
      text: newText.trim(),
      startSec: old.startSec,
      endSec: old.endSec,
      translation: old.translation,
    );
    return true;
  }

  /// Sets the second-language line of [index] (empty clears it).
  bool setTranslation(int index, String translation) {
    if (index < 0 || index >= _lines.length) return false;
    _pushUndo();
    final old = _lines[index];
    _lines[index] = SubtitleLine(
      text: old.text,
      startSec: old.startSec,
      endSec: old.endSec,
      words: List<SubtitleWord>.from(old.words),
      translation: translation.trim(),
    );
    return true;
  }

  /// Deletes line [index]. Returns false when the index is invalid.
  bool deleteLine(int index) {
    if (index < 0 || index >= _lines.length) return false;
    _pushUndo();
    _lines.removeAt(index);
    return true;
  }

  /// Adds a hand-typed line after [afterIndex] (or at the end when
  /// null). The new line starts at the previous line's end (or 0)
  /// and lasts [durationSec]. No word timings (even-split fallback).
  bool addManualLine(
    String text, {
    int? afterIndex,
    double durationSec = 2.0,
  }) {
    if (text.trim().isEmpty) return false;
    _pushUndo();
    final start = afterIndex == null
        ? (_lines.isEmpty ? 0.0 : _lines.last.endSec)
        : (_lines[afterIndex].endSec);
    final insertAt = afterIndex == null ? _lines.length : afterIndex + 1;
    _lines.insert(
      insertAt,
      SubtitleLine(
        text: text.trim(),
        startSec: start,
        endSec: start + durationSec.clamp(0.5, 30.0),
      ),
    );
    return true;
  }

  /// Splits line [index] after word [wordIndex] (0-based: words
  /// 0..wordIndex stay in the first half). The time window splits
  /// proportionally to the halves' character counts. Word timings
  /// are dropped on both halves. Returns false on a bad index or
  /// when the line has fewer than 2 words.
  bool splitLine(int index, int wordIndex) {
    if (index < 0 || index >= _lines.length) return false;
    final line = _lines[index];
    final words = line.text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 2 || wordIndex < 0 || wordIndex >= words.length - 1) {
      return false;
    }
    final first = words.sublist(0, wordIndex + 1).join(' ');
    final second = words.sublist(wordIndex + 1).join(' ');
    final totalChars = first.length + second.length;
    final duration = line.endSec - line.startSec;
    final splitAt =
        line.startSec + duration * (first.length / totalChars);
    _pushUndo();
    _lines[index] = SubtitleLine(
      text: first,
      startSec: line.startSec,
      endSec: splitAt,
      translation: line.translation,
    );
    _lines.insert(
      index + 1,
      SubtitleLine(text: second, startSec: splitAt, endSec: line.endSec),
    );
    return true;
  }

  /// Merges line [index] with the next line (texts joined with a
  /// space, window spans both). The first line's translation is kept.
  /// Returns false when there is no next line.
  bool mergeWithNext(int index) {
    if (index < 0 || index >= _lines.length - 1) return false;
    _pushUndo();
    final first = _lines[index];
    final second = _lines[index + 1];
    _lines[index] = SubtitleLine(
      text: '${first.text} ${second.text}'.trim(),
      startSec: first.startSec,
      endSec: second.endSec,
      translation: first.translation,
    );
    _lines.removeAt(index + 1);
    return true;
  }

  /// Shifts ALL lines by [deltaSeconds] (+0.5 / -0.5 in the UI).
  /// The first line never starts before 0 — a negative shift is
  /// clamped so the earliest line starts at 0.
  void shiftAll(double deltaSeconds) {
    if (_lines.isEmpty || deltaSeconds == 0) return;
    final minStart =
        _lines.map((l) => l.startSec).reduce((a, b) => a < b ? a : b);
    final shift = (minStart + deltaSeconds) < 0 ? -minStart : deltaSeconds;
    if (shift == 0) return;
    _pushUndo();
    _lines = _lines
        .map(
          (l) => SubtitleLine(
            text: l.text,
            startSec: l.startSec + shift,
            endSec: l.endSec + shift,
            words: l.words
                .map(
                  (w) => SubtitleWord(
                    word: w.word,
                    startSec: w.startSec + shift,
                    endSec: w.endSec + shift,
                  ),
                )
                .toList(),
            translation: l.translation,
          ),
        )
        .toList();
  }

  /// Nudges one line by [deltaSeconds] (same clamping as [shiftAll]
  /// for that line only). Adjacent lines are NOT moved — the caller
  /// sees overlaps in the list and can fix them with shift/split.
  bool nudgeLine(int index, double deltaSeconds) {
    if (index < 0 || index >= _lines.length || deltaSeconds == 0) {
      return false;
    }
    final line = _lines[index];
    final shift =
        (line.startSec + deltaSeconds) < 0 ? -line.startSec : deltaSeconds;
    if (shift == 0) return false;
    _pushUndo();
    _lines[index] = SubtitleLine(
      text: line.text,
      startSec: line.startSec + shift,
      endSec: line.endSec + shift,
      words: line.words
          .map(
            (w) => SubtitleWord(
              word: w.word,
              startSec: w.startSec + shift,
              endSec: w.endSec + shift,
            ),
          )
          .toList(),
      translation: line.translation,
    );
    return true;
  }
}
