// TJ Pro v1.16.0 — FUNCTIONAL tests for the five groups:
//   G1 Full English conversion: the whole Guide is free of
//      Roman Urdu tokens, and the new English entries exist.
//   G2 Motion M3: the PIP window math (clamp / full / visible /
//      local time / drag) + the export filter gate (present only
//      when a window is set — the historical string otherwise).
//   G3 Timeline T7: A22 badge keys from real state, C3 label
//      clamp + palette, A23 model defaults + copy, the black
//      stand-in export command.
//   G4 Waveform + captions lane: the A18 caption span mapping
//      (timeline-relative vs per-clip, clamped).
//   G5 NS B7: the filmstrip frame-time math.
// Widget level: the VE rail carries the new Disable / Label
// tools, and the PIP lane segment renders for a motion handoff.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/fx_pack.dart';
import 'package:tj_pro/services/pro_editor.dart';
import 'package:tj_pro/video/video_editor_controller.dart';
import 'package:tj_pro/video/video_editor_screen.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';
import 'package:tj_pro/video/widgets/tool_rows.dart';
import 'package:tj_pro/widgets/tool_guide.dart';

/// A clip-row host with ONE real clip: only the members the row
/// builds from are real (clips / selected / busy + the Disable
/// action, which behaves exactly like the screen's: it flips
/// the selected clip's flag); everything else falls through
/// noSuchMethod and is never touched during build.
class _FakeClipRowHost extends VideoEditorController {
  @override
  void update(VoidCallback fn) => fn();

  @override
  BuildContext get context =>
      throw UnimplementedError('not used while building the row');

  @override
  List<VideoClip> clips = [
    VideoClip(File('/x.mp4'), const Duration(seconds: 6), 1.6),
  ];

  @override
  int selected = 0;

  @override
  bool busy = false;

  int disableTaps = 0;

  @override
  void toggleSelectedClipDisabled() {
    disableTaps++;
    clips[selected].disabled = !clips[selected].disabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void _mockPathProvider(String root) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => root,
  );
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------
  group('G1 — the Guide is fully English', () {
    // Unambiguous Roman Urdu tokens (none of these is an English
    // word the app uses; 'band'/'kam' style collisions excluded).
    const tokens = [
      'kar', 'karo', 'mein', 'hai', 'hain', 'nahi', 'apna', 'apni',
      'liye', 'wala', 'wali', 'hoga', 'jayega', 'chahiye', 'bhi',
      'aur', 'yeh', 'woh', 'karke', 'deta', 'sakta', 'raha', 'gaya',
      'pehle', 'baad', 'abhi', 'sirf', 'lekin', 'kyunki', 'idhar',
      'udhar', 'kaisa', 'kaisi', 'kitna', 'zyada', 'acha', 'theek',
      'bilkul', 'zaroor', 'shayad', 'lagta', 'hoti', 'hota', 'karte',
      'karta', 'milta', 'jata', 'aata', 'dekho', 'batao', 'chalo',
      'khol', 'dabao', 'lagao', 'hataye', 'badlo', 'rakho',
      'wapas', 'masla', 'banao', 'fasla',
    ];

    test('no Roman Urdu token in any guide entry', () {
      for (final e in kToolGuides.entries) {
        final text = [
          e.value.title,
          e.value.what,
          ...e.value.steps,
          ...e.value.tips,
        ].join('  ').toLowerCase();
        for (final t in tokens) {
          expect(
            RegExp('\\b$t\\b').hasMatch(text),
            isFalse,
            reason: '${e.key} still contains "$t"',
          );
        }
      }
    });

    test('the new English entries exist with English copy', () {
      expect(toolGuideFor('ve.disable')!.title, 'Disable');
      expect(toolGuideFor('ve.label'), isNotNull);
      final overlay = toolGuideFor('ve.overlay')!;
      expect(
        overlay.steps.join(' '),
        contains('PIP timing'),
      );
      final motion = toolGuideFor('motion')!;
      expect(motion.steps.join(' '), contains('Video Editor'));
      expect(motion.steps.join(' '), contains('PIP timing'));
    });
  });

