// v1.12 A1 + A2 — FUNCTIONAL tests for VE Timeline Markers and
// VE Captions SRT/VTT import/export.
//
// A1: beat times come out of detection as SOURCE-FILE seconds;
// these tests pin the mapping onto timeline seconds (music =
// identity, clip = clipStart + (beat - trimStart), beats outside
// the used trim range dropped), the trim-handle file-domain
// conversion, and the snap behaviour (a marker is a snap target
// within the threshold and ignored outside it).
//
// A2: SRT/VTT parsing (header, cue identifiers, cue settings,
// NOTE blocks, short MM:SS.mmm times, Urdu text) and the
// export → import round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/caption_service.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';

void main() {
  group('A1 beatsToTimeline — the time-base mapping', () {
    test('music source: beats are already timeline seconds', () {
      final out = TimelineMath.beatsToTimeline(
        beats: const [0.5, 1.25, 60.0],
        sourceIsMusic: true,
        sourceClipIndex: -1,
        clipStarts: const [0, 10],
        trimStarts: const [0, 2],
        effectiveDurations: const [10, 5],
      );
      expect(out, [0.5, 1.25, 60.0]);
    });

    test('clip source: clipStart + (beat - trimStart), trim window only',
        () {
      // Clip 1 starts at timeline 10s, uses file seconds [2, 7]
      // (trimStart 2, effective 5s). Beats are FILE seconds.
      final out = TimelineMath.beatsToTimeline(
        beats: const [1.0, 2.0, 2.5, 4.0, 7.0, 9.0],
        sourceIsMusic: false,
        sourceClipIndex: 1,
        clipStarts: const [0, 10],
        trimStarts: const [0, 2],
        effectiveDurations: const [10, 5],
      );
      // 1.0 and 9.0 are trimmed-away content — dropped.
      // 2.0 -> 10.0 (the used range's first frame),
      // 2.5 -> 10.5, 4.0 -> 12.0, 7.0 -> 15.0 (last frame).
      expect(out, [10.0, 10.5, 12.0, 15.0]);
    });

    test('clip source gone (index -1 / out of range): no ticks', () {
      final out = TimelineMath.beatsToTimeline(
        beats: const [1.0, 2.0],
        sourceIsMusic: false,
        sourceClipIndex: -1,
        clipStarts: const [0],
        trimStarts: const [0],
        effectiveDurations: const [10],
      );
      expect(out, isEmpty);
    });

    test('no beats: empty', () {
      final out = TimelineMath.beatsToTimeline(
        beats: const [],
        sourceIsMusic: true,
        sourceClipIndex: -1,
        clipStarts: const [],
        trimStarts: const [],
        effectiveDurations: const [],
      );
      expect(out, isEmpty);
    });
  });

  group('A1 markers as snap targets', () {
    test('playhead within threshold lands exactly on the marker', () {
      // The resting-playhead / Split snap: threshold 0.15.
      final points = [...TimelineMath.boundaries(const [10, 5]), 12.0];
      expect(TimelineMath.snapSec(12.12, points, 0.15), 12.0);
      expect(TimelineMath.snapSec(11.9, points, 0.15), 12.0);
    });

    test('playhead outside threshold ignores the marker', () {
      final points = [...TimelineMath.boundaries(const [10, 5]), 12.0];
      expect(TimelineMath.snapSec(12.4, points, 0.15), 12.4);
      expect(TimelineMath.snapSec(11.5, points, 0.15), 11.5);
    });

    test('trim conversion: timeline points inside the clip become '
        'file-second targets, and the handle lands on them', () {
      // Clip at timeline [10, 15], trimStart 2 (file domain).
      final filePoints = TimelineMath.trimSnapFilePoints(
        clipStart: 10,
        trimStart: 2,
        effectiveDuration: 5,
        timelinePoints: const [10.5, 12.0, 30.0],
      );
      // 30.0 belongs to another clip — dropped.
      expect(filePoints, [2.5, 4.0]);
      // The trim snap (threshold 0.08, the handles' own): a drag
      // ending at file 4.05 lands exactly on the marker's frame.
      expect(
        TimelineMath.snapSec(4.05, [0.0, ...filePoints], 0.08),
        4.0,
      );
      // Outside the trim threshold the marker is ignored.
      expect(
        TimelineMath.snapSec(4.3, [0.0, ...filePoints], 0.08),
        4.3,
      );
    });
  });

  group('A2 SRT import', () {
    test('parses a sample file into the expected segments', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:03,500\n'
          'Pehli line\n'
          '\n'
          '2\n'
          '00:00:04,000 --> 00:00:06,250\n'
          'Dusri line\n'
          'doosri satar\n'
          '\n'
          '3\n'
          '00:01:00,000 --> 00:01:02,000\n'
          'آخری اردو لائن\n';
      final segs = CaptionService.parseSrt(srt);
      expect(segs.length, 3);
      expect(segs[0].text, 'Pehli line');
      expect(segs[0].start, 1.0);
      expect(segs[0].end, 3.5);
      expect(segs[1].text, 'Dusri line\ndoosri satar');
      expect(segs[1].start, 4.0);
      expect(segs[1].end, 6.25);
      expect(segs[2].start, 60.0);
      expect(segs[2].end, 62.0);
    });

    test('parseSubtitle dispatches SRT content to the SRT parser', () {
      const srt = '1\n00:00:00,500 --> 00:00:02,000\nHello\n';
      final segs = CaptionService.parseSubtitle(srt);
      expect(segs.length, 1);
      expect(segs.single.start, 0.5);
    });
  });

  group('A2 VTT import', () {
    test('header, NOTE, cue ids, settings and short times handled', () {
      const vtt = 'WEBVTT - test file\n'
          '\n'
          'NOTE this is a comment block\n'
          'spanning two lines\n'
          '\n'
          'cue-1\n'
          '00:01.000 --> 00:04.000 position:50%,center\n'
          'Pehla cue\n'
          '\n'
          '00:00:05.500 --> 00:00:08.000 align:start\n'
          'Dusra cue\n'
          'urdu متن یہاں\n'
          '\n'
          '1:02:03.250 --> 1:02:05.000\n'
          'Lamba waqt wala cue\n';
      final segs = CaptionService.parseVtt(vtt);
      expect(segs.length, 3);
      expect(segs[0].text, 'Pehla cue');
      expect(segs[0].start, 1.0);
      expect(segs[0].end, 4.0);
      expect(segs[1].start, 5.5);
      expect(segs[1].end, 8.0);
      expect(segs[1].text, contains('urdu'));
      expect(segs[2].start, 3723.25);
      expect(segs[2].end, 3725.0);
    });

    test('parseSubtitle dispatches WEBVTT content to the VTT parser', () {
      const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n';
      final segs = CaptionService.parseSubtitle(vtt);
      expect(segs.length, 1);
      expect(segs.single.text, 'Hi');
    });

    test('garbage yields no segments (import must change nothing)', () {
      expect(CaptionService.parseSubtitle('not a subtitle file'), isEmpty);
      expect(CaptionService.parseVtt('WEBVTT\n\nno cues here'), isEmpty);
    });
  });

  group('A2 export round-trip', () {
    final segments = [
      CaptionSegment('Pehli line', 1.0, 3.5),
      CaptionSegment('Dusri line\ndo satar', 4.25, 6.0),
      CaptionSegment('اردو لائن', 60.0, 62.5),
    ];

    test('segments -> buildSrt -> parseSrt returns equivalents', () {
      final back = CaptionService.parseSrt(CaptionService.buildSrt(segments));
      expect(back.length, segments.length);
      for (var i = 0; i < segments.length; i++) {
        expect(back[i].text, segments[i].text);
        expect(back[i].start, closeTo(segments[i].start, 0.001));
        expect(back[i].end, closeTo(segments[i].end, 0.001));
      }
    });

    test('buildVtt carries the WEBVTT header and round-trips', () {
      final vtt = CaptionService.buildVtt(segments);
      expect(vtt.startsWith('WEBVTT'), isTrue);
      final back = CaptionService.parseVtt(vtt);
      expect(back.length, segments.length);
      for (var i = 0; i < segments.length; i++) {
        expect(back[i].text, segments[i].text);
        expect(back[i].start, closeTo(segments[i].start, 0.001));
        expect(back[i].end, closeTo(segments[i].end, 0.001));
      }
    });
  });
}
