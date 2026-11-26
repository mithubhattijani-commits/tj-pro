// CHECK #6 — Gemini Logo Lighting + Camera: spec-conformance tests.
// Spec: ~/workspace/your_files/MASTER-PROMPT-LOGO-LIGHTING-CAMERA.txt
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_lighting_camera.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<ui.Image> _makeImage(
  int w,
  int h,
  void Function(Canvas canvas, Size size) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final img = await picture.toImage(w, h);
  picture.dispose();
  return img;
}

Future<ui.Image> _uniformImage(int w, int h, Color color) {
  return _makeImage(w, h, (canvas, size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color,
    );
  });
}

/// White square (25%..75%) on a fully transparent canvas.
Future<ui.Image> _centredSquareImage(int w, int h) {
  return _makeImage(w, h, (canvas, size) {
    canvas.drawRect(
      Rect.fromLTRB(w * 0.25, h * 0.25, w * 0.75, h * 0.75),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  });
}

Future<Uint8List> _renderPainter(CustomPainter painter, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final img = await picture.toImage(w, h);
  picture.dispose();
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return data!.buffer.asUint8List();
}

List<int> _px(Uint8List b, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return <int>[b[i], b[i + 1], b[i + 2], b[i + 3]];
}

double _brightness(List<int> p) => (p[0] + p[1] + p[2]) / 3.0;

double _regionBrightness(
  Uint8List b,
  int w,
  int x0,
  int x1,
  int y0,
  int y1,
) {
  var sum = 0.0;
  var count = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      sum += _brightness(_px(b, w, x, y));
      count++;
    }
  }
  return sum / count;
}

