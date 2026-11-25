/// LOGO PARTS SERVICE — ELEMENT MODEL (redesign Build 1,
/// 2026-11-25; spec: LOGO-PARTS-REDESIGN-2026-11-25.md).
/// Build 2 adds the SCENE: the generated glow layer behind
/// the whole logo and the three base plates (cut / none /
/// ghost), plus the per-part Andaaz — Swing motion and Pulse
/// breathing — all through the same one painter.
/// Build 3 (Polish) adds the Light Sweep over the finished
/// logo, the Narmi (easing) shaping of every oscillating
/// motion, and the Keying mazbooti strength on the proposal.
///
/// The device-side half of the Logo Parts engine (the pure
/// model + box proposal live in lib/news/logo_parts.dart).
///
/// - [proposePartsForFile] decodes a logo file and returns
///   parts whose BOXES the auto tajweez proposed — the master
///   image itself is never cut or modified.
/// - [paintParts] is the ONE painter behind the combined
///   preview, the per-part previews and the export frames:
///   it draws the CUT BASE (the master with every part's box
///   erased, so a part that turns away shows whatever is
///   behind the logo — no inpainting, per spec) and then each
///   part's box region of the master, rotating around its own
///   box centre, in list (layer) order.
/// - [generatePartsFrames] renders the export loop frames
///   through the same painter — preview and export cannot
///   drift.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../news/logo_parts.dart';
import 'logo_cube.dart' show kLogoCubeFocal;
import 'logo_loop_service.dart' show kLogoLoopFps;

/// Identity matrix for the 3D part shader (column-major) —
/// the same convention as logo_cube.dart's texture shader.
final Float64List _identityMatrix = Float64List.fromList(<double>[
  1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1,
]);

/// The projected canvas corners (TL, TR, BR, BL) of a part's
/// BOX when it turns around the VERTICAL axis through its
/// PIVOT (default: the box's own centre; Option 22 lets the
/// user move it) — the cube-style 3D rotation. Pure geometry
/// (the same perspective the Logo Cube uses:
/// [kLogoCubeFocal] camera distance, frame = 1 unit), so the
/// painter and the tests read identical numbers.
///
/// At angle 0 the corners are exactly the box rect, whatever
/// the pivot; at ±90° the box is edge-on (a vertical line
/// through the pivot); past that the back face shows,
/// mirrored like a real coin.
List<ui.Offset> logoPart3DBoxCorners({
  required ui.Size size,
  required LogoBox box,
  required double angle,
  double? pivotX,
  double? pivotY,
  double scale = 1,
}) {
  final cx = pivotX ?? box.centreX;
  final cy = pivotY ?? box.centreY;
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  // Box corners as offsets from the PIVOT, in frame
  // fractions: TL, TR, BR, BL. [scale] (the Pulse swell)
  // grows/shrinks the offsets around the pivot before the
  // projection — at scale 1 the corners are exactly the
  // Build 1 geometry.
  final unit = [
    ((box.x - cx) * scale, (box.y - cy) * scale),
    ((box.x + box.w - cx) * scale, (box.y - cy) * scale),
    ((box.x + box.w - cx) * scale, (box.y + box.h - cy) * scale),
    ((box.x - cx) * scale, (box.y + box.h - cy) * scale),
  ];
  return [
    for (final (dx, dy) in unit)
      () {
        final x1 = dx * cosA;
        final z1 = -dx * sinA;
        final scale = kLogoCubeFocal / (kLogoCubeFocal - z1);
        return ui.Offset(
          (cx + x1 * scale) * size.width,
          (cy + dy * scale) * size.height,
        );
      }(),
  ];
}

/// The shading brightness (0..1) of a 3D-turning part at
/// [angle] — full when facing the camera, dimmest edge-on;
/// the cube's classic read (0.42 floor + facing).
double logoPart3DBrightness(double angle) =>
    (0.42 + 0.58 * math.cos(angle).abs()).clamp(0.0, 1.0);

class LogoPartsService {
  LogoPartsService._();

