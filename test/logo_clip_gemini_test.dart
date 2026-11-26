// Functional + pixel + widget tests for the Gemini-generated Logo Clip file
// (lib/logo/logo_clip.dart) — check phase before integration.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_clip.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBackdropPainter extends CustomPainter {
  _FakeBackdropPainter(this.log, this.color);

  final List<String> log;
  final Color color;
  Size? lastSize;

  @override
  void paint(Canvas canvas, Size size) {
    log.add('backdrop');
    lastSize = size;
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FakeBackdropPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FakeRevealPainter extends CustomPainter {
  _FakeRevealPainter(this.log);

  final List<String> log;

  @override
  void paint(Canvas canvas, Size size) {
    log.add('reveal');
    canvas.drawRect(
      const Rect.fromLTWH(2, 2, 6, 6),
      Paint()..color = const Color(0xFF00FF00),
    );
  }

  @override
  bool shouldRepaint(covariant _FakeRevealPainter oldDelegate) => false;
}

class _Recorder {
  ui.Image? lastImage;
  double? lastProgress;
  double? lastSpinAngle;
  int calls = 0;

  // A single stored closure instance — identity must be stable across calls
  // (a fresh closure per access would defeat painter identity checks).
  late final LogoClipRevealPainterBuilder builder;

  _Recorder() {
    builder = (ui.Image image, double progress, double spinAngle) {
      calls++;
      lastImage = image;
      lastProgress = progress;
      lastSpinAngle = spinAngle;
      return _FakeRevealPainter(<String>[]);
    };
  }
}

Future<ui.Image> _makeLogoImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 20, 20),
    Paint()..color = const Color(0xFFCC6633),
  );
  return recorder.endRecording().toImage(20, 20);
}

