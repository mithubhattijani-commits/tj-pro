// Functional tests for the Gemini-generated Text/Shapes logo creators
// (lib/logo/logo_text_shapes.dart) — check phase before any integration.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_text_shapes.dart';

Future<Uint8List> _rgba(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

int _countColored(Uint8List px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 8) n++;
  }
  return n;
}

int _alphaAt(Uint8List px, int size, double fx, double fy) {
  final x = (fx * size).floor().clamp(0, size - 1);
  final y = (fy * size).floor().clamp(0, size - 1);
  return px[(y * size + x) * 4 + 3];
}

int _alphaAtWH(Uint8List px, int w, int h, double fx, double fy) {
  final x = (fx * w).floor().clamp(0, w - 1);
  final y = (fy * h).floor().clamp(0, h - 1);
  return px[(y * w + x) * 4 + 3];
}

bool _bytesDiffer(Uint8List a, Uint8List b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

const _gold = <Color>[Color(0xFFFFF3B0), Color(0xFFF59E0B), Color(0xFFB45309)];

void main() {
  group('data lists', () {
    test('exactly 8 text styles with the required names, in order', () {
      expect(kLogoTextStyles.length, 8);
      expect(
        kLogoTextStyles.map((s) => s.name).toList(),
        <String>[
          'Bold Gold',
          'Neon Glow',
          'Chrome Block',
          'Royal Serif',
          'Modern Sans',
          'Retro Script',
          'Fire Text',
          'Ocean Clean',
        ],
      );
      // ids unique, every style fully filled
      expect(kLogoTextStyles.map((s) => s.id).toSet().length, 8);
      for (final s in kLogoTextStyles) {
        expect(s.gradientColors.length, greaterThanOrEqualTo(2),
            reason: s.name);
        expect(s.fontFamily, isNotEmpty, reason: s.name);
      }
    });

    test('exactly 12 shapes with the required names, in order', () {
      expect(kLogoShapes.length, 12);
      expect(
        kLogoShapes.map((s) => s.name).toList(),
        <String>[
          'Circle Badge',
          'Star',
          'Shield',
          'Hexagon',
          'Ribbon Banner',
          'Diamond',
          'Oval Seal',
          'Play Triangle',
          'Heart',
          'Crown',
          'Lightning Bolt',
          'Sun Burst',
        ],
      );
      expect(kLogoShapes.map((s) => s.id).toSet().length, 12);
    });
  });

  group('renderLogoText', () {
    test('real text renders: transparent corners, colored pixels inside',
        () async {
      final img = await renderLogoText(
        text: 'TJ Pro',
        style: kLogoTextStyles.first,
        fontSize: 120,
      );
      expect(img.width, greaterThan(50));
      expect(img.height, greaterThan(50));
      expect(img.width, lessThanOrEqualTo(2048));
      final px = await _rgba(img);
      // four corners transparent
      expect(_alphaAtWH(px, img.width, img.height, 0.01, 0.01), 0);
      expect(_alphaAtWH(px, img.width, img.height, 0.99, 0.01), 0);
      expect(_alphaAtWH(px, img.width, img.height, 0.01, 0.99), 0);
      expect(_alphaAtWH(px, img.width, img.height, 0.99, 0.99), 0);
      // a meaningful amount of colored pixels (the letters)
      final colored = _countColored(px);
      expect(colored, greaterThan(img.width * img.height * 0.02));
      expect(colored, lessThan(img.width * img.height * 0.9));
      // gradient proof: more than a handful of distinct opaque colors
      final colors = <int>{};
      for (var i = 0; i < px.length; i += 4) {
        if (px[i + 3] > 200) {
          colors.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
        }
      }
      expect(colors.length, greaterThan(5));
      img.dispose();
    });

    test('empty and whitespace text return a 1x1 image, no crash', () async {
      for (final t in <String>['', '   ', '\n\t ']) {
        final img = await renderLogoText(
          text: t,
          style: kLogoTextStyles.first,
        );
        expect(img.width, 1);
        expect(img.height, 1);
        img.dispose();
      }
    });

    test('very long text is capped at 2048 px wide', () async {
      final img = await renderLogoText(
        text: 'WWWWWWWWWW' * 6,
        style: kLogoTextStyles.first,
        fontSize: 220,
      );
      expect(img.width, lessThanOrEqualTo(2048));
      expect(img.width, greaterThan(1000)); // scaling really engaged
      img.dispose();
    });

    test('stroke style and no-stroke style render differently', () async {
      final withStroke = await renderLogoText(
        text: 'Nigraan',
        style: kLogoTextStyles.first, // Bold Gold, strokeWidth 4
        fontSize: 100,
      );
      final noStrokeStyle = kLogoTextStyles
          .firstWhere((s) => s.id == 'modern_sans'); // strokeWidth 0
      final noStroke = await renderLogoText(
        text: 'Nigraan',
        style: noStrokeStyle,
        fontSize: 100,
      );
      final a = await _rgba(withStroke);
      final b = await _rgba(noStroke);
      expect(_bytesDiffer(a, b), isTrue);
      withStroke.dispose();
      noStroke.dispose();
    });

    test('missing-font style (Retro Script / Pacifico) still renders',
        () async {
      final retro =
          kLogoTextStyles.firstWhere((s) => s.id == 'retro_script');
      final img = await renderLogoText(
        text: 'Style',
        style: retro,
        fontSize: 110,
      );
      final px = await _rgba(img);
      expect(_countColored(px), greaterThan(200));
      img.dispose();
    });
  });

  group('renderLogoShape — pixel proof per shape', () {
    test('every shape: sane coverage, all coverages distinct', () async {
      const size = 256;
      final coverages = <String, int>{};
      final renders = <String, Uint8List>{};
      for (final shape in kLogoShapes) {
        final img = await renderLogoShape(
          shapeId: shape.id,
          colors: _gold,
          size: size,
        );
        expect(img.width, size, reason: shape.name);
        expect(img.height, size, reason: shape.name);
        final px = await _rgba(img);
        renders[shape.id] = px;
        final cov = _countColored(px);
        coverages[shape.id] = cov;
        final frac = cov / (size * size);
        expect(frac, greaterThan(0.03),
            reason: '${shape.name} coverage too low: $frac');
        expect(frac, lessThan(0.85),
            reason: '${shape.name} coverage too high: $frac');
        img.dispose();
      }
      // No two shapes may share the exact same coverage — a shared value
      // would be the fingerprint of a degenerate shared fallback path.
      final values = coverages.values.toList();
      expect(values.toSet().length, values.length,
          reason: 'coverages: $coverages');
      // And no two renders may be pixel-identical.
      final ids = renders.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(_bytesDiffer(renders[ids[i]]!, renders[ids[j]]!), isTrue,
              reason: '${ids[i]} vs ${ids[j]} rendered identically');
        }
      }
    });

    test('spot checks prove the shapes are what they claim', () async {
      const size = 256;
      Future<Uint8List> render(String id) async {
        final img =
            await renderLogoShape(shapeId: id, colors: _gold, size: size);
        final px = await _rgba(img);
        img.dispose();
        return px;
      }

      // Star: top point covered, upper-left area outside the point empty.
      final star = await render('star');
      expect(_alphaAt(star, size, 0.50, 0.11), greaterThan(8));
      expect(_alphaAt(star, size, 0.16, 0.16), 0);

      // Circle badge: centre covered, corner empty.
      final circle = await render('circle_badge');
      expect(_alphaAt(circle, size, 0.50, 0.50), greaterThan(8));
      expect(_alphaAt(circle, size, 0.04, 0.04), 0);

      // Heart: cleft at top-centre empty, bottom tip covered.
      final heart = await render('heart');
      expect(_alphaAt(heart, size, 0.50, 0.26), 0);
      expect(_alphaAt(heart, size, 0.50, 0.83), greaterThan(8));

      // Play triangle: body near the (rounded) tip covered, area above empty.
      // The tip corner is rounded with a 0.14 lerp, so at mid-height the
      // boundary sits near nx=0.868 — sample safely inside it.
      final play = await render('play_triangle');
      expect(_alphaAt(play, size, 0.78, 0.50), greaterThan(8));
      expect(_alphaAt(play, size, 0.50, 0.12), 0);

      // Ribbon: middle band covered, top area above the band empty.
      final ribbon = await render('ribbon_banner');
      expect(_alphaAt(ribbon, size, 0.50, 0.44), greaterThan(8));
      expect(_alphaAt(ribbon, size, 0.50, 0.10), 0);
    });

    test('single-color list still renders (duplicated internally)',
        () async {
      final img = await renderLogoShape(
        shapeId: 'star',
        colors: const <Color>[Color(0xFF00FF00)],
        size: 128,
      );
      final px = await _rgba(img);
      expect(_countColored(px), greaterThan(100));
      img.dispose();
    });
  });

  group('widgets', () {
    testWidgets('LogoTextCreator: type → preview → Use This Logo fires',
        (tester) async {
      ui.Image? created;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogoTextCreator(onCreated: (img) => created = img),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField), 'Nigraan');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Preview shows the rendered logo image.
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('Use This Logo'), findsOneWidget);

      await tester.tap(find.text('Use This Logo'));
      await tester.pump();
      expect(created, isNotNull);
      expect(created!.width, greaterThan(50));
      created!.dispose();
    });

    testWidgets('LogoTextCreator: rapid re-renders do not crash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogoTextCreator(onCreated: (_) {}),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField), 'A');
        await tester.enterText(find.byType(TextField), 'AB');
        await tester.enterText(find.byType(TextField), 'ABC');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('LogoShapePicker: 12 cells, pick a shape → onPicked fires',
        (tester) async {
      ui.Image? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogoShapePicker(onPicked: (img) => picked = img),
          ),
        ),
      );
      await tester.pump();

      for (final shape in kLogoShapes) {
        expect(find.text(shape.name), findsOneWidget, reason: shape.name);
      }
      expect(find.text('Color Scheme'), findsOneWidget);

      await tester.ensureVisible(find.text('Heart'));
      await tester.pump();
      await tester.tap(find.text('Heart'));
      await tester.pump();

      await tester.ensureVisible(find.text('Use This Shape'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use This Shape'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      expect(picked, isNotNull);
      expect(picked!.width, 512);
      expect(picked!.height, 512);
      picked!.dispose();
    });
  });
}
