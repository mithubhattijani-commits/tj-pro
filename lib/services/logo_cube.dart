/// LOGO CUBE ENGINE (Build 12, v1.9.0 — fix-list point #12).
///
/// The user's order of 2026-11-25: the News Studio logo must
/// rotate CONTINUOUSLY through full 360° rounds, and any image
/// the user picks must become a real rotating 3D CUBE logo —
/// the broadcast-cube form, where the image is textured onto
/// the cube's faces (so the "backwards text" problem of a flat
/// full spin does not arise: each face carries the image
/// upright for its own pass across the front).
///
/// This file is the SHARED geometry + painter used by BOTH
/// render paths, so preview and export can never drift:
///
///   * Preview — `LogoCubeView` (lib/news/widgets/rotating_logo.dart)
///     paints with [paintLogoCube] on a Flutter CustomPaint canvas.
///   * Export — `LogoLoopService.generateFrames` renders PNG
///     frames with the same [paintLogoCube] on a dart:ui canvas
///     and FFmpeg loops them (the existing image2 pipeline).
///
/// Rendering technique: the 8 cube corners are rotated (fixed
/// X tilt, then Y by the frame angle) and perspective-projected;
/// each visible face is drawn as two triangles through
/// `Canvas.drawVertices` with an `ImageShader` of the logo
/// texture and per-vertex shading colours (BlendMode.modulate).
/// That is real textured 3D — not a flat image with a wobble,
/// not a shear. Faces are drawn far-to-near (painter's
/// algorithm); a face whose rotated outward normal points away
/// from the camera is never drawn.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Identity matrix for the texture shader (column-major).
final Float64List _identityMatrix = Float64List.fromList(<double>[
  1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1,
]);

/// Fixed downward tilt (radians about the X axis) so the top
/// face stays visible, broadcast-cube style. Applied AFTER the
/// Y rotation, so the tilt axis is always the screen's
/// horizontal axis.
const double kLogoCubeTiltX = 0.42;

/// Camera distance in cube units (the cube's edge is 1 unit).
/// 3.2 gives a mild, professional perspective — faces compress
/// honestly at the turn without fisheye distortion.
const double kLogoCubeFocal = 3.2;

/// One full revolution of the cube, in seconds (preview) — the
/// export loop uses the same period (48 frames at 12 fps = 4 s
/// per revolution; see logo_loop_service.dart).
const double kLogoCubeRevolutionSeconds = 6;

/// Face indices (outward normal direction in cube space).
const int kCubeFaceFront = 0; // +Z
const int kCubeFaceRight = 1; // +X
const int kCubeFaceBack = 2; // -Z
const int kCubeFaceLeft = 3; // -X
const int kCubeFaceTop = 4; // +Y
const int kCubeFaceBottom = 5; // -Y

/// Build 13 (point #19): the per-face settings keys (the Logo
/// panel's face names, in face-index order) — ChannelPreset
/// .logoCubeFacePaths is keyed by these.
const List<String> kLogoCubeFaceKeys = [
  'front',
  'right',
  'back',
  'left',
  'top',
  'bottom',
];

/// The face index for a [kLogoCubeFaceKeys] key, or -1.
int logoCubeFaceIndex(String key) => kLogoCubeFaceKeys.indexOf(key);

/// Build 13 (point #19): the signed rotation angle for a spin
/// direction — clockwise keeps the historic positive sweep,
/// counter-clockwise negates it. Preview and export both route
/// through this so the direction can never drift apart.
double logoCubeAngleFor(double progress, {required bool clockwise}) =>
    logoCubeAngle(progress) * (clockwise ? 1 : -1);

/// The continuous rotation angle (radians) at [progress]
/// (0..1 of one revolution): a plain linear sweep 0 → 2π.
/// Frame N of a loop and frame 0 are the same angle, so the
/// loop point is seamless by construction.
double logoCubeAngle(double progress) =>
    progress.clamp(0.0, 1.0) * 2 * math.pi;

/// One cube face after projection: the four canvas corners (in
/// the same order as [uvCorners]), the matching texture
/// coordinates, the shading brightness (0..1) and the mean
/// camera-space depth (larger = farther from the camera).
class LogoCubeFace {
  const LogoCubeFace({
    required this.face,
    required this.corners,
    required this.uvCorners,
    required this.brightness,
    required this.depth,
  });