Future<Uint8List> _renderClip(
  LogoClipPainter painter, {
  int w = 100,
  int h = 80,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

void main() {
  group('LogoClipSettings validation', () {
    test('defaults are exactly as specified', () {
      const s = LogoClipSettings.defaults;
      expect(s.durationSec, 5);
      expect(s.aspectId, 'wide');
      expect(s.revealStyleId, 'fade_zoom');
      expect(s.backdropId, 'midnight_studio');
      expect(s.backdropGlow, 0.6);
      expect(s.spinAfterReveal, isFalse);
      expect(s.spinSpeed, 1.0);
      expect(s.revealDurationMs, 1200);
      expect(s.outputSize, const Size(1920, 1080));
      expect(s, const LogoClipSettings());
    });

    test('durationSec snaps to nearest of 3/5/8', () {
      final cases = <int, int>{
        -5: 3, 0: 3, 1: 3, 2: 3, 3: 3, 4: 3,
        5: 5, 6: 5, 7: 8, 8: 8, 9: 8, 100: 8,
      };
      cases.forEach((input, want) {
        expect(LogoClipSettings(durationSec: input).durationSec, want,
            reason: 'durationSec $input');
      });
    });

    test('aspectId: unknown falls back to wide; sizes are exact', () {
      expect(const LogoClipSettings(aspectId: 'bogus').aspectId, 'wide');
      expect(const LogoClipSettings(aspectId: '').aspectId, 'wide');
      expect(const LogoClipSettings(aspectId: 'square').outputSize,
          const Size(1080, 1080));
      expect(const LogoClipSettings(aspectId: 'portrait').outputSize,
          const Size(1080, 1920));
      expect(const LogoClipSettings(aspectId: 'wide').outputSize,
          const Size(1920, 1080));
    });

    test('revealStyleId: unknown falls back to fade_zoom; duration map exact',
        () {
      expect(const LogoClipSettings(revealStyleId: 'bogus').revealStyleId,
          'fade_zoom');
      final map = <String, int>{
        'fade_zoom': 1200,
        'slide_wipe': 1000,
        'shine_sweep': 1400,
        'bounce_in': 1100,
        'spin_reveal': 1300,
        'rise_glow': 1500,
        'none': 0,
      };
      map.forEach((id, ms) {
        final s = LogoClipSettings(revealStyleId: id);
        expect(s.revealStyleId, id);
        expect(s.revealDurationMs, ms, reason: id);
      });
    });

    test('backdropId: unknown falls back to plain_dark, valid ids kept', () {
      expect(const LogoClipSettings(backdropId: 'bogus').backdropId,
          'plain_dark');
      for (final id in LogoClipSettings.allowedBackdropIds) {
        expect(LogoClipSettings(backdropId: id).backdropId, id);
      }
    });

    test('glow and spinSpeed clamp, NaN falls back to defaults', () {
      expect(const LogoClipSettings(backdropGlow: -0.5).backdropGlow, 0.0);
      expect(const LogoClipSettings(backdropGlow: 1.5).backdropGlow, 1.0);
      expect(LogoClipSettings(backdropGlow: double.nan).backdropGlow, 0.6);
      expect(const LogoClipSettings(spinSpeed: 0.0).spinSpeed, 0.5);
      expect(const LogoClipSettings(spinSpeed: 99.0).spinSpeed, 3.0);
      expect(LogoClipSettings(spinSpeed: double.nan).spinSpeed, 1.0);
    });

    test('equality and hashCode cover every field', () {
      const a = LogoClipSettings(
        durationSec: 8,
        aspectId: 'square',
        revealStyleId: 'bounce_in',
        backdropId: 'neon_grid',
        backdropGlow: 0.25,
        spinAfterReveal: true,
        spinSpeed: 2.0,
      );
      const b = LogoClipSettings(
        durationSec: 8,
        aspectId: 'square',
        revealStyleId: 'bounce_in',
        backdropId: 'neon_grid',
        backdropGlow: 0.25,
        spinAfterReveal: true,
        spinSpeed: 2.0,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(durationSec: 3), isFalse);
      expect(a == a.copyWith(aspectId: 'wide'), isFalse);
      expect(a == a.copyWith(revealStyleId: 'none'), isFalse);
      expect(a == a.copyWith(backdropId: 'plain_dark'), isFalse);
      expect(a == a.copyWith(backdropGlow: 0.5), isFalse);
      expect(a == a.copyWith(spinAfterReveal: false), isFalse);
      expect(a == a.copyWith(spinSpeed: 1.0), isFalse);
      expect(a.copyWith(), a);
    });

    test('toJson/fromJson round-trips', () {
      const s = LogoClipSettings(
        durationSec: 3,
        aspectId: 'portrait',
        revealStyleId: 'rise_glow',
        backdropId: 'deep_ocean',
        backdropGlow: 0.9,
        spinAfterReveal: true,
        spinSpeed: 2.5,
      );
      final back = LogoClipSettings.fromJson(
          Map<dynamic, dynamic>.from(s.toJson()));
      expect(back, s);
    });

    test('fromJson is fail-soft: empty, wrong types, NaN, partial', () {
      const d = LogoClipSettings.defaults;
      expect(LogoClipSettings.fromJson(<dynamic, dynamic>{}), d);
      expect(
        LogoClipSettings.fromJson(<dynamic, dynamic>{
          'durationSec': 'five',
          'aspectId': 42,
          'revealStyleId': true,
          'backdropId': 7.5,
          'backdropGlow': 'high',
          'spinAfterReveal': 'yes',
          'spinSpeed': 'fast',
        }),
        d,
      );
      expect(
        LogoClipSettings.fromJson(<dynamic, dynamic>{
          'backdropGlow': double.nan,
          'spinSpeed': double.nan,
        }),
        d,
      );
      final partial = LogoClipSettings.fromJson(
          <dynamic, dynamic>{'durationSec': 8, 'spinAfterReveal': true});
      expect(partial.durationSec, 8);
      expect(partial.spinAfterReveal, isTrue);
      expect(partial.backdropId, 'midnight_studio'); // missing → default
      expect(partial.aspectId, 'wide');
      // Unknown ids inside JSON go through the constructor fallbacks.
      final unknown = LogoClipSettings.fromJson(
          <dynamic, dynamic>{'backdropId': 'nope', 'aspectId': 'nope'});
      expect(unknown.backdropId, 'plain_dark');
      expect(unknown.aspectId, 'wide');
      // A JSON-style Map<String, dynamic> works too.
      final fromStringKeyed = LogoClipSettings.fromJson(
          <dynamic, dynamic>{'durationSec': 3});
      expect(fromStringKeyed.durationSec, 3);
    });
  });

  group('timing helpers', () {
    test('reveal progress: none is always 1, linear otherwise', () {
      const none = LogoClipSettings(revealStyleId: 'none');
      expect(logoClipRevealProgress(none, -100), 1.0);
      expect(logoClipRevealProgress(none, 0), 1.0);
      expect(logoClipRevealProgress(none, 500), 1.0);

      const fade = LogoClipSettings(); // 1200ms
      expect(logoClipRevealProgress(fade, -1), 0.0);
      expect(logoClipRevealProgress(fade, 0), 0.0);
      expect(logoClipRevealProgress(fade, 600), 0.5);
      expect(logoClipRevealProgress(fade, 1200), 1.0);
      expect(logoClipRevealProgress(fade, 9999), 1.0);

      const wipe = LogoClipSettings(revealStyleId: 'slide_wipe'); // 1000ms
      expect(logoClipRevealProgress(wipe, 250), 0.25);
    });

    test('spin angle: 0 during reveal / when off, linear after', () {
      const off = LogoClipSettings(); // spinAfterReveal false
      expect(logoClipSpinAngle(off, 999999), 0.0);

      const on = LogoClipSettings(spinAfterReveal: true); // fade 1200, x1.0
      expect(logoClipSpinAngle(on, 0), 0.0);
      expect(logoClipSpinAngle(on, 600), 0.0);
      expect(logoClipSpinAngle(on, 1200), 0.0);
      expect(logoClipSpinAngle(on, 1200 + 6000), closeTo(math.pi, 1e-9));
      expect(logoClipSpinAngle(on, 1200 + 12000), closeTo(2 * math.pi, 1e-9));

      const fast =
          LogoClipSettings(spinAfterReveal: true, spinSpeed: 2.0);
      expect(logoClipSpinAngle(fast, 1200 + 6000), closeTo(2 * math.pi, 1e-9));

      const noReveal =
          LogoClipSettings(revealStyleId: 'none', spinAfterReveal: true);
      expect(logoClipSpinAngle(noReveal, 6000), closeTo(math.pi, 1e-9));
    });

    test('frame count clamps fps to 1..60', () {
      const s = LogoClipSettings(); // 5s
      expect(logoClipFrameCount(s, 30), 150);
      expect(logoClipFrameCount(s, 0), 5);
      expect(logoClipFrameCount(s, -10), 5);
      expect(logoClipFrameCount(s, 100), 300);
      expect(logoClipFrameCount(const LogoClipSettings(durationSec: 3), 24),
          72);
    });
  });

  group('LogoClipPainter', () {
    late ui.Image logo;

    setUpAll(() async {
      logo = await _makeLogoImage();
    });

    test('paints backdrop first, then logo; builders get exact values',
        () async {
      final log = <String>[];
      final backdrop = _FakeBackdropPainter(log, const Color(0xFFFF0000));
      final rec = _Recorder();
      CustomPainter builder(ui.Image img, double p, double a) {
        rec.builder(img, p, a);
        return _FakeRevealPainter(log);
      }
      const settings = LogoClipSettings(spinAfterReveal: true);
      final painter = LogoClipPainter(
        logoImage: logo,
        settings: settings,
        timeMs: 1200 + 6000,
        backdropPainter: backdrop,
        revealPainterFor: builder,
      );
      await _renderClip(painter);
      expect(log, <String>['backdrop', 'reveal']);
      expect(backdrop.lastSize, const Size(100, 80));
      expect(rec.calls, 1);
      expect(identical(rec.lastImage, logo), isTrue);
      expect(rec.lastProgress, 1.0);
      expect(rec.lastSpinAngle, closeTo(math.pi, 1e-9));
    });

    test('mid-reveal progress is passed through', () async {
      final rec = _Recorder();
      final painter = LogoClipPainter(
        logoImage: logo,
        settings: const LogoClipSettings(),
        timeMs: 600,
        backdropPainter: _FakeBackdropPainter(<String>[], Colors.red),
        revealPainterFor: rec.builder,
      );
      await _renderClip(painter);
      expect(rec.lastProgress, 0.5);
      expect(rec.lastSpinAngle, 0.0);
    });

    test('deterministic: same inputs render identical pixels', () async {
      LogoClipPainter make(int t) => LogoClipPainter(
            logoImage: logo,
            settings: const LogoClipSettings(),
            timeMs: t,
            backdropPainter:
                _FakeBackdropPainter(<String>[], const Color(0xFF102030)),
            revealPainterFor: _Recorder().builder,
          );
      final a = await _renderClip(make(600));
      final b = await _renderClip(make(600));
      expect(_bytesEqual(a, b), isTrue);
    });

    test('empty size draws nothing and does not throw', () {
      final log = <String>[];
      final painter = LogoClipPainter(
        logoImage: logo,
        settings: const LogoClipSettings(),
        timeMs: 100,
        backdropPainter: _FakeBackdropPainter(log, Colors.red),
        revealPainterFor: _Recorder().builder,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, Size.zero);
      painter.paint(canvas, const Size(0, 50));
      recorder.endRecording();
      expect(log, isEmpty);
    });

    test('shouldRepaint compares all fields', () {
      final backdrop = _FakeBackdropPainter(<String>[], Colors.red);
      final rec = _Recorder();
      LogoClipPainter make({
        int timeMs = 100,
        LogoClipSettings settings = const LogoClipSettings(),
        CustomPainter? bp,
      }) =>
          LogoClipPainter(
            logoImage: logo,
            settings: settings,
            timeMs: timeMs,
            backdropPainter: bp ?? backdrop,
            revealPainterFor: rec.builder,
          );
      final base = make();
      expect(make().shouldRepaint(base), isFalse);
      expect(make(timeMs: 101).shouldRepaint(base), isTrue);
      expect(
          make(settings: const LogoClipSettings(durationSec: 8))
              .shouldRepaint(base),
          isTrue);
      expect(
          make(bp: _FakeBackdropPainter(<String>[], Colors.red))
              .shouldRepaint(base),
          isTrue);
    });
  });

  group('LogoClipPreview widget', () {
    late ui.Image logo;

    setUpAll(() async {
      logo = await _makeLogoImage();
    });

    Widget app({
      LogoClipSettings initial = LogoClipSettings.defaults,
      void Function(LogoClipSettings)? onChanged,
    }) {
      return MaterialApp(
        home: LogoClipPreview(
          logoImage: logo,
          backdropPainterFor: (String id, double glow) =>
              _FakeBackdropPainter(<String>[], const Color(0xFF102030)),
          revealPainterFor: (ui.Image img, double p, double a) =>
              _FakeRevealPainter(<String>[]),
          initialSettings: initial,
          onSettingsChanged: onChanged,
        ),
      );
    }

    Slider sliderAt(WidgetTester tester, int index) =>
        tester.widgetList<Slider>(find.byType(Slider)).elementAt(index);

    testWidgets('mounts with all controls and fixed 46% preview height',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget); // auto-playing
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Aspect'), findsOneWidget);
      expect(find.text('Reveal'), findsOneWidget);
      expect(find.text('Backdrop'), findsOneWidget);
      expect(find.text('Spin after reveal'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      // 800x600 test surface → 0.46 * 600 = 276.
      final sized = find.byWidgetPredicate((w) =>
          w is SizedBox && w.height != null && (w.height! - 276).abs() < 0.5);
      expect(sized, findsOneWidget);
    });

    testWidgets('auto-play advances the scrub slider', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      final before = sliderAt(tester, 0).value;
      await tester.pump(const Duration(milliseconds: 600));
      final after = sliderAt(tester, 0).value;
      expect(after, greaterThan(before + 100));
    });

    testWidgets('Pause tap stops playback; Play resumes', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      final parked = sliderAt(tester, 0).value;
      await tester.pump(const Duration(seconds: 1));
      expect(sliderAt(tester, 0).value, parked);
      await tester.tap(find.text('Play'));
      await tester.pump(); // process the tap; the ticker starts this frame
      await tester.pump(const Duration(milliseconds: 400));
      expect(sliderAt(tester, 0).value, greaterThan(parked));
    });

    testWidgets('scrubbing the slider parks the animation', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.drag(find.byType(Slider).first, const Offset(120, 0));
      await tester.pump();
      expect(find.text('Play'), findsOneWidget); // stopped
      final parked = sliderAt(tester, 0).value;
      expect(parked, greaterThan(0));
      await tester.pump(const Duration(seconds: 1));
      expect(sliderAt(tester, 0).value, parked);
    });

    testWidgets('every chip row reports through onSettingsChanged',
        (tester) async {
      final seen = <LogoClipSettings>[];
      await tester.pumpWidget(app(onChanged: seen.add));
      await tester.pump();

      await tester.tap(find.text('8s'));
      await tester.pump();
      expect(seen.last.durationSec, 8);

      await tester.tap(find.text('Square'));
      await tester.pump();
      expect(seen.last.aspectId, 'square');

      await tester.ensureVisible(find.text('Shine Sweep'));
      await tester.pump();
      await tester.tap(find.text('Shine Sweep'));
      await tester.pump();
      expect(seen.last.revealStyleId, 'shine_sweep');

      await tester.ensureVisible(find.text('Deep Ocean'));
      await tester.pump();
      await tester.tap(find.text('Deep Ocean'));
      await tester.pump();
      expect(seen.last.backdropId, 'deep_ocean');

      expect(seen.length, 4);
    });

    testWidgets('duration change preserves the time proportion',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      // Pause first, then park at ~half of the 5s clip via the slider value.
      await tester.tap(find.text('Pause'));
      await tester.pump();
      await tester.drag(find.byType(Slider).first, const Offset(150, 0));
      await tester.pump();
      final beforeMs = sliderAt(tester, 0).value;
      final fraction = beforeMs / 5000.0;
      expect(fraction, greaterThan(0.2));
      expect(fraction, lessThan(0.9));

      await tester.tap(find.text('8s'));
      await tester.pump();
      final slider = sliderAt(tester, 0);
      expect(slider.max, 8000);
      expect(slider.value / 8000.0, closeTo(fraction, 0.03));
    });

    testWidgets('spin switch reports and reveals the speed slider',
        (tester) async {
      final seen = <LogoClipSettings>[];
      await tester.pumpWidget(app(onChanged: seen.add));
      await tester.pump();
      expect(find.text('Spin speed'), findsNothing);
      await tester.ensureVisible(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(seen.last.spinAfterReveal, isTrue);
      expect(find.text('Spin speed'), findsOneWidget);
    });

    testWidgets('glow slider reports a changed glow value', (tester) async {
      final seen = <LogoClipSettings>[];
      await tester.pumpWidget(app(onChanged: seen.add));
      await tester.pump();
      // Slider order: 0 = playback scrub, 1 = backdrop glow.
      await tester.ensureVisible(find.byType(Slider).at(1));
      await tester.pump();
      await tester.drag(find.byType(Slider).at(1), const Offset(-80, 0));
      await tester.pump();
      expect(seen, isNotEmpty);
      expect(seen.last.backdropGlow, lessThan(0.6));
    });

    testWidgets('unmount disposes cleanly', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
