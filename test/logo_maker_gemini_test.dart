// Functional tests for the Gemini-generated Logo Maker section
// (lib/logo/logo_maker_section.dart) — check phase before any integration.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';

Future<ui.Image> _makeTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Solid asymmetric-ish logo block on a transparent 40x40 canvas.
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
  int size = 200,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LogoDepthPainter(image: img, settings: settings, spinAngle: angle)
      .paint(canvas, Size(size.toDouble(), size.toDouble()));
  final picture = recorder.endRecording();
  final out = await picture.toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

int _countNonTransparent(Uint8List px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 8) n++;
  }
  return n;
}

bool _bytesDiffer(Uint8List a, Uint8List b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

void main() {
  group('LogoMakerSettings JSON', () {
    test('round-trip preserves every field', () {
      const original = LogoMakerSettings(
        presetId: 'neon_pulse',
        materialId: 'neon',
        depth: 33,
        bevel: 11,
        shadowOn: false,
        shadowBlur: 25,
        shadowOpacity: 0.6,
        spinSpeed: 2.5,
        spinOn: false,
        glowOn: true,
        glowIntensity: 0.9,
      );
      final restored = LogoMakerSettings.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('empty JSON yields the documented defaults', () {
      expect(
        LogoMakerSettings.fromJson(const <String, dynamic>{}),
        const LogoMakerSettings(),
      );
    });

    test('unknown materialId falls back to gold', () {
      final s = LogoMakerSettings.fromJson(
        const <String, dynamic>{'materialId': 'does_not_exist'},
      );
      expect(s.materialId, 'gold');
    });

    test('out-of-range numbers are clamped', () {
      final s = LogoMakerSettings.fromJson(const <String, dynamic>{
        'depth': 999,
        'bevel': -5,
        'shadowBlur': 500,
        'shadowOpacity': 7,
        'spinSpeed': 42,
        'glowIntensity': -1,
      });
      expect(s.depth, 40);
      expect(s.bevel, 0);
      expect(s.shadowBlur, 40);
      expect(s.shadowOpacity, 0.8);
      expect(s.spinSpeed, 3);
      expect(s.glowIntensity, 0);
    });

    test('copyWith changes only the named fields', () {
      const base = LogoMakerSettings();
      final changed = base.copyWith(depth: 5, glowOn: true);
      expect(changed.depth, 5);
      expect(changed.glowOn, isTrue);
      expect(changed.materialId, base.materialId);
      expect(changed, isNot(base));
    });
  });

  group('Presets and materials', () {
    test('exactly 10 presets with the required names and unique ids', () {
      expect(kLogoStylePresets, hasLength(10));
      expect(
        kLogoStylePresets.map((p) => p.name).toSet(),
        <String>{
          'Gold Spin',
          'Chrome Flip',
          'Neon Pulse',
          'Glass Shine',
          'Royal Gold',
          'Silver Swing',
          'Fire Glow',
          'Ocean Wave',
          'Sunset Gradient',
          'Mono Classic',
        },
      );
      expect(
        kLogoStylePresets.map((p) => p.id).toSet(),
        hasLength(10),
      );
    });

    test('every preset material exists in the materials map', () {
      for (final preset in kLogoStylePresets) {
        expect(
          kLogoMaterials.containsKey(preset.materialId),
          isTrue,
          reason: 'preset ${preset.id} -> ${preset.materialId}',
        );
        expect(preset.gradientColors, isNotEmpty);
        expect(preset.depth, inInclusiveRange(0, 40));
        expect(preset.bevel, inInclusiveRange(0, 20));
      }
    });

    test('materials map has exactly the 10 required ids', () {
      expect(
        kLogoMaterials.keys.toSet(),
        <String>{
          'gold',
          'chrome',
          'silver',
          'neon',
          'glass',
          'fire',
          'ocean',
          'sunset',
          'mono',
          'none',
        },
      );
      expect(kLogoMaterials['none'], isEmpty);
      for (final entry in kLogoMaterials.entries) {
        if (entry.key != 'none') {
          expect(entry.value.length, greaterThanOrEqualTo(2),
              reason: 'material ${entry.key} needs a gradient');
        }
      }
    });
  });

  group('LogoDepthPainter rendering', () {
    late ui.Image img;

    setUpAll(() async {
      img = await _makeTestImage();
    });

    test('smoke: every material renders without exception', () async {
      for (final materialId in kLogoMaterials.keys) {
        final px = await _renderPainter(
          img,
          LogoMakerSettings(materialId: materialId, glowOn: true),
          0,
        );
        expect(px.length, 200 * 200 * 4, reason: 'material $materialId');
        expect(_countNonTransparent(px), greaterThan(0),
            reason: 'material $materialId drew nothing');
      }
    });

    test('smoke: extremes of depth/bevel/glow/angles never throw', () async {
      final combos = <LogoMakerSettings>[
        const LogoMakerSettings(depth: 0, bevel: 0, shadowOn: false),
        const LogoMakerSettings(
          depth: 40,
          bevel: 20,
          shadowBlur: 40,
          shadowOpacity: 0.8,
          glowOn: true,
          glowIntensity: 1,
        ),
        const LogoMakerSettings(depth: 40, bevel: 20, materialId: 'none'),
      ];
      final angles = <double>[0, math.pi / 2, math.pi, 3 * math.pi / 2];
      for (final settings in combos) {
        for (final angle in angles) {
          final px = await _renderPainter(img, settings, angle);
          expect(px.length, 200 * 200 * 4);
        }
      }
    });

    test('depth > 0 covers strictly more pixels than depth = 0', () async {
      const base = LogoMakerSettings(
        materialId: 'none',
        shadowOn: false,
        bevel: 0,
        depth: 0,
      );
      final flat = await _renderPainter(img, base, 0);
      final deep = await _renderPainter(img, base.copyWith(depth: 40), 0);
      expect(
        _countNonTransparent(deep),
        greaterThan(_countNonTransparent(flat)),
      );
    });

    test('gold material changes pixels vs no material', () async {
      const base = LogoMakerSettings(
        materialId: 'none',
        shadowOn: false,
        bevel: 0,
        depth: 0,
      );
      final none = await _renderPainter(img, base, 0);
      final gold = await _renderPainter(
        img,
        base.copyWith(materialId: 'gold'),
        0,
      );
      expect(_bytesDiffer(none, gold), isTrue);
    });

    test('edge-on spin (90 degrees) is much narrower than front view',
        () async {
      const settings = LogoMakerSettings(
        materialId: 'none',
        shadowOn: false,
        bevel: 0,
        depth: 0,
      );
      final front = await _renderPainter(img, settings, 0);
      final edge = await _renderPainter(img, settings, math.pi / 2);
      expect(
        _countNonTransparent(edge),
        lessThan(_countNonTransparent(front) ~/ 4),
      );
    });

    test('back-facing view (180 degrees) differs from front view', () async {
      const settings = LogoMakerSettings(
        materialId: 'none',
        shadowOn: false,
        bevel: 0,
        depth: 0,
      );
      final front = await _renderPainter(img, settings, 0);
      final back = await _renderPainter(img, settings, math.pi);
      expect(_bytesDiffer(front, back), isTrue);
    });

    test('shouldRepaint reacts to image, settings and angle', () {
      const settings = LogoMakerSettings();
      final a = LogoDepthPainter(image: img, settings: settings, spinAngle: 0);
      expect(
        a.shouldRepaint(
          LogoDepthPainter(image: img, settings: settings, spinAngle: 0),
        ),
        isFalse,
      );
      expect(
        a.shouldRepaint(
          LogoDepthPainter(image: img, settings: settings, spinAngle: 0.5),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          LogoDepthPainter(
            image: img,
            settings: settings.copyWith(depth: 1),
            spinAngle: 0,
          ),
        ),
        isTrue,
      );
    });
  });

  group('LogoMakerSection widget', () {
    late ui.Image img;

    setUpAll(() async {
      img = await _makeTestImage();
    });

    Widget harness({
      LogoMakerSettings? initial,
      void Function(LogoMakerSettings)? onChanged,
      void Function(LogoMakerSettings)? onSave,
      VoidCallback? onClose,
    }) {
      return MaterialApp(
        home: LogoMakerSection(
          logoImage: img,
          initialSettings:
              initial ?? const LogoMakerSettings(spinOn: false),
          onSettingsChanged: onChanged ?? (_) {},
          onSave: onSave ?? (_) {},
          onClose: onClose ?? () {},
        ),
      );
    }

    testWidgets(
        'dock shows only the real tools (v1.19.0 G5); logo panel is '
        'the default; style panel has its controls', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('Logo Maker'), findsOneWidget);
      for (final label in <String>['Logo', 'Style', 'Spin']) {
        expect(find.text(label), findsOneWidget, reason: 'dock: $label');
      }
      // The placeholder tools are GONE from the dock — no dead
      // buttons (Cube/Parts keep their controls in News Studio).
      for (final label in <String>['Cube', 'Parts', 'Decorate', 'Timing']) {
        expect(find.text(label), findsNothing, reason: 'dock: $label');
      }
      // Save appears twice: top bar button + dock button.
      expect(find.text('Save'), findsNWidgets(2));

      // Default panel = Logo source menu.
      expect(find.text('Logo Source'), findsOneWidget);
      expect(find.text('Current Image'), findsOneWidget);
      expect(find.text('Create from Text'), findsOneWidget);
      expect(find.text('Pick a Shape / Badge'), findsOneWidget);

      // Style panel controls: 4 sliders, 2 switches, headings.
      await tester.tap(find.text('Style'));
      await tester.pump();
      expect(find.byType(Slider), findsNWidgets(4));
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.text('Presets'), findsOneWidget);
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Depth'), findsOneWidget);
      expect(find.text('Bevel'), findsOneWidget);
      expect(find.text('Shadow Blur'), findsOneWidget);
      expect(find.text('Glow Intensity'), findsOneWidget);
    });

    testWidgets('tapping a preset fires onSettingsChanged with its values',
        (tester) async {
      LogoMakerSettings? captured;
      await tester.pumpWidget(harness(onChanged: (s) => captured = s));
      await tester.pump();
      await tester.tap(find.text('Style'));
      await tester.pump();

      final chip = find.text('Chrome Flip');
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.presetId, 'chrome_flip');
      expect(captured!.materialId, 'chrome');
      expect(captured!.depth, 22);
      expect(captured!.bevel, 10);
    });

    testWidgets('tapping a material chip fires onSettingsChanged',
        (tester) async {
      LogoMakerSettings? captured;
      await tester.pumpWidget(harness(onChanged: (s) => captured = s));
      await tester.pump();
      await tester.tap(find.text('Style'));
      await tester.pump();

      // 'Chrome' is the 2nd material chip — the horizontal ListView builds
      // lazily, so the last chip ('None') is not in the tree until scrolled.
      final chip = find.text('Chrome');
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.materialId, 'chrome');
    });

    testWidgets('top Save button fires onSave; back arrow fires onClose',
        (tester) async {
      LogoMakerSettings? saved;
      var closed = false;
      await tester.pumpWidget(harness(
        onSave: (s) => saved = s,
        onClose: () => closed = true,
      ));
      await tester.pump();

      await tester.tap(find.text('Save').first);
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.presetId, 'gold_spin');

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('dock buttons switch panels; no placeholder panel remains',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // Spin panel: exactly one switch + one slider, real controls.
      await tester.tap(find.text('Spin'));
      await tester.pump();
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Spin Speed'), findsOneWidget);
      expect(find.text('Controls coming in the next step.'), findsNothing);

      await tester.tap(find.text('Style'));
      await tester.pump();
      expect(find.byType(Slider), findsNWidgets(4));
      expect(find.text('Controls coming in the next step.'), findsNothing);

      await tester.tap(find.text('Logo'));
      await tester.pump();
      expect(find.text('Logo Source'), findsOneWidget);
      expect(find.text('Controls coming in the next step.'), findsNothing);
    });

    testWidgets('spin enabled pumps animated frames without error',
        (tester) async {
      await tester.pumpWidget(harness(
        initial: const LogoMakerSettings(spinOn: true),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CustomPaint), findsWidgets);
      // Unmount so the repeating controller is disposed before test end.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
