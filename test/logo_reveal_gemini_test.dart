// Functional + pixel tests for the Gemini-generated Logo Reveal + Backdrops
// file (lib/logo/logo_reveal_backdrops.dart) — check phase before integration.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_reveal_backdrops.dart';

const Color _kOrange = Color(0xFFCC6633);
const Color _kBlue = Color(0xFF3366CC);

late ui.Image _logo;

Future<ui.Image> _makeLogoImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Two-tone asymmetric logo: left half orange, right half blue, fully opaque.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 30, 60),
    Paint()..color = _kOrange,
  );
  canvas.drawRect(
    const Rect.fromLTWH(30, 0, 30, 60),
    Paint()..color = _kBlue,
  );
  final picture = recorder.endRecording();
  return picture.toImage(60, 60);
}

Future<Uint8List> _renderReveal(
  String styleId,
  double progress, {
  int size = 200,
  Color? background,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = background,
    );
  }
  LogoRevealPainter(image: _logo, styleId: styleId, progress: progress)
      .paint(canvas, Size.square(size.toDouble()));
  final picture = recorder.endRecording();
  final out = await picture.toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _renderBackdrop(
  String backdropId, {
  double glowIntensity = 0.6,
  int w = 120,
  int h = 90,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LogoBackdropPainter(backdropId: backdropId, glowIntensity: glowIntensity)
      .paint(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

List<int> _px(Uint8List px, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return <int>[px[i], px[i + 1], px[i + 2], px[i + 3]];
}

int _countVisible(Uint8List px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 8) n++;
  }
  return n;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _hasNearWhite(Uint8List px) {
  for (var i = 0; i < px.length; i += 4) {
    if (px[i] > 235 && px[i + 1] > 235 && px[i + 2] > 235 && px[i + 3] > 8) {
      return true;
    }
  }
  return false;
}

void main() {
  setUp(() async {
    _logo = await _makeLogoImage();
  });

  group('metadata — prompt contract', () {
    test('reveal styles: exactly 6, exact ids/names/durations', () {
      expect(kLogoRevealStyles.length, 6);
      expect(
        kLogoRevealStyles.map((s) => s.id).toList(),
        <String>[
          'fade_zoom',
          'slide_wipe',
          'shine_sweep',
          'bounce_in',
          'spin_reveal',
          'rise_glow',
        ],
      );
      expect(
        kLogoRevealStyles.map((s) => s.name).toList(),
        <String>[
          'Fade Zoom',
          'Slide Wipe',
          'Shine Sweep',
          'Bounce In',
          'Spin Reveal',
          'Rise & Glow',
        ],
      );
      expect(
        kLogoRevealStyles.map((s) => s.durationMs).toList(),
        <int>[1200, 1000, 1400, 1100, 1300, 1500],
      );
    });

    test('backdrops: exactly 6, exact ids/names', () {
      expect(kLogoBackdrops.length, 6);
      expect(
        kLogoBackdrops.map((b) => b.id).toList(),
        <String>[
          'midnight_studio',
          'royal_stage',
          'neon_grid',
          'soft_spotlight',
          'deep_ocean',
          'plain_dark',
        ],
      );
      expect(
        kLogoBackdrops.map((b) => b.name).toList(),
        <String>[
          'Midnight Studio',
          'Royal Stage',
          'Neon Grid',
          'Soft Spotlight',
          'Deep Ocean',
          'Plain Dark',
        ],
      );
    });
  });

  group('LogoRevealPainter', () {
    test('progress 0 draws nothing for every style', () async {
      for (final s in kLogoRevealStyles) {
        final px = await _renderReveal(s.id, 0.0);
        expect(_countVisible(px), 0, reason: '${s.id} at progress 0');
      }
    });

    test('progress 1.0 end state is byte-identical for every style',
        () async {
      Uint8List? reference;
      for (final s in kLogoRevealStyles) {
        final px = await _renderReveal(s.id, 1.0);
        expect(_countVisible(px), greaterThan(0), reason: s.id);
        if (reference == null) {
          reference = px;
        } else {
          expect(
            _bytesEqual(px, reference),
            isTrue,
            reason: '${s.id} end state differs from fade_zoom',
          );
        }
      }
    });

    test('progress 0.5 every style draws and differs from its end state',
        () async {
      for (final s in kLogoRevealStyles) {
        final mid = await _renderReveal(s.id, 0.5);
        final end = await _renderReveal(s.id, 1.0);
        expect(_countVisible(mid), greaterThan(0), reason: '${s.id} mid');
        expect(
          _bytesEqual(mid, end),
          isFalse,
          reason: '${s.id} mid render must differ from settled state',
        );
      }
    });

    test('unknown styleId behaves exactly like fade_zoom', () async {
      final unknown = await _renderReveal('does_not_exist', 0.5);
      final fade = await _renderReveal('fade_zoom', 0.5);
      expect(_bytesEqual(unknown, fade), isTrue);
    });

    test(
        'shine_sweep: nothing outside the logo area, bright band on the logo',
        () async {
      final px = await _renderReveal('shine_sweep', 0.5);
      // Logo dest rect on a 200px canvas is the centered 160x160 box
      // (20..180). Corners and edge midpoints outside it stay transparent.
      for (final point in <List<int>>[
        <int>[5, 5],
        <int>[195, 5],
        <int>[5, 195],
        <int>[195, 195],
        <int>[100, 8],
        <int>[100, 192],
      ]) {
        expect(
          _px(px, 200, point[0], point[1])[3],
          0,
          reason: 'background pixel at $point must stay transparent',
        );
      }
      // The band must actually brighten some logo pixels to near white…
      expect(_hasNearWhite(px), isTrue);
      // …while the plain settled logo contains no near-white pixel at all.
      final plain = await _renderReveal('fade_zoom', 1.0);
      expect(_hasNearWhite(plain), isFalse);
    });

    test(
        'shine_sweep over a solid background: logo away from the band keeps '
        'its exact colour and the background stays untouched', () async {
      const grey = Color(0xFF808080);
      final px = await _renderReveal(
        'shine_sweep',
        0.5,
        background: grey,
      );
      // (30,30) is inside the orange half of the logo, far from the band
      // (band is near the centre at progress 0.5). If the whole logo were
      // screen-blended with the background, this pixel would wash out to
      // roughly (230,165,115) instead of the logo's own (204,102,51).
      final logoPixel = _px(px, 200, 30, 30);
      expect(logoPixel[0], inInclusiveRange(201, 207), reason: 'red');
      expect(logoPixel[1], inInclusiveRange(99, 105), reason: 'green');
      expect(logoPixel[2], inInclusiveRange(48, 54), reason: 'blue');
      expect(logoPixel[3], 255, reason: 'alpha');
      // A background-only pixel far from the logo keeps the exact grey.
      final bgPixel = _px(px, 200, 4, 4);
      expect(bgPixel, <int>[128, 128, 128, 255]);
    });

    test('shouldRepaint reacts to image/style/progress/glow changes', () {
      final base = LogoRevealPainter(
        image: _logo,
        styleId: 'fade_zoom',
        progress: 0.5,
      );
      expect(
        base.shouldRepaint(
          LogoRevealPainter(image: _logo, styleId: 'fade_zoom', progress: 0.5),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          LogoRevealPainter(image: _logo, styleId: 'fade_zoom', progress: 0.6),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          LogoRevealPainter(
            image: _logo,
            styleId: 'bounce_in',
            progress: 0.5,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          LogoRevealPainter(
            image: _logo,
            styleId: 'fade_zoom',
            progress: 0.5,
            glowColor: const Color(0xFFFF0000),
          ),
        ),
        isTrue,
      );
    });
  });

  group('LogoBackdropPainter', () {
    test('every backdrop fills the whole canvas opaquely', () async {
      for (final b in kLogoBackdrops) {
        final px = await _renderBackdrop(b.id);
        var minAlpha = 255;
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] < minAlpha) minAlpha = px[i];
        }
        expect(minAlpha, 255, reason: '${b.id} must cover every pixel');
      }
    });

    test('every backdrop is deterministic (two paints are identical)',
        () async {
      for (final b in kLogoBackdrops) {
        final first = await _renderBackdrop(b.id);
        final second = await _renderBackdrop(b.id);
        expect(
          _bytesEqual(first, second),
          isTrue,
          reason: '${b.id} repaint must be pixel-identical',
        );
      }
    });

    test('the 6 backdrops are pairwise different', () async {
      final renders = <String, Uint8List>{};
      for (final b in kLogoBackdrops) {
        renders[b.id] = await _renderBackdrop(b.id);
      }
      final ids = renders.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(
            _bytesEqual(renders[ids[i]]!, renders[ids[j]]!),
            isFalse,
            reason: '${ids[i]} vs ${ids[j]}',
          );
        }
      }
    });

    test('unknown backdropId renders exactly like plain_dark', () async {
      final unknown = await _renderBackdrop('does_not_exist');
      final plain = await _renderBackdrop('plain_dark');
      expect(_bytesEqual(unknown, plain), isTrue);
    });

    test('glowIntensity changes the render', () async {
      final dim = await _renderBackdrop('midnight_studio', glowIntensity: 0.0);
      final bright =
          await _renderBackdrop('midnight_studio', glowIntensity: 1.0);
      expect(_bytesEqual(dim, bright), isFalse);
    });

    test('shouldRepaint reacts to backdrop/glow changes', () {
      final base = LogoBackdropPainter(backdropId: 'neon_grid');
      expect(
        base.shouldRepaint(LogoBackdropPainter(backdropId: 'neon_grid')),
        isFalse,
      );
      expect(
        base.shouldRepaint(LogoBackdropPainter(backdropId: 'deep_ocean')),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          LogoBackdropPainter(backdropId: 'neon_grid', glowIntensity: 0.9),
        ),
        isTrue,
      );
    });
  });

  group('LogoRevealStudio widget', () {
    String percentText(WidgetTester tester) {
      final finder = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('%'),
      );
      return tester.widget<Text>(finder).data!;
    }

    Future<void> pumpStudio(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(home: LogoRevealStudio(logoImage: _logo)),
      );
    }

    testWidgets('mounts with title, all 12 chips and the Play button',
        (tester) async {
      await pumpStudio(tester);
      expect(find.text('Logo Reveal Studio'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      for (final s in kLogoRevealStyles) {
        expect(find.text(s.name), findsOneWidget, reason: 'style ${s.name}');
      }
      for (final b in kLogoBackdrops) {
        expect(find.text(b.name), findsOneWidget, reason: 'backdrop ${b.name}');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-play runs to the settled end state and stays there',
        (tester) async {
      await pumpStudio(tester);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(percentText(tester), contains('100%'));
      // Long after finishing, the logo stays settled (no repeat, no reset).
      await tester.pump(const Duration(seconds: 3));
      expect(percentText(tester), contains('100%'));
    });

    testWidgets('Play restarts the animation from 0', (tester) async {
      await pumpStudio(tester);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(percentText(tester), contains('100%'));
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(percentText(tester), isNot(contains('100%')));
      await tester.pump(const Duration(milliseconds: 1400));
      expect(percentText(tester), contains('100%'));
    });

    testWidgets('scrubbing the slider pauses auto-play at that progress',
        (tester) async {
      await pumpStudio(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(0.5);
      await tester.pump();
      expect(percentText(tester), contains('50%'));
      // If auto-play were still running it would finish within 1.2s;
      // after 3 more seconds the progress must still be exactly 50%.
      await tester.pump(const Duration(seconds: 3));
      expect(percentText(tester), contains('50%'));
    });

    testWidgets('tapping a style chip restarts with that style',
        (tester) async {
      await pumpStudio(tester);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(percentText(tester), contains('100%'));
      await tester.tap(find.text('Spin Reveal'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(percentText(tester), isNot(contains('100%')));
      expect(percentText(tester), contains('1300ms'));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(percentText(tester), contains('100%'));
    });

    testWidgets('unmounting disposes the controller cleanly', (tester) async {
      await pumpStudio(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
