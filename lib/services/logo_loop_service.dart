/// Rotating-logo loop generation for the reel export (Phase 7).
///
/// Per `~/workspace/tj-pro-news-maker/rotation-decision.md` the export
/// logo 3D-rotates, and a user-replaced logo rotates the same way. Two
/// loop sources exist:
///
///   1. The pre-rendered `logo-rotating-alpha.mov` (default logo only),
///      ping-ponged in-graph by
///      [FfmpegService.logoLoopOverlayCommand] — see
///      `lib/services/asset_download_service.dart` (`getLogoMov`).
///   2. A GENERATED loop (this file): dart:ui renders N frames of the
///      logo with a `Matrix4.rotationY` yoyo sweep — the exact same
///      swing the preview uses (`logoSwingAngle` in
///      `lib/news/widgets/rotating_logo.dart`: ±0.7 rad, ease-in-out)
///      — into `frame_%02d.png` files, and FFmpeg loops them with the
///      image2 demuxer (`-stream_loop -1`). No alpha video encoder is
///      needed anywhere: the frames carry the alpha channel as PNGs.
///
/// The generated loop is used for a user-replaced logo (no
/// pre-rendered loop can exist for an arbitrary file) AND as the
/// fallback for the default logo when the mov has not been downloaded
/// yet. The frame sequence covers one full out-and-back cycle, so the
/// last frame flows into the first with no snap when `-stream_loop`
/// repeats it. Frames are cached per logo file (path + size + mtime)
/// in the work dir — regenerating 48 frames costs a render each time.
///
/// FFmpeg `perspective` was REJECTED for this (decision doc): it is a
/// shear, not a true rotationY, the loop point is not clean, and it
/// burns CPU on every output frame instead of rendering once.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show FontWeight, Matrix4, TextPainter, TextSpan, TextStyle;

/// Frames in one full yoyo cycle (12 fps × 4 s loop).
const int kLogoLoopFrameCount = 48;

/// Frame rate the image2 input is looped at.
const int kLogoLoopFps = 12;

/// Rendered frame size (square, RGBA PNG).
const int kLogoLoopFrameSize = 512;

/// Max swing, mirroring the preview
/// (`kLogoSwingRadians` in rotating_logo.dart).
const double kLogoLoopSwingRadians = 0.7;

/// Ease-in-out, mirroring the preview's `Curves.easeInOut` on the
/// angle tween.
double _easeInOut(double t) {
  final v = t.clamp(0.0, 1.0);
  return v < 0.5 ? 2 * v * v : 1 - math.pow(-2 * v + 2, 2) / 2;
}

/// The rotationY angle (radians) of frame [index] in a [frames]-frame
/// full yoyo cycle. Frame 0 sits at -0.7 rad, the middle frame at
/// +0.7, and the last frame returns to (almost) -0.7 — so the loop
/// point is seamless by construction, exactly like the preview's
/// `repeat(reverse: true)` controller. Text never mirrors: the swing
/// stays well under π/2.
double logoLoopAngle(int index, [int frames = kLogoLoopFrameCount]) {
  final c = (index % frames) / frames; // 0..1 over one full cycle
  final p = c < 0.5 ? c * 2 : 2 - 2 * c; // out 0..1, back 1..0
  return -kLogoLoopSwingRadians + 2 * kLogoLoopSwingRadians * _easeInOut(p);
}

/// Cache key for a logo file: file name + size + mtime, so a replaced
/// logo (same path, new content) regenerates instead of reusing stale
/// frames. The default tile uses `default_<initial>`.
String logoLoopCacheKey({File? logoFile, String initial = 'N'}) {
  if (logoFile == null) return 'default_${initial.toUpperCase()}';
  try {
    final stat = logoFile.statSync();
    final name = logoFile.path.split('/').last.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    return '${name}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
  } catch (_) {
    return 'logo_${logoFile.path.hashCode.abs()}';
  }
}

class LogoLoopService {
  /// Renders the full rotating loop for [logoFile] (a user-picked logo
  /// PNG/JPG; null = the channel's default initial-letter tile) into
  /// [outDir] as `frame_00.png` … `frame_47.png` (see
  /// [kLogoLoopFrameCount]). Cache-first: when all frames already
  /// exist in [outDir] they are returned untouched (0 renders).
  /// Returns the frame files in order. Throws when the logo file
  /// cannot be decoded (callers fall back to skipping the logo pass,
  /// never to failing the export).
  static Future<List<File>> generateFrames({
    File? logoFile,
    required Directory outDir,
    String initial = 'N',
  }) async {
    const frames = kLogoLoopFrameCount;
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

    ui.Image? logo;
    if (logoFile != null) {
      final bytes = await logoFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      logo = frame.image;
    }
    final made = <File>[];
    try {
      for (var i = 0; i < frames; i++) {
        final angle = logoLoopAngle(i, frames);
        final png = await _renderFrame(
          logo: logo,
          initial: initial,
          angle: angle,
          size: size,
        );
        final file = File(
          '${outDir.path}/frame_${i.toString().padLeft(2, '0')}.png',
        );
        await file.writeAsBytes(png);
        made.add(file);
      }
    } finally {
      logo?.dispose();
    }
    return made;
  }

  /// One frame: the logo (or the default tile) drawn under a
  /// rotationY transform with the preview's perspective entry
  /// (0.0015), centred in a transparent [size]×[size] canvas.
  static Future<List<int>> _renderFrame({
    required ui.Image? logo,
    required String initial,
    required double angle,
    required int size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final s = size.toDouble();
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0015)
      ..rotateY(angle);
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.transform(matrix.storage);
    canvas.translate(-s / 2, -s / 2);
    if (logo != null) {
      // Cover-fit the logo into the square, like the preview's
      // BoxFit.cover.
      final lw = logo.width.toDouble();
      final lh = logo.height.toDouble();
      final scale = math.max(s / lw, s / lh);
      final dw = lw * scale;
      final dh = lh * scale;
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, lw, lh),
        ui.Rect.fromLTWH((s - dw) / 2, (s - dh) / 2, dw, dh),
        ui.Paint(),
      );
    } else {
      // Default tile — the same look as the template renderer draws
      // when no logo file exists (purple rounded rect + initial).
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
      painter.paint(
        canvas,
        ui.Offset(0, (s - painter.height) / 2),
      );
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    if (bytes == null) throw StateError('Frame render produced no bytes.');
    return bytes.buffer.asUint8List();
  }
}
