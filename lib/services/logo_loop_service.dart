/// Rotating-logo loop generation for the reel export.
///
/// Build 12 (v1.9.0, fix-list point #12) — SUPERSEDES the
/// 20 Nov 2026 swing decision. The old design oscillated the
/// logo ±0.7 rad (a yoyo "swing") because a FLAT logo's text
/// reads backwards for half of a full turn. The user's direct
/// order of 2026-11-25 replaces it: the logo rotates
/// CONTINUOUSLY through full 360° rounds, and the form is a
/// real 3D CUBE carrying the image on its faces (broadcast
/// cube logos) — each face reads upright on its own pass.
///
/// Two loop sources exist:
///
///   1. A GENERATED loop (this file): the shared cube engine
///      (`lib/services/logo_cube.dart` — the same geometry +
///      painter the preview uses) renders 48 PNG frames of one
///      full revolution into `frame_%02d.png` files, and FFmpeg
///      loops them with the image2 demuxer (`-stream_loop -1`).
///      Used for a user-picked logo (image OR the default tile)
///      and as the fallback for the default logo.
///   2. The pre-rendered `logo-rotating-alpha.mov` (default
///      logo only, non-parity templates), ping-ponged in-graph
///      by [FfmpegService.logoLoopOverlayCommand] — that asset
///      is a finished video of the channel's own cube-style
///      logo; the parity (Final template) path prefers the
///      generated cube frames for a picked logo and the user's
///      green-screen logo video for the default (unchanged).
///
/// The frame sequence covers exactly one revolution, so the
/// last frame flows into the first with no snap when
/// `-stream_loop` repeats it. Frames are cached per logo file
/// (path + size + mtime) in the work dir — regenerating 48
/// frames costs a render each time. The cache key carries a
/// `cube3d_` prefix so pre-Build-12 swing frames are never
/// reused.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show FontWeight, TextPainter, TextSpan, TextStyle;

import 'logo_cube.dart';

/// Frames in one full revolution (12 fps × 4 s loop).
const int kLogoLoopFrameCount = 48;

/// Frame rate the image2 input is looped at.
const int kLogoLoopFps = 12;

/// Rendered frame size (square, RGBA PNG).
const int kLogoLoopFrameSize = 512;

/// The rotation angle (radians) of frame [index] in a
/// [frames]-frame loop: a continuous linear sweep 0 → 2π over
/// the loop (Build 12 — full rotation, no yoyo). Frame 0 and
/// frame [frames] are the same angle, so the loop point is
/// seamless by construction.
double logoLoopAngle(int index, [int frames = kLogoLoopFrameCount]) {
  return logoCubeAngle((index % frames) / frames);
}

/// Cache key for a logo file: file name + size + mtime, so a replaced
/// logo (same path, new content) regenerates instead of reusing stale
/// frames. The default tile uses `default_<initial>`. The `cube3d_`
/// prefix versions the Build 12 cube frames apart from the old
/// swing frames.
String logoLoopCacheKey({
  File? logoFile,
  String initial = 'N',
  String variant = '',
}) {
  // Build 13 (point #19): [variant] carries the cube settings
  // (faces / speed / direction / tilt / pedestal) so frames
  // rendered for one view are never reused for another. Callers
  // without settings pass nothing and keep the old keys.
  final suffix = variant.isEmpty ? '' : '_$variant';
  if (logoFile == null) {
    return 'cube3d_default_${initial.toUpperCase()}$suffix';
  }
  try {
    final stat = logoFile.statSync();
    final name = logoFile.path.split('/').last.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    return 'cube3d_${name}_${stat.size}_${stat.modified.millisecondsSinceEpoch}$suffix';
  } catch (_) {
    return 'cube3d_logo_${logoFile.path.hashCode.abs()}$suffix';
  }
}

/// Build 13 (point #19): the cache-key variant for a set of
/// cube settings — every input that changes the rendered
/// frames is in it (face files by path+mtime, speed, direction,
/// tilt, pedestal).
String logoCubeVariantKey({
  required Map<String, String> facePaths,
  required double speedSec,
  required bool clockwise,
  required double tiltX,
  required bool pedestal,
}) {
  final buf = StringBuffer()
    ..write('s${speedSec.toStringAsFixed(2)}')
    ..write(clockwise ? '_cw' : '_ccw')
    ..write('_t${tiltX.toStringAsFixed(2)}')
    ..write(pedestal ? '_ped' : '_nped');
  final keys = facePaths.keys.toList()..sort();
  for (final k in keys) {
    final f = File(facePaths[k]!);
    var stamp = 'x';
    try {
      final st = f.statSync();
      stamp = '${st.size}_${st.modified.millisecondsSinceEpoch}';
    } catch (_) {}
    buf.write('_f$k$stamp');
  }
  return buf.toString();
}