  // ---------------------------------------------------------------
  group('G2 — PIP window math (M3)', () {
    test('defaults resolve to the full timeline', () {
      final w = TimelineMath.pipWindowClamp(start: 0, end: -1, totalDur: 30);
      expect(w.start, 0);
      expect(w.end, 30);
      expect(
        TimelineMath.pipWindowIsFull(start: 0, end: -1, totalDur: 30),
        isTrue,
      );
    });

    test('a stored window clamps inside the timeline', () {
      final w = TimelineMath.pipWindowClamp(start: 25, end: 99, totalDur: 30);
      expect(w.start, 25);
      expect(w.end, 30);
      final tiny =
          TimelineMath.pipWindowClamp(start: 29.99, end: 30, totalDur: 30);
      expect(tiny.end - tiny.start,
          greaterThanOrEqualTo(TimelineMath.pipMinWindowSec - 1e-9));
      expect(tiny.end, 30);
      expect(
        TimelineMath.pipWindowClamp(start: 0, end: -1, totalDur: 0).end,
        0,
      );
    });

    test('visibility is start-inclusive, end-exclusive', () {
      expect(TimelineMath.pipVisibleAt(t: 1.99, start: 2, end: 5), isFalse);
      expect(TimelineMath.pipVisibleAt(t: 2, start: 2, end: 5), isTrue);
      expect(TimelineMath.pipVisibleAt(t: 4.99, start: 2, end: 5), isTrue);
      expect(TimelineMath.pipVisibleAt(t: 5, start: 2, end: 5), isFalse);
    });

    test('the inset local time starts at the window and loops', () {
      expect(TimelineMath.pipLocalTime(t: 1, start: 2, pipDur: 3), 0);
      expect(TimelineMath.pipLocalTime(t: 2, start: 2, pipDur: 3), 0);
      expect(TimelineMath.pipLocalTime(t: 3.5, start: 2, pipDur: 3), 1.5);
      expect(TimelineMath.pipLocalTime(t: 8, start: 2, pipDur: 3), 0);
      expect(TimelineMath.pipLocalTime(t: 9, start: 2, pipDur: 3), 1);
      expect(TimelineMath.pipLocalTime(t: 9, start: 2, pipDur: 0), 0);
    });

    test('dragging moves the whole window, length preserved', () {
      final w = TimelineMath.pipWindowDragged(
          start: 4, end: 9, deltaSec: 3, totalDur: 20);
      expect(w.start, 7);
      expect(w.end, 12);
      final clamped = TimelineMath.pipWindowDragged(
          start: 4, end: 9, deltaSec: 100, totalDur: 20);
      expect(clamped.start, 15);
      expect(clamped.end, 20);
      final left = TimelineMath.pipWindowDragged(
          start: 4, end: 9, deltaSec: -100, totalDur: 20);
      expect(left.start, 0);
      expect(left.end, 5);
    });

    test('the export gate appears ONLY when a window is set', () {
      final plain = pipOverlayFilter(
        pipLabel: '[1:v]',
        position: PipPosition.bottomRight,
        pipScale: 0.3,
        margin: 16,
        outLabel: '[v]',
      );
      expect(plain.contains('enable='), isFalse);
      final gated = pipOverlayFilter(
        pipLabel: '[1:v]',
        position: PipPosition.bottomRight,
        pipScale: 0.3,
        margin: 16,
        outLabel: '[v]',
        windowEnable: 'between(t,2.000,5.500)',
      );
      expect(gated, contains(":enable='between(t,2.000,5.500)'"));
      // Apart from the gate the two graphs are identical.
      expect(gated.replaceAll(":enable='between(t,2.000,5.500)'", ''),
          plain);
    });

    test('the keyframed PIP filter gates the same way', () {
      const track = KeyframeTrack(
        start: ProKeyframe(timeSec: 0, xNorm: 0.5, yNorm: 0.5),
        end: ProKeyframe(timeSec: 4, xNorm: 0.6, yNorm: 0.5),
      );
      final plain = keyframedPipFilter(
        baseLabel: '[0:v]',
        pipLabel: '[1:v]',
        track: track,
        videoW: 1280,
        videoH: 720,
        pipW: 320,
        pipH: 180,
        outLabel: '[v]',
      );
      expect(plain.contains('enable='), isFalse);
      final gated = keyframedPipFilter(
        baseLabel: '[0:v]',
        pipLabel: '[1:v]',
        track: track,
        videoW: 1280,
        videoH: 720,
        pipW: 320,
        pipH: 180,
        outLabel: '[v]',
        windowEnable: 'between(t,1.000,4.000)',
      );
      expect(gated, contains('between(t,1.000,4.000)'));
    });
  });