  final int face;
  final List<ui.Offset> corners;
  final List<ui.Offset> uvCorners;
  final double brightness;
  final double depth;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// A face's local frame: outward normal + the texture U axis.
/// V always runs along +Y for the lateral faces (texture top =
/// cube top); the top face uses U = +X, V = +Z.
class _FaceDef {
  const _FaceDef(this.face, this.normal, this.uAxis);
  final int face;
  final _Vec3 normal;
  final _Vec3 uAxis;
}

const List<_FaceDef> _faceDefs = [
  _FaceDef(kCubeFaceFront, _Vec3(0, 0, 1), _Vec3(1, 0, 0)),
  _FaceDef(kCubeFaceRight, _Vec3(1, 0, 0), _Vec3(0, 0, -1)),
  _FaceDef(kCubeFaceBack, _Vec3(0, 0, -1), _Vec3(-1, 0, 0)),
  _FaceDef(kCubeFaceLeft, _Vec3(-1, 0, 0), _Vec3(0, 0, 1)),
  _FaceDef(kCubeFaceTop, _Vec3(0, 1, 0), _Vec3(1, 0, 0)),
  _FaceDef(kCubeFaceBottom, _Vec3(0, -1, 0), _Vec3(1, 0, 0)),
];

/// The four 3D corners of [def]'s face, ordered so the matching
/// UVs read the texture upright when this face fronts the
/// camera: top-left, top-right, bottom-right, bottom-left in
/// the face's own (U, V) frame.
List<_Vec3> _faceCorners(_FaceDef def) {
  final n = def.normal;
  final u = def.uAxis;
  // V axis = the cube-space direction of texture-down on this
  // face: lateral faces run V along -Y (texture top is +Y);
  // top/bottom faces run V along +Z / -Z respectively.
  final _Vec3 v;
  if (def.face == kCubeFaceTop) {
    v = const _Vec3(0, 0, 1);
  } else if (def.face == kCubeFaceBottom) {
    v = const _Vec3(0, 0, -1);
  } else {
    v = const _Vec3(0, -1, 0);
  }
  _Vec3 corner(double su, double sv) => _Vec3(
        n.x * 0.5 + u.x * su * 0.5 + v.x * sv * 0.5,
        n.y * 0.5 + u.y * su * 0.5 + v.y * sv * 0.5,
        n.z * 0.5 + u.z * su * 0.5 + v.z * sv * 0.5,
      );
  // (su, sv): U right, V down — corners TL, TR, BR, BL.
  return [
    corner(-1, -1),
    corner(1, -1),
    corner(1, 1),
    corner(-1, 1),
  ];
}

/// Texture coordinates for [def]'s corners (same order as
/// [_faceCorners]) in a [texW]×[texH] texture.
List<ui.Offset> _faceUvs(_FaceDef def, double texW, double texH) {
  if (def.face == kCubeFaceTop || def.face == kCubeFaceBottom) {
    // Top/bottom: U along +X, V along ±Z — computed from the
    // corner positions so the mapping stays consistent.
    return _faceCorners(def)
        .map(
          (c) => ui.Offset(
            (c.x + 0.5) * texW,
            (def.face == kCubeFaceTop ? (c.z + 0.5) : (0.5 - c.z)) *
                texH,
          ),
        )
        .toList();
  }
  final u = def.uAxis;
  return _faceCorners(def)
      .map(
        (c) => ui.Offset(
          ((c.x * u.x + c.y * u.y + c.z * u.z) + 0.5) * texW,
          (0.5 - c.y) * texH,
        ),
      )
      .toList();
}

_Vec3 _rotate(_Vec3 p, double angleY, double tiltX) {
  final cy = math.cos(angleY);
  final sy = math.sin(angleY);
  // Rotate about Y first (the spin), then tilt about X — always
  // around the screen's horizontal axis. Build 13 (point #19):
  // the tilt is the USER's view control now (default 0 =
  // 'Front'); callers that pass nothing get the historic fixed
  // broadcast tilt [kLogoCubeTiltX].
  final x1 = p.x * cy + p.z * sy;
  final z1 = -p.x * sy + p.z * cy;
  final y1 = p.y;
  final cx = math.cos(tiltX);
  final sx = math.sin(tiltX);
  final y2 = y1 * cx - z1 * sx;
  final z2 = y1 * sx + z1 * cx;
  return _Vec3(x1, y2, z2);
}

/// The visible faces of the cube at [angleY], projected into a
/// square canvas of [size] px centred on [center], sorted
/// far-to-near for the painter's algorithm. Texture space is
/// [textureWidth]×[textureHeight] px.
List<LogoCubeFace> logoCubeFaces({
  required double angleY,
  required ui.Offset center,
  required double size,
  required double textureWidth,
  required double textureHeight,
  double tiltX = kLogoCubeTiltX,
}) {
  final faces = <LogoCubeFace>[];
  for (final def in _faceDefs) {
    final normal = _rotate(def.normal, angleY, tiltX);
    // Camera looks down -Z from +Z: a face is visible when its
    // rotated outward normal points TOWARD the camera (+Z).
    if (normal.z <= 0.02) continue;
    final corners3 = _faceCorners(def);
    final projected = <ui.Offset>[];
    var depthSum = 0.0;
    for (final c in corners3) {
      final r = _rotate(c, angleY, tiltX);
      final d = kLogoCubeFocal - r.z;
      final px = r.x * kLogoCubeFocal / d;
      final py = r.y * kLogoCubeFocal / d;
      projected.add(
        ui.Offset(center.dx + px * size, center.dy - py * size),
      );
      depthSum += d;
    }
    // Shading: full brightness facing the camera, dimmer at
    // the glancing angles — the classic cube read.
    final brightness = 0.42 + 0.58 * normal.z;
    faces.add(
      LogoCubeFace(
        face: def.face,
        corners: projected,
        uvCorners: _faceUvs(def, textureWidth, textureHeight),
        brightness: brightness.clamp(0.0, 1.0),
        depth: depthSum / corners3.length,
      ),
    );
  }
  faces.sort((a, b) => b.depth.compareTo(a.depth));
  return faces;
}

/// Paints the rotating cube: [texture] on the cube faces,
/// centred at [center], [size] px edge, at [angleY] radians.
/// Shared verbatim by the preview widget and the export frame
/// renderer.
void paintLogoCube(
  ui.Canvas canvas, {
  required ui.Offset center,
  required double size,
  required double angleY,
  required ui.Image texture,
  double tiltX = kLogoCubeTiltX,
  Map<int, ui.Image>? faceTextures,
  bool pedestal = false,
}) {
  // Build 13 (point #19): the optional pedestal — a dark base
  // plate with a gold rim under the cube, drawn first so the
  // cube sits ON it. Off by default (no pedestal existed
  // before Build 13, so the default look is unchanged).
  if (pedestal) {
    final plateRect = ui.Rect.fromCenter(
      center: ui.Offset(center.dx, center.dy + size * 0.66),
      width: size * 1.25,
      height: size * 0.26,
    );
    canvas.drawOval(
      plateRect,
      ui.Paint()
        ..color = const ui.Color(0xE61A1D24)
        ..isAntiAlias = true,
    );
    canvas.drawOval(
      plateRect,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (size * 0.02).clamp(1.0, 4.0)
        ..color = const ui.Color(0xFFFFC800)
        ..isAntiAlias = true,
    );
  }
  final faces = logoCubeFaces(
    angleY: angleY,
    center: center,
    size: size,
    textureWidth: texture.width.toDouble(),
    textureHeight: texture.height.toDouble(),
    tiltX: tiltX,
  );
  // Build 13 (point #19): per-face textures — a face with its
  // own image uses it (with ITS dimensions as the UV space);
  // every other face uses the main texture, exactly as before.
  final shaders = <ui.Image, ui.ImageShader>{};
  ui.ImageShader shaderFor(ui.Image img) => shaders.putIfAbsent(
        img,
        () => ui.ImageShader(
          img,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          _identityMatrix,
        ),
      );
  for (final face in faces) {
    final faceTexture = faceTextures?[face.face] ?? texture;
    // A face's own texture needs UVs in ITS pixel space; the
    // projected corners/shading stay the main pass's.
    final uv = faceTexture == texture
        ? face.uvCorners
        : _faceUvs(
            _faceDefs[face.face],
            faceTexture.width.toDouble(),
            faceTexture.height.toDouble(),
          );
    final c = face.corners;
    final shade = (face.brightness * 255).round().clamp(0, 255);
    final color = ui.Color.fromARGB(255, shade, shade, shade);
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
        ..shader = shaderFor(faceTexture)
        ..isAntiAlias = true,
    );
    // A hairline edge keeps the cube's faces readable against
    // busy video underneath.
    final edge = ui.Path()
      ..moveTo(c[0].dx, c[0].dy)
      ..lineTo(c[1].dx, c[1].dy)
      ..lineTo(c[2].dx, c[2].dy)
      ..lineTo(c[3].dx, c[3].dy)
      ..close();
    canvas.drawPath(
      edge,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (size * 0.006).clamp(0.6, 3.0)
        ..color = const ui.Color(0x59000000)
        ..isAntiAlias = true,
    );
  }
}