  /// Decodes [logoFile] and proposes element parts for it
  /// (auto tajweez — see [proposeLogoBoxes]). Returns an
  /// empty list when no boxes could be proposed — the caller
  /// says so honestly and the user can still draw boxes.
  /// [keyingStrength] (Option 3, Build 3) is the Logo tab's
  /// Keying mazbooti slider — it sets the tolerance of the
  /// border keying inside the proposal; the default is the
  /// exact strength Builds 1–2 always used.
  static Future<List<LogoPart>> proposePartsForFile(
    File logoFile, {
    double keyingStrength = kLogoKeyingStrengthDefault,
  }) async {
    final bytes = await logoFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) {
      image.dispose();
      return const [];
    }
    final boxes = proposeLogoBoxes(
      rgba: bd.buffer.asUint8List(),
      width: image.width,
      height: image.height,
      keyTolerance: logoKeyingToleranceForStrength(keyingStrength),
    );
    image.dispose();
    if (boxes.isEmpty) return const [];
    return logoPartsFromBoxes(sourcePath: logoFile.path, boxes: boxes);
  }

  static Future<ui.Image?> _decodeFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Loads the master logo texture the parts look into
  /// (fail-soft: a missing/undecodable file reads as null and
  /// the painters simply draw nothing — never a crash).
  static Future<ui.Image?> loadMasterTexture(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _decodeFile(File(path));
  }

  /// One cycle of an oscillating motion at [phase] (in
  /// turns, 0..1 per cycle), shaped by [easing] (Option 27,
  /// Build 3): 'smooth' (Narm) is the sine — 0 at phase 0,
  /// +1 at the quarter, 0 at the half, −1 at three quarters;
  /// 'linear' (Barabar) is the triangle through the SAME
  /// points at a constant rate. The two agree at the cycle's
  /// start, extremes and end — they differ mid-phase, which
  /// is exactly the softness the choice controls. 'smooth'
  /// reproduces the Builds 1–2 motion bit-for-bit.
  static double oscillation(String easing, double phase) {
    if (easing == kLogoEasingLinear) {
      final p = phase - phase.floorToDouble();
      if (p < 0.25) return 4 * p;
      if (p < 0.75) return 2 - 4 * p;
      return 4 * p - 4;
    }
    return math.sin(phase * 2 * math.pi);
  }

  /// The rotation angle (radians) of [part] at loop time
  /// [tSec] — shared by the preview painters and the frame
  /// renderer so all of them show the same motion. The start
  /// waqfa (delaySec) is a PHASE offset inside the seamless
  /// loop: the cycle is shifted, never paused, so the
  /// 12-second loop can never jump at the wrap.
  ///
  /// ANDAAZ (Build 2): in Swing mode the angle is a pendulum
  /// — ±swingDeg around the pivot, one full back-and-forth
  /// per speedSec — instead of whole revolutions. The
  /// pendulum's shape is the part's Narmi (Build 3): the
  /// sine (Narm) or the constant-rate triangle (Barabar).
  static double partAngleAt(LogoPart part, double tSec) {
    if (!part.rotate) return 0;
    final phase = (tSec - part.delaySec) / part.speedSec;
    if (part.motionMode == kLogoPartMotionSwing) {
      final swing =
          part.swingDeg * math.pi / 180 * oscillation(part.easing, phase);
      return part.direction == 'ccw' ? -swing : swing;
    }
    final angle = phase * 2 * math.pi;
    return part.direction == 'ccw' ? -angle : angle;
  }

  /// The Pulse scale of [part] at loop time [tSec] (Build 2,
  /// Option 23): 1 when pulse is off; otherwise a gentle
  /// breathing swell on [kLogoPartPulsePeriodSec] — also a
  /// divisor of the master loop, so the loop stays seamless.
  /// Pulse is independent of the rotate switch and of the
  /// motion mode: a still part can still breathe. Its shape
  /// is the part's Narmi (Build 3), like the Swing's.
  static double partScaleAt(LogoPart part, double tSec) {
    if (!part.pulseOn) return 1;
    final phase = (tSec - part.delaySec) / kLogoPartPulsePeriodSec;
    return 1 +
        kLogoPartPulseMaxAmp *
            part.pulseStrength *
            oscillation(part.easing, phase);
  }

  /// Resolves the AUTO glow colour of a decoded logo image
  /// (its dominant colour) — used by the previews and the
  /// frame renderer when the scene's glow colour is 'auto'.
  static Future<int?> dominantColorOfImage(ui.Image image) async {
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      return dominantLogoColorArgb(bd.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// The part's box as a pixel rect inside a canvas of [size].
  static ui.Rect boxRectIn(ui.Size size, LogoBox box) => ui.Rect.fromLTWH(
        box.x * size.width,
        box.y * size.height,
        box.w * size.width,
        box.h * size.height,
      );

  /// The part's box as a pixel rect inside its master texture.
  static ui.Rect boxSrcRect(ui.Image texture, LogoBox box) =>
      ui.Rect.fromLTWH(
        box.x * texture.width,
        box.y * texture.height,
        box.w * texture.width,
        box.h * texture.height,
      );

  /// Paints the whole logo at loop time [tSec] into [canvas]
  /// inside [size], back to front:
  /// 1. the GLOW (Build 2) — a generated layer behind the
  ///    whole logo: its silhouette, tinted + blurred. Only
  ///    when the scene's glow is on and a colour is known
  ///    (the scene's own colour, or [autoGlowColorArgb] —
  ///    the master's dominant colour, resolved by the
  ///    caller because reading pixels is async);
  /// 2. the BASE plate (Option 33) — 'cut': the master with
  ///    every part's box erased (a part that turns away
  ///    leaves a see-through hole, exactly like a broadcast
  ///    logo bug over video); 'ghost': the whole master,
  ///    untouched; 'none': no base at all;
  /// 3. every part in list (layer) order, each turning
  ///    around its OWN pivot (box centre by default) and
  ///    breathing by its own pulse.
  static void paintParts(
    ui.Canvas canvas,
    ui.Size size,
    List<LogoPart> parts,
    ui.Image? master,
    double tSec, {
    LogoPartsScene? scene,
    int? autoGlowColorArgb,
  }) {
    if (master == null) return;
    final sc = scene ?? LogoPartsScene();
    final fullSrc = ui.Rect.fromLTWH(
      0,
      0,
      master.width.toDouble(),
      master.height.toDouble(),
    );
    final fullDst = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    // 1. Glow — behind everything.
    if (sc.glowOn) {
      final colorArgb = sc.glowColorArgb ?? autoGlowColorArgb;
      if (colorArgb != null) {
        _paintGlow(canvas, size, master, sc, colorArgb, tSec);
      }
    }
    if (parts.isEmpty) {
      if (sc.baseMode != kLogoPartsBaseNone) {
        canvas.drawImageRect(master, fullSrc, fullDst, paint);
      }
      // The Light Sweep crosses the whole logo even before
      // any part exists (it rides the master's silhouette).
      if (sc.sweepOn) _paintSweep(canvas, size, master, sc, tSec);
      return;
    }
    // 2. Base plate.
    switch (sc.baseMode) {
      case kLogoPartsBaseNone:
        break; // no base — only the parts (+ glow) exist
      case kLogoPartsBaseGhost:
        canvas.drawImageRect(master, fullSrc, fullDst, paint);
      default: // cut
        canvas.saveLayer(fullDst, ui.Paint());
        canvas.drawImageRect(master, fullSrc, fullDst, paint);
        final erase = ui.Paint()..blendMode = ui.BlendMode.clear;
        for (final part in parts) {
          canvas.drawRect(boxRectIn(size, part.box), erase);
        }
        canvas.restore();
    }
    // 3. Parts, back to front (list order = layer order).
    for (final part in parts) {
      _paintPartBox(
        canvas,
        size,
        master,
        dstBox: part.box,
        srcRect: boxSrcRect(master, part.box),
        angle: partAngleAt(part, tSec),
        style: part.rotationStyle,
        pivotFrac: ui.Offset(part.pivotX, part.pivotY),
        scale: partScaleAt(part, tSec),
      );
    }
    // 4. The Light Sweep (Build 3) — over everything, the
    // channel-ident shine crossing the finished logo.
    if (sc.sweepOn) _paintSweep(canvas, size, master, sc, tSec);
  }

  /// How many Light Sweep passes cross the logo inside one
  /// master loop at the scene's sweep speed — always a
  /// whole number (1 at speed 0, 4 at speed 1), so the
  /// sweep is periodic in the 12s loop at ANY slider
  /// position and the loop can never jump.
  static int sweepPassesPerLoop(LogoPartsScene scene) =>
      1 + (scene.sweepSpeed * 3).round();

  /// The Light Sweep band's centre (frame fraction, x) at
  /// loop time [tSec] (Option 34, Build 3). Inside a pass
  /// the band travels from −0.4 (off-frame left) to 1.4
  /// (off-frame right) over the pass's first 55%; for the
  /// rest of the pass it rests off-frame and this returns
  /// 2.0 (parked — the painter skips it). Pure, so the
  /// painter and the tests read identical numbers.
  static double sweepCentreAt(LogoPartsScene scene, double tSec) {
    final period = kLogoPartsLoopSec / sweepPassesPerLoop(scene);
    final local = (tSec % period) / period;
    const active = 0.55;
    if (local >= active) return 2.0;
    return -0.4 + (local / active) * 1.8;
  }

  /// The Light Sweep itself: a soft diagonal band of white
  /// light, drawn in a layer and masked by the master's
  /// silhouette (dstIn) so the shine exists ONLY on the
  /// logo — the channel-ident read. Off-frame phases draw
  /// nothing.
  static void _paintSweep(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image master,
    LogoPartsScene scene,
    double tSec,
  ) {
    final centre = sweepCentreAt(scene, tSec);
    if (centre < -0.5 || centre > 1.5) return;
    final fullSrc = ui.Rect.fromLTWH(
      0,
      0,
      master.width.toDouble(),
      master.height.toDouble(),
    );
    final fullDst = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.saveLayer(fullDst, ui.Paint());
    canvas.save();
    canvas.translate(centre * size.width, size.height / 2);
    canvas.rotate(-0.32);
    final bandW = size.width * 0.30;
    final bandRect = ui.Rect.fromLTWH(
      -bandW / 2,
      -size.height,
      bandW,
      size.height * 2,
    );
    final gradient = ui.Gradient.linear(
      ui.Offset(-bandW / 2, 0),
      ui.Offset(bandW / 2, 0),
      const [
        ui.Color(0x00FFFFFF),
        ui.Color(0x8CFFFFFF),
        ui.Color(0x00FFFFFF),
      ],
      const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(bandRect, ui.Paint()..shader = gradient);
    canvas.restore();
    canvas.drawImageRect(
      master,
      fullSrc,
      fullDst,
      ui.Paint()..blendMode = ui.BlendMode.dstIn,
    );
    canvas.restore();
  }

  /// The generated glow layer: the master's silhouette,
  /// tinted to [colorArgb] (srcIn keeps only the silhouette
  /// shape), blurred by the spread, grown a touch by the
  /// spread, and alpha-set by the (possibly breathing)
  /// intensity. 'spin' motion turns the layer slowly around
  /// the frame centre — one turn per master loop.
  static void _paintGlow(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image master,
    LogoPartsScene scene,
    int colorArgb,
    double tSec,
  ) {
    var intensity = scene.glowIntensity;
    if (scene.glowMotion == kLogoGlowMotionPulse) {
      // Breathing: the strength swells and settles on a 6s
      // cycle (a divisor of the 12s loop — seamless), shaped
      // by the scene's Narmi (Build 3): at 'smooth' this is
      // the exact sine Builds 1–2 shipped (the −0.25 phase
      // starts the breath settled, at its lowest).
      intensity *= 0.72 + 0.28 * oscillation(scene.easing, tSec / 6 - 0.25);
    }
    if (intensity <= 0.01) return;
    final alpha = (intensity.clamp(0, 1) * 255).round();
    final sigma = (0.5 + scene.glowSpread * 0.07 * size.width)
        .clamp(0.5, size.width);
    final glowPaint = ui.Paint()
      ..colorFilter = ui.ColorFilter.mode(
        ui.Color((alpha << 24) | (colorArgb & 0x00FFFFFF)),
        ui.BlendMode.srcIn,
      )
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: ui.TileMode.decal,
      );
    final fullSrc = ui.Rect.fromLTWH(
      0,
      0,
      master.width.toDouble(),
      master.height.toDouble(),
    );
    final grow = 1 + scene.glowSpread * 0.15;
    final gw = size.width * grow;
    final gh = size.height * grow;
    final dst = ui.Rect.fromLTWH(
      (size.width - gw) / 2,
      (size.height - gh) / 2,
      gw,
      gh,
    );
    canvas.save();
    if (scene.glowMotion == kLogoGlowMotionSpin) {
      final centre = ui.Offset(size.width / 2, size.height / 2);
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(tSec / kLogoPartsLoopSec * 2 * math.pi);
      canvas.translate(-centre.dx, -centre.dy);
    }
    canvas.drawImageRect(master, fullSrc, dst, glowPaint);
    canvas.restore();
  }

  /// Paints ONE part alone, its box region filling the whole
  /// canvas — the per-part row preview (the element itself,
  /// turning around the canvas centre by its own settings).
  static void paintPart(
    ui.Canvas canvas,
    ui.Size size,
    LogoPart part,
    ui.Image? master,
    double tSec,
  ) {
    if (master == null) return;
    // The pivot expressed inside the crop: the box fills the
    // canvas, so the pivot lands at its relative position
    // within the box (dead centre unless the user moved it).
    final pivotInCrop = ui.Offset(
      (part.pivotX - part.box.x) / part.box.w,
      (part.pivotY - part.box.y) / part.box.h,
    );
    _paintPartBox(
      canvas,
      size,
      master,
      dstBox: const LogoBox(x: 0, y: 0, w: 1, h: 1),
      srcRect: boxSrcRect(master, part.box),
      angle: partAngleAt(part, tSec),
      style: part.rotationStyle,
      pivotFrac: pivotInCrop,
      scale: partScaleAt(part, tSec),
    );
  }

  /// Draws [texture]'s [srcRect] into the [dstBox] region of
  /// a [size] canvas, rotated by [angle] around the PIVOT
  /// ([pivotFrac], canvas fractions) and scaled by [scale]
  /// (the Pulse swell) around the same pivot — in-plane for
  /// the Flat style, around the vertical axis through the
  /// pivot for the 3D style.
  static void _paintPartBox(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image texture, {
    required LogoBox dstBox,
    required ui.Rect srcRect,
    required double angle,
    required String style,
    required ui.Offset pivotFrac,
    double scale = 1,
  }) {
    final dst = boxRectIn(size, dstBox);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    if (angle == 0 && scale == 1) {
      canvas.drawImageRect(texture, srcRect, dst, paint);
      return;
    }
    if (style == kLogoPartStyle3d) {
      _paintPart3D(
        canvas,
        size,
        texture,
        dstBox,
        srcRect,
        angle,
        pivotFrac,
        scale,
      );
      return;
    }
    final pivot = ui.Offset(
      pivotFrac.dx * size.width,
      pivotFrac.dy * size.height,
    );
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    if (scale != 1) canvas.scale(scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawImageRect(texture, srcRect, dst, paint);
    canvas.restore();
  }

  /// Paints one part turning around the vertical axis through
  /// its PIVOT (the 3D style) — the part's box region on
  /// a perspective-projected plane, drawn as two triangles
  /// through drawVertices with an ImageShader, exactly the
  /// technique the Logo Cube uses, with the same
  /// facing-based shading. Preview and export share this
  /// through [paintParts], so a 3D part renders identically
  /// in both.
  static void _paintPart3D(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image texture,
    LogoBox dstBox,
    ui.Rect srcRect,
    double angle,
    ui.Offset pivotFrac,
    double scale,
  ) {
    final corners = logoPart3DBoxCorners(
      size: size,
      box: dstBox,
      angle: angle,
      pivotX: pivotFrac.dx,
      pivotY: pivotFrac.dy,
      scale: scale,
    );
    // Texture corners matching TL, TR, BR, BL — kept attached
    // to the same plane corners as it turns, so past edge-on
    // the back shows mirrored, like a real spinning coin.
    final uv = <ui.Offset>[
      srcRect.topLeft,
      srcRect.topRight,
      srcRect.bottomRight,
      srcRect.bottomLeft,
    ];
    final shade = (logoPart3DBrightness(angle) * 255).round().clamp(0, 255);
    final color = ui.Color.fromARGB(255, shade, shade, shade);
    final c = corners;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.fromList(<double>[
        c[0].dx, c[0].dy, c[1].dx, c[1].dy, c[2].dx, c[2].dy, //
        c[0].dx, c[0].dy, c[2].dx, c[2].dy, c[3].dx, c[3].dy,
      ]),
      textureCoordinates: Float32List.fromList(<double>[
        uv[0].dx, uv[0].dy, uv[1].dx, uv[1].dy, uv[2].dx, uv[2].dy, //
        uv[0].dx, uv[0].dy, uv[2].dx, uv[2].dy, uv[3].dx, uv[3].dy,
      ]),
      colors: Int32List.fromList(<int>[
        color.toARGB32(), color.toARGB32(), color.toARGB32(), //
        color.toARGB32(), color.toARGB32(), color.toARGB32(),
      ]),
    );
    canvas.drawVertices(
      vertices,
      ui.BlendMode.modulate,
      ui.Paint()
        ..shader = ui.ImageShader(
          texture,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          _identityMatrix,
        )
        ..isAntiAlias = true,
    );
  }

  /// Renders ONE parts frame at [size] px.
  static Future<ui.Image> renderPartsFrame({
    required List<LogoPart> parts,
    required ui.Image? masterTexture,
    required int size,
    required double tSec,
    bool greenScreen = false,
    LogoPartsScene? scene,
    int? autoGlowColorArgb,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final sz = ui.Size(size.toDouble(), size.toDouble());
    if (greenScreen) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, sz.width, sz.height),
        ui.Paint()..color = const ui.Color(0xFF00B140),
      );
    }
    paintParts(
      canvas,
      sz,
      parts,
      masterTexture,
      tSec,
      scene: scene,
      autoGlowColorArgb: autoGlowColorArgb,
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    picture.dispose();
    return img;
  }

  /// Generates the full seamless loop of frame PNGs
  /// (frame_%02d.png, 12 fps, [kLogoPartsLoopSec] seconds)
  /// into [outDir] — the export contract. [greenScreen] fills
  /// the background with solid green (Permanent Logo export).
  /// The master is decoded once from the parts' shared
  /// source; a missing master renders empty frames rather
  /// than failing the export.
  static Future<void> generatePartsFrames({
    required List<LogoPart> parts,
    required Directory outDir,
    int size = 512,
    bool greenScreen = false,
    LogoPartsScene? scene,
  }) async {
    final master = parts.isEmpty
        ? null
        : await loadMasterTexture(parts.first.sourcePath);
    try {
      // The AUTO glow colour is resolved ONCE from the
      // master — every frame of the loop shares it.
      final autoGlow = (scene != null &&
              scene.glowOn &&
              scene.glowColorArgb == null &&
              master != null)
          ? await dominantColorOfImage(master)
          : null;
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final total = (kLogoPartsLoopSec * kLogoLoopFps).round();
      for (var i = 0; i < total; i++) {
        final tSec = i / kLogoLoopFps;
        final img = await renderPartsFrame(
          parts: parts,
          masterTexture: master,
          size: size,
          tSec: tSec,
          greenScreen: greenScreen,
          scene: scene,
          autoGlowColorArgb: autoGlow,
        );
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (png == null) continue;
        await File(
          p.join(
            outDir.path,
            'frame_${i.toString().padLeft(2, '0')}.png',
          ),
        ).writeAsBytes(png.buffer.asUint8List(), flush: true);
      }
    } finally {
      master?.dispose();
    }
  }
}
