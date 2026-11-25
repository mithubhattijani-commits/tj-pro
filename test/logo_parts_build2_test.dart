/// Logo Parts REDESIGN — Build 2 (Glow + Andaaz) proofs.
///
/// (a) the generated glow renders BEHIND the logo, and its
///     measured brightness + footprint grow with the
///     intensity and spread sliders;
/// (b) a custom glow colour changes the glow's hue vs the
///     AUTO colour (the logo's dominant colour);
/// (c) the three base plates (cut / none / ghost) render
///     measurably different results under a turned part;
/// (d) Swing stays within its set angle and oscillates;
/// (e) Pulse changes the part's rendered size between
///     phases;
/// (f) preview/export parity for a scene using glow +
///     swing, through the one shared painter;
/// (g) Build 1 saves load with the Build 2 defaults (glow
///     off, base cut, motion = Poora chakkar, pulse off),
///     and Build 2 saves round-trip whole;
/// (h) glow Pulse motion breathes — the halo's energy
///     changes with time;
/// (i) the Glow dock tab is LIVE in the Maker: its switch,
///     colour, motion, base and preview-background controls
///     write the preset's scene; the Ghumao tab's Andaaz
///     (Swing) and Pulse controls write the selected part.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/logo_parts_service.dart';

// ----------------------------------------------------------------
// Synthetic RGBA helpers (the Build 1 pattern).
// ----------------------------------------------------------------

Uint8List _blank(int w, int h) => Uint8List(w * h * 4);

void _fill(
  Uint8List rgba,
  int w,
  int x0,
  int y0,
  int x1,
  int y1,
  int r,
  int g,
  int b, {
  int a = 255,
}) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final o = (y * w + x) * 4;
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = a;
    }
  }
}

(int, int, int, int) _px(Uint8List rgba, int w, int x, int y) {
  final o = (y * w + x) * 4;
  return (rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]);
}

Future<ui.Image> _imageOf(Uint8List rgba, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

Future<Uint8List> _rgbaOf(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

int _diffPixels(Uint8List a, Uint8List b) {
  var n = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

/// True when (x, y) is genuinely OUTSIDE the silhouette:
/// the master is transparent there AND at all four direct
/// neighbours. (The 1px margin keeps the master's own
/// resampling edge-bleed out of the halo measurement.)
bool _outside(Uint8List master, int s, int x, int y) {
  bool clear(int px, int py) {
    if (px < 0 || py < 0 || px >= s || py >= s) return true;
    return master[(py * s + px) * 4 + 3] < 128;
  }

  return clear(x, y) &&
      clear(x - 1, y) &&
      clear(x + 1, y) &&
      clear(x, y - 1) &&
      clear(x, y + 1);
}

/// The glow's total presence OUTSIDE the master's opaque
/// silhouette (the halo) — sum of rendered alpha there.
int _haloEnergy(Uint8List rendered, Uint8List master, int s) {
  var sum = 0;
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      if (_outside(master, s, x, y)) sum += rendered[(y * s + x) * 4 + 3];
    }
  }
  return sum;
}

/// How many halo pixels are visibly lit (the footprint).
int _haloCount(Uint8List rendered, Uint8List master, int s) {
  var n = 0;
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      if (_outside(master, s, x, y) &&
          rendered[(y * s + x) * 4 + 3] >= 10) {
        n++;
      }
    }
  }
  return n;
}

/// A master with one red block in the middle, transparent
/// everywhere else — a clean silhouette for glow tests.
Uint8List _blockMaster() {
  const s = 128;
  final rgba = _blank(s, s);
  _fill(rgba, s, 44, 44, 84, 84, 220, 30, 30);
  return rgba;
}

