// TJ Pro v1.15.0 — FUNCTIONAL regression tests for the five
// groups (user phone-test points #29–#32 + the Split diagnosis
// + Timeline T5):
//   G1 Split: strip geometry pin (line x == centre-second x at
//      several zooms), the transport readout never truncates.
//      (resolveSplit's mode/refusal semantics are pinned in
//      tools_fix_wave_test.dart's P0-2 group.)
//   G2 Panel nizam: VE — a tool open hides the timeline and the
//      stage GROWS; the drill-down swaps sections in one line
//      (PIP + Precut). NS — the existing collapse model pinned
//      (preview size invariant, dock stays). Photo — the toolbar
//      ⇄ panel swap pinned.
//   G3 Overflow: VE keyboard panels with a simulated keyboard
//      inset — no render exception (Point #31).
//   G4 Home: the "Works offline…" block is gone (Point #30).
//   G5 NS T5: markers model (JSON round-trip + old-JSON load),
//      nsDragTrimmed math, lane controls, markers UI, drag
//      reorder end-to-end.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/photo/photo_editor_screen.dart';
import 'package:tj_pro/video/video_editor_panels.dart';
import 'package:tj_pro/video/video_editor_screen.dart';
import 'package:tj_pro/video/widgets/editor_stage.dart';
import 'package:tj_pro/video/widgets/panel_controls.dart';
import 'package:tj_pro/video/widgets/timeline_bar.dart';
import 'package:tj_pro/video/widgets/tool_rows.dart';
import 'package:tj_pro/video/widgets/transport_row.dart';

void _mockPathProvider(String dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir;
      if (call.method == 'getTemporaryDirectory') return '${dir}_tmp';
      return null;
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void _noError(WidgetTester tester, String what) {
  final e = tester.takeException();
  expect(e, isNull, reason: 'render exception in $what: $e');
}

/// Opens a Video Editor tool from the main row (dragging the
/// rail until the label is built), like panel_overflow_test.
/// The finder is scoped to the MainToolRow: a bare find.text
/// also matches same-named labels elsewhere on the screen
/// (the probe that found this tapped the wrong 'Text').
Future<void> _openVeTool(WidgetTester tester, String label) async {
  final target = find.descendant(
    of: find.byType(MainToolRow),
    matching: find.text(label),
  );
  for (var i = 0; i < 14 && target.evaluate().isEmpty; i++) {
    for (final rail in find.byType(ListView).evaluate()) {
      await tester.drag(find.byWidget(rail.widget), const Offset(-240, 0));
    }
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsWidgets, reason: 'VE tool $label not found');
  // The rail item can sit half off-screen — tapping then misses.
  await tester.ensureVisible(target.first);
  await _frames(tester);
  await tester.tap(target.first);
  await _frames(tester);
}

Future<void> _pumpVe(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: VideoEditorScreen()));
  await _frames(tester);
  _noError(tester, 'VE initial build');
}

