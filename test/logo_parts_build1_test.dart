/// Logo Parts REDESIGN — Build 1 (element model) proofs.
///
/// (a) a box crop contains EXACTLY the box's pixels;
/// (b) a part's rendered rotation pivots on the BOX centre
///     (pixel proof, with the box centre ≠ frame centre, and
///     the cut base keeping non-part content in place);
/// (c) auto tajweez on synthetic logos: text-inside-box
///     merges into ONE element, two separate boxes stay two,
///     one-line letters join into one word box;
/// (d) two parts with different speeds/directions render
///     measurably different frames;
/// (e) old slice-model settings load as NO parts (no crash);
/// (f) preview/export parity: the export frame renderer and
///     the shared painter (the preview's only paint path)
///     produce identical pixels;
/// (g) hisay tools: merge = union box, split tiles the box,
///     sequence staggers, sync zeroes;
/// (h) waqt + pivot: delay is a seamless phase offset, and a
///     moved pivot provably moves the rendered orbit.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/services/logo_parts_service.dart';

// ----------------------------------------------------------------
// Synthetic RGBA helpers.
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

void _outline(
  Uint8List rgba,
  int w,
  int x0,
  int y0,
  int x1,
  int y1,
  int thickness,
  int r,
  int g,
  int b,
) {
  _fill(rgba, w, x0, y0, x1, y0 + thickness, r, g, b);
  _fill(rgba, w, x0, y1 - thickness, x1, y1, r, g, b);
  _fill(rgba, w, x0, y0, x0 + thickness, y1, r, g, b);
  _fill(rgba, w, x1 - thickness, y0, x1, y1, r, g, b);
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
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('(a) box crop = exactly the box pixels', () {
    test('crop bytes match the source region pixel for pixel', () {
      const w = 100, h = 80;
      final rgba = _blank(w, h);
      // Every pixel encodes its own coordinates.
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          rgba[o] = x;
          rgba[o + 1] = y;
          rgba[o + 2] = (x + y) % 256;
          rgba[o + 3] = 255;
        }
      }
      // Box (0.25, 0.25, 0.5, 0.5) → pixels x 25..74, y 20..59
      // (binary-exact fractions, so the pixel rect is exact).
      final crop = cropLogoBoxRgba(
        rgba: rgba,
        width: w,
        height: h,
        box: const LogoBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
      );
      expect(crop.width, 50);
      expect(crop.height, 40);
      expect(crop.pixelCount, 50 * 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 50; x++) {
          expect(
            _px(crop.rgba, 50, x, y),
            (25 + x, 20 + y, (25 + x + 20 + y) % 256, 255),
            reason: 'crop pixel ($x,$y) must be source (${25 + x},${20 + y})',
          );
        }
      }
    });

    test('tap hit-test: topmost (last painted) part wins', () {
      final parts = logoPartsFromBoxes(
        sourcePath: '/logo.png',
        boxes: const [
          LogoBox(x: 0, y: 0, w: 0.6, h: 0.6),
          LogoBox(x: 0.4, y: 0.4, w: 0.6, h: 0.6),
        ],
      );
      // Overlap zone → the second (top) part.
      expect(logoPartIndexAtPoint(parts, 0.5, 0.5), 1);
      // Only-first zone → the first part.
      expect(logoPartIndexAtPoint(parts, 0.1, 0.1), 0);
      // Outside both → -1.
      expect(logoPartIndexAtPoint(parts, 0.95, 0.05), -1);
    });
  });

  group('(b) rotation pivots on the BOX centre (pixel proof)', () {
    // Master 128²: top-left quadrant is the part's box (red,
    // white marker at its top-left corner); a blue block in
    // the bottom-right is base content (no part covers it).
    Uint8List master() {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 0, 0, 64, 64, 220, 30, 30); // the box, red
      _fill(rgba, s, 4, 4, 12, 12, 255, 255, 255); // marker
      _fill(rgba, s, 88, 88, 120, 120, 30, 30, 220); // base blue
      return rgba;
    }

    LogoPart part() => LogoPart(
          id: 'p0',
          name: 'P',
          sourcePath: '/master.png',
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
          speedSec: 2, // t=1.0 → exactly 180°
        );

    test('180° turn: content stays in the box, marker swaps corner', () async {
      final img = await _imageOf(master(), 128, 128);
      final at0 = await LogoPartsService.renderPartsFrame(
        parts: [part()],
        masterTexture: img,
        size: 128,
        tSec: 0,
      );
      final px0 = await _rgbaOf(at0);
      at0.dispose();
      // Resting: marker top-left, box centre red.
      expect(_px(px0, 128, 7, 7), (255, 255, 255, 255));
      expect(_px(px0, 128, 32, 32), (220, 30, 30, 255));

      final at180 = await LogoPartsService.renderPartsFrame(
        parts: [part()],
        masterTexture: img,
        size: 128,
        tSec: 1.0,
      );
      final px = await _rgbaOf(at180);
      at180.dispose();
      img.dispose();
      // The marker rotated around the BOX centre (32,32) and
      // now sits at the box's bottom-right corner.
      expect(_px(px, 128, 56, 56), (255, 255, 255, 255));
      // Its old spot shows the red that came from the opposite
      // corner — the box still occupies exactly its own rect.
      expect(_px(px, 128, 7, 7), (220, 30, 30, 255));
      expect(_px(px, 128, 32, 32), (220, 30, 30, 255));
      // Nothing swung into the opposite quadrant (that is
      // what rotation around the FRAME centre would have
      // done), and the base's blue block never moved.
      expect(_px(px, 128, 96, 32), (0, 0, 0, 0));
      expect(_px(px, 128, 104, 104), (30, 30, 220, 255));
    });
  });

  group('(c) auto tajweez on synthetic logos', () {
    test('text inside its outline box merges into ONE element', () {
      const w = 200, h = 120;
      final rgba = _blank(w, h);
      _fill(rgba, w, 0, 0, w, h, 255, 255, 255); // white bg
      // Element 1: red outline box + three dark glyphs inside.
      _outline(rgba, w, 10, 30, 90, 90, 4, 220, 30, 30);
      for (final gx in [25, 45, 65]) {
        _fill(rgba, w, gx, 50, gx + 8, 70, 30, 30, 30);
      }
      // Element 2: a separate filled blue box with light
      // glyph holes punched in it (still one element).
      _fill(rgba, w, 120, 40, 170, 80, 30, 30, 220);
      _fill(rgba, w, 132, 52, 140, 68, 255, 255, 255);
      _fill(rgba, w, 148, 52, 156, 68, 255, 255, 255);

      final boxes = proposeLogoBoxes(rgba: rgba, width: w, height: h);
      expect(boxes.length, 2, reason: 'boxes: $boxes');
      // One box on the outline+text element, one on the blue.
      expect(
        boxes.any((b) => (b.centreX - 0.25).abs() < 0.04 &&
            (b.centreY - 0.50).abs() < 0.04),
        isTrue,
        reason: 'outline element box missing: $boxes',
      );
      expect(
        boxes.any((b) => (b.centreX - 0.725).abs() < 0.04),
        isTrue,
        reason: 'blue element box missing: $boxes',
      );
    });

    test('two separate boxes stay two elements', () {
      const w = 160, h = 100;
      final rgba = _blank(w, h);
      _fill(rgba, w, 0, 0, w, h, 255, 255, 255);
      _fill(rgba, w, 10, 20, 60, 70, 220, 30, 30);
      _fill(rgba, w, 100, 20, 150, 70, 30, 30, 220);
      final boxes = proposeLogoBoxes(rgba: rgba, width: w, height: h);
      expect(boxes.length, 2, reason: 'boxes: $boxes');
      expect(boxes.any((b) => b.centreX < 0.4), isTrue);
      expect(boxes.any((b) => b.centreX > 0.6), isTrue);
    });

    test('letters on one line join into ONE word box', () {
      const w = 160, h = 80;
      final rgba = _blank(w, h);
      _fill(rgba, w, 0, 0, w, h, 255, 255, 255);
      for (final gx in [20, 36, 52, 68, 84]) {
        _fill(rgba, w, gx, 32, gx + 10, 48, 30, 30, 30);
      }
      final boxes = proposeLogoBoxes(rgba: rgba, width: w, height: h);
      expect(boxes.length, 1, reason: 'boxes: $boxes');
      // The single box spans the whole word.
      expect(boxes.single.x, lessThan(0.16));
      expect(boxes.single.right, greaterThan(0.56));
    });
  });

  group('(d) speed/direction change the rendered frames', () {
    Future<Uint8List> frame({
      required double speed,
      required String direction,
      required double tSec,
    }) async {
      const s = 128;
      final rgba = _blank(s, s);
      _fill(rgba, s, 0, 0, 64, 128, 220, 30, 30); // left half
      _fill(rgba, s, 8, 8, 24, 24, 255, 255, 255); // marker
      final img = await _imageOf(rgba, s, s);
      final part = LogoPart(
        id: 'p0',
        name: 'P',
        sourcePath: '/master.png',
        box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
        speedSec: speed,
        direction: direction,
      );
      final frame = await LogoPartsService.renderPartsFrame(
        parts: [part],
        masterTexture: img,
        size: 128,
        tSec: tSec,
      );
      final px = await _rgbaOf(frame);
      frame.dispose();
      img.dispose();
      return px;
    }

    test('different speeds and directions render differently', () async {
      final fast = await frame(speed: 2, direction: 'cw', tSec: 1.5);
      final slow = await frame(speed: 12, direction: 'cw', tSec: 1.5);
      final ccw = await frame(speed: 2, direction: 'ccw', tSec: 1.5);
      expect(_diffPixels(fast, slow), greaterThan(200));
      expect(_diffPixels(fast, ccw), greaterThan(200));
    });
  });

  group('(e) old settings never crash the new model', () {
    test('slice-model payloads and junk decode to empty', () {
      expect(
        decodeLogoParts(
          '[{"id":"a","name":"A","imagePath":"/parts/part_0.png",'
          '"rotate":true,"direction":"cw","speedSec":6,'
          '"centreX":0.31,"centreY":0.42}]',
        ),
        isEmpty,
      );
      expect(decodeLogoParts('[{"model":2,"id":"x"}]'), isEmpty);
      expect(decodeLogoParts('{{{'), isEmpty);
      // A valid element-model entry still loads.
      final ok = decodeLogoParts(
        '[{"model":2,"id":"a","name":"NEWS","sourcePath":"/logo.png",'
        '"box":{"x":0.1,"y":0.2,"w":0.3,"h":0.4},"rotate":true,'
        '"direction":"cw","speedSec":6,"rotationStyle":"flat"}]',
      );
      expect(ok.length, 1);
      expect(ok.single.name, 'NEWS');
      expect(ok.single.centreX, closeTo(0.25, 1e-9));
    });
  });

  group('(f) preview/export parity through the shared painter', () {
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
        ),
        LogoPart(
          id: 'b',
          name: 'B',
          sourcePath: '/master.png',
          box: const LogoBox(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
          speedSec: 3,
          direction: 'ccw',
          rotationStyle: kLogoPartStyle3d,
        ),
      ];
      // The export path.
      final viaExport = await LogoPartsService.renderPartsFrame(
        parts: parts,
        masterTexture: img,
        size: 128,
        tSec: 0.7,
      );
      final exportPx = await _rgbaOf(viaExport);
      viaExport.dispose();
      // The preview path: LogoPartsView's painter is a direct
      // delegate to LogoPartsService.paintParts — render the
      // same call on a bare canvas and compare.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      LogoPartsService.paintParts(
        canvas,
        const ui.Size(128, 128),
        parts,
        img,
        0.7,
      );
      final picture = recorder.endRecording();
      final viaPainter = await picture.toImage(128, 128);
      picture.dispose();
      final painterPx = await _rgbaOf(viaPainter);
      viaPainter.dispose();
      img.dispose();
      expect(_diffPixels(exportPx, painterPx), 0);
      // And the frame is not blank — the animation is real.
      expect(exportPx.any((v) => v != 0), isTrue);
    });
  });

  group('Logo Parts Build 1 — Groups 4/5 (hisay tools, waqt, pivot)', () {
    test('(g) merge = union box + selected settings; split tiles the box',
        () {
      final a = LogoPart(
        id: 'a',
        name: 'NEWS',
        sourcePath: '/m.png',
        box: const LogoBox(x: 0.1, y: 0.1, w: 0.3, h: 0.2),
        speedSec: 3,
        direction: 'ccw',
        rotationStyle: kLogoPartStyle3d,
        delaySec: 0.4,
      );
      final b = LogoPart(
        id: 'b',
        name: 'HD',
        sourcePath: '/m.png',
        box: const LogoBox(x: 0.35, y: 0.25, w: 0.3, h: 0.3),
        speedSec: 12,
      );
      final merged = mergeLogoParts(a, b);
      expect(merged.box.x, closeTo(0.1, 1e-9));
      expect(merged.box.y, closeTo(0.1, 1e-9));
      expect(merged.box.x + merged.box.w, closeTo(0.65, 1e-9));
      expect(merged.box.y + merged.box.h, closeTo(0.55, 1e-9));
      expect(merged.name, 'NEWS + HD');
      expect(merged.speedSec, 3);
      expect(merged.direction, 'ccw');
      expect(merged.rotationStyle, kLogoPartStyle3d);
      expect(merged.delaySec, 0.4);

      final halves = splitLogoPart(a);
      expect(halves, hasLength(2));
      expect(halves[0].box.x, a.box.x);
      expect(halves[0].box.w + halves[1].box.w, closeTo(a.box.w, 1e-9));
      expect(halves[1].box.x, closeTo(a.box.x + a.box.w / 2, 1e-9));
      expect(halves[0].box.y, a.box.y);
      expect(halves[0].box.h, a.box.h);
      expect(halves[0].id, isNot(halves[1].id));
      expect(halves[1].speedSec, 3);
      expect(halves[1].delaySec, 0.4);
    });

    test('(g2) sequence staggers 0.2s per part; sync zeroes every delay',
        () {
      final parts = [
        for (var i = 0; i < 3; i++)
          LogoPart(
            id: 'p$i',
            name: 'P$i',
            sourcePath: '/m.png',
            box: LogoBox(x: 0.1 * i, y: 0, w: 0.1, h: 0.1),
            delaySec: 1.5,
          ),
      ];
      final staggered = staggerLogoPartDelays(parts);
      expect(staggered.map((p) => p.delaySec), [0.0, 0.2, 0.4]);
      // The originals are untouched (copies, never mutation).
      expect(parts.every((p) => p.delaySec == 1.5), isTrue);
      final synced = syncLogoPartDelays(staggered);
      expect(synced.every((p) => p.delaySec == 0), isTrue);
    });

    test('(h) delay is a phase offset — same angle, shifted; loop seamless',
        () {
      LogoPart part(double delay) => LogoPart(
            id: 'p',
            name: 'P',
            sourcePath: '/m.png',
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
            speedSec: 4,
            delaySec: delay,
          );
      // Delay 1s at t=2 == no delay at t=1 (a quarter turn).
      expect(
        LogoPartsService.partAngleAt(part(1), 2),
        closeTo(LogoPartsService.partAngleAt(part(0), 1), 1e-9),
      );
      // One full 12s loop later the angle repeats exactly
      // (3 whole turns at speed 4) — the loop can never jump.
      final drift =
          (LogoPartsService.partAngleAt(part(0.6), 12.3) -
                  LogoPartsService.partAngleAt(part(0.6), 0.3)) /
              (2 * math.pi);
      expect(drift, closeTo(3.0, 1e-9));
      // Two parts, same speed, different delays: different
      // angles at the same instant.
      expect(
        LogoPartsService.partAngleAt(part(0), 0.5) ==
            LogoPartsService.partAngleAt(part(0.2), 0.5),
        isFalse,
      );
    });

    test('(h2) pivot pixel proof — moving the pivot moves the orbit',
        () async {
      // Master 128x128: red in the top-left quadrant only.
      final rgba = _blank(128, 128);
      _fill(rgba, 128, 0, 0, 64, 64, 220, 30, 30);
      final img = await _imageOf(rgba, 128, 128);
      LogoPart part(double pdx, double pdy) => LogoPart(
            id: 'p',
            name: 'P',
            sourcePath: '/m.png',
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
            speedSec: 2, // t=1.0 → exactly 180°
            pivotDx: pdx,
            pivotDy: pdy,
          );
      Future<Uint8List> render(LogoPart p) async {
        final frame = await LogoPartsService.renderPartsFrame(
          parts: [p],
          masterTexture: img,
          size: 128,
          tSec: 1.0,
        );
        final px = await _rgbaOf(frame);
        frame.dispose();
        return px;
      }

      // Default pivot = the box centre (32,32)px: at 180° the
      // red quadrant lands at the box's bottom-right — still
      // inside the top-left quadrant of the frame.
      final centred = await render(part(0, 0));
      expect(_px(centred, 128, 48, 48), (220, 30, 30, 255));
      expect(_px(centred, 128, 112, 112), (0, 0, 0, 0));
      // Pivot dragged to the FRAME centre (64,64)px: the same
      // 180° turn now throws the red quadrant across the frame
      // into the bottom-right.
      final moved = await render(part(0.25, 0.25));
      expect(_px(moved, 128, 112, 112), (220, 30, 30, 255));
      expect(_px(moved, 128, 48, 48), (0, 0, 0, 0));
      img.dispose();
    });

    test('(h3) 3D corners honour the pivot; JSON keeps delay + pivot', () {
      const box = LogoBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4);
      // Angle 0: the box rect, whatever the pivot.
      final atRest = logoPart3DBoxCorners(
        size: const ui.Size(128, 128),
        box: box,
        angle: 0,
        pivotX: 0.5,
        pivotY: 0.5,
      );
      expect(atRest[0].dx, closeTo(0.1 * 128, 0.01));
      expect(atRest[2].dx, closeTo(0.5 * 128, 0.01));
      // Pivot on the box's right edge (x=0.5): edge-on at 90°,
      // every corner collapses onto the pivot's vertical line.
      final edgeOn = logoPart3DBoxCorners(
        size: const ui.Size(128, 128),
        box: box,
        angle: math.pi / 2,
        pivotX: 0.5,
        pivotY: 0.3,
      );
      for (final c in edgeOn) {
        expect(c.dx, closeTo(0.5 * 128, 0.75));
      }
      // JSON round-trip carries the new fields.
      final part = LogoPart(
        id: 'p',
        name: 'P',
        sourcePath: '/m.png',
        box: box,
        delaySec: 0.6,
        pivotDx: 0.05,
        pivotDy: -0.03,
      );
      final back = LogoPart.fromJson(part.toJson());
      expect(back.delaySec, 0.6);
      expect(back.pivotDx, 0.05);
      expect(back.pivotDy, -0.03);
      expect(back.pivotX, closeTo(box.centreX + 0.05, 1e-9));
    });
  });
}