class LogoLoopService {
  /// Renders the full rotating CUBE loop for [logoFile] (a
  /// user-picked logo PNG/JPG; null = the channel's default
  /// initial-letter tile) into [outDir] as `frame_00.png` …
  /// `frame_47.png` (see [kLogoLoopFrameCount]). Cache-first:
  /// when all frames already exist in [outDir] they are
  /// returned untouched (0 renders). Returns the frame files in
  /// order. Throws when the logo file cannot be decoded
  /// (callers fall back to skipping the logo pass, never to
  /// failing the export).
  static Future<List<File>> generateFrames({
    File? logoFile,
    required Directory outDir,
    String initial = 'N',
    Map<String, String> facePaths = const {},
    double tiltX = kLogoCubeTiltX,
    double speedSec = 4.0,
    bool clockwise = true,
    bool pedestal = false,
  }) async {
    // Build 13 (point #19): the loop length follows the cube
    // speed setting (frames = speedSec x 12 fps). The DEFAULT
    // (4 s -> 48 frames) reproduces the pre-Build-13 export
    // loop exactly for callers that pass no settings (the
    // Video Editor); News Studio passes the preset's values.
    final frames =
        (speedSec * kLogoLoopFps).round().clamp(12, 240).toInt();
    const size = kLogoLoopFrameSize;
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final existing = <File>[];
    var allExist = true;
    for (var i = 0; i < frames; i++) {
      final f = File('${outDir.path}/frame_${i.toString().padLeft(2, '0')}.png');
      if (await f.exists()) {
        existing.add(f);
      } else {
        allExist = false;
        break;
      }
    }
    if (allExist) return existing;

    ui.Image? texture;
    if (logoFile != null) {
      final bytes = await logoFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      texture = frame.image;
    } else {
      texture = await renderLogoTileTexture(initial: initial, size: 512);
    }
    // Build 13: per-face textures — a face file that cannot be
    // decoded is simply skipped (that face keeps the main
    // texture); a broken face pick never fails the export.
    final faceTextures = <int, ui.Image>{};
    for (final entry in facePaths.entries) {
      final faceIndex = logoCubeFaceIndex(entry.key);
      if (faceIndex < 0) continue;
      try {
        final bytes = await File(entry.value).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        faceTextures[faceIndex] = frame.image;
      } catch (_) {}
    }
    final made = <File>[];
    try {
      for (var i = 0; i < frames; i++) {
        final angle = logoCubeAngleFor(
          i / frames,
          clockwise: clockwise,
        );
        final png = await renderLogoCubeFrame(
          texture: texture,
          angle: angle,
          size: size,
          tiltX: tiltX,
          faceTextures: faceTextures.isEmpty ? null : faceTextures,
          pedestal: pedestal,
        );
        final file = File(
          '${outDir.path}/frame_${i.toString().padLeft(2, '0')}.png',
        );
        await file.writeAsBytes(png);
        made.add(file);
      }
    } finally {
      texture.dispose();
      for (final img in faceTextures.values) {
        img.dispose();
      }
    }
    return made;
  }

  /// The default channel tile (purple rounded rect + initial
  /// letter) rendered into a texture image for the cube — the
  /// same look the preview's initial tile and the template
  /// renderer draw when no logo file exists.
  static Future<ui.Image> renderLogoTileTexture({
    required String initial,
    required int size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final s = size.toDouble();
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, 0, s, s),
        ui.Radius.circular(s * 0.109),
      ),
      ui.Paint()..color = const ui.Color(0xFF7C3AED),
    );
    final letter = initial.trim().isEmpty
        ? 'N'
        : initial.trim()[0].toUpperCase();
    final painter = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: s * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: ui.TextAlign.center,
    )..layout(maxWidth: s);
    painter.paint(canvas, ui.Offset(0, (s - painter.height) / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    return image;
  }

  /// One export frame: the cube at [angle] on a transparent
  /// [size]×[size] canvas, drawn with the SHARED cube painter
  /// (the preview paints the identical geometry).
  static Future<List<int>> renderLogoCubeFrame({
    required ui.Image texture,
    required double angle,
    required int size,
    double tiltX = kLogoCubeTiltX,
    Map<int, ui.Image>? faceTextures,
    bool pedestal = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final s = size.toDouble();
    paintLogoCube(
      canvas,
      center: ui.Offset(s / 2, s / 2),
      // The cube's projected silhouette is ~1.22× its edge at
      // the diagonal angles; an 0.82 factor keeps every angle
      // inside the frame with a small margin.
      size: s * 0.82,
      angleY: angle,
      texture: texture,
      tiltX: tiltX,
      faceTextures: faceTextures,
      pedestal: pedestal,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    if (bytes == null) throw StateError('Frame render produced no bytes.');
    return bytes.buffer.asUint8List();
  }
}