int _countWhere(Uint8List b, bool Function(List<int> p) test) {
  var n = 0;
  for (var i = 0; i < b.length; i += 4) {
    if (test(<int>[b[i], b[i + 1], b[i + 2], b[i + 3]])) n++;
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

int _diffCount(Uint8List a, Uint8List b) {
  var n = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

void main() {
  group('LogoLightingCameraSettings — defaults & equality', () {
    test('defaults are exactly the spec values', () {
      const s = LogoLightingCameraSettings.defaults;
      expect(s.lightingOn, isFalse);
      expect(s.lightAngleDeg, -35);
      expect(s.lightIntensity, 0.6);
      expect(s.shadowDepth, 0.45);
      expect(s.rimGlow, 0.0);
      expect(s.cameraTiltX, 0.0);
      expect(s.cameraTiltY, 0.0);
      expect(s.cameraZoom, 1.0);
      expect(s.cameraRotationDeg, 0.0);
      expect(const LogoLightingCameraSettings(), s);
    });

    test('== and hashCode by value', () {
      const a = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 10,
        rimGlow: 0.5,
      );
      const b = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 10,
        rimGlow: 0.5,
      );
      const c = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 11,
        rimGlow: 0.5,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith changes only the named field and clamps', () {
      const s = LogoLightingCameraSettings.defaults;
      final t = s.copyWith(cameraZoom: 99);
      expect(t.cameraZoom, 1.8);
      expect(t.lightAngleDeg, s.lightAngleDeg);
      expect(s.copyWith(lightAngleDeg: -999).lightAngleDeg, -180);
      expect(s.copyWith(lightIntensity: -1).lightIntensity, 0);
      expect(s.copyWith(cameraRotationDeg: 45).cameraRotationDeg, 30);
    });
  });

  group('LogoLightingCameraSettings — JSON', () {
    test('toJson/fromJson roundtrip preserves a custom settings', () {
      const s = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 123,
        lightIntensity: 0.25,
        shadowDepth: 0.75,
        rimGlow: 0.4,
        cameraTiltX: -0.3,
        cameraTiltY: 0.8,
        cameraZoom: 1.4,
        cameraRotationDeg: -12,
      );
      final back = LogoLightingCameraSettings.fromJson(s.toJson());
      expect(back, s);
    });

    test('fromJson never throws on garbage and falls back to defaults', () {
      const d = LogoLightingCameraSettings.defaults;
      expect(LogoLightingCameraSettings.fromJson(null), d);
      expect(LogoLightingCameraSettings.fromJson('nonsense'), d);
      expect(LogoLightingCameraSettings.fromJson(42), d);
      expect(LogoLightingCameraSettings.fromJson(const <int>[1, 2]), d);
      expect(LogoLightingCameraSettings.fromJson(const <String, dynamic>{}), d);
    });

    test('fromJson: bad field values fall back per-field, good ones survive',
        () {
      final s = LogoLightingCameraSettings.fromJson(<String, dynamic>{
        'lightingOn': 'yes', // not a bool -> default false
        'lightAngleDeg': 'abc', // not a num -> default -35
        'lightIntensity': 0.9, // good
        'shadowDepth': double.nan, // non-finite -> default 0.45
        'rimGlow': double.infinity, // non-finite -> default 0
        'cameraTiltX': 7, // int num, clamps to 1
        'cameraZoom': 0.1, // clamps to 0.6
        'cameraRotationDeg': -20, // int num -> -20.0
      });
      expect(s.lightingOn, isFalse);
      expect(s.lightAngleDeg, -35);
      expect(s.lightIntensity, 0.9);
      expect(s.shadowDepth, 0.45);
      expect(s.rimGlow, 0.0);
      expect(s.cameraTiltX, 1.0);
      expect(s.cameraZoom, 0.6);
      expect(s.cameraRotationDeg, -20.0);
    });
  });

  group('LogoLightingCameraSettings — isNeutral', () {
    test('defaults are neutral', () {
      expect(LogoLightingCameraSettings.defaults.isNeutral, isTrue);
    });

    test('lighting on (camera neutral) is NOT neutral', () {
      expect(
        const LogoLightingCameraSettings(lightingOn: true).isNeutral,
        isFalse,
      );
    });

    test('lighting off: rim/shadow/intensity do not affect neutrality', () {
      expect(
        const LogoLightingCameraSettings(
          rimGlow: 0.9,
          shadowDepth: 1,
          lightIntensity: 0,
        ).isNeutral,
        isTrue,
      );
    });

    test('any camera change alone breaks neutrality', () {
      expect(
        const LogoLightingCameraSettings(cameraZoom: 1.1).isNeutral,
        isFalse,
      );
      expect(
        const LogoLightingCameraSettings(cameraTiltX: 0.1).isNeutral,
        isFalse,
      );
      expect(
        const LogoLightingCameraSettings(cameraTiltY: -0.1).isNeutral,
        isFalse,
      );
      expect(
        const LogoLightingCameraSettings(cameraRotationDeg: 5).isNeutral,
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Presets
  // -------------------------------------------------------------------------

  group('kLogoLightPresets — exact spec values', () {
    test('exactly 6 presets, exact ids and names, in order', () {
      expect(kLogoLightPresets.length, 6);
      expect(
        kLogoLightPresets.map((p) => p.id).toList(),
        <String>[
          'none',
          'studio_soft',
          'dramatic_side',
          'top_light',
          'neon_rim',
          'stage_tilt',
        ],
      );
      expect(
        kLogoLightPresets.map((p) => p.name).toList(),
        <String>[
          'No Light',
          'Studio Soft',
          'Dramatic Side',
          'Top Light',
          'Neon Rim',
          'Stage Tilt',
        ],
      );
    });

    void checkPreset(
      String id, {
      required bool on,
      required double angle,
      required double intensity,
      required double shadow,
      required double rim,
      double tiltX = 0,
      double tiltY = 0,
      double zoom = 1,
      double rotation = 0,
    }) {
      final p = kLogoLightPresets.firstWhere((e) => e.id == id);
      expect(p.settings.lightingOn, on, reason: '$id lightingOn');
      expect(p.settings.lightAngleDeg, angle, reason: '$id angle');
      expect(p.settings.lightIntensity, intensity, reason: '$id intensity');
      expect(p.settings.shadowDepth, shadow, reason: '$id shadow');
      expect(p.settings.rimGlow, rim, reason: '$id rim');
      expect(p.settings.cameraTiltX, tiltX, reason: '$id tiltX');
      expect(p.settings.cameraTiltY, tiltY, reason: '$id tiltY');
      expect(p.settings.cameraZoom, zoom, reason: '$id zoom');
      expect(p.settings.cameraRotationDeg, rotation, reason: '$id rotation');
    }

    test('every preset carries the exact spec settings', () {
      checkPreset('none',
          on: false, angle: -35, intensity: 0.6, shadow: 0.45, rim: 0);
      checkPreset('studio_soft',
          on: true, angle: -50, intensity: 0.45, shadow: 0.3, rim: 0.15);
      checkPreset('dramatic_side',
          on: true,
          angle: 5,
          intensity: 0.85,
          shadow: 0.7,
          rim: 0.3,
          tiltY: 0.15);
      checkPreset('top_light',
          on: true,
          angle: -90,
          intensity: 0.65,
          shadow: 0.5,
          rim: 0.2,
          tiltX: -0.1);
      checkPreset('neon_rim',
          on: true, angle: 160, intensity: 0.5, shadow: 0.35, rim: 0.9);
      checkPreset('stage_tilt',
          on: true,
          angle: -35,
          intensity: 0.6,
          shadow: 0.45,
          rim: 0.25,
          tiltX: 0.2,
          tiltY: -0.25,
          zoom: 1.1,
          rotation: -4);
      expect(
        kLogoLightPresets.first.settings,
        LogoLightingCameraSettings.defaults,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Painter
  // -------------------------------------------------------------------------

  group('LogoLightingCameraPainter — pixels', () {
    test('neutral output is pixel-identical to a plain contain-fit draw',
        () async {
      final img = await _uniformImage(100, 100, const Color(0xFF808080));
      final got = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: LogoLightingCameraSettings.defaults,
        ),
        100,
        100,
      );
      // Reference: background fill + plain drawImageRect (default Paint).
      final ref = await _renderPainter(
        _PlainDrawPainter(img),
        100,
        100,
      );
      final diffs = _diffCount(got, ref);
      // ignore: avoid_print
      print('NEUTRAL PIXEL DIFF BYTES: $diffs / ${got.length}');
      expect(_bytesEqual(got, ref), isTrue,
          reason: 'neutral render differed in $diffs bytes');
      img.dispose();
    });

    test('background colour fills the corners around a fitted logo',
        () async {
      final img = await _centredSquareImage(50, 100);
      final got = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: LogoLightingCameraSettings.defaults,
        ),
        100,
        100,
      );
      // 50x100 image contain-fits to 50x100 centred -> corners are background.
      expect(_px(got, 100, 2, 2), <int>[5, 9, 20, 255]);
      expect(_px(got, 100, 97, 97), <int>[5, 9, 20, 255]);
      img.dispose();
    });

    test('light from the right (angle 0): right side brighter than left',
        () async {
      final img = await _uniformImage(100, 100, const Color(0xFF808080));
      final got = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: const LogoLightingCameraSettings(
            lightingOn: true,
            lightAngleDeg: 0,
            lightIntensity: 0.6,
            shadowDepth: 0.45,
            rimGlow: 0,
          ),
        ),
        100,
        100,
      );
      final left = _regionBrightness(got, 100, 5, 30, 10, 90);
      final right = _regionBrightness(got, 100, 70, 95, 10, 90);
      // ignore: avoid_print
      print('ANGLE0 left=$left right=$right');
      expect(right, greaterThan(left + 3),
          reason: 'light side (right) must be brighter: L=$left R=$right');
      img.dispose();
    });

    test('light from the left (angle 180): left side brighter than right',
        () async {
      final img = await _uniformImage(100, 100, const Color(0xFF808080));
      final got = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: const LogoLightingCameraSettings(
            lightingOn: true,
            lightAngleDeg: 180,
            lightIntensity: 0.6,
            shadowDepth: 0.45,
            rimGlow: 0,
          ),
        ),
        100,
        100,
      );
      final left = _regionBrightness(got, 100, 5, 30, 10, 90);
      final right = _regionBrightness(got, 100, 70, 95, 10, 90);
      // ignore: avoid_print
      print('ANGLE180 left=$left right=$right');
      expect(left, greaterThan(right + 3),
          reason: 'light side (left) must be brighter: L=$left R=$right');
      img.dispose();
    });

    test('light from the top (angle -90): top brighter than bottom', () async {
      final img = await _uniformImage(100, 100, const Color(0xFF808080));
      final got = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: const LogoLightingCameraSettings(
            lightingOn: true,
            lightAngleDeg: -90,
            lightIntensity: 0.6,
            shadowDepth: 0.45,
            rimGlow: 0,
          ),
        ),
        100,
        100,
      );
      final top = _regionBrightness(got, 100, 10, 90, 5, 30);
      final bottom = _regionBrightness(got, 100, 10, 90, 70, 95);
      // ignore: avoid_print
      print('ANGLE-90 top=$top bottom=$bottom');
      expect(top, greaterThan(bottom + 3),
          reason: 'light side (top) must be brighter: T=$top B=$bottom');
      img.dispose();
    });

    test('more shadowDepth darkens the far side more', () async {
      final img = await _uniformImage(100, 100, const Color(0xFF808080));
      Future<double> farSide(double shadow) async {
        final got = await _renderPainter(
          LogoLightingCameraPainter(
            logoImage: img,
            settings: LogoLightingCameraSettings(
              lightingOn: true,
              lightAngleDeg: 0,
              lightIntensity: 0,
              shadowDepth: shadow,
              rimGlow: 0,
            ),
          ),
          100,
          100,
        );
        return _regionBrightness(got, 100, 2, 25, 10, 90);
      }

      final none = await farSide(0);
      final deep = await farSide(0.9);
      // ignore: avoid_print
      print('SHADOW far side: depth0=$none depth0.9=$deep');
      expect(deep, lessThan(none - 5),
          reason: 'far side must darken with shadowDepth: $none -> $deep');
      img.dispose();
    });

    test('rimGlow adds cyan-tinted pixels that rim 0 does not have', () async {
      final img = await _centredSquareImage(100, 100);
      Future<int> cyanCount(double rim) async {
        final got = await _renderPainter(
          LogoLightingCameraPainter(
            logoImage: img,
            settings: LogoLightingCameraSettings(
              lightingOn: true,
              lightAngleDeg: 0,
              lightIntensity: 0.6,
              shadowDepth: 0.45,
              rimGlow: rim,
            ),
          ),
          100,
          100,
        );
        return _countWhere(
          got,
          (p) => p[1] - p[0] > 30 && p[2] - p[0] > 30,
        );
      }

      final noRim = await cyanCount(0);
      final rim = await cyanCount(0.9);
      // ignore: avoid_print
      print('RIM cyan pixels: rim0=$noRim rim0.9=$rim');
      expect(noRim, 0);
      expect(rim, greaterThan(0),
          reason: 'rim glow must introduce cyan edge pixels');
      img.dispose();
    });

    test('cameraZoom 1.5 makes the logo occupy more area', () async {
      final img = await _centredSquareImage(100, 100);
      Future<int> whiteCount(double zoom) async {
        final got = await _renderPainter(
          LogoLightingCameraPainter(
            logoImage: img,
            settings: LogoLightingCameraSettings(cameraZoom: zoom),
          ),
          200,
          200,
        );
        return _countWhere(got, (p) => p[0] > 200 && p[1] > 200 && p[2] > 200);
      }

      final z1 = await whiteCount(1.0);
      final z15 = await whiteCount(1.5);
      // ignore: avoid_print
      print('ZOOM white pixels: 1.0=$z1 1.5=$z15');
      expect(z15, greaterThan(z1 * 1.8),
          reason: 'zoom 1.5 should roughly square the area: $z1 -> $z15');
      img.dispose();
    });

    test('rotation and tilt change the output without crashing', () async {
      final img = await _centredSquareImage(100, 100);
      final neutral = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: LogoLightingCameraSettings.defaults,
        ),
        100,
        100,
      );
      final rotated = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: const LogoLightingCameraSettings(cameraRotationDeg: 20),
        ),
        100,
        100,
      );
      final tilted = await _renderPainter(
        LogoLightingCameraPainter(
          logoImage: img,
          settings: const LogoLightingCameraSettings(cameraTiltY: 0.8),
        ),
        100,
        100,
      );
      expect(_bytesEqual(rotated, neutral), isFalse);
      expect(_bytesEqual(tilted, neutral), isFalse);
      img.dispose();
    });

    test('zero-size canvas and 1x1 image do not crash', () async {
      final tiny = await _uniformImage(1, 1, const Color(0xFFFF0000));
      final painter = LogoLightingCameraPainter(
        logoImage: tiny,
        settings: const LogoLightingCameraSettings(
          lightingOn: true,
          rimGlow: 0.5,
          cameraTiltX: 0.5,
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => painter.paint(canvas, Size.zero), returnsNormally);
      expect(() => painter.paint(canvas, const Size(0, 50)), returnsNormally);
      expect(() => painter.paint(canvas, const Size(10, 10)), returnsNormally);
      recorder.endRecording().dispose();
      tiny.dispose();
    });

    test('deterministic: same input renders byte-identical output', () async {
      final img = await _centredSquareImage(100, 100);
      const settings = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: -50,
        rimGlow: 0.4,
        cameraTiltY: 0.3,
        cameraZoom: 1.2,
        cameraRotationDeg: 5,
      );
      final a = await _renderPainter(
        LogoLightingCameraPainter(logoImage: img, settings: settings),
        120,
        120,
      );
      final b = await _renderPainter(
        LogoLightingCameraPainter(logoImage: img, settings: settings),
        120,
        120,
      );
      expect(_bytesEqual(a, b), isTrue);
      img.dispose();
    });

    test('shouldRepaint follows image identity and settings equality',
        () async {
      final img = await _uniformImage(10, 10, const Color(0xFF000000));
      final img2 = await _uniformImage(10, 10, const Color(0xFF000000));
      const s = LogoLightingCameraSettings.defaults;
      final base = LogoLightingCameraPainter(logoImage: img, settings: s);
      expect(
        base.shouldRepaint(
          LogoLightingCameraPainter(logoImage: img, settings: s),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          LogoLightingCameraPainter(
            logoImage: img,
            settings: const LogoLightingCameraSettings(cameraZoom: 1.2),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          LogoLightingCameraPainter(logoImage: img2, settings: s),
        ),
        isTrue,
      );
      img.dispose();
      img2.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Panel
  // -------------------------------------------------------------------------

  group('LogoLightingCameraPanel — widgets', () {
    Widget harness(
      LogoLightingCameraSettings settings,
      List<LogoLightingCameraSettings> captured,
    ) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LogoLightingCameraPanel(
              settings: settings,
              onChanged: captured.add,
            ),
          ),
        ),
      );
    }

    Future<void> pumpPanel(
      WidgetTester tester,
      LogoLightingCameraSettings settings,
      List<LogoLightingCameraSettings> captured,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(settings, captured));
      await tester.pump();
    }

    testWidgets('renders switch, 6 chips, 8 sliders and Reset, no exception',
        (tester) async {
      final captured = <LogoLightingCameraSettings>[];
      await pumpPanel(tester, LogoLightingCameraSettings.defaults, captured);
      expect(tester.takeException(), isNull);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(8));
      for (final name in <String>[
        'No Light',
        'Studio Soft',
        'Dramatic Side',
        'Top Light',
        'Neon Rim',
        'Stage Tilt',
        'Lighting',
        'Light Angle',
        'Light Intensity',
        'Shadow Depth',
        'Rim Glow',
        'Camera Tilt X',
        'Camera Tilt Y',
        'Camera Zoom',
        'Rotation',
        'Reset',
      ]) {
        expect(find.text(name), findsOneWidget, reason: 'missing label $name');
      }
    });

    testWidgets('preset chip tap fires onChanged with that preset',
        (tester) async {
      final captured = <LogoLightingCameraSettings>[];
      await pumpPanel(tester, LogoLightingCameraSettings.defaults, captured);
      await tester.ensureVisible(find.text('Neon Rim'));
      await tester.tap(find.text('Neon Rim'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(captured, isNotEmpty);
      expect(
        captured.last,
        kLogoLightPresets.firstWhere((p) => p.id == 'neon_rim').settings,
      );
    });

    testWidgets('switch tap flips lightingOn', (tester) async {
      final captured = <LogoLightingCameraSettings>[];
      await pumpPanel(tester, LogoLightingCameraSettings.defaults, captured);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(captured, isNotEmpty);
      expect(captured.last.lightingOn, isTrue);
      expect(
        captured.last.copyWith(lightingOn: false),
        LogoLightingCameraSettings.defaults,
      );
    });

    testWidgets('each slider drag changes only its own field', (tester) async {
      // Slider order in the panel: Light Angle, Light Intensity, Shadow
      // Depth, Rim Glow, Camera Tilt X, Camera Tilt Y, Camera Zoom, Rotation.
      const initial = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: -35,
        lightIntensity: 0.6,
        shadowDepth: 0.45,
        rimGlow: 0.3,
        cameraTiltX: 0,
        cameraTiltY: 0,
        cameraZoom: 1.0,
        cameraRotationDeg: 0,
      );
      final fields = <String, double Function(LogoLightingCameraSettings)>{
        'lightAngleDeg': (s) => s.lightAngleDeg,
        'lightIntensity': (s) => s.lightIntensity,
        'shadowDepth': (s) => s.shadowDepth,
        'rimGlow': (s) => s.rimGlow,
        'cameraTiltX': (s) => s.cameraTiltX,
        'cameraTiltY': (s) => s.cameraTiltY,
        'cameraZoom': (s) => s.cameraZoom,
        'cameraRotationDeg': (s) => s.cameraRotationDeg,
      };
      final keys = fields.keys.toList();

      for (var i = 0; i < 8; i++) {
        final captured = <LogoLightingCameraSettings>[];
        await pumpPanel(tester, initial, captured);
        final slider = find.byType(Slider).at(i);
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(40, 0));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'slider $i (${keys[i]}) threw');
        expect(captured, isNotEmpty, reason: 'slider $i fired nothing');
        final last = captured.last;
        for (final entry in fields.entries) {
          if (entry.key == keys[i]) {
            // A Material Slider first jumps to the finger's down-position,
            // then follows the drag — so assert the value moved UP during
            // the gesture itself (last vs first callback), not vs the
            // pre-gesture value.
            expect(captured.length, greaterThan(1),
                reason: 'slider $i should emit a drag sequence');
            expect(
              entry.value(last),
              greaterThan(entry.value(captured.first)),
              reason: 'slider $i should increase ${entry.key} while '
                  'dragging right',
            );
          } else {
            expect(
              entry.value(last),
              entry.value(initial),
              reason: 'slider $i must not change ${entry.key}',
            );
          }
        }
        expect(last.lightingOn, initial.lightingOn);
      }
    });

    testWidgets('Reset fires onChanged with defaults', (tester) async {
      final captured = <LogoLightingCameraSettings>[];
      await pumpPanel(
        tester,
        const LogoLightingCameraSettings(
          lightingOn: true,
          rimGlow: 0.8,
          cameraZoom: 1.5,
        ),
        captured,
      );
      await tester.ensureVisible(find.text('Reset'));
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(captured, isNotEmpty);
      expect(captured.last, LogoLightingCameraSettings.defaults);
    });
  });
}

/// Reference painter: background fill + plain contain-fit draw, default Paint.
class _PlainDrawPainter extends CustomPainter {
  _PlainDrawPainter(this.img);
  final ui.Image img;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF050914),
    );
    final scale = size.width / img.width < size.height / img.height
        ? size.width / img.width
        : size.height / img.height;
    final w = img.width * scale;
    final h = img.height * scale;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _PlainDrawPainter oldDelegate) => false;
}