void main() {
  setUpAll(() {
    _mockPathProvider('/tmp/tj_pro_v1150');
    Directory('/tmp/tj_pro_v1150').createSync(recursive: true);
    Directory('/tmp/tj_pro_v1150_tmp').createSync(recursive: true);
    // Tiny real PNGs: the Photo Editor image + the Maker's two
    // photo clips (photo clips skip the video duration probe).
    const png = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    File('/tmp/tj_pro_v1150/pixel.png').writeAsBytesSync(png);
    File('/tmp/tj_pro_v1150/a.png').writeAsBytesSync(png);
    File('/tmp/tj_pro_v1150/b.png').writeAsBytesSync(png);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------
  group('G1 — strip geometry (the 26px Split bug)', () {
    test('halfPad == lineX, and content x of the centre second '
        'lands exactly on the line at every zoom', () {
      for (final w in [360.0, 393.0, 412.0, 800.0]) {
        // The invariant the bug broke: padding and line agree.
        expect(TimelineMath.stripHalfPad(w), TimelineMath.stripLineX(w));
        // …and the padding is exactly 26px more than the old,
        // wrong formula (maxWidth/2 − 52).
        expect(TimelineMath.stripHalfPad(w) - (w / 2 - 52), 26.0);
        for (final pps in [12.0, 42.0, 120.0]) {
          for (final sec in [0.0, 5.0, 37.5, 120.0]) {
            // Scrolled so [sec] is centred: offset = sec × pps.
            // Its drawn x relative to the viewport must be the
            // line's x — zero error, not 26px.
            final drawn = TimelineMath.stripContentX(w, sec, pps) - sec * pps;
            expect(drawn, TimelineMath.stripLineX(w),
                reason: 'w=$w pps=$pps sec=$sec');
          }
        }
      }
    });

    testWidgets('the drawn playhead line sits at the strip centre',
        (tester) async {
      await _pumpVe(tester, const Size(393, 852));
      final bar = find.byType(TimelineBar);
      expect(bar, findsOneWidget);
      final barRect = tester.getRect(bar);
      final lines = find.byWidgetPredicate((w) =>
          w is Container && w.color == const Color(0xFFFFD60A));
      expect(lines, findsWidgets);
      Rect? lineRect;
      for (final e in lines.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        if ((r.width - 2).abs() < 0.6 && r.height > 40) lineRect = r;
      }
      expect(lineRect, isNotNull,
          reason: 'the 2px gold playhead line was not found');
      final expected =
          barRect.left + 52 + TimelineMath.stripLineX(barRect.width);
      expect(lineRect!.left, closeTo(expected, 1.6));
    });

    testWidgets('transport readout never ellipsizes (G1.6)',
        (tester) async {
      await _pumpVe(tester, const Size(360, 640));
      final timeFinder = find.byKey(const Key('tpTimeText'));
      expect(timeFinder, findsOneWidget);
      final text = tester.widget<Text>(timeFinder);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.softWrap, isFalse);
      expect(
        find.ancestor(of: timeFinder, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tlTimeCentre')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------
  group('G4 — Home text block removed (Point #30)', () {
    testWidgets('no "Works offline" paragraph anywhere on Home',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _frames(tester);
      _noError(tester, 'Home initial build');
      expect(find.textContaining('Works offline'), findsNothing);
      expect(find.textContaining('No account, no uploads'), findsNothing);
      // Scroll the whole list — the block must not be hiding
      // below the fold either; neighbours must still exist.
      for (var i = 0; i < 4; i++) {
        await tester.drag(
            find.byType(ListView).first, const Offset(0, -500));
        await _frames(tester);
        expect(find.textContaining('Works offline'), findsNothing);
      }
      expect(find.text('About'), findsWidgets);
      _noError(tester, 'Home after scrolling');
    });
  });

  // ---------------------------------------------------------------
  group('G2 — splitPanelSections (pure)', () {
    test('splits on SectionTitles and consumes the titles', () {
      final sections = splitPanelSections([
        SectionTitle('A'),
        const Text('1'),
        SectionTitle('B'),
        const Text('2'),
        const Text('3'),
      ]);
      expect(sections.length, 2);
      expect(sections[0].title, 'A');
      expect(sections[0].children.length, 1);
      expect(sections[1].title, 'B');
      expect(sections[1].children.length, 2);
    });

    test('unwraps a lone PanelColumn', () {
      final sections = splitPanelSections([
        PanelColumn(children: [
          SectionTitle('A'),
          const Text('1'),
          SectionTitle('B'),
          const Text('2'),
        ]),
      ]);
      expect(sections.map((s) => s.title), ['A', 'B']);
    });

    test('no titles → a single Main section (no drill)', () {
      final sections = splitPanelSections([const Text('x')]);
      expect(sections.length, 1);
      expect(PanelDrillDown.appliesTo([const Text('x')]), isFalse);
    });

    test('preamble content becomes the Main section', () {
      final sections = splitPanelSections([
        const Text('intro'),
        SectionTitle('A'),
        const Text('1'),
      ]);
      expect(sections.map((s) => s.title), ['Main', 'A']);
    });

    test('section icons resolve', () {
      expect(panelSectionIcon('Mask'), Icons.crop_square);
      expect(panelSectionIcon('PIP style'), Icons.text_format);
      expect(panelSectionIcon('Kuch bhi'), Icons.tune);
    });
  });

  // ---------------------------------------------------------------
  group('G2 — VE panel nizam (Points #29 + #32)', () {
    testWidgets('tool open: timeline hides, the stage GROWS',
        (tester) async {
      await _pumpVe(tester, const Size(393, 852));
      expect(find.byType(TimelineBar), findsOneWidget);
      final transportTopBefore =
          tester.getTopLeft(find.byType(TransportRow)).dy;

      await _openVeTool(tester, 'Text');
      expect(
          find.byKey(const Key('video-panel-text')), findsOneWidget);
      // Point #32: the timeline is GONE while the panel is open…
      expect(find.byType(TimelineBar), findsNothing);
      // …and the freed height went to the stage: the transport
      // row (directly under the stage) sits LOWER than before.
      final transportTopAfter =
          tester.getTopLeft(find.byType(TransportRow)).dy;
      expect(transportTopAfter, greaterThan(transportTopBefore + 10),
          reason: 'stage did not grow when the timeline hid');
      _noError(tester, 'VE Text panel open');

      // Closing the panel brings the timeline back.
      await tester.tap(find.byTooltip('Apply').first);
      await _frames(tester);
      expect(find.byType(TimelineBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Precut drill: sections swap in one line',
        (tester) async {
      await _pumpVe(tester, const Size(393, 852));
      await _openVeTool(tester, 'Precut');
      // The Trim body has 6 sections → the drill rail shows.
      expect(find.byKey(const Key('panelDrillDown')), findsOneWidget);
      // First section (Trim selected clip) is showing; the Trim
      // mode chips live in the SECOND section — not built yet.
      expect(find.byKey(const Key('trimModeRoll')), findsNothing);
      await tester.tap(find.text('Trim mode'));
      await _frames(tester);
      expect(find.byKey(const Key('trimModeRoll')), findsOneWidget);
      _noError(tester, 'Precut drill swap');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('PIP drill: the user\'s own example (Point #29)',
        (tester) async {
      await _pumpVe(tester, const Size(393, 852));
      await _openVeTool(tester, 'PIP');
      // Sub-tabs in ONE line: Sticker / Keyframes / PIP (scoped
      // to the tab row — the panel header may carry the same
      // word).
      final pipTab = find.descendant(
        of: find.byType(PanelTabRow),
        matching: find.text('PIP'),
      );
      expect(pipTab, findsOneWidget);
      await tester.tap(pipTab);
      await _frames(tester);
      // Turn the PIP overlay on — its body gains sections.
      final sw = find.widgetWithText(SwitchListTile, 'PIP video overlay');
      expect(sw, findsOneWidget);
      await tester.tap(sw);
      await _frames(tester);
      expect(find.byKey(const Key('panelDrillDown')), findsOneWidget);
      // Section chips in the line; first section is showing.
      expect(find.text('PIP position'), findsOneWidget);
      expect(find.text('PIP video overlay'), findsOneWidget);
      // Swap to the Position section: only its controls show.
      await tester.tap(find.text('PIP position'));
      await _frames(tester);
      expect(find.text('topLeft'), findsOneWidget);
      expect(find.text('PIP video overlay'), findsNothing);
      _noError(tester, 'PIP drill swap');
      await tester.pump(const Duration(seconds: 10));
    });
  });

  // ---------------------------------------------------------------
  group('G3 — keyboard overflow (Point #31)', () {
    // The user's flow: a panel is open, THEN the keyboard comes
    // up (every VE keyboard lives inside a panel). Before the
    // fix this painted "BOTTOM OVERFLOWED BY 111 PIXELS" — the
    // fixed chrome (top bar + transport + TIMELINE + panel)
    // exceeded the keyboard-shrunk body. With the timeline
    // hidden (Point #32) the panel state fits at both sizes.
    Future<void> keyboardCase(
        WidgetTester tester, Size size, double inset) async {
      await _pumpVe(tester, size);
      await _openVeTool(tester, 'Text');
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      await _frames(tester);
      _noError(tester, 'Text panel with keyboard at $size');
      // Titles + Captions tabs carry text fields too.
      for (final tab in ['Titles', 'Captions']) {
        final t = find.text(tab);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await _frames(tester);
          _noError(tester, '$tab tab with keyboard at $size');
        }
      }
      // Keyboard down, panel still open, then panel closes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 0);
      await tester.pump();
      await _frames(tester);
      _noError(tester, 'keyboard dismissed at $size');
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('360x640 with a 280px keyboard: no overflow',
        (tester) async {
      await keyboardCase(tester, const Size(360, 640), 280);
    });

    testWidgets('393x852 with a 300px keyboard: no overflow',
        (tester) async {
      await keyboardCase(tester, const Size(393, 852), 300);
    });

    testWidgets('keyboard up with NO panel at 393x852 (the '
        'close-panel transient on a real-size phone)', (tester) async {
      await _pumpVe(tester, const Size(393, 852));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await _frames(tester);
      _noError(tester, 'no-panel keyboard transient at 393x852');
      await tester.pump(const Duration(seconds: 10));
    });
  });

  // ---------------------------------------------------------------
  group('G2 — NS + Photo models pinned', () {
    Future<void> pumpMaker(WidgetTester tester, NewsProject project) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await _frames(tester);
      _noError(tester, 'Maker initial build');
    }

    testWidgets('NS: tool open collapses the timeline, preview '
        'size unchanged, dock stays', (tester) async {
      final project = NewsProject.create()
        ..clipPaths = [
          '/tmp/tj_pro_v1150/a.png',
          '/tmp/tj_pro_v1150/b.png',
        ];
      await pumpMaker(tester, project);
      final zone = find.byKey(const Key('makerLowerZone'));
      expect(zone, findsOneWidget);
      expect(find.byKey(const Key('tlClip-0')), findsOneWidget);
      final topBefore = tester.getTopLeft(zone).dy;
      final heightBefore = tester.getSize(zone).height;

      // Open the Media tool from the dock.
      final target = find.byKey(const Key('makerTool-media'));
      for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byKey(const Key('makerToolLine')),
          const Offset(-240, 0),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(target);
      await _frames(tester);
      expect(find.byKey(const Key('makerPanel-media')), findsOneWidget);
      // Timeline collapsed away…
      expect(find.byKey(const Key('tlClip-0')), findsNothing);
      expect(find.byKey(const Key('tlPlayPause')), findsNothing);
      // …preview size invariant (Point #27)…
      expect(tester.getTopLeft(zone).dy, closeTo(topBefore, 0.5));
      expect(tester.getSize(zone).height, closeTo(heightBefore, 0.5));
      // …and the dock is still at the bottom (siblings hidden
      // behind the one open panel, per Point #29's model).
      expect(find.byKey(const Key('makerToolLine')), findsOneWidget);
      _noError(tester, 'Maker media panel open');
    });

    testWidgets('Photo: toolbar swaps to the one panel (Point #29 '
        'model)', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: PhotoEditorScreen(
              initialImagePath: '/tmp/tj_pro_v1150/pixel.png',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await _frames(tester);
      _noError(tester, 'Photo initial build');
      expect(find.text('Canvas'), findsWidgets);
      final textTool = find.text('Text');
      for (var i = 0; i < 14 && textTool.evaluate().isEmpty; i++) {
        for (final rail in find.byType(ListView).evaluate()) {
          await tester.drag(
              find.byWidget(rail.widget), const Offset(-240, 0));
        }
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(textTool, findsWidgets, reason: 'Photo Text tool not found');
      await tester.ensureVisible(textTool.first);
      await _frames(tester);
      await tester.tap(textTool.first);
      await _frames(tester);
      // The panel replaced the toolbar (siblings hidden)…
      expect(find.byKey(const Key('photo-panel-text')), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      // …and its sub-tabs drill inside (TextZone): tapping Font
      // shows only the font sub-panel, no error.
      final font = find.text('Font');
      if (font.evaluate().isNotEmpty) {
        await tester.tap(font.first);
        await _frames(tester);
      }
      _noError(tester, 'Photo Text panel');
      await tester.pump(const Duration(seconds: 6));
    });
  });

  // ---------------------------------------------------------------
  group('G5 — NS markers model (B9)', () {
    test('normalise: sorted, deduped, negatives dropped', () {
      final p = NewsProject(id: 'x', timelineMarkers: [5, 1, 1.02, -3, 2.5]);
      expect(p.timelineMarkers, [1.0, 2.5, 5.0]);
    });

    test('toggle adds, then removes within 0.1 s', () {
      var m = NewsProject.toggledTimelineMarkers(const [], 3.0);
      expect(m, [3.0]);
      m = NewsProject.toggledTimelineMarkers(m, 3.05);
      expect(m, isEmpty);
      m = NewsProject.toggledTimelineMarkers(const [1.0, 9.0], 5.0);
      expect(m, [1.0, 5.0, 9.0]);
    });

    test('JSON round-trip keeps markers; OLD json loads empty', () {
      final p = NewsProject.create()..timelineMarkers = [2.0, 7.5];
      final back = NewsProject.fromJson(p.toJson());
      expect(back.timelineMarkers, [2.0, 7.5]);
      final oldJson = p.toJson()..remove('timelineMarkers');
      expect(NewsProject.fromJson(oldJson).timelineMarkers, isEmpty);
      // Malformed entries are skipped, never fatal.
      final badJson = p.toJson()
        ..['timelineMarkers'] = ['x', 4, null];
      expect(NewsProject.fromJson(badJson).timelineMarkers, [4.0]);
    });

    test('copyWith preserves markers unless replaced', () {
      final p = NewsProject.create()..timelineMarkers = [1.0];
      expect(p.copyWith().timelineMarkers, [1.0]);
      expect(
          p.copyWith(timelineMarkers: [9.0]).timelineMarkers, [9.0]);
    });
  });

  group('G5 — nsDragTrimmed math (B3)', () {
    test('right edge: shrink sets an end; growing back to the '
        'file end restores the full range', () {
      var t = nsDragTrimmed(ClipTrim.full, 20, false, -5);
      expect(t.endSec, 15.0);
      t = nsDragTrimmed(t, 20, false, 10);
      expect(t.endSec, isNull); // full range again
      expect(t.isFullRange, isTrue);
    });

    test('right edge clamps at start + 0.3', () {
      final t = nsDragTrimmed(
          const ClipTrim(startSec: 10, endSec: 12), 20, false, -5);
      expect(t.endSec, closeTo(10.3, 1e-9));
    });

    test('left edge moves the start; clamps at 0 and end − 0.3',
        () {
      var t = nsDragTrimmed(ClipTrim.full, 20, true, 5);
      expect(t.startSec, 5.0);
      t = nsDragTrimmed(ClipTrim.full, 20, true, -10);
      expect(t.startSec, 0.0);
      t = nsDragTrimmed(
          const ClipTrim(startSec: 0, endSec: 8), 20, true, 10);
      expect(t.startSec, closeTo(7.7, 1e-9));
    });
  });

  group('G5 — Maker timeline haath ka kaam (widget)', () {
    Future<NewsProject> pumpMaker2(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final project = NewsProject.create()
        ..clipPaths = [
          '/tmp/tj_pro_v1150/a.png',
          '/tmp/tj_pro_v1150/b.png',
        ]
        ..clipTrims = [
          const ClipTrim(startSec: 1),
          ClipTrim.full,
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await _frames(tester);
      _noError(tester, 'Maker (2 clips) initial build');
      return project;
    }

    testWidgets('trim handles sit on the SELECTED clip only; a '
        'drag without a probed duration changes nothing', (tester) async {
      final project = await pumpMaker2(tester);
      expect(find.byKey(const Key('nsTrimL-0')), findsOneWidget);
      expect(find.byKey(const Key('nsTrimR-0')), findsOneWidget);
      expect(find.byKey(const Key('nsTrimL-1')), findsNothing);
      // Photo clips have no probed file duration — the honest
      // gate: dragging must not invent a trim.
      await tester.drag(
          find.byKey(const Key('nsTrimR-0')), const Offset(60, 0));
      await _frames(tester);
      expect(project.clipTrims[0].startSec, 1.0);
      expect(project.clipTrims[0].endSec, isNull);
      _noError(tester, 'trim handle drag (unprobed)');
    });

    testWidgets('marker add at the playhead, tap removes it',
        (tester) async {
      final project = await pumpMaker2(tester);
      expect(project.timelineMarkers, isEmpty);
      await tester.tap(find.byKey(const Key('nsMarkerAdd')));
      await _frames(tester);
      expect(project.timelineMarkers, [0.0]);
      expect(find.byKey(const Key('nsMarker-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nsMarker-0')));
      await _frames(tester);
      expect(project.timelineMarkers, isEmpty);
      _noError(tester, 'marker toggle');
    });

    testWidgets('lane eye hides and restores the V1 lane (B10)',
        (tester) async {
      await pumpMaker2(tester);
      expect(find.byKey(const Key('tlClip-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nsLaneEye-v1')));
      await _frames(tester);
      expect(find.byKey(const Key('tlClip-0')), findsNothing);
      await tester.tap(find.byKey(const Key('nsLaneEye-v1')));
      await _frames(tester);
      expect(find.byKey(const Key('tlClip-0')), findsOneWidget);
      _noError(tester, 'lane eye toggle');
    });

    testWidgets('A2 mute is the real export switch (B10)',
        (tester) async {
      final project = await pumpMaker2(tester);
      expect(project.voiceMusicEnabled, isTrue);
      await tester.tap(find.byKey(const Key('nsLaneMute-a2')));
      await _frames(tester);
      expect(project.voiceMusicEnabled, isFalse);
      await tester.tap(find.byKey(const Key('nsLaneMute-a2')));
      await _frames(tester);
      expect(project.voiceMusicEnabled, isTrue);
      _noError(tester, 'A2 mute toggle');
    });

    testWidgets('long-press drag reorders clips, trims travel '
        'with their clip (B4)', (tester) async {
      final project = await pumpMaker2(tester);
      final block = find.byKey(const Key('tlClip-0'));
      expect(block, findsOneWidget);
      final centre = tester.getCenter(block);
      final gesture = await tester.startGesture(centre);
      // Hold past the long-press timeout, then drag right past
      // the second clip's centre in steps.
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await _frames(tester);
      expect(project.clipPaths, [
        '/tmp/tj_pro_v1150/b.png',
        '/tmp/tj_pro_v1150/a.png',
      ]);
      // The (path, trim) pairs moved together: a.png kept its
      // startSec 1 trim, now at index 1.
      expect(project.clipTrims[0].isFullRange, isTrue);
      expect(project.clipTrims[1].startSec, 1.0);
      _noError(tester, 'drag reorder');
    });
  });
}
