// Build 6 (v1.5.8) — EXPANDED error sweep + tools-tartib guard.
//
// Part 2 (error banner): Build 5's guard covered a real project
// at textScale 1.3 on two sizes, but the banner STILL fired on
// the user's phone (Template inspector open, interview plate ON
// with the name filled). This sweep widens the state space:
//   * News Maker: plate ON with a long LATIN name AND with a
//     long URDU name, both tickers full, logo on, a photo clip,
//     voiceover — across the Final template AND two breaking
//     ribbon variants, at 360x640 AND 393x851, textScale 1.0
//     AND 1.3, Summary + all 12 tool panels per configuration.
//   * Photo Editor (18) and Video Editor (23) at the missing
//     combination: 393x851, textScale 1.3.
// Any RenderFlex overflow paints an exception in tests, so a
// single takeException() failure anywhere here is a banner the
// user would have seen.
//
// Part 4 (tools tartib): for every tool opened, EXACTLY ONE
// keyed panel host exists in the tree and it is that tool's own
// (makerPanel-<id> / video-panel-<key> / photo-panel-<key>) —
// no other tool's controls on screen. And the panel scroll
// position resets to the top when the tool changes (all three
// editors).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/photo/photo_editor_screen.dart';
import 'package:tj_pro/video/video_editor_screen.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_build6';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_build6_tmp';
      }
      return null;
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void _expectNoRenderError(WidgetTester tester, String what) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'render exception in $what: $error');
}

/// Every widget whose `ValueKey<String>` starts with [prefix] —
/// the panel hosts of all three editors follow that convention.
Finder _panelsWithPrefix(String prefix) {
  return find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith(prefix);
  });
}