  // ---------------------------------------------------------------
  group('G3 — badges, labels, disable (T7)', () {
    List<String> badges({
      bool isPhoto = false,
      bool muted = false,
      double volume = 1,
      double trimStart = 0,
      double trimEnd = -1,
      bool hasDetachedAudio = false,
      bool disabled = false,
    }) =>
        TimelineMath.clipBadgeKeys(
          isPhoto: isPhoto,
          muted: muted,
          volume: volume,
          trimStart: trimStart,
          trimEnd: trimEnd,
          hasDetachedAudio: hasDetachedAudio,
          disabled: disabled,
        );

    test('a plain clip shows no badges', () {
      expect(badges(), isEmpty);
    });

    test('badges come from real state, in order', () {
      expect(badges(muted: true), ['mute']);
      expect(badges(volume: 0.5), ['vol']);
      // Muted wins over the volume badge (a muted clip's gain is
      // not what the user hears).
      expect(badges(muted: true, volume: 0.5), ['mute']);
      expect(badges(trimStart: 1.2), ['trim']);
      expect(badges(trimEnd: 8), ['trim']);
      expect(badges(hasDetachedAudio: true), ['detach']);
      expect(badges(isPhoto: true), ['photo']);
      expect(
        badges(disabled: true, muted: true, trimStart: 2, isPhoto: true),
        ['off', 'mute', 'trim', 'photo'],
      );
    });

    test('labels clamp into the palette; 0 is none', () {
      expect(TimelineMath.clipLabelArgb.length, 7);
      expect(TimelineMath.clipLabelArgb[0], 0x00000000);
      expect(TimelineMath.clipLabelClamp(-3), 0);
      expect(TimelineMath.clipLabelClamp(4), 4);
      expect(TimelineMath.clipLabelClamp(99),
          TimelineMath.clipLabelArgb.length - 1);
    });

    test('VideoClip defaults keep old projects identical, and '
        'copy() carries the new fields', () {
      final c = VideoClip(File('/x.mp4'), const Duration(seconds: 8), 1.6);
      expect(c.disabled, isFalse);
      expect(c.colorLabel, 0);
      c.disabled = true;
      c.colorLabel = 3;
      final copy = c.copy();
      expect(copy.disabled, isTrue);
      expect(copy.colorLabel, 3);
    });

    test('the black stand-in command is exact-duration, black '
        'and silent', () {
      final cmd = FfmpegService.blackClipCommand(
        durationSec: 2.5,
        width: 1280,
        height: 720,
        fps: 30,
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains('color=c=black:s=1280x720:r=30'));
      expect(cmd, contains('anullsrc=channel_layout=stereo'));
      expect(cmd, contains('-t 2.500'));
      expect(cmd, contains('-c:a aac'));
      // A zero/negative duration can never reach ffmpeg.
      final zero = FfmpegService.blackClipCommand(
        durationSec: 0,
        width: 1280,
        height: 720,
        fps: 30,
        output: '/tmp/out.mp4',
      );
      expect(zero, contains('-t 0.100'));
    });
  });

