// Build 2 (Master Plan Phase 1 + 2): pure stage geometry, timeline
// math and the stage guide painter for the Video Editor.
//
// Everything in this file is side-effect free and unit-tested
// (test/build2_stage_timeline_test.dart). The editor's State keeps
// the widgets and the gestures; the NUMBERS live here so the
// canvas/timeline behaviour can be pinned by tests — the Phase 2
// rule for the #5/#29/#30 sync family: tests first, changes after.
//
// Nothing here removes or alters any existing behaviour by itself:
// the State delegates to these helpers only where the old inline
// math did exactly the same thing (timeline totals/starts), or
// where Phase 1/2 explicitly adds the new behaviour (canvas frame,
// snapping).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import '../../services/font_registry.dart';
import '../../services/fx_pack.dart';
import '../../services/pro_editor.dart';
import '../../theme.dart';
import '../editor_models.dart';
import '../video_editor_controller.dart';

/// Geometry of the interactive canvas (Phase 1): the canvas frame
/// is the stage's centre of truth — the chosen Canvas ratio made
/// real on screen. The media is contain-fitted inside the frame
/// (never stretched), and every stage tap maps through the frame's
/// actual rects instead of the old fixed-16:9 approximation.
class CanvasGeometry {
  CanvasGeometry._();

  /// Canvas ratio (width / height) for a Canvas-panel key.
  /// 'Original' (and any unknown key) keeps the media's own ratio;
  /// a broken media ratio falls back to 16:9 rather than dividing
  /// by zero downstream.
  static double ratioFor(String aspectKey, double mediaAspect) {
    switch (aspectKey) {
      case '9:16':
        return 9 / 16;
      case '16:9':
        return 16 / 9;
      case '1:1':
        return 1;
      case '4:5':
        return 4 / 5;
      default:
        return (mediaAspect.isFinite && mediaAspect > 0)
            ? mediaAspect
            : 16 / 9;
    }
  }

  /// The largest rect of [ratio] (width / height) centred inside
  /// [stage]. A degenerate stage or ratio yields [Rect.zero].
  static Rect frameRect(Size stage, double ratio) {
    if (stage.width <= 0 || stage.height <= 0 || ratio <= 0) {
      return Rect.zero;
    }
    var w = stage.width;
    var h = w / ratio;
    if (h > stage.height) {
      h = stage.height;
      w = h * ratio;
    }
    return Rect.fromLTWH(
      (stage.width - w) / 2,
      (stage.height - h) / 2,
      w,
      h,
    );
  }

  /// Contain fit: the largest rect of [mediaAspect] inside [frame],
  /// centred — the whole media visible, letterboxed, NEVER
  /// stretched (Phase 1's core promise, PRO-SPEC point 11).
  static Rect containRect(Rect frame, double mediaAspect) {
    if (frame.width <= 0 || frame.height <= 0 || mediaAspect <= 0) {
      return frame;
    }
    var w = frame.width;
    var h = w / mediaAspect;
    if (h > frame.height) {
      h = frame.height;
      w = h * mediaAspect;
    }
    return Rect.fromLTWH(
      frame.left + (frame.width - w) / 2,
      frame.top + (frame.height - h) / 2,
      w,
      h,
    );
  }

  /// Cover fit: the smallest rect of [mediaAspect] that covers
  /// [frame], centred (overflow cropped by the frame's clip).
  static Rect coverRect(Rect frame, double mediaAspect) {
    if (frame.width <= 0 || frame.height <= 0 || mediaAspect <= 0) {
      return frame;
    }
    var w = frame.width;
    var h = w / mediaAspect;
    if (h < frame.height) {
      h = frame.height;
      w = h * mediaAspect;
    }
    return Rect.fromLTWH(
      frame.left + (frame.width - w) / 2,
      frame.top + (frame.height - h) / 2,
      w,
      h,
    );
  }

  /// Map [point] (in the same coordinate space as [rect]) to
  /// rect-normalized 0..1 coordinates; null when the point falls
  /// outside [rect] — a letterbox tap is NOT a media point.
  static Offset? normalizedIn(Rect rect, Offset point) {
    if (rect.width <= 0 || rect.height <= 0) return null;
    final x = (point.dx - rect.left) / rect.width;
    final y = (point.dy - rect.top) / rect.height;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return Offset(x, y);
  }

