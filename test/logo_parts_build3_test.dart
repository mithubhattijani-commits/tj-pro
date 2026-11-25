/// LOGO PARTS REDESIGN — BUILD 3 (Polish) tests.
///
/// Groups:
/// (a) the Light Sweep (Option 34) — a bright band visibly
///     crosses the logo between two loop phases and is
///     absent when off; the band's centre is a pure function
///     of time, periodic in the 12s loop at any speed;
/// (b) Narmi / Easing (Option 27) — 'linear' (Barabar) vs
///     'smooth' (Narm) change a Swing's and a Pulse's
///     mid-phase value while the cycle's start, extremes
///     and end agree exactly; the glow pulse breathes by
///     the scene's easing too;
/// (c) Export size (Option 39) — the parts frame generator
///     honours 512 and 1024, producing frames of exactly
///     those sizes with the same content layout;
/// (d) Settings copy (Option 40) — the target part's
///     animation fields become the source's while its box,
///     name and id stay its own, and its rendered motion
///     (angle + scale over time) matches the source's;
/// (e) Keying mazbooti (Option 3) — a higher strength keys
///     measurably more background than a low one on a
///     synthetic logo, and the default strength reproduces
///     the Builds 1–2 tolerance (42) exactly;
/// (f) preview/export parity on a scene using sweep +
///     easing, through the one shared painter;
/// (g) Build 2 saved settings load with the Build 3
///     defaults (sweep off, easing Narm, export 512, keying
///     default), and Build 3 settings round-trip whole;
/// (i) the Maker wires all five: the Logo tab's keying
///     slider, the Waqt tab's Narmi chips, the Glow tab's
///     sweep switch, the Save tab's export-size chips and
///     the Ghumao tab's settings copy/paste all write the
///     preset's scene / parts.
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
// Synthetic RGBA helpers (the Build 1/2 pattern).
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
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

/// A master with one red block in the middle on transparency.
Uint8List _blockMaster([int s = 128]) {
  final rgba = _blank(s, s);
  _fill(rgba, s, s ~/ 4, s ~/ 4, s * 3 ~/ 4, s * 3 ~/ 4, 220, 30, 30);
  return rgba;
}

/// One still part over the block — the composite is the
/// master itself, so any brightness change is the sweep's.
List<LogoPart> _blockParts() => [
      LogoPart(
        id: 'a',
        name: 'Block',
        sourcePath: '/master.png',
        box: const LogoBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
        rotate: false,
      ),
    ];

Future<Uint8List> _renderScene({
  required Uint8List masterRgba,
  required List<LogoPart> parts,
  required LogoPartsScene scene,
  required double tSec,
  int s = 128,
}) async {
  final img = await _imageOf(masterRgba, s, s);
  final frame = await LogoPartsService.renderPartsFrame(
    parts: parts,
    masterTexture: img,
    size: s,
    tSec: tSec,
    scene: scene,
  );
  final px = await _rgbaOf(frame);
  frame.dispose();
  img.dispose();
  return px;
}

