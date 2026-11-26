/// v1.19.0 — Logo Maker INTEGRATION proofs:
///
/// - G1: the section opens as a route (pushLogoMakerSection),
///   the News Studio Logo panel carries the entry button and
///   tapping it opens the maker on the preset's logo; the
///   Logo panel's Text/Shapes sources replace the current
///   logo and report it to the host.
/// - G2: the Spin panel's switch + speed slider write the
///   settings, and the settings survive a preset JSON
///   round-trip (the persistence mechanism) and a re-open.
/// - G3: the depth painter's static cache renders pixel-equal
///   output to the direct path (front / back / edge-on) and
///   invalidates exactly when image/settings/size change.
/// - G4: unknown shape ids fail loudly in renderLogoShape and
///   draw nothing in the painter — no silent hexagon.
/// - G5: the Logo Maker guide entry exists.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';
import 'package:tj_pro/logo/logo_text_shapes.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/widgets/tool_guide.dart';

Future<ui.Image> _makeTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 24, 16),
    Paint()..color = const Color(0xFFCC6633),
  );
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 10, 16),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(40, 40);
}

Future<Uint8List> _renderPainter(
  ui.Image img,
  LogoMakerSettings settings,
  double angle, {
  int size = 240,
  ui.Image? staticFront,
  ui.Image? staticBack,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LogoDepthPainter(
    image: img,
    settings: settings,
    spinAngle: angle,
    staticFront: staticFront,
    staticBack: staticBack,
  ).paint(canvas, Size(size.toDouble(), size.toDouble()));
  final picture = recorder.endRecording();
  final out = await picture.toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

/// (meanAbsDiff, fraction of pixels whose largest channel
/// difference exceeds [threshold]).
(double, double) _diffStats(Uint8List a, Uint8List b, {int threshold = 8}) {
  var total = 0;
  var hot = 0;
  final pixels = a.length ~/ 4;
  for (var i = 0; i < a.length; i += 4) {
    var maxDiff = 0;
    for (var c = 0; c < 4; c++) {
      final d = (a[i + c] - b[i + c]).abs();
      total += d;
      if (d > maxDiff) maxDiff = d;
    }
    if (maxDiff > threshold) hot++;
  }
  return (total / (pixels * 4), hot / pixels);
}

void main() {
  group('G3 — static cache parity and invalidation', () {
    late ui.Image img;

    setUpAll(() async {
      img = await _makeTestImage();
    });

    const settings = LogoMakerSettings(
      depth: 26,
      bevel: 12,
      glowOn: true,
      glowIntensity: 0.7,
      materialId: 'gold',
    );
    const size = Size(240, 240);

    test('static render size = logo rect + 2x margin', () async {
      final stat = await renderLogoDepthStatic(
        image: img,
        settings: settings,
        backFacing: false,
        size: size,
      );
      final dest = logoDepthDestRect(img, size);
      final margin = logoDepthStaticMargin(settings);
      expect(stat.width, (dest.width + margin * 2).ceil());
      expect(stat.height, (dest.height + margin * 2).ceil());
      stat.dispose();
    });

    test('cached path renders pixel-equal to the direct path', () async {
      final front = await renderLogoDepthStatic(
        image: img,
        settings: settings,
        backFacing: false,
        size: size,
      );
      final back = await renderLogoDepthStatic(
        image: img,
        settings: settings,
        backFacing: true,
        size: size,
      );
      for (final angle in <double>[0, math.pi / 2, math.pi]) {
        final direct = await _renderPainter(img, settings, angle);
        final cached = await _renderPainter(
          img,
          settings,
          angle,
          staticFront: front,
          staticBack: back,
        );
        final (mean, hot) = _diffStats(direct, cached);
        expect(mean, lessThan(1.5), reason: 'angle $angle mean diff');
        expect(hot, lessThan(0.02), reason: 'angle $angle hot pixels');
      }
      front.dispose();
      back.dispose();
    });

    test('cache renders once per combination, invalidates on change',
        () async {
      final cache = LogoDepthImageCache();
      expect(cache.isReadyFor(img, settings, size), isFalse);
      expect(await cache.ensure(img, settings, size), isTrue);
      expect(cache.renderCount, 2);
      expect(cache.isReadyFor(img, settings, size), isTrue);

      // Same combination again: no re-render.
      expect(await cache.ensure(img, settings, size), isTrue);
      expect(cache.renderCount, 2);

      // Settings change invalidates.
      final changed = settings.copyWith(depth: 30);
      expect(cache.isReadyFor(img, changed, size), isFalse);
      expect(await cache.ensure(img, changed, size), isTrue);
      expect(cache.renderCount, 4);

      // Size change invalidates.
      expect(await cache.ensure(img, changed, const Size(200, 200)), isTrue);
      expect(cache.renderCount, 6);

      cache.clear();
      expect(cache.frontImage, isNull);
      expect(cache.isReadyFor(img, changed, size), isFalse);
    });
  });

  group('G4 — unknown shape ids fail loudly, draw nothing', () {
    test('renderLogoShape throws ArgumentError for an unknown id', () async {
      await expectLater(
        renderLogoShape(
          shapeId: 'does_not_exist',
          colors: const <Color>[Color(0xFFF59E0B)],
          size: 128,
        ),
        throwsArgumentError,
      );
      expect(isKnownLogoShapeId('does_not_exist'), isFalse);
      expect(isKnownLogoShapeId('star'), isTrue);
    });

    test('the painter draws nothing for an unknown id (no hexagon)',
        () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const LogoShapePainter(
        shapeId: 'does_not_exist',
        colors: <Color>[Color(0xFFF59E0B)],
      ).paint(canvas, const Size(128, 128));
      final picture = recorder.endRecording();
      final out = await picture.toImage(128, 128);
      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = data!.buffer.asUint8List();
      var alphaSum = 0;
      for (var i = 3; i < px.length; i += 4) {
        alphaSum += px[i];
      }
      expect(alphaSum, 0);
      out.dispose();
    });

    test('a known shape still renders real coverage', () async {
      final star = await renderLogoShape(
        shapeId: 'star',
        colors: const <Color>[Color(0xFFF59E0B)],
        size: 128,
      );
      final data = await star.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = data!.buffer.asUint8List();
      var colored = 0;
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] > 8) colored++;
      }
      expect(colored, greaterThan(500));
      star.dispose();
    });
  });

  group('G2 — settings persistence through the preset JSON', () {
    test('logoMakerSettingsJson round-trips preset + settings', () {
      const settings = LogoMakerSettings(
        presetId: 'royal_gold',
        materialId: 'chrome',
        depth: 31,
        spinOn: false,
        spinSpeed: 2.25,
        glowOn: true,
      );
      final preset = ChannelPreset(id: 't1', name: 'Test')
        ..logoMakerSettingsJson = jsonEncode(settings.toJson());
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.logoMakerSettingsJson, preset.logoMakerSettingsJson);
      final parsed = LogoMakerSettings.fromJson(
        jsonDecode(restored.logoMakerSettingsJson) as Map<String, dynamic>,
      );
      expect(parsed, settings);
    });

    test('a legacy preset JSON without the key loads with empty settings',
        () {
      final preset = ChannelPreset(id: 't2', name: 'Legacy');
      final json = preset.toJson()..remove('logoMakerSettingsJson');
      final restored = ChannelPreset.fromJson(json);
      expect(restored.logoMakerSettingsJson, '');
      expect(
        LogoMakerSettings.fromJson(const <String, dynamic>{}),
        const LogoMakerSettings(),
      );
    });
  });

  group('G5 — guide entry', () {
    test('ns.logo_maker guide exists and explains the maker', () {
      final entry = toolGuideFor('ns.logo_maker');
      expect(entry, isNotNull);
      expect(entry!.title, 'Logo Maker');
      expect(entry.what, isNotEmpty);
      expect(entry.steps.length, greaterThanOrEqualTo(4));
      expect(entry.tips, isNotEmpty);
    });
  });

  group('G1/G2 — section integration', () {
    late ui.Image img;

    setUpAll(() async {
      img = await _makeTestImage();
    });

    /// A phone-height surface: on the default 800x600 test
    /// surface the section's panel viewport is short enough
    /// that the source buttons sit below the fold.
    void usePhoneSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget harness({
      LogoMakerSettings? initial,
      void Function(LogoMakerSettings)? onChanged,
      void Function(ui.Image)? onImageChanged,
    }) {
      return MaterialApp(
        home: LogoMakerSection(
          logoImage: img,
          initialSettings: initial ?? const LogoMakerSettings(spinOn: false),
          onSettingsChanged: onChanged ?? (_) {},
          onSave: (_) {},
          onClose: () {},
          onLogoImageChanged: onImageChanged,
        ),
      );
    }

    testWidgets('pushLogoMakerSection opens the maker as a route and '
        'the back arrow pops it', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => pushLogoMakerSection(
                    context,
                    logoImage: img,
                    initialSettings: const LogoMakerSettings(spinOn: false),
                    onSettingsChanged: (_) {},
                    onSave: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LogoMakerSection), findsOneWidget);
      expect(find.text('Logo Source'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LogoMakerSection), findsNothing);
    });

    testWidgets('Shapes source: picking a shape replaces the logo and '
        'reports it to the host', (tester) async {
      usePhoneSize(tester);
      ui.Image? reported;
      await tester.pumpWidget(harness(onImageChanged: (i) => reported = i));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('logoMakerShapesButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('logoMakerShapesButton')));
      await tester.pump();
      expect(find.byType(LogoShapePicker), findsOneWidget);

      await tester.ensureVisible(find.text('Star'));
      await tester.pump();
      await tester.tap(find.text('Star'));
      await tester.pump();
      await tester.ensureVisible(find.text('Use This Shape'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use This Shape'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      expect(reported, isNotNull);
      expect(reported!.width, 512);
      // Back at the source menu, labelled as the shape logo.
      expect(find.text('Logo Source'), findsOneWidget);
      expect(find.text('Shape logo'), findsOneWidget);
    });

    testWidgets('Text source: creating a text logo replaces the logo and '
        'reports it to the host', (tester) async {
      usePhoneSize(tester);
      ui.Image? reported;
      await tester.pumpWidget(harness(onImageChanged: (i) => reported = i));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('logoMakerTextButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('logoMakerTextButton')));
      await tester.pump();
      expect(find.byType(LogoTextCreator), findsOneWidget);

      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField), 'TJ');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.ensureVisible(find.text('Use This Logo'));
      await tester.pump();
      await tester.tap(find.text('Use This Logo'));
      await tester.pump();

      expect(reported, isNotNull);
      expect(find.text('Logo Source'), findsOneWidget);
      expect(find.text('Text logo'), findsOneWidget);
    });

    testWidgets('Spin panel: switch and speed slider write the settings',
        (tester) async {
      usePhoneSize(tester);
      LogoMakerSettings? last;
      await tester.pumpWidget(harness(onChanged: (s) => last = s));
      await tester.pump();

      await tester.tap(find.text('Spin'));
      await tester.pump();
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pump();
      expect(last, isNotNull);
      expect(last!.spinOn, isTrue);

      await tester.ensureVisible(find.byType(Slider));
      await tester.pump();
      await tester.drag(find.byType(Slider), const Offset(80, 0));
      await tester.pump();
      expect(last!.spinSpeed, greaterThan(1.0));
    });

    testWidgets('re-opening restores the saved spin settings', (tester) async {
      const saved = LogoMakerSettings(spinOn: true, spinSpeed: 2.5);
      await tester.pumpWidget(harness(initial: saved));
      await tester.pump();

      await tester.tap(find.text('Spin'));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('2.5x'), findsOneWidget);

      // Unmount so the repeating spin controller is disposed.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('G1 — News Studio entry', () {
    late Directory tmp;
    late File logoFile;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('tjpro_v1190_logo_maker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tmp.path;
          }
          if (call.method == 'getTemporaryDirectory') {
            return '${tmp.path}_tmp';
          }
          return null;
        },
      );
      // The News Maker state constructs an AudioRecorder at
      // init; the record plugin has no test implementation and
      // its async create call would otherwise surface as a
      // MissingPluginException (the established NS-test mock).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (MethodCall call) async => null,
      );
      logoFile = File('${tmp.path}/logo.png');
      await logoFile.writeAsBytes(
        <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
          0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
          0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
          0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
          0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
          0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
          0x82,
        ],
      );
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> openTool(WidgetTester tester, String id) async {
      final target = find.byKey(Key('makerTool-$id'));
      for (var i = 0; i < 12; i++) {
        if (target.evaluate().isNotEmpty) {
          final rect = tester.getRect(target);
          if (rect.left >= 0 && rect.right <= 393) break;
        }
        await tester.drag(
          find.byKey(const Key('makerToolLine')),
          const Offset(-240, 0),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(target);
      await frames(tester);
    }

    testWidgets('the Logo panel carries the entry and it opens the maker',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final preset = ChannelPreset.nigraanTv()..logoPath = logoFile.path;
      final project = NewsProject.create(presetId: preset.id);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: preset,
            initialProject: project,
          ),
        ),
      );
      await frames(tester);

      await openTool(tester, 'logo');
      expect(find.byKey(const Key('makerPanel-logo')), findsOneWidget);
      expect(find.byKey(const Key('logoMakerOpenButton')), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('logoMakerOpenButton')));
        await Future<void>.delayed(const Duration(milliseconds: 900));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LogoMakerSection), findsOneWidget);
      expect(find.text('Logo Source'), findsOneWidget);

      // Back returns to News Studio.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(LogoMakerSection), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