  // ---------------------------------------------------------------
  group('G4 — caption lane spans (A18)', () {
    const segs = [(start: 1.0, end: 2.5), (start: 3.0, end: 4.0)];

    test('timeline-relative segments sit at their own times', () {
      final spans = TimelineMath.captionStripSpans(
        segments: segs,
        timelineRelative: true,
        selectedClipStart: 10,
        totalDur: 60,
      );
      expect(spans[0].start, 1.0);
      expect(spans[1].end, 4.0);
    });

    test('per-clip segments offset onto the selected clip', () {
      final spans = TimelineMath.captionStripSpans(
        segments: segs,
        timelineRelative: false,
        selectedClipStart: 10,
        totalDur: 60,
      );
      expect(spans[0].start, 11.0);
      expect(spans[0].end, 12.5);
      expect(spans[1].start, 13.0);
    });

    test('spans clamp to the timeline end', () {
      final spans = TimelineMath.captionStripSpans(
        segments: const [(start: 55.0, end: 70.0)],
        timelineRelative: false,
        selectedClipStart: 10,
        totalDur: 60,
      );
      expect(spans.single.start, 60.0);
      expect(spans.single.end, 60.0);
    });
  });

  // ---------------------------------------------------------------
  group('G5 — NS filmstrip frame times (B7)', () {
    test('a short clip gets a single mid frame', () {
      expect(nsStripFrameTimes(3), [1.5]);
      expect(nsStripFrameTimes(0), [0.5]);
    });

    test('longer clips get spread midpoints, capped at 6', () {
      final t = nsStripFrameTimes(20);
      expect(t.length, 5);
      expect(t.first, 2.0);
      expect(t.last, 18.0);
      final capped = nsStripFrameTimes(120);
      expect(capped.length, 6);
      expect(capped.first, 10.0);
      expect(capped.last, 110.0);
      // Strictly increasing, all inside the clip.
      for (var i = 1; i < capped.length; i++) {
        expect(capped[i] > capped[i - 1], isTrue);
      }
      expect(capped.every((x) => x > 0 && x < 120), isTrue);
    });
  });

  // ---------------------------------------------------------------
  group('Widget — VE rail + PIP lane', () {
    setUpAll(() {
      _mockPathProvider('/tmp/tj_pro_v1160');
      Directory('/tmp/tj_pro_v1160').createSync(recursive: true);
      // The motion handoff only lands when the file exists.
      File('/tmp/tj_pro_v1160/motion.mp4')
          .writeAsBytesSync(const [0, 1, 2, 3]);
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('the clip row carries Disable + Label, and Disable '
        'toggles the clip state end-to-end', (tester) async {
      final host = _FakeClipRowHost();
      Widget app() => MaterialApp(
            home: Scaffold(body: ClipToolRow(host)),
          );
      await tester.pumpWidget(app());
      await _frames(tester);
      expect(tester.takeException(), isNull);
      // The row is a lazy horizontal ListView: scroll the two
      // new items into the built range.
      await tester.scrollUntilVisible(find.text('Label'), 120);
      await _frames(tester);
      expect(find.text('Label'), findsOneWidget);
      final disable = find.text('Disable');
      await tester.scrollUntilVisible(disable, 120);
      await _frames(tester);
      expect(disable, findsOneWidget);
      await tester.ensureVisible(disable);
      await _frames(tester);
      await tester.tap(disable);
      await _frames(tester);
      // The action ran on the host and flipped the clip's state…
      expect(host.disableTaps, 1);
      expect(host.clips.single.disabled, isTrue);
      // …and a rebuilt row reflects it: the item now offers Enable.
      await tester.pumpWidget(app());
      await _frames(tester);
      await tester.scrollUntilVisible(find.text('Enable'), 120);
      await _frames(tester);
      expect(find.text('Enable'), findsOneWidget);
    });

    testWidgets('a motion handoff shows the PIP lane segment, '
        'and the window state round-trips through the controller',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: VideoEditorScreen(
            initialPipVideoPath: '/tmp/tj_pro_v1160/motion.mp4'),
      ));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pipWindowSeg')), findsOneWidget);
      final host = tester.state(find.byType(VideoEditorScreen))
          as VideoEditorController;
      expect(host.fxPip, isTrue);
      expect(host.pipStartSec, 0);
      expect(host.pipEndSec, -1);
      host.pipStartSec = 2.5;
      host.pipEndSec = 7;
      expect(host.pipStartSec, 2.5);
      expect(host.pipEndSec, 7);
    });
  });
}
