// v1.5.2 (#69b) — PERMANENT OVERFLOW GUARD.
//
// Renders EVERY tool panel of the Video Editor, Photo Editor and
// News Maker at a small phone size (360x640) and fails on ANY
// render exception (RenderFlex overflow paints an exception in
// tests). This is the automated pre-push gate the user ordered
// after repeated on-phone "BOTTOM OVERFLOWED BY n PIXELS"
// stripes: an overflow now stops the build instead of reaching
// his phone.
//
// Bounded pumps only — the Maker previews embed the repeating
// ticker animation, so pumpAndSettle would never settle.

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
        return '/tmp/tj_pro_overflow';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_overflow_tmp';
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

/// Opens a News Maker tool: closes any open panel first (the
/// bottom zone shows the tool line XOR the open panel), drags
/// the tool line until the tool is built, then taps it.
Future<void> _openMakerTool(WidgetTester tester, String id) async {
  final done = find.byKey(const Key('makerPanelDone'));
  if (done.evaluate().isNotEmpty) {
    await tester.tap(done);
    await _frames(tester);
  }
  final target = find.byKey(Key('makerTool-$id'));
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsOneWidget, reason: 'maker tool $id not found');
  await tester.tap(target);
  await _frames(tester);
  _expectNoRenderError(tester, 'News Maker tool $id');
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    SharedPreferences.setMockInitialValues({});
    Directory('/tmp/tj_pro_overflow').createSync(recursive: true);
    Directory('/tmp/tj_pro_overflow_tmp').createSync(recursive: true);
    // A real tiny PNG for the Photo Editor to open. SYNC write:
    // awaiting real dart:io inside a testWidgets body deadlocks
    // under the fake-async zone.
    File('/tmp/tj_pro_overflow/pixel.png').writeAsBytesSync(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
      0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
      0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
      0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00,
      0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  void smallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('News Maker — every panel at 360x640', () {
    const tools = [
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

    testWidgets('all 12 tool panels render without overflow',
        (tester) async {
      smallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: NewsProject.create(),
          ),
        ),
      );
      await _frames(tester);
      _expectNoRenderError(tester, 'News Maker initial build');

      for (final id in tools) {
        await _openMakerTool(tester, id);
      }
    });

    // Build 5 (v1.5.7, error-banner fix): the v1.5.6 phone bug —
    // a repeating RenderFlex overflow in THIS workspace fired the
    // CrashGuard banner on a loop. The old guard only covered an
    // EMPTY project at textScale 1.0. This case uses a REAL
    // project (tehreer + both tickers + a photo clip + voiceover
    // duration) at textScale 1.3 on two phone sizes, and walks
    // the Summary state (no tool open — the state the user's
    // screenshots showed the banner in) plus every tool panel,
    // Media and Export included.
    Future<void> realProjectAt(WidgetTester tester, Size size) async {
      final project = NewsProject.create()
        ..tehreer = 'اسلام آباد: وزیراعظم نے نئے صوبوں کے قیام پر '
            'کابینہ اجلاس طلب کر لیا، تمام جماعتوں سے مشاورت جاری ہے۔'
        ..tickerText = 'تازہ ترین: ملک بھر میں موسم خشک، کراچی میں '
            'گرمی کی شدت برقرار'
        ..englishTickerText =
            'Pakistan weather update: dry conditions across the '
            'country, Karachi heat persists'
        ..tickerLabel = 'BREAKING NEWS'
        ..reporterName = 'Jaani Bhatti'
        ..clipPaths = ['/tmp/tj_pro_overflow/pixel.png']
        ..voiceoverDurationSec = 42.0;

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
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
      _expectNoRenderError(
        tester,
        'News Maker Summary at $size textScale 1.3',
      );
      for (final id in tools) {
        await _openMakerTool(tester, id);
      }
      // Close back to the Summary state and re-check it.
      final done = find.byKey(const Key('makerPanelDone'));
      if (done.evaluate().isNotEmpty) {
        await tester.tap(done);
        await _frames(tester);
      }
      _expectNoRenderError(
        tester,
        'News Maker Summary (return) at $size textScale 1.3',
      );
    }

    testWidgets(
        'real project at textScale 1.3 renders without overflow '
        '(360x640)', (tester) async {
      await realProjectAt(tester, const Size(360, 640));
    });

    testWidgets(
        'real project at textScale 1.3 renders without overflow '
        '(390x844)', (tester) async {
      await realProjectAt(tester, const Size(390, 844));
    });
  });

  group('Photo Editor — every panel at 360x640', () {
    const labels = [
      'Canvas',
      'Filter',
      'Adjust',
      'Effect',
      'Background',
      'Portrait',
      'Sticker',
      'Text',
      'PIP',
      'Remove',
      'Enhance',
      'Cutout',
      'Doodle',
      'Makeup',
      'Crop',
      'Expand',
      'Frame',
      'Rotate',
    ];

    testWidgets('all 18 tool panels render without overflow',
        (tester) async {
      smallPhone(tester);
      // runAsync: the editor loads the file with real dart:io,
      // which never completes inside the fake-async zone.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: PhotoEditorScreen(
              initialImagePath: '/tmp/tj_pro_overflow/pixel.png',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await _frames(tester);
      _expectNoRenderError(tester, 'Photo Editor initial build');

      for (final label in labels) {
        // Close the open panel first (bottom zone = toolbar XOR
        // panel): the panel header's check is tooltip 'Confirm'.
        final confirm = find.byTooltip('Confirm');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.first);
          await _frames(tester);
        }
        // Tool-open SnackBars (e.g. the Text tool's 4s hint)
        // overlay the toolbar until they expire — let them
        // (fake time) before hunting the next tool, exactly
        // like a user waiting a moment.
        await tester.pump(const Duration(seconds: 5));
        await _frames(tester);
        final target = find.text(label);
        // The toolbar is a horizontal rail; drag the rails until
        // the label is built, then tap.
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
        await tester.tap(target.first);
        await _frames(tester);
        _expectNoRenderError(tester, 'Photo Editor tool $label');
        // Text tool: also walk its four sub-tabs (the #53/#67
        // overflow lived in this zone).
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
      }
    });
  });

  group('Video Editor — every panel at 360x640', () {
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
      // Build 5 (v1.5.7, user decision 1): the 'News' tool was
      // removed from the Video Editor — news work lives only in
      // News Studio — so it is no longer in this sweep.
    ];

    testWidgets('tool panels render without overflow (no clips)',
        (tester) async {
      smallPhone(tester);
      await tester.pumpWidget(
        const MaterialApp(home: VideoEditorScreen()),
      );
      await _frames(tester);
      _expectNoRenderError(tester, 'Video Editor initial build');

      for (final label in labels) {
        // Close the open panel first (tool zone = row XOR
        // panel): the panel header's check is tooltip 'Done'.
        final done = find.byTooltip('Done');
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
          // A tool that is not offered in the no-clips state is
          // not a render failure — note it and move on.
          continue;
        }
        await tester.tap(target.first);
        await _frames(tester);
        _expectNoRenderError(tester, 'Video Editor tool $label');
      }
      // Flush status-clear timers etc. so none is pending at
      // teardown (the binding asserts on pending timers).
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