  /// Same mapping as [normalizedIn] but clamped into the rect —
  /// edge taps count as edge points instead of being dropped.
  static Offset normalizedClamped(Rect rect, Offset point) {
    if (rect.width <= 0 || rect.height <= 0) return Offset.zero;
    return Offset(
      ((point.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((point.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }
}

/// The ONE timeline model's pure math (Phase 2). The State's
/// `_totalDurationSec` / `_clipStartSec` / seek-index logic delegate
/// here so the #5/#29/#30 invariants (one total, starts are prefix
/// sums, seek lands in the containing clip) are unit-testable
/// without a platform video player.
class TimelineMath {
  TimelineMath._();

  // ---- Strip geometry (v1.15.0 G1 — the 26px Split bug). ----
  /// Width of the timeline strip's fixed left column (the lane
  /// label / + tile column). The scrollable strip viewport is the
  /// bar's width minus this.
  static const double stripLeftColumnWidth = 52;

  /// Leading content padding inside the strip. It MUST be exactly
  /// half the strip viewport: the fixed centre playhead line stands
  /// at [stripLineX], so with halfPad == lineX the time under the
  /// line is exactly `scrollOffset / pxPerSec` at every zoom.
  /// (The pre-v1.15 formula `maxWidth/2 - 52` was 26px short, so
  /// every centre-based action — Split above all — landed early.)
  static double stripHalfPad(double barWidth) =>
      (barWidth - stripLeftColumnWidth) / 2;

  /// X of the fixed centre playhead line, measured from the strip
  /// viewport's left edge (i.e. inside the Expanded next to the
  /// left column).
  static double stripLineX(double barWidth) =>
      (barWidth - stripLeftColumnWidth) / 2;

  /// Content X (inside the scrollable content) where [sec] is
  /// drawn at [pps] px/sec.
  static double stripContentX(double barWidth, double sec, double pps) =>
      stripHalfPad(barWidth) + sec * pps;

  /// Total timeline length: the sum of every clip's effective
  /// (trimmed) duration, in order.
  static double totalSec(List<double> durations) =>
      durations.fold(0.0, (sum, d) => sum + d);

  /// Timeline position (seconds) where clip [index] starts — the
  /// prefix sum of the durations before it. Out-of-range indices
  /// clamp to the ends.
  static double startSec(List<double> durations, int index) {
    var start = 0.0;
    final upto = math.min(index, durations.length);
    for (var j = 0; j < upto; j++) {
      start += durations[j];
    }
    return start;
  }

  /// The clip containing timeline position [sec]: the first clip
  /// whose end is past [sec], or the last clip when [sec] runs to
  /// the very end (the seek loop's long-standing semantics).
  /// Returns -1 for an empty timeline.
  static int indexAtSec(List<double> durations, double sec) {
    if (durations.isEmpty) return -1;
    var acc = 0.0;
    for (var i = 0; i < durations.length; i++) {
      if (sec < acc + durations[i] || i == durations.length - 1) {
        return i;
      }
      acc += durations[i];
    }
    return durations.length - 1;
  }

  /// Clip boundary times (every clip start + the total) — the
  /// snap points for scrubbing.
  static List<double> boundaries(List<double> durations) {
    final pts = <double>[0];
    var acc = 0.0;
    for (final d in durations) {
      acc += d;
      pts.add(acc);
    }
    return pts;
  }

  /// Snap [value] to the nearest of [points] when it is within
  /// [threshold]; otherwise return [value] unchanged.
  /// Build 4 player fix: a timeline ScrollEnd may only turn into
  /// a scrub-seek when the user actually scrubbed — never while
  /// the player is playing (the strip is following it) and never
  /// for a programmatic jumpTo's manufactured notifications.
  static bool scrubSeekOnScrollEnd({
    required bool isPlaying,
    required bool programmaticScroll,
  }) => !isPlaying && !programmaticScroll;

  static double snapSec(
    double value,
    List<double> points,
    double threshold,
  ) {
    var best = value;
    var bestDist = threshold;
    for (final p in points) {
      final dist = (p - value).abs();
      if (dist <= bestDist) {
        best = p;
        bestDist = dist;
      }
    }
    return best;
  }

  /// A1 (v1.12): map detected beat times onto TIMELINE seconds.
  ///
  /// Beat detection returns times relative to the START OF THE
  /// FILE it analysed — never timeline seconds. The two sources
  /// map differently:
  /// * the music file starts at timeline 0, so its beats are
  ///   already timeline seconds;
  /// * a clip's beats are FILE seconds of that clip: a beat at
  ///   file second `b` appears on the timeline at
  ///   `clipStart + (b - trimStart)`, and only while `b` lies
  ///   inside the clip's used range `[trimStart, trimEnd]`
  ///   (trimEnd = trimStart + effectiveDuration). Beats outside
  ///   the used range are trimmed away content — they draw
  ///   nothing and snap nothing.
  ///
  /// [sourceClipIndex] is the index (into the parallel lists) of
  /// the clip the beats were detected on, or -1 when the source
  /// was the music file / the clip is gone.
  static List<double> beatsToTimeline({
    required List<double> beats,
    required bool sourceIsMusic,
    required int sourceClipIndex,
    required List<double> clipStarts,
    required List<double> trimStarts,
    required List<double> effectiveDurations,
  }) {
    if (beats.isEmpty) return const [];
    if (sourceIsMusic) {
      return [for (final b in beats) if (b >= 0) b];
    }
    if (sourceClipIndex < 0 ||
        sourceClipIndex >= clipStarts.length ||
        sourceClipIndex >= trimStarts.length ||
        sourceClipIndex >= effectiveDurations.length) {
      return const [];
    }
    final start = clipStarts[sourceClipIndex];
    final ts = trimStarts[sourceClipIndex];
    final te = ts + effectiveDurations[sourceClipIndex];
    return [
      for (final b in beats)
        if (b >= ts && b <= te) start + (b - ts),
    ];
  }

  /// A1 (v1.12): convert TIMELINE-domain snap points (beats,
  /// markers) into the FILE-domain values a trim handle drags.
  ///
  /// A trim handle edits `trimStart`/`trimEnd` (file seconds of
  /// one clip), while beats and markers live in timeline
  /// seconds. A timeline point `t` strictly inside the clip's
  /// span corresponds to the file second
  /// `trimStart + (t - clipStart)` — snapping a handle to that
  /// value makes the content at `t` the clip's new edge frame.
  /// Points outside the span belong to other clips and are
  /// dropped (the clip's own edges are the caller's existing
  /// 0 / full-duration points).
  static List<double> trimSnapFilePoints({
    required double clipStart,
    required double trimStart,
    required double effectiveDuration,
    required List<double> timelinePoints,
  }) {
    final clipEnd = clipStart + effectiveDuration;
    return [
      for (final t in timelinePoints)
        if (t > clipStart && t < clipEnd) trimStart + (t - clipStart),
    ];
  }

  /// Long-press drag reorder (Phase 2): the index the dragged
  /// clip should occupy when its centre reaches [centreSec]
  /// (absolute timeline seconds), walking from [from] across
  /// neighbour midpoints in the CURRENT arrangement described by
  /// [durations] (effective seconds per clip, in order).
  static int dragTargetIndex(
    List<double> durations,
    int from,
    double centreSec,
  ) {
    if (from < 0 || from >= durations.length) return from;
    var idx = from;
    var start = 0.0;
    for (var i = 0; i < from; i++) {
      start += durations[i];
    }
    final draggedDur = durations[from];
    while (idx < durations.length - 1 &&
        centreSec > start + draggedDur + durations[idx + 1] / 2) {
      // The dragged clip's new slot starts after the neighbour it
      // just crossed.
      start += durations[idx + 1];
      idx++;
    }
    while (idx > 0 && centreSec < start - durations[idx - 1] / 2) {
      start -= durations[idx - 1];
      idx--;
    }
    return idx;
  }

  // ---- v1.14.0 T1: Precision (A13 / A14 / A20). ----

  /// A14: timecode for [sec] at [fps] frames per second, in the
  /// pro format H:MM:SS:FF. Negative times clamp to zero; the
  /// frame count is the FLOOR of the fractional part (the frame
  /// the playhead sits ON, never the next one).
  static String formatTimecode(double sec, int fps) {
    final f = fps <= 0 ? 30 : fps;
    final t = sec.isFinite && sec > 0 ? sec : 0.0;
    final totalFrames = (t * f).floor();
    final frames = totalFrames % f;
    final totalSec = totalFrames ~/ f;
    final s = totalSec % 60;
    final m = (totalSec ~/ 60) % 60;
    final h = totalSec ~/ 3600;
    String two(int v) => v.toString().padLeft(2, '0');
    return '$h:${two(m)}:${two(s)}:${two(frames)}';
  }

  /// A14: the ruler's label step (seconds) for a zoom of
  /// [pxPerSec] px/s — the smallest "round" step whose labels
  /// stay at least ~56 px apart, so the ruler is readable at
  /// every zoom instead of the old fixed 2 s.
  static double rulerStepSec(double pxPerSec) {
    const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0];
    for (final s in steps) {
      if (s * pxPerSec >= 56) return s;
    }
    return steps.last;
  }

  /// A13: the px-per-second that fits a [totalSec] timeline into
  /// [widthPx] of strip — clamped to the timeline's zoom range,
  /// so a very long project lands on the minimum zoom (and
  /// scrolls) instead of shrinking to nothing.
  static double pxPerSecToFit({
    required double totalSec,
    required double widthPx,
  }) {
    if (totalSec <= 0 || widthPx <= 0) return 42;
    return (widthPx / totalSec).clamp(12.0, 120.0).toDouble();
  }

  /// A20: the snap threshold (seconds) for the current settings.
  /// OFF always yields 0 (= never snap — [snapSec] with a 0
  /// threshold only snaps an EXACT hit, and callers skip the
  /// call entirely when this returns 0). Strength scales the
  /// long-standing bases: playhead 0.15 s, trim handles 0.08 s;
  /// 0 = Halki (×0.5), 1 = Normal (×1), 2 = Mazboot (×2).
  static double snapThreshold({
    required bool on,
    required int strength,
    required bool forTrim,
  }) {
    if (!on) return 0;
    final base = forTrim ? 0.08 : 0.15;
    final factor = switch (strength) {
      0 => 0.5,
      2 => 2.0,
      _ => 1.0,
    };
    return base * factor;
  }

  // ---- v1.14.0 T2: Trim modes (A6 / A7 / A25). ----

  /// The shortest piece a trim mode may leave behind — the same
  /// 0.3 s floor Split and the trim handles already enforce.
  static const double minClipSec = 0.3;

  /// A6 ROLL: move the boundary between clip A (before) and clip
  /// B (after) by [delta] seconds (+ = later). A's used end and
  /// B's used start move TOGETHER, so the pair's total length —
  /// and therefore the whole timeline's — never changes. The
  /// delta is clamped by both files: A cannot extend past its
  /// file end or shrink below [minClipSec]; B cannot start
  /// before its file start or shrink below [minClipSec].
  /// Returns the new A effective-end (file seconds), the new B
  /// trim-start (file seconds) and the delta actually applied;
  /// null when no movement is possible at all.
  static ({double aEnd, double bStart, double delta})? rollEdit({
    required double aTrimStart,
    required double aEffEnd,
    required double aFull,
    required double bTrimStart,
    required double bEffEnd,
    required double delta,
  }) {
    final lo = math.max(
      aTrimStart + minClipSec - aEffEnd,
      -bTrimStart,
    );
    final hi = math.min(
      aFull - aEffEnd,
      bEffEnd - minClipSec - bTrimStart,
    );
    if (hi < lo) return null;
    final d = delta.clamp(lo, hi).toDouble();
    if (d == 0) return null;
    return (aEnd: aEffEnd + d, bStart: bTrimStart + d, delta: d);
  }

  /// A7 SLIP: slide clip C's USED WINDOW inside its own file by
  /// [delta] seconds — trimStart and effective end move by the
  /// same amount, so the clip's position and length on the
  /// timeline do not change at all; only WHICH part of the file
  /// plays changes. Clamped to the file's bounds. Null when no
  /// movement is possible (window already spans the whole file).
  static ({double start, double end, double delta})? slipEdit({
    required double trimStart,
    required double effEnd,
    required double full,
    required double delta,
  }) {
    final lo = -trimStart;
    final hi = full - effEnd;
    if (hi < lo) return null;
    final d = delta.clamp(lo, hi).toDouble();
    if (d == 0) return null;
    return (start: trimStart + d, end: effEnd + d, delta: d);
  }

  /// A25: the new trimStart (file seconds) that moves clip C's
  /// start edge exactly onto the playhead — or null when the
  /// playhead is not strictly inside the clip's timeline span
  /// (with the [minClipSec] tail protected: a playhead too close
  /// to the clip's end clamps to the last legal start).
  static double? trimStartToPlayhead({
    required double clipStartSec,
    required double playheadSec,
    required double trimStart,
    required double effEnd,
  }) {
    final inside = playheadSec - clipStartSec;
    final effDur = effEnd - trimStart;
    if (inside <= 0 || inside >= effDur) return null;
    final candidate = trimStart + inside;
    return candidate.clamp(trimStart, effEnd - minClipSec).toDouble();
  }

  /// A25: the new effective end (file seconds) that moves clip
  /// C's end edge exactly onto the playhead — the mirror of
  /// [trimStartToPlayhead].
  static double? trimEndToPlayhead({
    required double clipStartSec,
    required double playheadSec,
    required double trimStart,
    required double effEnd,
  }) {
    final inside = playheadSec - clipStartSec;
    final effDur = effEnd - trimStart;
    if (inside <= 0 || inside >= effDur) return null;
    final candidate = trimStart + inside;
    return candidate.clamp(trimStart + minClipSec, effEnd).toDouble();
  }

  // ---- v1.14.0 T3: Selection & Range (A4 / A5). ----

  /// A4: the clip order after moving every selected clip one
  /// step in [direction] (-1 = peeche, +1 = aage). Returns the
  /// NEW list of OLD indices (a permutation of 0..count-1): a
  /// selected clip swaps with an unselected neighbour; selected
  /// neighbours move as a block; a selected clip at the edge
  /// stays. Pure permutation math — the State applies it to the
  /// clip objects.
  static List<int> multiMoveOrder({
    required int count,
    required Set<int> selected,
    required int direction,
  }) {
    final order = [for (var i = 0; i < count; i++) i];
    if (count < 2 || selected.isEmpty || direction == 0) return order;
    final sel = [for (final idx in order) selected.contains(idx)];
    if (direction > 0) {
      for (var i = count - 2; i >= 0; i--) {
        if (sel[i] && !sel[i + 1]) {
          final t = order[i];
          order[i] = order[i + 1];
          order[i + 1] = t;
          sel[i] = false;
          sel[i + 1] = true;
        }
      }
    } else {
      for (var i = 1; i < count; i++) {
        if (sel[i] && !sel[i - 1]) {
          final t = order[i];
          order[i] = order[i - 1];
          order[i - 1] = t;
          sel[i] = false;
          sel[i - 1] = true;
        }
      }
    }
    return order;
  }

  /// A5: the per-clip plan for deleting the timeline range
  /// [rangeIn, rangeOut) — one [RangeClipAction] per clip, in
  /// order. A clip the range misses entirely is kept; a clip
  /// fully inside is removed; a clip the range clips on one
  /// side is trimmed on that side; a clip the range punches
  /// through the middle of is SPLIT into the two surviving
  /// pieces. Pieces shorter than 0.05 s are not worth keeping:
  /// they collapse into the neighbouring action (a split with
  /// a sliver on one side becomes a one-sided trim; slivers on
  /// both sides become a removal).
  static List<RangeClipAction> rangeDeletePlan({
    required List<double> clipStarts,
    required List<double> effDurations,
    required List<double> trimStarts,
    required double rangeIn,
    required double rangeOut,
  }) {
    const sliver = 0.05;
    final out = <RangeClipAction>[];
    for (var i = 0; i < clipStarts.length; i++) {
      final s = clipStarts[i];
      final dur = effDurations[i];
      final e = s + dur;
      final ts = trimStarts[i];
      if (rangeOut <= s || rangeIn >= e) {
        out.add(const RangeClipAction.keep());
        continue;
      }
      if (rangeIn <= s && rangeOut >= e) {
        out.add(const RangeClipAction.remove());
        continue;
      }
      final leftDur = rangeIn - s; // survives on the left
      final rightDur = e - rangeOut; // survives on the right
      if (rangeIn > s && rangeOut < e) {
        // The range punches through the middle: split, unless a
        // side is a sliver.
        if (leftDur < sliver && rightDur < sliver) {
          out.add(const RangeClipAction.remove());
        } else if (leftDur < sliver) {
          out.add(RangeClipAction.trimLeft(ts + (rangeOut - s)));
        } else if (rightDur < sliver) {
          out.add(RangeClipAction.trimRight(ts + (rangeIn - s)));
        } else {
          out.add(RangeClipAction.split(
            ts + (rangeIn - s),
            ts + (rangeOut - s),
          ));
        }
        continue;
      }
      if (rangeIn > s) {
        // Range starts inside, runs past the end: keep the left.
        out.add(leftDur < sliver
            ? const RangeClipAction.remove()
            : RangeClipAction.trimRight(ts + (rangeIn - s)));
      } else {
        // Range ends inside, started before: keep the right.
        out.add(rightDur < sliver
            ? const RangeClipAction.remove()
            : RangeClipAction.trimLeft(ts + (rangeOut - s)));
      }
    }
    return out;
  }

  // ---- PIP window (v1.16.0 G2 — Motion M3 placement). ----

  /// The PIP window's minimum length, in seconds.
  static const double pipMinWindowSec = 0.1;

  /// Resolves the stored PIP window (start, end with end == -1
  /// meaning "to the end") against the timeline's total duration
  /// into a concrete (start, end) pair: start clamped into
  /// [0, total - min], end clamped into [start + min, total].
  /// A total of 0 (no clips) resolves to (0, 0).
  static ({double start, double end}) pipWindowClamp({
    required double start,
    required double end,
    required double totalDur,
  }) {
    if (totalDur <= 0) return (start: 0, end: 0);
    var s = start.clamp(0.0, totalDur).toDouble();
    var e = (end < 0 ? totalDur : end).clamp(0.0, totalDur).toDouble();
    if (e - s < pipMinWindowSec) {
      e = s + pipMinWindowSec;
      if (e > totalDur) {
        e = totalDur;
        s = (e - pipMinWindowSec).clamp(0.0, totalDur).toDouble();
      }
    }
    return (start: s, end: e);
  }

  /// True when the window covers the whole timeline (the stored
  /// default: start 0 and end -1/at the end) — the export then
  /// takes its historical, ungated path byte-for-byte.
  static bool pipWindowIsFull({
    required double start,
    required double end,
    required double totalDur,
  }) {
    if (start > 0.001) return false;
    if (end < 0) return true;
    return totalDur <= 0 || end >= totalDur - 0.001;
  }

  /// Whether the PIP inset is visible at timeline time [t] for a
  /// RESOLVED window (see [pipWindowClamp]): start inclusive, end
  /// exclusive — the same gate the export's
  /// `enable='between(t,start,end)'` applies.
  static bool pipVisibleAt({
    required double t,
    required double start,
    required double end,
  }) =>
      t >= start && t < end;

  /// The inset's own playback position at timeline time [t]: the
  /// window starts the inset at its 0, and a shorter inset loops
  /// (the preview controller loops; the export keeps its stock
  /// end-of-stream behaviour — see the G2 note in the report).
  static double pipLocalTime({
    required double t,
    required double start,
    required double pipDur,
  }) {
    if (pipDur <= 0) return 0;
    final local = t - start;
    if (local <= 0) return 0;
    return local % pipDur;
  }

  /// Dragging the PIP lane segment by [deltaSec] moves the whole
  /// window (start and end together, length preserved), clamped
  /// so the window never leaves the timeline.
  static ({double start, double end}) pipWindowDragged({
    required double start,
    required double end,
    required double deltaSec,
    required double totalDur,
  }) {
    final len = end - start;
    if (totalDur <= 0 || len <= 0) return (start: start, end: end);
    var s = (start + deltaSec).clamp(0.0, totalDur - len).toDouble();
    if (s < 0) s = 0;
    return (start: s, end: s + len);
  }

  // ---- Clip identity (v1.16.0 G3 — T7: A22 badges + C3 labels). ----

  /// The C3 colour-label palette: index 0 = no label, 1..6 map
  /// to these colours. Stored on the clip as an int so old
  /// projects (no field) read as 0.
  static const List<int> clipLabelArgb = [
    0x00000000, // 0 = none
    0xFFE53935, // 1 red
    0xFFFB8C00, // 2 orange
    0xFFFDD835, // 3 yellow
    0xFF43A047, // 4 green
    0xFF1E88E5, // 5 blue
    0xFF8E24AA, // 6 purple
  ];

  /// Clamps a stored colour-label value into the palette range.
  static int clipLabelClamp(int label) =>
      label.clamp(0, clipLabelArgb.length - 1).toInt();

  /// A18 (v1.16.0 G4): where each caption segment sits on the
  /// timeline, as (start, end) spans — the SAME mapping the
  /// export applies in _adjustedCaptions (minus its speed
  /// scaling, which is an export-time transform): timeline-
  /// relative segments sit at their own times; per-clip
  /// segments sit on the selected clip (offset by its start).
  /// Spans are clamped into [0, totalDur].
  static List<({double start, double end})> captionStripSpans({
    required List<({double start, double end})> segments,
    required bool timelineRelative,
    required double selectedClipStart,
    required double totalDur,
  }) {
    final offset = timelineRelative ? 0.0 : selectedClipStart;
    return [
      for (final s in segments)
        (
          start: (offset + s.start).clamp(0.0, totalDur).toDouble(),
          end: (offset + s.end).clamp(0.0, totalDur).toDouble(),
        ),
    ];
  }

  /// A22: the badge keys a clip block shows, derived ONLY from
  /// the clip's real state, in display order. Keys: 'off'
  /// (disabled), 'mute', 'vol' (volume changed), 'trim'
  /// (trimmed), 'detach' (audio unlinked), 'photo'.
  static List<String> clipBadgeKeys({
    required bool isPhoto,
    required bool muted,
    required double volume,
    required double trimStart,
    required double trimEnd,
    required bool hasDetachedAudio,
    required bool disabled,
  }) {
    final out = <String>[];
    if (disabled) out.add('off');
    if (muted) out.add('mute');
    if (!muted && (volume - 1).abs() > 0.001) out.add('vol');
    if (trimStart > 0.001 || trimEnd >= 0) out.add('trim');
    if (hasDetachedAudio) out.add('detach');
    if (isPhoto) out.add('photo');
    return out;
  }
}

/// v1.14.0 T3 (A5): what a range delete does to ONE clip — see
/// [TimelineMath.rangeDeletePlan]. [trimStart]/[effEnd] are the
/// FILE-second values the action sets (split sets both: the
/// left piece's new end and the right piece's new start).
class RangeClipAction {
  const RangeClipAction.keep()
      : kind = RangeActionKind.keep,
        trimStart = null,
        effEnd = null;
  const RangeClipAction.remove()
      : kind = RangeActionKind.remove,
        trimStart = null,
        effEnd = null;
  const RangeClipAction.trimLeft(this.trimStart)
      : kind = RangeActionKind.trimLeft,
        effEnd = null;
  const RangeClipAction.trimRight(this.effEnd)
      : kind = RangeActionKind.trimRight,
        trimStart = null;
  const RangeClipAction.split(this.effEnd, this.trimStart)
      : kind = RangeActionKind.split;

  final RangeActionKind kind;

  /// New trimStart (file sec) for trimLeft / split.
  final double? trimStart;

  /// New effective end (file sec) for trimRight / split.
  final double? effEnd;
}

enum RangeActionKind { keep, remove, trimLeft, trimRight, split }

/// Why a Split was refused (v1.15.0 G1): the screen turns each
/// into a clear status message instead of silently cutting
/// somewhere else.
enum SplitRefusal {
  /// The target clip is under 0.3 s — nothing sensible to cut.
  tooSmall,

  /// Playhead mode: the line sits (almost) exactly on the target
  /// clip's edge — cutting there would only shave a sliver. The
  /// old code fell back to the midpoint here, which is what made
  /// repeated Split taps halve the clip again and again (the
  /// "kai dafa dabana parta hai" cascade).
  atEdge,
}

/// The outcome of resolving a Split tap — which clip is cut and
/// at what FILE second, whether the cut is exactly where the user
/// is looking ([atPlayhead]), or a [refusal] explaining why no
/// cut happened.
class SplitResolution {
  const SplitResolution({
    required this.index,
    required this.cutFileSec,
    required this.atPlayhead,
    this.refusal,
  });

  final int index;
  final double cutFileSec;
  final bool atPlayhead;
  final SplitRefusal? refusal;
}

/// Resolves a Split (v1.15.0 G1 — the full diagnosis fix). Pure —
/// the editor screen calls this and the regression tests pin it.
///
/// Two modes, chosen by the Split panel's "Playhead par /
/// Darmiyan se" toggle ([playheadMode]):
///
/// * Playhead mode (the default): the cut targets the clip UNDER
///   the strip's centre line ([centreSec]) — not the stale
///   selection — at exactly the line's position inside it. When
///   the strip has not been laid out ([centreSec] null) the
///   preview clock's position inside the selected clip is used.
///   A position within 0.15 s of either edge of the target clip
///   is REFUSED ([SplitRefusal.atEdge]) — never a silent midpoint
///   fallback.
/// * Midpoint mode: the SELECTED clip is cut at its midpoint and
///   [SplitResolution.atPlayhead] is false, so the status can say
///   "darmiyan se kata" truthfully.
///
/// A target clip under 0.3 s is refused ([SplitRefusal.tooSmall])
/// in both modes. Invalid inputs return null.
SplitResolution? resolveSplit({
  required List<double> effectiveDurations,
  required List<double> trimStarts,
  required int selected,
  required double clockInsideSelected,
  double? centreSec,
  bool playheadMode = true,
}) {
  if (effectiveDurations.isEmpty ||
      selected < 0 ||
      selected >= effectiveDurations.length) {
    return null;
  }
  final int target;
  final double inside;
  if (playheadMode) {
    if (centreSec != null) {
      target = TimelineMath.indexAtSec(effectiveDurations, centreSec);
      inside =
          centreSec - TimelineMath.startSec(effectiveDurations, target);
    } else {
      target = selected;
      inside = clockInsideSelected;
    }
  } else {
    target = selected;
    inside = effectiveDurations[selected] / 2;
  }
  final eff = effectiveDurations[target];
  if (eff < 0.3) {
    return SplitResolution(
      index: target,
      cutFileSec: trimStarts[target] + eff / 2,
      atPlayhead: playheadMode,
      refusal: SplitRefusal.tooSmall,
    );
  }
  if (!playheadMode) {
    return SplitResolution(
      index: target,
      cutFileSec: trimStarts[target] + eff / 2,
      atPlayhead: false,
    );
  }
  final clamped = inside.clamp(0.0, eff).toDouble();
  if (clamped <= 0.15 || clamped >= eff - 0.15) {
    return SplitResolution(
      index: target,
      cutFileSec: trimStarts[target] + clamped,
      atPlayhead: true,
      refusal: SplitRefusal.atEdge,
    );
  }
  return SplitResolution(
    index: target,
    cutFileSec: trimStarts[target] + clamped,
    atPlayhead: true,
  );
}

/// Rule-of-thirds grid + safe zones drawn over the canvas frame
/// (Phase 1, PRO-SPEC point 15). Pure guide lines: thirds in faint
/// white, the 90% action-safe and 80% title-safe rects in faint
/// gold. Painted only while the user's grid toggle is on.
class StageGridPainter extends CustomPainter {
  const StageGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final third = Paint()
      ..color = const Color(0x3DFFFFFF)
      ..strokeWidth = 1;
    for (final f in const [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * f, 0),
        Offset(size.width * f, size.height),
        third,
      );
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        third,
      );
    }
    final safe = Paint()
      ..color = const Color(0x59FFD76A)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // Action-safe (5% inset) and title-safe (10% inset).
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.05,
        size.height * 0.05,
        size.width * 0.9,
        size.height * 0.9,
      ),
      safe,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.1,
        size.height * 0.1,
        size.width * 0.8,
        size.height * 0.8,
      ),
      safe,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Build 3 (Phase 3): the Custom speed-ramp graph's geometry — ONE
/// mapping shared by the curve painter (which draws the three
/// plateaus + drag handles) and the panel's drag handler (which
/// turns a finger position back into a point speed), so the point
/// the user grabs is exactly the point that moves. The ramp model
/// is three plateaus (start / middle / end thirds) with speeds in
/// [minSpeed]..[maxSpeed] — the same range the point sliders use.
class SpeedRampMath {
  SpeedRampMath._();

