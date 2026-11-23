// Build 2 (Master Plan Phase 1 + 2) — stage geometry + timeline
// math tests.
//
// The Phase 2 risk rule: the timeline's sync invariants (#5/#29/
// #30 — one total, prefix-sum starts, seek lands in the containing
// clip) get pinned by tests BEFORE the timeline code changes. The
// State delegates its totals/starts/seek-index to TimelineMath, so
// these tests ARE the sync tests. CanvasGeometry pins Phase 1's
// promise: the media is contain-fitted inside the chosen canvas
// frame and never stretched, and stage taps map through the real
// frame rects (the fixed-16:9 approximation is gone).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/video/editor_stage.dart';
import 'package:tj_pro/video/video_editor_screen.dart';

void main() {
  group('CanvasGeometry.ratioFor', () {
    test('panel keys map to their ratios', () {
      expect(CanvasGeometry.ratioFor('9:16', 1.5), 9 / 16);
      expect(CanvasGeometry.ratioFor('16:9', 1.5), 16 / 9);
      expect(CanvasGeometry.ratioFor('1:1', 1.5), 1);
      expect(CanvasGeometry.ratioFor('4:5', 1.5), 4 / 5);
    });

    test('Original keeps the media ratio; broken ratios fall back', () {
      expect(CanvasGeometry.ratioFor('Original', 1.33), 1.33);
      expect(CanvasGeometry.ratioFor('Original', 0), 16 / 9);
      expect(CanvasGeometry.ratioFor('Original', double.nan), 16 / 9);
      expect(CanvasGeometry.ratioFor('Original', double.infinity), 16 / 9);
    });
  });

  group('CanvasGeometry.frameRect', () {
    test('9:16 frame in a portrait stage is width-bound, centred', () {
      final r = CanvasGeometry.frameRect(const Size(400, 800), 9 / 16);
      expect(r.width, 400);
      expect(r.height, closeTo(711.11, 0.01));
      expect(r.left, 0);
      expect(r.top, closeTo((800 - 711.11) / 2, 0.01));
    });

    test('16:9 frame in a portrait stage is width-bound', () {
      final r = CanvasGeometry.frameRect(const Size(400, 800), 16 / 9);
      expect(r.width, 400);
      expect(r.height, 225);
      expect(r.top, (800 - 225) / 2);
    });

    test('9:16 frame in a landscape stage is height-bound', () {
      final r = CanvasGeometry.frameRect(const Size(800, 400), 9 / 16);
      expect(r.height, 400);
      expect(r.width, 225);
      expect(r.left, (800 - 225) / 2);
    });

    test('degenerate inputs give Rect.zero', () {
      expect(CanvasGeometry.frameRect(Size.zero, 1), Rect.zero);
      expect(CanvasGeometry.frameRect(const Size(400, 400), 0), Rect.zero);
    });
  });

  group('CanvasGeometry.containRect — never stretched', () {
    test('16:9 media inside a 9:16 frame letterboxes, centred', () {
      const frame = Rect.fromLTWH(0, 44, 400, 711);
      final r = CanvasGeometry.containRect(frame, 16 / 9);
      expect(r.width, 400);
      expect(r.height, 225);
      expect(r.left, 0);
      expect(r.top, closeTo(44 + (711 - 225) / 2, 0.001));
      // The rect keeps the media's own ratio — no stretch.
      expect(r.width / r.height, closeTo(16 / 9, 0.001));
    });

    test('9:16 media inside a 16:9 frame pillarboxes, centred', () {
      const frame = Rect.fromLTWH(0, 0, 800, 450);
      final r = CanvasGeometry.containRect(frame, 9 / 16);
      expect(r.height, 450);
      expect(r.width, closeTo(253.125, 0.001));
      expect(r.left, closeTo((800 - 253.125) / 2, 0.001));
    });

    test('matching ratios fill the frame exactly', () {
      const frame = Rect.fromLTWH(10, 20, 300, 300);
      expect(CanvasGeometry.containRect(frame, 1), frame);
    });
  });

  group('CanvasGeometry.coverRect', () {
    test('16:9 media covers a 9:16 frame, overflowing sideways', () {
      const frame = Rect.fromLTWH(0, 0, 400, 711);
      final r = CanvasGeometry.coverRect(frame, 16 / 9);
      expect(r.height, 711);
      expect(r.width, greaterThan(400));
      expect(r.left, lessThan(0));
    });
  });

  group('CanvasGeometry tap mapping', () {
    const rect = Rect.fromLTWH(100, 50, 400, 225);

    test('centre maps to (0.5, 0.5), corners to (0,0)/(1,1)', () {
      expect(
        CanvasGeometry.normalizedIn(rect, const Offset(300, 162.5)),
        const Offset(0.5, 0.5),
      );
      expect(
        CanvasGeometry.normalizedIn(rect, const Offset(100, 50)),
        Offset.zero,
      );
      expect(
        CanvasGeometry.normalizedIn(rect, const Offset(500, 275)),
        const Offset(1, 1),
      );
    });

    test('a letterbox tap (outside the media rect) is NOT a point', () {
      expect(CanvasGeometry.normalizedIn(rect, const Offset(99, 100)), isNull);
      expect(CanvasGeometry.normalizedIn(rect, const Offset(300, 276)), isNull);
    });

    test('clamped mapping keeps edge taps on the edge', () {
      expect(
        CanvasGeometry.normalizedClamped(rect, const Offset(0, 999)),
        const Offset(0, 1),
      );
    });
  });

  group('TimelineMath — the #5/#29/#30 invariants', () {
    const durs = [4.0, 6.5, 3.0];

    test('total is the plain sum of effective durations', () {
      expect(TimelineMath.totalSec(durs), 13.5);
      expect(TimelineMath.totalSec(const []), 0);
    });

    test('starts are prefix sums', () {
      expect(TimelineMath.startSec(durs, 0), 0);
      expect(TimelineMath.startSec(durs, 1), 4.0);
      expect(TimelineMath.startSec(durs, 2), 10.5);
      expect(TimelineMath.startSec(durs, 99), 13.5);
    });

    test('indexAtSec lands in the containing clip', () {
      expect(TimelineMath.indexAtSec(durs, 0), 0);
      expect(TimelineMath.indexAtSec(durs, 3.999), 0);
      expect(TimelineMath.indexAtSec(durs, 4.0), 1);
      expect(TimelineMath.indexAtSec(durs, 10.5), 2);
      // The very end still resolves to the last clip (seek loop
      // semantics), never out of range.
      expect(TimelineMath.indexAtSec(durs, 13.5), 2);
      expect(TimelineMath.indexAtSec(durs, 999), 2);
      expect(TimelineMath.indexAtSec(const [], 3), -1);
    });

    test('boundaries are every start plus the total', () {
      expect(TimelineMath.boundaries(durs), [0, 4.0, 10.5, 13.5]);
      expect(TimelineMath.boundaries(const []), [0]);
    });

    test('snapSec snaps only within the threshold, to the nearest', () {
      expect(TimelineMath.snapSec(4.05, const [0, 4.0, 10.5], 0.1), 4.0);
      expect(TimelineMath.snapSec(4.2, const [0, 4.0, 10.5], 0.1), 4.2);
      expect(TimelineMath.snapSec(0.0, const [0, 4.0], 0.1), 0.0);
      expect(TimelineMath.snapSec(9.9, const [0, 4.0], 0.1), 9.9);
    });

    test('VideoClip effective durations feed the model (trims)', () {
      // The State hands TimelineMath the clips' effectiveDuration
      // values; pin what those are for the trim edge cases.
      VideoClip clip(double durSec, {double ts = 0, double te = -1}) {
        final c = VideoClip(
          File('/tmp/b2_fake_clip.mp4'),
          Duration(milliseconds: (durSec * 1000).round()),
          16 / 9,
        );
        c.trimStart = ts;
        c.trimEnd = te;
        return c;
      }

      // trimEnd -1 = full duration; trims cut from both ends.
      expect(clip(10).effectiveDuration, 10);
      expect(clip(10, ts: 2).effectiveDuration, 8);
      expect(clip(10, ts: 2, te: 7).effectiveDuration, 5);
      expect(clip(10, te: 4).effectiveDuration, 4);

      final clips = [clip(10, ts: 2, te: 6), clip(8), clip(5, ts: 1)];
      final durs = clips.map((c) => c.effectiveDuration).toList();
      expect(durs, [4.0, 8.0, 4.0]);
      expect(TimelineMath.totalSec(durs), 16.0);
      expect(TimelineMath.startSec(durs, 2), 12.0);
    });
  });

  group('TimelineMath.dragTargetIndex — long-press drag reorder', () {
    // Slots: A [0,4) B [4,12) C [12,16).
    final durs = [4.0, 8.0, 4.0];

    test('no movement keeps the index', () {
      expect(TimelineMath.dragTargetIndex(durs, 0, 2), 0);
      expect(TimelineMath.dragTargetIndex(durs, 1, 8), 1);
      expect(TimelineMath.dragTargetIndex(durs, 2, 14), 2);
    });

    test('crossing the next midpoint swaps right, one and two slots', () {
      // Dragging A (centre 2): B's midpoint is 4 + 8/2 = 8.
      expect(TimelineMath.dragTargetIndex(durs, 0, 7.9), 0);
      expect(TimelineMath.dragTargetIndex(durs, 0, 8.1), 1);
      // Past B the arrangement is B A C, so C's midpoint is 14.
      expect(TimelineMath.dragTargetIndex(durs, 0, 10.1), 1);
      expect(TimelineMath.dragTargetIndex(durs, 0, 14.1), 2);
      expect(TimelineMath.dragTargetIndex(durs, 0, 100), 2);
    });

    test('crossing the previous midpoint swaps left', () {
      // Dragging C (centre 14): B's midpoint is 12 - 8/2 = 8.
      expect(TimelineMath.dragTargetIndex(durs, 2, 8.1), 2);
      expect(TimelineMath.dragTargetIndex(durs, 2, 7.9), 1);
      // Past B, A's midpoint from C's new slot: 4 - 4/2 = 2.
      expect(TimelineMath.dragTargetIndex(durs, 2, 1.9), 0);
      expect(TimelineMath.dragTargetIndex(durs, 2, -50), 0);
    });

    test('middle clip walks both ways; bad index is a no-op', () {
      // B (centre 8) right past C's midpoint: 12 + 4/2 = 14.
      expect(TimelineMath.dragTargetIndex(durs, 1, 14.1), 2);
      // B left past A's midpoint: 4 - 4/2 = 2.
      expect(TimelineMath.dragTargetIndex(durs, 1, 1.9), 0);
      expect(TimelineMath.dragTargetIndex(durs, 5, 10), 5);
      expect(TimelineMath.dragTargetIndex(const [], 0, 10), 0);
    });
  });

  group('FfmpegService.exportDims — 4:5 is real end-to-end', () {
    test('4:5 dims follow the width-driven pattern', () {
      expect(FfmpegService.exportDims('4:5', 0), (720, 900));
      expect(FfmpegService.exportDims('4:5', 1), (1080, 1350));
      expect(FfmpegService.exportDims('4:5', 2), (2160, 2700));
    });

    test('existing ratios unchanged; unknown stays null', () {
      expect(FfmpegService.exportDims('9:16', 1), (1080, 1920));
      expect(FfmpegService.exportDims('16:9', 0), (1280, 720));
      expect(FfmpegService.exportDims('1:1', 2), (2160, 2160));
      expect(FfmpegService.exportDims('Original', 1), isNull);
    });
  });
}