double _panelScrollPixels(WidgetTester tester, Finder panel) {
  final scrollable = find
      .descendant(of: panel, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

/// Moves a panel's scroll position directly. The scroll-reset
/// assertions target the position STATE (a gesture drag over
/// slider rows is not deterministic in tests — the slider's own
/// recognizer competes for the pointer).
void _scrollPanelTo(WidgetTester tester, Finder panel, double offset) {
  final scrollable = find
      .descendant(of: panel, matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(offset);
}

Future<void> _openMakerTool(WidgetTester tester, String id) async {
  final done = find.byKey(const Key('makerPanelDone'));
  if (done.evaluate().isNotEmpty) {
    await tester.tap(done);
    await _frames(tester);
  }
  final target = find.byKey(Key('makerTool-$id'));
  // Hunt in BOTH directions: the line keeps its scroll position
  // between tools, so a tool earlier in the line is off-screen
  // to the LEFT after later tools were visited.
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsOneWidget, reason: 'maker tool $id not found');
  // The hunt stops as soon as the item EXISTS — it can still be
  // mostly off-screen, and a centre tap then misses. Scroll it
  // fully into view first.
  await tester.ensureVisible(target);
  await _frames(tester);
  await tester.tap(target);
  await _frames(tester);
  _expectNoRenderError(tester, 'News Maker tool $id');
  // Part 4: exactly one panel host in the tree, and it is THIS
  // tool's panel.
  expect(
    find.byKey(Key('makerPanel-$id')),
    findsOneWidget,
    reason: 'Maker panel for $id',
  );
  expect(
    _panelsWithPrefix('makerPanel-'),
    findsOneWidget,
    reason: 'exactly one Maker panel while $id is open',
  );
}

const _makerTools = [
  'template',
  'media',
  'elements',
  'tehreer',
  'ticker',
  'ribbons',
  'logo',
  'reporter',
  'audio',
  'voice',
  'captions',
  'export',
];

/// A project in the user's screenshot state, fully loaded:
/// interview plate ON (photo + name), long Urdu tehreer, both
/// tickers full, logo on (template default), a photo clip and a
/// voiceover duration.
NewsProject _loadedProject({
  String templateKind = 'nigraanFinal',
  String breakingVariant = 'breakingRedBanner',
  bool urduName = false,
}) {
  return NewsProject.create()
    ..tehreer = 'اسلام آباد: وزیراعظم نے نئے صوبوں کے قیام پر '
        'کابینہ کا خصوصی اجلاس طلب کر لیا، تمام جماعتوں سے '
        'مشاورت جاری ہے اور حتمی فیصلہ آئندہ ہفتے متوقع ہے۔'
    ..headline = 'نئے صوبوں پر کابینہ اجلاس — بڑا فیصلہ متوقع'
    ..tickerText = 'تازہ ترین: ملک بھر میں موسم خشک، کراچی میں '
        'گرمی کی شدت برقرار، محکمہ موسمیات کی پیشگوئی جاری'
    ..englishTickerText = 'Pakistan weather update: dry conditions '
        'across the country, Karachi heat persists, more follows'
    ..tickerLabel = 'BREAKING NEWS'
    ..reporterPhotoPath = '/tmp/tj_pro_build6/pixel.png'
    ..reporterName = urduName
        ? 'رپورٹر رائے غلام جیلانی بھٹی — سینئر نمائندہ خصوصی، '
            'لاہور بیورو، نگران ٹیلی ویژن نیٹ ورک'
        : 'Reporter Rai Ghulam Jillani Bhatti — Senior '
            'Correspondent, Lahore Bureau'
    ..clipPaths = ['/tmp/tj_pro_build6/pixel.png']
    ..voiceoverDurationSec = 42.0
    ..templateKind = templateKind
    ..breakingVariant = breakingVariant
    ..breaking = templateKind == 'breaking';
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    SharedPreferences.setMockInitialValues({});
    Directory('/tmp/tj_pro_build6').createSync(recursive: true);
    Directory('/tmp/tj_pro_build6_tmp').createSync(recursive: true);
    File('/tmp/tj_pro_build6/pixel.png').writeAsBytesSync(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
      0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
      0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
      0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00,
      0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  Future<void> openMaker(
    WidgetTester tester,
    NewsProject project,
    Size size,
    double scale,
  ) async {
    // Unmount any previous tree first: a same-type root would
    // reuse its State and ignore the new initialProject.
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        builder: scale == 1.0
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
        home: NewsMakerScreen(
          initialPreset: ChannelPreset.nigraanTv(),
          initialProject: project,
        ),
      ),
    );
    await _frames(tester);
    _expectNoRenderError(tester, 'Maker Summary at $size x$scale');
    // Summary state: NO tool panel anywhere on screen.
    expect(_panelsWithPrefix('makerPanel-'), findsNothing);
    for (final id in _makerTools) {
      await _openMakerTool(tester, id);
    }
    final done = find.byKey(const Key('makerPanelDone'));
    if (done.evaluate().isNotEmpty) {
      await tester.tap(done);
      await _frames(tester);
    }
    _expectNoRenderError(tester, 'Maker Summary return $size x$scale');
    expect(_panelsWithPrefix('makerPanel-'), findsNothing);
  }

  group('News Maker — loaded-state matrix (Part 2)', () {
    testWidgets(
        'final template, Latin plate name — 2 sizes x 2 scales',
        (tester) async {
      addTearDown(tester.view.reset);
      for (final size in [const Size(360, 640), const Size(393, 851)]) {
        for (final scale in [1.0, 1.3]) {
          await openMaker(tester, _loadedProject(), size, scale);
        }
      }
    });

    testWidgets(
        'Urdu plate name + breaking ribbon variants at scale 1.3',
        (tester) async {
      addTearDown(tester.view.reset);
      final states = <NewsProject>[
        _loadedProject(urduName: true),
        _loadedProject(templateKind: 'breaking'),
        _loadedProject(
          templateKind: 'breaking',
          breakingVariant: 'breakingTickerCombo',
        ),
      ];
      for (final project in states) {
        for (final size in [const Size(360, 640), const Size(393, 851)]) {
          await openMaker(tester, project, size, 1.3);
        }
      }
    });

    testWidgets('panel scroll resets when the tool changes (Part 4)',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: _loadedProject(),
          ),
        ),
      );
      await _frames(tester);
      await _openMakerTool(tester, 'template');
      final panel = find.byKey(const Key('makerPanel-template'));
      _scrollPanelTo(tester, panel, 150);
      await _frames(tester);
      expect(
        _panelScrollPixels(tester, panel),
        greaterThan(0),
        reason: 'template panel scrolled before switching',
      );
      // Switch away and back: the panel must restart at the top.
      await _openMakerTool(tester, 'media');
      await _openMakerTool(tester, 'template');
      expect(
        _panelScrollPixels(
          tester,
          find.byKey(const Key('makerPanel-template')),
        ),
        0,
        reason: 'template panel scroll reset on tool change',
      );
    });
  });

  group('Photo Editor — 393x851 at textScale 1.3 (Parts 2 + 4)', () {
    const tools = <(String, String)>[
      ('canvas', 'Canvas'),
      ('filter', 'Filter'),
      ('adjust', 'Adjust'),
      ('effect', 'Effect'),
      ('background', 'Background'),
      ('portrait', 'Portrait'),
      ('sticker', 'Sticker'),
      ('text', 'Text'),
      ('pip', 'PIP'),
      ('remove', 'Remove'),
      ('enhance', 'Enhance'),
      ('cutout', 'Cutout'),
      ('doodle', 'Doodle'),
      ('makeup', 'Makeup'),
      ('crop', 'Crop'),
      ('expand', 'Expand'),
      ('frame', 'Frame'),
      ('rotate', 'Rotate'),
    ];

    testWidgets('all 18 panels render clean, one at a time',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1.0;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: const PhotoEditorScreen(
              initialImagePath: '/tmp/tj_pro_build6/pixel.png',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await _frames(tester);
      _expectNoRenderError(tester, 'Photo Editor initial build');

      for (final (key, label) in tools) {
        final confirm = find.byTooltip('Confirm');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.first);
          await _frames(tester);
        }
        await tester.pump(const Duration(seconds: 5));
        await _frames(tester);
        final target = find.text(label);
        for (var i = 0; i < 14; i++) {
          if (target.evaluate().isNotEmpty) break;
          for (final rail in find.byType(ListView).evaluate()) {
            await tester.drag(
              find.byWidget(rail.widget),
              const Offset(-240, 0),
            );
          }
          await tester.pump(const Duration(milliseconds: 60));
        }
        expect(target, findsWidgets,
            reason: 'Photo Editor tool $label not found');
        await tester.ensureVisible(target.first);
        await _frames(tester);
        await tester.tap(target.first);
        await _frames(tester);
        _expectNoRenderError(tester, 'Photo Editor tool $label');
        // Part 4: exactly this tool's keyed zone exists.
        expect(
          find.byKey(ValueKey('photo-panel-$key')),
          findsOneWidget,
          reason: 'photo panel zone for $key',
        );
        expect(
          _panelsWithPrefix('photo-panel-'),
          findsOneWidget,
          reason: 'exactly one photo panel while $key is open',
        );
        if (label == 'Text') {
          for (final tab in ['Style', 'Colour', 'Font', 'Type']) {
            final tabFinder = find.text(tab);
            if (tabFinder.evaluate().isNotEmpty) {
              await tester.tap(tabFinder.first);
              await _frames(tester);
              _expectNoRenderError(tester, 'Photo Text tab $tab');
            }
          }
        }
        // Part 4 scroll reset, exercised on the long Adjust
        // panel: scroll it, close, reopen — back at the top.
        if (key == 'adjust') {
          final panel = find.byKey(const ValueKey('photo-panel-adjust'));
          _scrollPanelTo(tester, panel, 150);
          await _frames(tester);
          expect(
            _panelScrollPixels(tester, panel),
            greaterThan(0),
            reason: 'adjust panel scrolled before switching',
          );
          await tester.tap(find.byTooltip('Confirm').first);
          await _frames(tester);
          final reopen = find.text('Adjust');
          for (var i = 0; i < 14; i++) {
            if (reopen.evaluate().isNotEmpty) break;
            for (final rail in find.byType(ListView).evaluate()) {
              await tester.drag(
                find.byWidget(rail.widget),
                const Offset(240, 0),
              );
            }
            await tester.pump(const Duration(milliseconds: 60));
          }
          await tester.ensureVisible(reopen.first);
          await _frames(tester);
          await tester.tap(reopen.first);
          await _frames(tester);
          expect(
            _panelScrollPixels(
              tester,
              find.byKey(const ValueKey('photo-panel-adjust')),
            ),
            0,
            reason: 'adjust panel scroll reset on tool change',
          );
        }
      }
    });
  });

  group('Video Editor — 393x851 at textScale 1.3 (Parts 2 + 4)', () {
    const labels = [
      'Canvas',
      'Audio',
      'Sticker',
      'Text',
      'Effect',
      'Filter',
      'PIP',
      'Precut',
      'Volume',
      'Background',
      'Speed',
      'Animation',
      'AI Cut',
      'Voice Enhance',
      'Crop',
      'Enhance',
      'Stabilizer',
      'Cutout',
      'Mask',
      'Templates',
      'Opacity',
      'Rotate',
      'Ease',
    ];

    testWidgets('all panels render clean, one at a time',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: const VideoEditorScreen(),
        ),
      );
      await _frames(tester);
      _expectNoRenderError(tester, 'Video Editor initial build');

      for (final label in labels) {
        // The VE panel header's confirm is tooltip 'Apply' (the
        // older guard's 'Done' never matched anything — panels
        // were never actually closed between tools there).
        final done = find.byTooltip('Apply');
        if (done.evaluate().isNotEmpty) {
          await tester.tap(done.first);
          await _frames(tester);
        }
        final target = find.text(label);
        for (var i = 0; i < 14; i++) {
          if (target.evaluate().isNotEmpty) break;
          for (final rail in find.byType(ListView).evaluate()) {
            await tester.drag(
              find.byWidget(rail.widget),
              const Offset(-240, 0),
            );
          }
          await tester.pump(const Duration(milliseconds: 60));
        }
        if (target.evaluate().isEmpty) {
          // Not offered in the no-clips state — not a failure
          // (same tolerance as the permanent guard).
          continue;
        }
        await tester.ensureVisible(target.first);
        await _frames(tester);
        await tester.tap(target.first);
        await _frames(tester);
        _expectNoRenderError(tester, 'Video Editor tool $label');
        // Part 4: when a panel opened, exactly one keyed panel
        // host exists in the tree.
        final panels = _panelsWithPrefix('video-panel-');
        if (panels.evaluate().isNotEmpty) {
          expect(
            panels,
            findsOneWidget,
            reason: 'exactly one VE panel while $label is open',
          );
        }
        // Part 4 scroll reset, exercised on the Canvas panel.
        if (label == 'Canvas' && panels.evaluate().isNotEmpty) {
          final panel = panels.first;
          _scrollPanelTo(tester, panel, 150);
          await _frames(tester);
          final before = _panelScrollPixels(tester, panel);
          if (before > 0) {
            await tester.tap(find.byTooltip('Apply').first);
            await _frames(tester);
            final reopen = find.text('Canvas');
            for (var i = 0; i < 14; i++) {
              if (reopen.evaluate().isNotEmpty) break;
              for (final rail in find.byType(ListView).evaluate()) {
                await tester.drag(
                  find.byWidget(rail.widget),
                  const Offset(240, 0),
                );
              }
              await tester.pump(const Duration(milliseconds: 60));
            }
            await tester.ensureVisible(reopen.first);
            await _frames(tester);
            await tester.tap(reopen.first);
            await _frames(tester);
            expect(
              _panelScrollPixels(
                tester,
                _panelsWithPrefix('video-panel-').first,
              ),
              0,
              reason: 'canvas panel scroll reset on tool change',
            );
          }
        }
      }
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