Future<Uint8List> _renderGlow({
  required Uint8List masterRgba,
  required LogoPartsScene scene,
  double tSec = 0,
  int? autoGlowColorArgb,
}) async {
  const s = 128;
  final img = await _imageOf(masterRgba, s, s);
  final frame = await LogoPartsService.renderPartsFrame(
    parts: const [],
    masterTexture: img,
    size: s,
    tSec: tSec,
    scene: scene,
    autoGlowColorArgb: autoGlowColorArgb,
  );
  final px = await _rgbaOf(frame);
  frame.dispose();
  img.dispose();
  return px;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('(a) glow renders behind the logo and grows with its sliders', () {
    test('intensity: a stronger glow lights the halo more', () async {
      final master = _blockMaster();
      LogoPartsScene scene(double intensity) => LogoPartsScene(
            glowOn: true,
            glowColorArgb: 0xFF0000FF,
            glowIntensity: intensity,
            glowSpread: 0.5,
          );
      final low = await _renderGlow(masterRgba: master, scene: scene(0.25));
      final high = await _renderGlow(masterRgba: master, scene: scene(1.0));
      final eLow = _haloEnergy(low, master, 128);
      final eHigh = _haloEnergy(high, master, 128);
      expect(eLow, greaterThan(0), reason: 'the glow must exist at all');
      expect(eHigh, greaterThan(eLow * 1.5),
          reason: 'halo energy must grow with intensity ($eLow → $eHigh)');
      // The logo itself is untouched by its glow: the block
      // centre is still the master's pure red in both.
      expect(_px(high, 128, 64, 64), (220, 30, 30, 255));
      expect(_px(low, 128, 64, 64), (220, 30, 30, 255));
    });

    test('spread: a wider glow reaches further out', () async {
      final master = _blockMaster();
      LogoPartsScene scene(double spread) => LogoPartsScene(
            glowOn: true,
            glowColorArgb: 0xFF0000FF,
            glowIntensity: 1.0,
            glowSpread: spread,
          );
      final tight = await _renderGlow(masterRgba: master, scene: scene(0.05));
      final wide = await _renderGlow(masterRgba: master, scene: scene(0.95));
      final cTight = _haloCount(tight, master, 128);
      final cWide = _haloCount(wide, master, 128);
      expect(cWide, greaterThan(cTight),
          reason: 'halo footprint must grow with spread ($cTight → $cWide)');
      // And the glow is OFF when the switch is off: the halo
      // is empty (a few alpha units of resampling residue at
      // most — nothing next to a real glow's energy).
      final off = await _renderGlow(
        masterRgba: master,
        scene: LogoPartsScene(glowOn: false),
      );
      final eOff = _haloEnergy(off, master, 128);
      final eWide = _haloEnergy(wide, master, 128);
      expect(eOff, lessThan(16), reason: 'off means off (residue: $eOff)');
      expect(eOff, lessThan(eWide ~/ 100),
          reason: 'off halo must be negligible vs on ($eOff vs $eWide)');
    });
  });

  group('(b) glow colour: custom hue vs AUTO (dominant colour)', () {
    test('dominant colour of a red logo is red; of a blue one, blue', () {
      final red = _blockMaster();
      final cRed = dominantLogoColorArgb(red)!;
      expect((cRed >> 16) & 0xFF, greaterThan(150));
      expect((cRed >> 16) & 0xFF, greaterThan((cRed & 0xFF) + 60));
      const s = 64;
      final blue = _blank(s, s);
      _fill(blue, s, 10, 10, 50, 50, 30, 30, 220);
      final cBlue = dominantLogoColorArgb(blue)!;
      expect(cBlue & 0xFF, greaterThan(((cBlue >> 16) & 0xFF) + 60));
      // Fully transparent → no colour at all.
      expect(dominantLogoColorArgb(_blank(8, 8)), isNull);
    });

    test('the halo takes the custom colour; AUTO takes the logo colour',
        () async {
      final master = _blockMaster(); // red logo
      // A halo pixel just above the block (inside the glow,
      // outside the silhouette).
      (int, int, int, int) haloAt(Uint8List px) => _px(px, 128, 64, 36);
      final custom = await _renderGlow(
        masterRgba: master,
        scene: LogoPartsScene(
          glowOn: true,
          glowColorArgb: 0xFF0000FF, // blue
          glowIntensity: 1.0,
          glowSpread: 0.6,
        ),
      );
      final hc = haloAt(custom);
      expect(hc.$4, greaterThan(40), reason: 'halo pixel must be lit: $hc');
      expect(hc.$3, greaterThan(hc.$1),
          reason: 'custom blue glow must read blue: $hc');
      final auto = await _renderGlow(
        masterRgba: master,
        scene: LogoPartsScene(
          glowOn: true,
          glowColorArgb: null, // AUTO
          glowIntensity: 1.0,
          glowSpread: 0.6,
        ),
        autoGlowColorArgb: dominantLogoColorArgb(master),
      );
      final ha = haloAt(auto);
      expect(ha.$4, greaterThan(40), reason: 'halo pixel must be lit: $ha');
      expect(ha.$1, greaterThan(ha.$3),
          reason: 'AUTO glow must take the red logo colour: $ha');
    });
  });

  group('(c) the three base plates render differently', () {
    // Master: red content in the part's box (top-left), a
    // blue block bottom-right that NO part covers (base-only
    // content).
    Uint8List master() {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 8, 8, 56, 56, 220, 30, 30);
      _fill(rgba, s, 88, 88, 120, 120, 30, 30, 220);
      return rgba;
    }

    LogoPart part() => LogoPart(
          id: 'p0',
          name: 'P',
          sourcePath: '/master.png',
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
          speedSec: 2, // t=0.25 → 45°
        );

    Future<Uint8List> render(String baseMode) async {
      final img = await _imageOf(master(), 128, 128);
      final frame = await LogoPartsService.renderPartsFrame(
        parts: [part()],
        masterTexture: img,
        size: 128,
        tSec: 0.25,
        scene: LogoPartsScene(baseMode: baseMode),
      );
      final px = await _rgbaOf(frame);
      frame.dispose();
      img.dispose();
      return px;
    }

    test('cut vs none vs ghost — pixel proof at three spots', () async {
      final cut = await render(kLogoPartsBaseCut);
      final none = await render(kLogoPartsBaseNone);
      final ghost = await render(kLogoPartsBaseGhost);
      // The base-only blue block: present in cut + ghost,
      // GONE in none (there is no base at all).
      expect(_px(cut, 128, 104, 104), (30, 30, 220, 255));
      expect(_px(ghost, 128, 104, 104), (30, 30, 220, 255));
      expect(_px(none, 128, 104, 104), (0, 0, 0, 0));
      // A spot the 45° turn vacated inside the box: cut and
      // none show through (transparent); ghost still shows
      // the original red sitting underneath.
      expect(_px(cut, 128, 10, 10), (0, 0, 0, 0));
      expect(_px(none, 128, 10, 10), (0, 0, 0, 0));
      expect(_px(ghost, 128, 10, 10), (220, 30, 30, 255));
      // The part itself renders in all three (its centre is
      // red everywhere).
      for (final px in [cut, none, ghost]) {
        expect(_px(px, 128, 32, 32), (220, 30, 30, 255));
      }
      // And the three frames measurably differ overall.
      expect(_diffPixels(cut, none), greaterThan(500));
      expect(_diffPixels(cut, ghost), greaterThan(500));
      expect(_diffPixels(none, ghost), greaterThan(500));
    });
  });

  group('(d) swing stays within its angle and oscillates', () {
    LogoPart swingPart({String direction = 'cw', bool rotate = true}) =>
        LogoPart(
          id: 'p',
          name: 'P',
          sourcePath: '/m.png',
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
          speedSec: 4,
          direction: direction,
          rotate: rotate,
          motionMode: kLogoPartMotionSwing,
          swingDeg: 30,
        );

    test('angle: 0 → +30° → 0 → −30°, never beyond', () {
      final p = swingPart();
      double at(double t) => LogoPartsService.partAngleAt(p, t);
      final maxRad = 30 * math.pi / 180;
      expect(at(0), closeTo(0, 1e-9));
      expect(at(1), closeTo(maxRad, 1e-9));
      expect(at(2), closeTo(0, 1e-9));
      expect(at(3), closeTo(-maxRad, 1e-9));
      var peak = 0.0;
      for (var t = 0.0; t <= 4.0; t += 0.05) {
        final a = at(t).abs();
        expect(a, lessThanOrEqualTo(maxRad + 1e-9),
            reason: 'swing must stay within ±30° (t=$t)');
        if (a > peak) peak = a;
      }
      expect(peak, closeTo(maxRad, 0.02));
      // Anti direction flips the pendulum's sign.
      expect(
        LogoPartsService.partAngleAt(swingPart(direction: 'ccw'), 1),
        closeTo(-maxRad, 1e-9),
      );
      // Rotate off = no swing at all.
      expect(LogoPartsService.partAngleAt(swingPart(rotate: false), 1), 0);
    });

    test('two swing phases render different frames', () async {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 0, 0, 64, 128, 220, 30, 30);
      _fill(rgba, s, 8, 8, 24, 24, 255, 255, 255);
      final img = await _imageOf(rgba, s, s);
      final part = LogoPart(
        id: 'p0',
        name: 'P',
        sourcePath: '/master.png',
        box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
        speedSec: 4,
        motionMode: kLogoPartMotionSwing,
        swingDeg: 35,
      );
      Future<Uint8List> frame(double t) async {
        final f = await LogoPartsService.renderPartsFrame(
          parts: [part],
          masterTexture: img,
          size: s,
          tSec: t,
        );
        final px = await _rgbaOf(f);
        f.dispose();
        return px;
      }

      final right = await frame(1); // swung +35°
      final left = await frame(3); // swung −35°
      img.dispose();
      expect(_diffPixels(right, left), greaterThan(200));
    });
  });

  group('(e) pulse changes the rendered size between phases', () {
    test('scale: 1 at rest phase, ±18% at the extremes (strength 1)', () {
      final p = LogoPart(
        id: 'p',
        name: 'P',
        sourcePath: '/m.png',
        box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
        rotate: false,
        pulseOn: true,
        pulseStrength: 1,
      );
      expect(LogoPartsService.partScaleAt(p, 0), closeTo(1, 1e-9));
      expect(LogoPartsService.partScaleAt(p, 0.75), closeTo(1.18, 1e-9));
      expect(LogoPartsService.partScaleAt(p, 2.25), closeTo(0.82, 1e-9));
      // One full pulse period later the scale repeats (the
      // 12s loop stays seamless).
      expect(
        LogoPartsService.partScaleAt(p, 3.75),
        closeTo(LogoPartsService.partScaleAt(p, 0.75), 1e-9),
      );
      // Pulse off → always exactly 1.
      final off = p.copyWith(pulseOn: false);
      expect(LogoPartsService.partScaleAt(off, 0.75), 1);
    });

    test('rendered footprint grows at the swell phase', () async {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 32, 32, 96, 96, 220, 30, 30); // the box's content
      final img = await _imageOf(rgba, s, s);
      final part = LogoPart(
        id: 'p0',
        name: 'P',
        sourcePath: '/master.png',
        box: const LogoBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
        rotate: false,
        pulseOn: true,
        pulseStrength: 1,
      );
      Future<int> redCount(double t) async {
        final f = await LogoPartsService.renderPartsFrame(
          parts: [part],
          masterTexture: img,
          size: s,
          tSec: t,
          scene: LogoPartsScene(baseMode: kLogoPartsBaseNone),
        );
        final px = await _rgbaOf(f);
        f.dispose();
        var n = 0;
        for (var i = 0; i < px.length; i += 4) {
          if (px[i] > 150 && px[i + 3] > 200) n++;
        }
        return n;
      }

      final rest = await redCount(0); // scale exactly 1
      final swelled = await redCount(0.75); // scale 1.18
      img.dispose();
      expect(rest, greaterThan(3000));
      expect(swelled, greaterThan(rest + 500),
          reason: 'the breathing part must cover more pixels ($rest → $swelled)');
    });
  });

  group('(f) preview/export parity — glow + swing scene', () {
    test('renderPartsFrame == direct paintParts render, pixel for pixel',
        () async {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 0, 0, 64, 64, 220, 30, 30);
      _fill(rgba, s, 64, 64, 128, 128, 30, 30, 220);
      _fill(rgba, s, 8, 8, 20, 20, 255, 255, 255);
      final img = await _imageOf(rgba, s, s);
      final parts = <LogoPart>[
        LogoPart(
          id: 'a',
          name: 'A',
          sourcePath: '/master.png',
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
          speedSec: 4,
          motionMode: kLogoPartMotionSwing,
          swingDeg: 40,
          pulseOn: true,
          pulseStrength: 0.8,
        ),
      ];
      final scene = LogoPartsScene(
        glowOn: true,
        glowColorArgb: 0xFF00BCD4,
        glowIntensity: 0.9,
        glowSpread: 0.7,
        baseMode: kLogoPartsBaseGhost,
      );
      final viaExport = await LogoPartsService.renderPartsFrame(
        parts: parts,
        masterTexture: img,
        size: s,
        tSec: 0.7,
        scene: scene,
      );
      final exportPx = await _rgbaOf(viaExport);
      viaExport.dispose();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      LogoPartsService.paintParts(
        canvas,
        const ui.Size(128, 128),
        parts,
        img,
        0.7,
        scene: scene,
      );
      final picture = recorder.endRecording();
      final viaPainter = await picture.toImage(128, 128);
      picture.dispose();
      final painterPx = await _rgbaOf(viaPainter);
      viaPainter.dispose();
      img.dispose();
      expect(_diffPixels(exportPx, painterPx), 0);
      expect(exportPx.any((v) => v != 0), isTrue);
    });
  });

  group('(g) saves: Build 1 loads with defaults; Build 2 round-trips', () {
    test('a Build 1 bare-list payload → parts + default scene', () {
      const build1Payload =
          '[{"model":2,"id":"a","name":"NEWS","sourcePath":"/logo.png",'
          '"box":{"x":0.1,"y":0.2,"w":0.3,"h":0.4},"rotate":true,'
          '"direction":"cw","speedSec":6,"rotationStyle":"flat",'
          '"delaySec":0,"pivotDx":0,"pivotDy":0}]';
      final data = decodeLogoPartsSave(build1Payload);
      expect(data.parts.length, 1);
      // The part's Build 2 fields land on their defaults:
      // Poora chakkar, pulse off.
      expect(data.parts.single.motionMode, kLogoPartMotionSpin);
      expect(data.parts.single.pulseOn, isFalse);
      // The scene lands on ITS defaults: glow off, base cut.
      expect(data.scene.glowOn, isFalse);
      expect(data.scene.baseMode, kLogoPartsBaseCut);
      expect(data.scene.glowColorArgb, isNull);
      // The old decoder reads the same payload identically.
      expect(decodeLogoParts(build1Payload).length, 1);
      // Slice-model junk still loads as nothing.
      final junk = decodeLogoPartsSave('[{"id":"a","imagePath":"/p.png"}]');
      expect(junk.parts, isEmpty);
      expect(junk.scene.glowOn, isFalse);
      expect(decodeLogoPartsSave('{{{').parts, isEmpty);
    });

    test('a Build 2 save round-trips parts + scene whole', () {
      final parts = [
        LogoPart(
          id: 'a',
          name: 'NEWS',
          sourcePath: '/logo.png',
          box: const LogoBox(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
          motionMode: kLogoPartMotionSwing,
          swingDeg: 45,
          pulseOn: true,
          pulseStrength: 0.7,
        ),
      ];
      final scene = LogoPartsScene(
        glowOn: true,
        glowColorArgb: 0xFF2979FF,
        glowIntensity: 0.6,
        glowSpread: 0.3,
        glowMotion: kLogoGlowMotionPulse,
        baseMode: kLogoPartsBaseGhost,
      );
      final back = decodeLogoPartsSave(encodeLogoPartsSave(parts, scene));
      expect(back.scene, scene);
      expect(back.parts.length, 1);
      final p = back.parts.single;
      expect(p.motionMode, kLogoPartMotionSwing);
      expect(p.swingDeg, 45);
      expect(p.pulseOn, isTrue);
      expect(p.pulseStrength, 0.7);
      // And the part-level JSON round-trip keeps them too.
      final pj = LogoPart.fromJson(parts.single.toJson());
      expect(pj.motionMode, kLogoPartMotionSwing);
      expect(pj.swingDeg, 45);
      expect(pj.pulseOn, isTrue);
    });
  });

  group('(h) glow pulse motion breathes', () {
    test('the halo energy changes with time', () async {
      final master = _blockMaster();
      final scene = LogoPartsScene(
        glowOn: true,
        glowColorArgb: 0xFF0000FF,
        glowIntensity: 1.0,
        glowSpread: 0.5,
        glowMotion: kLogoGlowMotionPulse,
      );
      final low = await _renderGlow(masterRgba: master, scene: scene, tSec: 0);
      final high =
          await _renderGlow(masterRgba: master, scene: scene, tSec: 3);
      final eLow = _haloEnergy(low, master, 128);
      final eHigh = _haloEnergy(high, master, 128);
      expect(eHigh, greaterThan(eLow),
          reason: 'a breathing glow must swell ($eLow → $eHigh)');
    });
  });

  group('(i) the Glow tab + Andaaz/Pulse controls are live in the Maker',
      () {
    late Directory tmp;
    late File logoFile;

    void mockPathProvider(String dir) {
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

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('tjpro_logo_build2');
      mockPathProvider(tmp.path);
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

    testWidgets('glow tab writes the scene; ghumao writes andaaz + pulse',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = logoFile.path
        ..logoParts = [
          LogoPart(
            id: 'part0',
            name: 'Part 1',
            sourcePath: logoFile.path,
            box: const LogoBox(x: 0.1, y: 0.1, w: 0.5, h: 0.5),
          ),
        ]
        ..logoPartsSourcePath = logoFile.path;
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: preset,
            initialProject: NewsProject.create(presetId: preset.id),
          ),
        ),
      );
      await frames(tester);
      await openTool(tester, 'logo');

      // --- Glow tab: switch, colour, motion, base, preview bg.
      await tester.ensureVisible(find.byKey(const Key('logoPartsTab-glow')));
      await tester.tap(find.byKey(const Key('logoPartsTab-glow')));
      await frames(tester);
      await tester.ensureVisible(find.byKey(const Key('logoGlowOn')));
      expect(preset.logoPartsScene.glowOn, isFalse);
      await tester.tap(find.byKey(const Key('logoGlowOn')));
      await frames(tester);
      expect(preset.logoPartsScene.glowOn, isTrue);
      expect(find.byKey(const Key('logoGlowIntensity')), findsOneWidget);
      expect(find.byKey(const Key('logoGlowSpread')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('logoGlowColor-4294952960')), // Gold 0xFFFFC800
      );
      await tester.tap(find.byKey(const Key('logoGlowColor-4294952960')));
      await frames(tester);
      expect(preset.logoPartsScene.glowColorArgb, 0xFFFFC800);
      await tester.ensureVisible(
        find.byKey(const Key('logoGlowMotion-spin')),
      );
      await tester.tap(find.byKey(const Key('logoGlowMotion-spin')));
      await frames(tester);
      expect(preset.logoPartsScene.glowMotion, kLogoGlowMotionSpin);
      await tester.ensureVisible(
        find.byKey(const Key('logoPartsBase-ghost')),
      );
      await tester.tap(find.byKey(const Key('logoPartsBase-ghost')));
      await frames(tester);
      expect(preset.logoPartsScene.baseMode, kLogoPartsBaseGhost);
      await tester.ensureVisible(
        find.byKey(const Key('logoPartsPreviewBg-green')),
      );
      await tester.tap(find.byKey(const Key('logoPartsPreviewBg-green')));
      await frames(tester);
      // The big preview's backdrop really turned green.
      expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                const Color(0xFF00B140)),
        findsWidgets,
      );

      // --- Ghumao tab: Andaaz (Swing) + Pulse on the part.
      await tester.ensureVisible(
        find.byKey(const Key('logoPartsTab-ghumao')),
      );
      await tester.tap(find.byKey(const Key('logoPartsTab-ghumao')));
      await frames(tester);
      await tester.ensureVisible(
        find.byKey(const Key('logoPartMotion-0-swing')),
      );
      await tester.tap(find.byKey(const Key('logoPartMotion-0-swing')));
      await frames(tester);
      expect(preset.logoParts.single.motionMode, kLogoPartMotionSwing);
      expect(find.byKey(const Key('logoPartSwingDeg-0')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('logoPartPulse-0')));
      await tester.tap(find.byKey(const Key('logoPartPulse-0')));
      await frames(tester);
      expect(preset.logoParts.single.pulseOn, isTrue);
      expect(
        find.byKey(const Key('logoPartPulseStrength-0')),
        findsOneWidget,
      );
    });
  });
}
