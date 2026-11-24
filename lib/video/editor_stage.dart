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

import 'package:flutter/material.dart';

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