  static const double minSpeed = 0.25;
  static const double maxSpeed = 2.0;

  /// The graph's plot area: a 4 px baseline inset at the bottom
  /// and 6 px of headroom at the top (the painter's long-standing
  /// margins).
  static double yForSpeed(double speed, double height) {
    final s = speed.clamp(minSpeed, maxSpeed);
    return height - 4 - (s / maxSpeed) * (height - 10);
  }

  /// Inverse of [yForSpeed]: the speed a drag at vertical position
  /// [y] (in a graph of [height]) sets, clamped to the point range.
  static double speedForY(double y, double height) {
    if (height <= 10) return 1.0;
    final v = (height - 4 - y) / (height - 10) * maxSpeed;
    return v.clamp(minSpeed, maxSpeed);
  }

  /// Which plateau a horizontal position falls in: 0 = start
  /// third, 1 = middle third, 2 = end third.
  static int thirdForX(double x, double width) {
    if (width <= 0) return 0;
    final t = (x / width * 3).floor();
    return t.clamp(0, 2);
  }

  /// The horizontal centre of plateau [third] — where its drag
  /// handle is drawn.
  static double centreX(int third, double width) =>
      width * (third + 0.5) / 3;
}

/// P1-1: the grain overlay's noise field — a deterministic
/// (fixed-seed) scatter of grey specks at the derived opacity,
/// the preview's stand-in for the export's `noise` filter.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final rnd = math.Random(42);
    final paint = Paint();
    final count =
        (size.width * size.height / 90).round().clamp(200, 6000);
    for (var i = 0; i < count; i++) {
      final v = rnd.nextInt(256);
      paint.color = Color.fromARGB(
        (opacity * 255).round().clamp(0, 255),
        v,
        v,
        v,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          rnd.nextDouble() * size.width,
          rnd.nextDouble() * size.height,
          1.3,
          1.3,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class StageCanvas extends StatelessWidget {
  final VideoEditorController host;
  final VideoClip clip;
  final VideoPlayerController? ctrl;
  final bool ready;
  const StageCanvas({super.key, required this.host, required this.clip, required this.ctrl, required this.ready});

  @override
  Widget build(BuildContext context) {
    final ctrl = this.ctrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageSize = constraints.biggest;
        final mediaAspect = (!clip.isPhoto && ready && ctrl != null)
            ? ctrl.value.aspectRatio
            : clip.aspectRatio;
        final ratio = CanvasGeometry.ratioFor(host.aspect, mediaAspect);
        final frame = CanvasGeometry.frameRect(stageSize, ratio);
        host.stageFrameRect = frame;
        host.stageMediaRect = CanvasGeometry.containRect(frame, mediaAspect);
        if (frame.width <= 0 || frame.height <= 0) {
          return const SizedBox.shrink();
        }
        final containLocal = host.stageMediaRect.shift(-frame.topLeft);
        return Stack(
          children: [
            // ---- The canvas frame ----
            Positioned.fromRect(
              rect: frame,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: host.frameBackdropColor()),
                    ),
                    // Transformed content (media + text + track
                    // pin): the export's transform pass scales the
                    // main pass output — which includes the
                    // drawtext text — so all of it lives inside
                    // the Transform.
                    Positioned.fill(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: host.stageTransformMatrix(frame.size),
                        child: Stack(
                          children: [
                            Positioned.fromRect(
                              rect: containLocal,
                              child: _stageMediaLayer(
                                clip,
                                ctrl,
                                ready,
                                containLocal.size,
                              ),
                            ),
                            if (host.text.trim().isNotEmpty)
                              _stageTextLayer(frame.size),
                          ],
                        ),
                      ),
                    ),
                    // v1.16.0 G3 (A23): a DISABLED clip previews
                    // as black + silent (its preview volume is
                    // bound in _loadPreview) — the same black the
                    // export renders for it.
                    if (clip.disabled)
                      Positioned.fromRect(
                        rect: frame,
                        child: Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_off,
                                color: Colors.white38,
                                size: 30,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Clip disabled',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // PIP live preview (§6.11): composited over the
                    // frame, NOT transformed — the export applies
                    // its PIP pass after the transform pass.
                    // Build 3: the layer rebuilds on every clock
                    // tick so a keyframed inset's pose interpolates
                    // LIVE with playback/scrubbing.
                    if (host.fxPip && host.fxPipVideo.isNotEmpty)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: host.clock,
                          builder: (context, _) => Stack(
                            children: [_pipPreviewLayer(frame.size)],
                          ),
                        ),
                      ),
                    // Build 3: the keyframed title/sticker posed
                    // live at the playhead (preview interpolation —
                    // the export renders the real PNG with the same
                    // track; this pill is its stage stand-in).
                    if (host.proKeyframes &&
                        (host.proTitle.trim().isNotEmpty ||
                            host.proSticker.trim().isNotEmpty))
                      AnimatedBuilder(
                        animation: host.clock,
                        builder: (context, _) => _kfTitleChip(containLocal),
                      ),
                    // Guides: thirds + safe zones over everything.
                    if (host.showGrid)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: const StageGridPainter(),
                        ),
                      ),
                    // The frame's edge, so the canvas is visible as
                    // an object on the black stage.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Grid / safe-zone toggle (stage corner).
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                key: const Key('stageGridToggle'),
                tooltip: 'Grid / safe zones',
                icon: Icon(
                  host.showGrid ? Icons.grid_on : Icons.grid_off,
                  color: host.showGrid ? TjProTheme.gold : Colors.white54,
                  size: 20,
                ),
                onPressed: () => host.update(() => host.showGrid = !host.showGrid),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mainMasked(Widget media, double aspect) {
    if (host.mainMask == 'none') return media;
    var mw = 480;
    var mh = (480 / aspect).round();
    if (mh > 480) {
      mh = 480;
      mw = (480 * aspect).round();
    }
    if (mw < 2 || mh < 2) return media;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.mounted) host.ensureMainMaskImage(mw, mh);
    });
    final img = host.mainMaskImage;
    if (img == null) return media;
    return ShaderMask(
      shaderCallback: (bounds) => ui.ImageShader(
        img,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        (Matrix4.diagonal3Values(
          bounds.width / img.width,
          bounds.height / img.height,
          1.0,
        )).storage,
      ),
      blendMode: BlendMode.dstIn,
      child: media,
    );
  }

  /// P1-1: the Adjust extras' non-matrix layers over the graded
  /// media — vignette (radial darkening; strength derived from
  /// the same vignette value as the export's filter) and grain
  /// (a seeded static noise field; opacity derived from the
  /// same noise amount). Both vanish at 0 and while comparing
  /// (the host getters return 0 then), exactly like the matrix.
  Widget _adjustOverlays(Widget media) {
    final vig = host.adjustVignetteStrength;
    final grain = host.adjustGrainOpacity;
    if (vig <= 0 && grain <= 0) return media;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        media,
        if (vig > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55 * vig),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        if (grain > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _GrainPainter(grain)),
            ),
          ),
      ],
    );
  }

  Widget _stageMediaLayer(
    VideoClip clip,
    VideoPlayerController? ctrl,
    bool ready,
    Size mediaBox,
  ) {
    if (clip.isPhoto) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: host.onStageScaleStart,
        onScaleUpdate: host.onStageScaleUpdate,
        onDoubleTap: host.resetStageTransform,
        child: _mainMasked(
          _adjustOverlays(
            ColorFiltered(
              colorFilter: ColorFilter.matrix(host.stageMatrix),
              child: Image.file(
                clip.file,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          clip.aspectRatio,
        ),
      );
    }
    if (!ready || ctrl == null) {
      return const Center(
        child: Text(
          'Loading preview…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => host.onPreviewTapDown(d, mediaBox),
      // §6.2 hold-to-compare: hold the stage to see the RAW frame,
      // release for the graded one.
      onLongPressStart: (_) => host.update(() => host.comparing = true),
      onLongPressEnd: (_) => host.update(() => host.comparing = false),
      onScaleStart: host.onStageScaleStart,
      onScaleUpdate: host.onStageScaleUpdate,
      onDoubleTap: host.resetStageTransform,
      child: Stack(
        children: [
          _mainMasked(
            _adjustOverlays(
              ColorFiltered(
                colorFilter: ColorFilter.matrix(host.stageMatrix),
                child: VideoPlayer(ctrl),
              ),
            ),
            ctrl.value.aspectRatio,
          ),
          if (host.trackStartX != null)
            Align(
              alignment: Alignment(
                host.trackStartX! * 2 - 1,
                host.trackStartY! * 2 - 1,
              ),
              child: const Icon(
                Icons.location_on,
                color: Colors.redAccent,
                size: 28,
              ),
            ),
          if (host.comparing)
            const Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Chip(
                  label: Text('Original'),
                  backgroundColor: Colors.black54,
                  labelStyle: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kfTitleChip(Rect containLocal) {
    final label = host.proTitle.trim().isNotEmpty
        ? host.proTitle.trim()
        : host.proSticker.trim();
    final total = host.totalDurationSec;
    final f = total > 0
        ? (host.globalPositionSec / total).clamp(0.0, 1.0)
        : 0.0;
    final pose = keyframePoseAt(
      KeyframeTrack(
        start: ProKeyframe(
          timeSec: 0,
          xNorm: host.kfStartX,
          yNorm: host.kfStartY,
          scale: host.kfStartScale,
          opacity: host.kfStartOpacity,
          rotationDeg: host.kfStartRotation,
        ),
        end: ProKeyframe(
          timeSec: 1,
          xNorm: host.kfEndX,
          yNorm: host.kfEndY,
          scale: host.kfEndScale,
          opacity: host.kfEndOpacity,
          rotationDeg: host.kfEndRotation,
        ),
      ),
      f,
      host.kfEasing,
    );
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: containLocal.left + pose.xNorm * containLocal.width,
            top: containLocal.top + pose.yNorm * containLocal.height,
            child: Opacity(
              opacity: pose.opacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: pose.rotationDeg * math.pi / 180,
                child: Transform.scale(
                  scale: pose.scale.clamp(0.1, 3.0),
                  // v1.17.0 (G3, Point #34a): the title/sticker
                  // chip is tappable like every other stage layer
                  // — a tap selects it and opens its editing tab.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      host.update(() => host.stageLayer = 'title');
                      host.openToolTab('text', 'titles');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageTextLayer(Size frameSize) =>
      StageTextLayer(host: host, frameSize: frameSize);

  Widget _pipPreviewLayer(Size stage) {
    // v1.16.0 G2 (Motion M3): the PIP window — outside
    // [pipStartSec, pipEndSec) the inset is not shown, exactly
    // like the export's enable gate. A full window (the
    // default) never hides it: pre-M3 behaviour.
    final total = host.totalDurationSec;
    if (total > 0 &&
        !TimelineMath.pipWindowIsFull(
          start: host.pipStartSec,
          end: host.pipEndSec,
          totalDur: total,
        )) {
      final w = TimelineMath.pipWindowClamp(
        start: host.pipStartSec,
        end: host.pipEndSec,
        totalDur: total,
      );
      if (!TimelineMath.pipVisibleAt(
        t: host.globalPositionSec,
        start: w.start,
        end: w.end,
      )) {
        return const SizedBox.shrink();
      }
    }
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    final ctrl = host.controller;
    // Main content rect (contain fit, centred on the black stage).
    double mainAspect = stage.aspectRatio;
    double basePxW = 1280;
    if (clip != null && clip.isPhoto) {
      mainAspect = clip.aspectRatio;
      basePxW = 1920;
    } else if (ctrl != null && ctrl.value.isInitialized) {
      mainAspect = ctrl.value.aspectRatio;
      basePxW = ctrl.value.size.width;
    }
    var dispW = stage.width;
    var dispH = dispW / mainAspect;
    if (dispH > stage.height) {
      dispH = stage.height;
      dispW = dispH * mainAspect;
    }
    final dispX = (stage.width - dispW) / 2;
    final dispY = (stage.height - dispH) / 2;
    final pipCtrl = host.pipController;
    final pipReady = pipCtrl != null && pipCtrl.value.isInitialized;
    final pipPxW = pipReady ? pipCtrl.value.size.width : 1280;
    final pipAspect = pipReady ? pipCtrl.value.aspectRatio : 16 / 9;
    final s = host.pipScale.clamp(0.15, 0.5);
    final pipW = dispW * pipPxW * s / basePxW;
    final pipH = pipW / pipAspect;
    final margin = dispW * 24 / basePxW;
    // Build 3 (Phase 3): with PIP keyframes ON, the inset's pose
    // comes from the keyframe track at the playhead (the SAME lerp
    // the export renders, via keyframePoseAt) — the corner preset
    // and drag offset no longer drive it.
    final kfPose = host.pipKeyframes
        ? keyframePoseAt(
            KeyframeTrack(
              start: ProKeyframe(
                timeSec: 0,
                xNorm: host.pkStartX,
                yNorm: host.pkStartY,
                opacity: host.pkStartOpacity,
              ),
              end: ProKeyframe(
                timeSec: 1,
                xNorm: host.pkEndX,
                yNorm: host.pkEndY,
                opacity: host.pkEndOpacity,
              ),
            ),
            host.totalDurationSec > 0
                ? (host.globalPositionSec / host.totalDurationSec).clamp(0.0, 1.0)
                : 0.0,
            host.pkEasing,
          )
        : null;
    final (lx, ty) = kfPose != null
        ? (dispX + kfPose.xNorm * dispW, dispY + kfPose.yNorm * dispH)
        : switch (host.pipPosition) {
            PipPosition.topLeft => (dispX + margin, dispY + margin),
            PipPosition.topRight => (
                dispX + dispW - pipW - margin,
                dispY + margin,
              ),
            PipPosition.bottomLeft => (
                dispX + margin,
                dispY + dispH - pipH - margin,
              ),
            _ => (
                dispX + dispW - pipW - margin,
                dispY + dispH - pipH - margin,
              ),
          };
    // Preview mask at a capped resolution (shapes/gradients are
    // scale-invariant; feather is relative to the short side).
    if (host.pipMask != 'none' && pipReady) {
      final mw = pipCtrl.value.size.width.round();
      final mh = pipCtrl.value.size.height.round();
      final cap = 480 / math.max(mw, mh);
      final sw = cap < 1 ? (mw * cap).round() : mw;
      final sh = cap < 1 ? (mh * cap).round() : mh;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.mounted) host.ensurePipMaskImage(sw, sh);
      });
    }
    Widget content = pipReady
        ? VideoPlayer(pipCtrl)
        : Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(color: TjProTheme.gold),
            ),
            child: const Center(
              child: Icon(
                Icons.picture_in_picture_alt,
                color: Colors.white70,
                size: 28,
              ),
            ),
          );
    if (host.pipMask != 'none' && host.pipMaskImage != null) {
      final img = host.pipMaskImage!;
      content = ShaderMask(
        shaderCallback: (bounds) => ui.ImageShader(
          img,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          (Matrix4.diagonal3Values(
            bounds.width / img.width,
            bounds.height / img.height,
            1.0,
          )).storage,
        ),
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }
    content = Opacity(
      opacity: kfPose != null
          ? kfPose.opacity.clamp(0.0, 1.0)
          : host.pipOpacity.clamp(0.1, 1.0),
      child: content,
    );
    final mode = host.pipBlendMode(host.pipBlend);
    if (mode != null) {
      content = BlendLayer(mode: mode, child: content);
    }
    // Build 2 (Phase 1): the inset is a stage LAYER — tap selects
    // it (gold outline) and opens the Elements row, drag moves it
    // (release snaps to the nearest corner of the contain rect —
    // the PipPosition model the export consumes), pinch rescales
    // it (the render clamp 0.15..0.5 above). Build 3: while PIP
    // keyframes drive the pose, drag/pinch stand down (the track
    // owns the position).
    final selected = host.stageLayer == 'pip';
    return Positioned(
      left: lx + (kfPose != null ? 0 : host.pipDragOffset.dx),
      top: ty + (kfPose != null ? 0 : host.pipDragOffset.dy),
      width: pipW,
      height: pipH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          host.update(() => host.stageLayer = 'pip');
          host.openToolTab('overlay', 'pip');
        },
        onScaleStart: (_) => host.pinchPipScale = host.pipScale,
        onScaleUpdate: (d) {
          if (host.pipKeyframes) return;
          host.update(() {
            if (d.pointerCount >= 2) {
              host.pipScale = (host.pinchPipScale * d.scale).clamp(0.15, 0.5);
            }
            host.pipDragOffset += d.focalPointDelta;
          });
        },
        onScaleEnd: (_) {
          if (host.pipKeyframes) return;
          final cxp = lx + host.pipDragOffset.dx + pipW / 2;
          final cyp = ty + host.pipDragOffset.dy + pipH / 2;
          final pos = (cxp < dispX + dispW / 2)
              ? (cyp < dispY + dispH / 2
                    ? PipPosition.topLeft
                    : PipPosition.bottomLeft)
              : (cyp < dispY + dispH / 2
                    ? PipPosition.topRight
                    : PipPosition.bottomRight);
          host.update(() {
            host.pipPosition = pos;
            host.pipDragOffset = Offset.zero;
          });
        },
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(color: TjProTheme.gold, width: 1.5),
                )
              : null,
          child: content,
        ),
      ),
    );
  }
}

class BlendLayer extends SingleChildRenderObjectWidget {
  const BlendLayer({super.key, required this.mode, required super.child});

  final BlendMode mode;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBlendLayer(mode);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBlendLayer renderObject,
  ) {
    renderObject.mode = mode;
  }
}

class RenderBlendLayer extends RenderProxyBox {
  RenderBlendLayer(this._mode);

  BlendMode _mode;

  set mode(BlendMode value) {
    if (_mode != value) {
      _mode = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_mode == BlendMode.srcOver) {
      super.paint(context, offset);
      return;
    }
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _mode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}

/// v1.17.0 (G3, Point #34): the stage text overlay as its own
/// stateful layer — it renders the Text tool's REAL style state
/// (font / size scale / colour / background pill — none of
/// which existed before this build, so the preview could only
/// ever show one hard-coded style), selects on tap with a
/// generous hit band, and PINCHES: a two-finger scale writes
/// [VideoEditorController.textSizeScale], the same value the
/// panel's Size slider edits and the export's drawtext uses.
class StageTextLayer extends StatefulWidget {
  const StageTextLayer({super.key, required this.host, required this.frameSize});

  final VideoEditorController host;
  final Size frameSize;

  @override
  State<StageTextLayer> createState() => _StageTextLayerState();
}

class _StageTextLayerState extends State<StageTextLayer> {
  double? _pinchBase;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final selected = host.stageLayer == 'text';
    var style = TextStyle(
      color: Color(host.textColorArgb),
      fontSize: 22 * host.textSizeScale,
      fontWeight: FontWeight.bold,
      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
    );
    if (host.textFontId.isNotEmpty) {
      style = UrduFonts.byId(host.textFontId).apply(style);
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.frameSize.height * 0.055,
      child: Center(
        child: GestureDetector(
          key: const Key('stageTextLayer'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            host.update(() => host.stageLayer = 'text');
            host.openToolTab('text', 'text');
          },
          onScaleStart: (details) {
            _pinchBase = host.textSizeScale;
            if (host.stageLayer != 'text') {
              host.update(() => host.stageLayer = 'text');
            }
          },
          onScaleUpdate: (details) {
            if (_pinchBase == null || details.scale == 1.0) return;
            final next = (_pinchBase! * details.scale).clamp(0.4, 3.0);
            host.update(() => host.textSizeScale = next);
          },
          onScaleEnd: (_) => _pinchBase = null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: host.textBgPill ? Colors.black54 : null,
              border: selected
                  ? Border.all(color: TjProTheme.gold, width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              host.text,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}