/// Pixels the sweep brightened inside the block, counted in
/// the frame's left or right third. The sweep's white band
/// over the red block lifts G and B far above the block's
/// own 30 — a rise over 40 in G+B is the band, nothing else.
int _sweepLit(Uint8List on, Uint8List off, int s, {required bool left}) {
  var n = 0;
  for (var y = s ~/ 4; y < s * 3 ~/ 4; y++) {
    for (var x = 0; x < s; x++) {
      final inThird = left ? x < s ~/ 3 : x >= s * 2 ~/ 3;
      if (!inThird) continue;
      final o = (y * s + x) * 4;
      final rise = (on[o + 1] + on[o + 2]) - (off[o + 1] + off[o + 2]);
      if (rise > 40) n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('(a) Light Sweep — the band crosses the logo', () {
    test('centre is a pure, loop-periodic function of time', () {
      final slow = LogoPartsScene(sweepOn: true, sweepSpeed: 0);
      expect(LogoPartsService.sweepPassesPerLoop(slow), 1);
      expect(LogoPartsService.sweepCentreAt(slow, 0), closeTo(-0.4, 1e-9));
      // Mid-pass: local 0.275 of 12s → halfway across.
      expect(LogoPartsService.sweepCentreAt(slow, 3.3), closeTo(0.5, 1e-9));
      // Rest of the pass: parked off-frame.
      expect(LogoPartsService.sweepCentreAt(slow, 8), 2.0);
      expect(LogoPartsService.sweepCentreAt(slow, 11.9), 2.0);
      // Seamless: the next loop starts exactly where this one did.
      expect(LogoPartsService.sweepCentreAt(slow, 12),
          LogoPartsService.sweepCentreAt(slow, 0));
      final fast = LogoPartsScene(sweepOn: true, sweepSpeed: 1);
      expect(LogoPartsService.sweepPassesPerLoop(fast), 4);
      expect(LogoPartsService.sweepCentreAt(fast, 3),
          LogoPartsService.sweepCentreAt(fast, 0));
    });

    test('the bright band is left early, right later, absent when off',
        () async {
      final master = _blockMaster();
      final onScene = LogoPartsScene(sweepOn: true, sweepSpeed: 0);
      final offScene = LogoPartsScene();
      // Speed 0 = one pass per 12s loop, active for 6.6s:
      // centre 0.30 at t≈2.57, centre 0.70 at t≈4.03.
      final off = await _renderScene(
          masterRgba: master, parts: _blockParts(), scene: offScene, tSec: 2.57);
      final left = await _renderScene(
          masterRgba: master, parts: _blockParts(), scene: onScene, tSec: 2.57);
      final right = await _renderScene(
          masterRgba: master, parts: _blockParts(), scene: onScene, tSec: 4.03);
      final offLater = await _renderScene(
          masterRgba: master, parts: _blockParts(), scene: offScene, tSec: 4.03);

      // Off is off at any time: nothing moves, nothing shines.
      expect(_diffPixels(off, offLater), 0);
      // Early phase: the band lights the LEFT third, not the right.
      expect(_sweepLit(left, off, 128, left: true), greaterThan(150));
      expect(_sweepLit(left, off, 128, left: false), lessThan(20));
      // Later phase: the band has crossed to the RIGHT third.
      expect(_sweepLit(right, offLater, 128, left: false), greaterThan(150));
      expect(_sweepLit(right, offLater, 128, left: true), lessThan(20));
      // The shine stays ON the logo: outside the block the
      // sweep changes nothing at all.
      var outsideDiff = 0;
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          final inside = x >= 32 && x < 96 && y >= 32 && y < 96;
          if (inside) continue;
          final o = (y * 128 + x) * 4;
          if (left[o] != off[o] ||
              left[o + 1] != off[o + 1] ||
              left[o + 2] != off[o + 2] ||
              left[o + 3] != off[o + 3]) {
            outsideDiff++;
          }
        }
      }
      expect(outsideDiff, 0,
          reason: 'the sweep must be masked to the logo silhouette');
    });
  });

  group('(b) Narmi — easing shapes Swing and Pulse', () {
    test('oscillation: endpoints agree, mid-phase differs', () {
      for (final phase in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(LogoPartsService.oscillation(kLogoEasingLinear, phase),
            closeTo(LogoPartsService.oscillation(kLogoEasingSmooth, phase),
                1e-9),
            reason: 'both easings must agree at phase $phase');
      }
      expect(LogoPartsService.oscillation(kLogoEasingSmooth, 0.125),
          closeTo(math.sqrt(0.5), 1e-9));
      expect(LogoPartsService.oscillation(kLogoEasingLinear, 0.125), 0.5);
    });

    test('a swing\'s mid-phase angle changes, its extremes do not', () {
      LogoPart swing(String easing) => LogoPart(
            id: 's',
            name: 'S',
            sourcePath: '/m.png',
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
            speedSec: 4,
            motionMode: kLogoPartMotionSwing,
            swingDeg: 40,
            easing: easing,
          );
      final smooth = swing(kLogoEasingSmooth);
      final linear = swing(kLogoEasingLinear);
      // Start of the cycle: both at rest.
      expect(LogoPartsService.partAngleAt(smooth, 0), 0);
      expect(LogoPartsService.partAngleAt(linear, 0), 0);
      // Quarter cycle: both at the full +40° extreme.
      expect(LogoPartsService.partAngleAt(smooth, 1),
          closeTo(LogoPartsService.partAngleAt(linear, 1), 1e-9));
      expect(LogoPartsService.partAngleAt(smooth, 1),
          closeTo(40 * math.pi / 180, 1e-9));
      // Mid-phase (eighth of the cycle): Narm is ahead of
      // Barabar — the softness difference, in numbers.
      final aSmooth = LogoPartsService.partAngleAt(smooth, 0.5);
      final aLinear = LogoPartsService.partAngleAt(linear, 0.5);
      expect(aSmooth, closeTo(40 * math.pi / 180 * math.sqrt(0.5), 1e-9));
      expect(aLinear, closeTo(20 * math.pi / 180, 1e-9));
      expect((aSmooth - aLinear).abs(), greaterThan(0.1));
    });

    test('a pulse\'s mid-phase scale changes, its peak does not', () {
      LogoPart pulse(String easing) => LogoPart(
            id: 'p',
            name: 'P',
            sourcePath: '/m.png',
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
            rotate: false,
            pulseOn: true,
            pulseStrength: 1,
            easing: easing,
          );
      final smooth = pulse(kLogoEasingSmooth);
      final linear = pulse(kLogoEasingLinear);
      // Peak of the breath (quarter of the 3s period): equal.
      expect(LogoPartsService.partScaleAt(smooth, 0.75),
          closeTo(1.18, 1e-9));
      expect(LogoPartsService.partScaleAt(linear, 0.75),
          closeTo(1.18, 1e-9));
      // Mid-phase: Narm swells further than Barabar.
      expect(LogoPartsService.partScaleAt(smooth, 0.375),
          closeTo(1 + 0.18 * math.sqrt(0.5), 1e-9));
      expect(LogoPartsService.partScaleAt(linear, 0.375), closeTo(1.09, 1e-9));
    });

    test('the glow pulse breathes by the SCENE easing', () async {
      final master = _blockMaster();
      LogoPartsScene scene(String easing) => LogoPartsScene(
            glowOn: true,
            glowColorArgb: 0xFF0000FF,
            glowIntensity: 1.0,
            glowSpread: 0.5,
            glowMotion: kLogoGlowMotionPulse,
            easing: easing,
          );
      int haloEnergy(Uint8List rendered) {
        var sum = 0;
        for (var y = 0; y < 128; y++) {
          for (var x = 0; x < 128; x++) {
            final inside = x >= 32 && x < 96 && y >= 32 && y < 96;
            if (!inside) sum += rendered[(y * 128 + x) * 4 + 3];
          }
        }
        return sum;
      }

      // t=2.25: the breath's phase is 0.125 — mid-phase,
      // where the two easings differ (Narm breathes stronger).
      final smoothMid = await _renderScene(
          masterRgba: master,
          parts: const [],
          scene: scene(kLogoEasingSmooth),
          tSec: 2.25);
      final linearMid = await _renderScene(
          masterRgba: master,
          parts: const [],
          scene: scene(kLogoEasingLinear),
          tSec: 2.25);
      expect(haloEnergy(smoothMid), greaterThan(haloEnergy(linearMid)));
      // t=0: both easings sit at the breath's settled low —
      // the renders are identical.
      final smooth0 = await _renderScene(
          masterRgba: master,
          parts: const [],
          scene: scene(kLogoEasingSmooth),
          tSec: 0);
      final linear0 = await _renderScene(
          masterRgba: master,
          parts: const [],
          scene: scene(kLogoEasingLinear),
          tSec: 0);
      expect(_diffPixels(smooth0, linear0), 0);
    });
  });

  group('(c) Export size — 512 halka / 1024 saaf', () {
    test('frames come out at exactly the chosen size, same layout',
        () async {
      final tmp = await Directory.systemTemp.createTemp('logo_b3_size');
      addTearDown(() => tmp.delete(recursive: true));
      // A real master PNG on disk (the export path reads files).
      final masterImg = await _imageOf(_blockMaster(), 128, 128);
      final png = await masterImg.toByteData(format: ui.ImageByteFormat.png);
      masterImg.dispose();
      final masterFile = File('${tmp.path}/master.png');
      await masterFile.writeAsBytes(png!.buffer.asUint8List());
      final parts = [
        LogoPart(
          id: 'a',
          name: 'All',
          sourcePath: masterFile.path,
          box: const LogoBox(x: 0, y: 0, w: 1, h: 1),
          rotate: false,
        ),
      ];
      Future<(int, Uint8List)> firstFrame(int size) async {
        final dir = Directory('${tmp.path}/frames$size');
        await LogoPartsService.generatePartsFrames(
          parts: parts,
          outDir: dir,
          size: size,
        );
        final files = dir.listSync().whereType<File>().toList();
        expect(files.length, 144,
            reason: 'a full 12s loop at 12fps, whatever the size');
        final codec = await ui.instantiateImageCodec(
            await File('${dir.path}/frame_00.png').readAsBytes());
        final frame = await codec.getNextFrame();
        final rgba = await _rgbaOf(frame.image);
        final w = frame.image.width;
        frame.image.dispose();
        return (w, rgba);
      }

      final (w512, px512) = await firstFrame(512);
      final (w1024, px1024) = await firstFrame(1024);
      expect(w512, 512);
      expect(w1024, 1024);
      // Same layout at both sizes: the block's centre is the
      // master's red, the corner is transparent.
      expect(_px(px512, 512, 256, 256), (220, 30, 30, 255));
      expect(_px(px1024, 1024, 512, 512), (220, 30, 30, 255));
      expect(_px(px512, 512, 4, 4).$4, 0);
      expect(_px(px1024, 1024, 8, 8).$4, 0);
      // And just outside the block (20% across) stays empty.
      expect(_px(px512, 512, 102, 256).$4, 0);
      expect(_px(px1024, 1024, 204, 512).$4, 0);
    },
        // The honest export path renders the full 144-frame
        // loop twice (512 + 1024 PNG encodes) — slow on a
        // shared VM, so this one test gets real time.
        timeout: const Timeout(Duration(minutes: 4)));
  });

  group('(d) Settings copy — animation only, never the box', () {
    final source = LogoPart(
      id: 'src',
      name: 'Source',
      sourcePath: '/master.png',
      box: const LogoBox(x: 0.1, y: 0.1, w: 0.3, h: 0.3),
      rotate: true,
      direction: 'ccw',
      speedSec: 3,
      rotationStyle: kLogoPartStyle3d,
      delaySec: 0.6,
      pivotDx: 0.01,
      pivotDy: -0.02,
      motionMode: kLogoPartMotionSwing,
      swingDeg: 55,
      pulseOn: true,
      pulseStrength: 0.8,
      easing: kLogoEasingLinear,
    );
    final target = LogoPart(
      id: 'dst',
      name: 'Apna Naam',
      sourcePath: '/master.png',
      box: const LogoBox(x: 0.5, y: 0.5, w: 0.4, h: 0.25),
    );

    test('the target\'s animation fields become the source\'s', () {
      final copied = copyLogoPartAnimation(source, target);
      expect(copied.rotate, source.rotate);
      expect(copied.direction, source.direction);
      expect(copied.speedSec, source.speedSec);
      expect(copied.rotationStyle, source.rotationStyle);
      expect(copied.delaySec, source.delaySec);
      expect(copied.pivotDx, source.pivotDx);
      expect(copied.pivotDy, source.pivotDy);
      expect(copied.motionMode, source.motionMode);
      expect(copied.swingDeg, source.swingDeg);
      expect(copied.pulseOn, source.pulseOn);
      expect(copied.pulseStrength, source.pulseStrength);
      expect(copied.easing, source.easing);
    });

    test('box, name, id and source stay the target\'s own', () {
      final copied = copyLogoPartAnimation(source, target);
      expect(copied.id, 'dst');
      expect(copied.name, 'Apna Naam');
      expect(copied.box, target.box);
      expect(copied.sourcePath, target.sourcePath);
    });

    test('the copied part moves exactly like the source', () {
      final copied = copyLogoPartAnimation(source, target);
      for (final t in [0.0, 0.7, 1.3, 2.9, 5.25, 11.9]) {
        expect(LogoPartsService.partAngleAt(copied, t),
            LogoPartsService.partAngleAt(source, t),
            reason: 'angle must match at t=$t');
        expect(LogoPartsService.partScaleAt(copied, t),
            LogoPartsService.partScaleAt(source, t),
            reason: 'scale must match at t=$t');
      }
    });
  });

  group('(e) Keying mazbooti — strength removes more background', () {
    // 60×60: white background, a light-grey "halo" block
    // (RGB distance ≈86.6 from white) and a red element
    // (distance ≈323 — never keyed at any strength).
    Uint8List synthetic() {
      final rgba = _blank(60, 60);
      _fill(rgba, 60, 0, 0, 60, 60, 255, 255, 255);
      _fill(rgba, 60, 10, 10, 25, 25, 205, 205, 205);
      _fill(rgba, 60, 35, 35, 55, 55, 200, 30, 30);
      return rgba;
    }

    int keyedCount(double strength) {
      final keyed = keyLogoBackgroundRgba(
        rgba: synthetic(),
        width: 60,
        height: 60,
        tolerance: logoKeyingToleranceForStrength(strength),
      );
      var n = 0;
      for (var i = 3; i < keyed.length; i += 4) {
        if (keyed[i] == 0) n++;
      }
      return n;
    }

    test('the default strength IS the Builds 1–2 tolerance', () {
      expect(logoKeyingToleranceForStrength(kLogoKeyingStrengthDefault),
          closeTo(42, 0.001));
      expect(logoKeyingToleranceForStrength(0), 10);
      expect(logoKeyingToleranceForStrength(1), 110);
    });

    test('low strength keys only the true background; high keys the halo too',
        () {
      final low = keyedCount(0);
      final high = keyedCount(1);
      // White only: 3600 − 225 (halo) − 400 (element).
      expect(low, 2975);
      // White + halo.
      expect(high, 3200);
      expect(high, greaterThan(low));
      // The red element survives even the strongest keying.
      final keyed = keyLogoBackgroundRgba(
        rgba: synthetic(),
        width: 60,
        height: 60,
        tolerance: logoKeyingToleranceForStrength(1),
      );
      expect(_px(keyed, 60, 45, 45), (200, 30, 30, 255));
    });

    test('the proposal itself follows the keying strength', () {
      bool anyBoxOver(List<LogoBox> boxes, double fx, double fy) =>
          boxes.any((b) => fx >= b.x && fx < b.x + b.w && fy >= b.y && fy < b.y + b.h);
      final def = proposeLogoBoxes(rgba: synthetic(), width: 60, height: 60);
      final strong = proposeLogoBoxes(
        rgba: synthetic(),
        width: 60,
        height: 60,
        keyTolerance: logoKeyingToleranceForStrength(1),
      );
      // Default: the halo is an element of its own.
      expect(anyBoxOver(def, 17.5 / 60, 17.5 / 60), isTrue);
      // Strong: the halo is keyed away — no box lives there.
      expect(anyBoxOver(strong, 17.5 / 60, 17.5 / 60), isFalse);
      // Both still find the red element.
      expect(anyBoxOver(def, 45 / 60, 45 / 60), isTrue);
      expect(anyBoxOver(strong, 45 / 60, 45 / 60), isTrue);
    });
  });

  group('(f) parity — sweep + easing through the one painter', () {
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
          easing: kLogoEasingLinear,
        ),
      ];
      final scene = LogoPartsScene(
        glowOn: true,
        glowColorArgb: 0xFF00BCD4,
        glowIntensity: 0.9,
        glowSpread: 0.7,
        baseMode: kLogoPartsBaseGhost,
        sweepOn: true,
        sweepSpeed: 0.5,
        easing: kLogoEasingLinear,
      );
      // t=1.2 with 3 passes per loop: the band sits mid-frame.
      final viaExport = await LogoPartsService.renderPartsFrame(
        parts: parts,
        masterTexture: img,
        size: s,
        tSec: 1.2,
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
        1.2,
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

  group('(g) backward compatibility — Build 2 saves, Build 3 defaults', () {
    test('a Build 2 payload loads with the Build 3 defaults', () {
      const payload = '{"model":2,"parts":[{"id":"a","name":"A",'
          '"sourcePath":"/m.png","box":{"x":0.1,"y":0.1,"w":0.3,"h":0.3},'
          '"rotate":true,"direction":"cw","speedSec":4,"rotationStyle":"3d",'
          '"delaySec":0.2,"pivotDx":0.0,"pivotDy":0.0,'
          '"motionMode":"swing","swingDeg":35,"pulseOn":true,'
          '"pulseStrength":0.5}],'
          '"scene":{"glowOn":true,"glowColorArgb":4278222848,'
          '"glowIntensity":0.9,"glowSpread":0.6,"glowMotion":"pulse",'
          '"baseMode":"ghost"}}';
      final data = decodeLogoPartsSave(payload);
      final parts = data.parts;
      final scene = data.scene;
      expect(parts, hasLength(1));
      // The Build 2 values survive…
      expect(parts.single.motionMode, kLogoPartMotionSwing);
      expect(parts.single.pulseOn, isTrue);
      expect(scene.glowOn, isTrue);
      expect(scene.baseMode, kLogoPartsBaseGhost);
      // …and every Build 3 field takes its default: sweep
      // off, easing Narm, export 512, keying the old default.
      expect(parts.single.easing, kLogoEasingSmooth);
      expect(scene.sweepOn, isFalse);
      expect(scene.sweepSpeed, 0.5);
      expect(scene.easing, kLogoEasingSmooth);
      expect(scene.exportSize, kLogoPartsExportSizeDefault);
      expect(scene.keyingStrength, kLogoKeyingStrengthDefault);
    });

    test('Build 3 settings round-trip whole', () {
      final parts = [
        LogoPart(
          id: 'a',
          name: 'A',
          sourcePath: '/m.png',
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
          easing: kLogoEasingLinear,
        ),
      ];
      final scene = LogoPartsScene(
        sweepOn: true,
        sweepSpeed: 0.8,
        easing: kLogoEasingLinear,
        exportSize: kLogoPartsExportSizeLarge,
        keyingStrength: 0.9,
      );
      final data2 = decodeLogoPartsSave(encodeLogoPartsSave(parts, scene));
      final parts2 = data2.parts;
      final scene2 = data2.scene;
      expect(parts2.single.easing, kLogoEasingLinear);
      expect(scene2.sweepOn, isTrue);
      expect(scene2.sweepSpeed, 0.8);
      expect(scene2.easing, kLogoEasingLinear);
      expect(scene2.exportSize, kLogoPartsExportSizeLarge);
      expect(scene2.keyingStrength, 0.9);
      expect(scene2, scene);
    });
  });

  group('(i) the Maker wires all five Build 3 controls', () {
    late Directory tmp;
    late File logoFile;

    void mockPathProvider(String path) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => path,
      );
    }

    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> openTool(WidgetTester tester, String id) async {
      final target = find.byKey(Key('makerTool-$id'));
      await tester.dragUntilVisible(
        target,
        find.byKey(const Key('makerToolLine')),
        const Offset(-60, 0),
      );
      await tester.tap(target);
      await frames(tester);
    }

    Future<void> openPartsTab(WidgetTester tester, String tab) async {
      final target = find.byKey(Key('logoPartsTab-$tab'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await frames(tester);
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('logo_b3_widget');
      logoFile = File('${tmp.path}/logo.png');
      // A 1×1 PNG as the master logo file.
      await logoFile.writeAsBytes(const [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
        0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
        0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, //
        0, 3, 1, 1, 0, 201, 172, 201, 104, 0, 0, 0, 0, 73, 69, 78, //
        68, 174, 66, 96, 130,
      ]);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    testWidgets(
        'keying slider, Narmi chips, sweep switch, export size and '
        'settings copy/paste all write the preset', (tester) async {
      mockPathProvider(tmp.path);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final partA = LogoPart(
        id: 'pa',
        name: 'Pehla',
        sourcePath: logoFile.path,
        box: const LogoBox(x: 0.05, y: 0.05, w: 0.4, h: 0.4),
        direction: 'ccw',
        speedSec: 3,
        rotationStyle: kLogoPartStyle3d,
        delaySec: 0.6,
        motionMode: kLogoPartMotionSwing,
        swingDeg: 55,
        pulseOn: true,
        pulseStrength: 0.8,
        easing: kLogoEasingLinear,
      );
      final partB = LogoPart(
        id: 'pb',
        name: 'Doosra',
        sourcePath: logoFile.path,
        box: const LogoBox(x: 0.55, y: 0.55, w: 0.4, h: 0.4),
      );
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = logoFile.path
        ..logoParts = [partA, partB]
        ..logoPartsSourcePath = logoFile.path;
      await tester.pumpWidget(MaterialApp(
        home: NewsMakerScreen(
          initialPreset: preset,
          initialProject: NewsProject.create(presetId: preset.id),
        ),
      ));
      await frames(tester);
      await openTool(tester, 'logo');

      // --- (5) Logo tab: the Keying mazbooti slider writes
      // the scene. Default tab after opening is Hisay — go
      // to Logo first.
      await openPartsTab(tester, 'logo');
      final slider = find.byKey(const Key('logoKeyingStrength'));
      await tester.ensureVisible(slider);
      await frames(tester);
      expect(preset.logoPartsScene.keyingStrength,
          kLogoKeyingStrengthDefault);
      await tester.drag(slider, const Offset(80, 0));
      await frames(tester);
      expect(preset.logoPartsScene.keyingStrength,
          greaterThan(kLogoKeyingStrengthDefault));

      // --- (2) Waqt tab: the Narmi chip writes the part.
      await openPartsTab(tester, 'waqt');
      final chipB = find.byKey(const Key('logoPartEasing-1-linear'));
      await tester.ensureVisible(chipB);
      await frames(tester);
      expect(preset.logoParts[1].easing, kLogoEasingSmooth);
      await tester.tap(chipB);
      await frames(tester);
      expect(preset.logoParts[1].easing, kLogoEasingLinear);

      // --- (1) Glow tab: the sweep switch writes the scene
      // and reveals the speed slider.
      await openPartsTab(tester, 'glow');
      final sweepSwitch = find.byKey(const Key('logoSweepOn'));
      await tester.ensureVisible(sweepSwitch);
      await frames(tester);
      expect(preset.logoPartsScene.sweepOn, isFalse);
      expect(find.byKey(const Key('logoSweepSpeed')), findsNothing);
      await tester.tap(sweepSwitch);
      await frames(tester);
      expect(preset.logoPartsScene.sweepOn, isTrue);
      expect(find.byKey(const Key('logoSweepSpeed')), findsOneWidget);

      // --- (3) Save tab: the export-size chip writes the scene.
      await openPartsTab(tester, 'save');
      final sizeChip = find.byKey(const Key('logoExportSize-1024'));
      await tester.ensureVisible(sizeChip);
      await frames(tester);
      expect(preset.logoPartsScene.exportSize, kLogoPartsExportSizeDefault);
      await tester.tap(sizeChip);
      await frames(tester);
      expect(preset.logoPartsScene.exportSize, kLogoPartsExportSizeLarge);

      // --- (4) Ghumao tab: copy part A's animation, select
      // part B in Hisay, paste — B's animation becomes A's,
      // B's box and name stay B's.
      await openPartsTab(tester, 'ghumao');
      final copyBtn = find.byKey(const Key('logoPartAnimCopy-0'));
      await tester.ensureVisible(copyBtn);
      await frames(tester);
      await tester.tap(copyBtn);
      await frames(tester);
      await openPartsTab(tester, 'hisay');
      final selectB = find.byKey(const Key('logoPartSelect-1'));
      await tester.ensureVisible(selectB);
      await frames(tester);
      await tester.tap(selectB);
      await frames(tester);
      await openPartsTab(tester, 'ghumao');
      final pasteBtn = find.byKey(const Key('logoPartAnimPaste-1'));
      await tester.ensureVisible(pasteBtn);
      await frames(tester);
      await tester.tap(pasteBtn);
      await frames(tester);
      final b = preset.logoParts[1];
      expect(b.direction, 'ccw');
      expect(b.speedSec, 3);
      expect(b.rotationStyle, kLogoPartStyle3d);
      expect(b.delaySec, 0.6);
      expect(b.motionMode, kLogoPartMotionSwing);
      expect(b.swingDeg, 55);
      expect(b.pulseOn, isTrue);
      expect(b.pulseStrength, 0.8);
      expect(b.easing, kLogoEasingLinear);
      expect(b.name, 'Doosra');
      expect(b.box, partB.box);
    });
  });
}
