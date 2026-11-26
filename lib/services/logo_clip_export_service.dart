/// Logo Clip EXPORT (v1.24.0, G1) — the checked Logo Clip
/// core (lib/logo/logo_clip.dart, Gemini CHECK #4) wired to a
/// real encode, following the integration note and the app's
/// proven frames pattern (v1.20.0's
/// [LogoMakerExportService.generateFrames]):
///
/// * Frames: [LogoClipPainter] rendered through a
///   PictureRecorder at the settings' output size, ONE frame
///   at a time, each PNG written straight to disk and its image
///   disposed — 240 frames never sit in memory together.
/// * Encode: the frames directory feeds ffmpeg's image2
///   demuxer through [FfmpegService.run] (libx264 / yuv420p —
///   both output sizes are even, so yuv420p is safe), then the
///   frames are deleted and only the MP4 stays.
///
/// The painter factories live here too, so the section's live
/// preview and this export build the reveal the exact same
/// way: the backdrop is the maker's [LogoBackdropPainter]
/// directly; the reveal goes through [LogoClipRevealPainter],
/// the wrapper the note prescribes — [LogoRevealPainter] has
/// no spin parameter, so the wrapper applies the post-reveal
/// spin as a centre-based horizontal scale (cos of the angle;
/// a negative cosine mirrors the logo — the maker's fake-3D
/// back face, exactly like its flat spin).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../logo/logo_clip.dart';
import '../logo/logo_reveal_backdrops.dart';
import 'ffmpeg_service.dart';

/// The wrapper reveal painter (integration note §2): paints
/// [LogoRevealPainter] for [image] at [progress], with the
/// post-reveal [spinAngle] applied as a horizontal scale about
/// the canvas centre — the same centre the reveal painter
/// fits the logo into (80% fit), so the spin pivots exactly
/// where the logo sits.
class LogoClipRevealPainter extends CustomPainter {
  const LogoClipRevealPainter({
    required this.image,
    required this.styleId,
    required this.progress,
    required this.spinAngle,
  });

  final ui.Image image;
  final String styleId;
  final double progress;
  final double spinAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final reveal = LogoRevealPainter(
      image: image,
      styleId: styleId,
      progress: progress,
    );
    if (spinAngle == 0.0) {
      reveal.paint(canvas, size);
      return;
    }
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(math.cos(spinAngle), 1.0);
    canvas.translate(-size.width / 2, -size.height / 2);
    reveal.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoClipRevealPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.styleId != styleId ||
        oldDelegate.progress != progress ||
        oldDelegate.spinAngle != spinAngle;
  }
}

/// The backdrop factory the clip preview and the export both
/// use — a top-level function, so its tear-off is ONE stable
/// identity everywhere (the clip painter compares factories
/// with `identical`).
CustomPainter logoClipBackdropPainter(String backdropId, double glow) {
  return LogoBackdropPainter(backdropId: backdropId, glowIntensity: glow);
}

/// Builds the reveal factory for one reveal [styleId]. Create
/// it ONCE per render pass (preview configuration / export
/// loop) and reuse the instance — the clip painter compares
/// factories with `identical`, so a fresh closure per frame
/// would repaint needlessly.
LogoClipRevealPainterBuilder logoClipRevealBuilder(String styleId) {
  return (ui.Image image, double progress, double spinAngle) {
    return LogoClipRevealPainter(
      image: image,
      styleId: styleId,
      progress: progress,
      spinAngle: spinAngle,
    );
  };
}

class LogoClipExportService {
  LogoClipExportService._();

  /// The encode frame rate (the note's contract).
  static const int fps = 30;

  /// Renders the clip's frames into [outDir] as
  /// `frame_%03d.png`, streaming: each frame is rendered,
  /// encoded to PNG, written and disposed before the next one
  /// starts. [onProgress] reports 0..1 across the frame loop.
  /// Returns the written files in frame order.
  static Future<List<File>> generateClipFrames({
    required ui.Image logoImage,
    required LogoClipSettings settings,
    required Directory outDir,
    int framesPerSecond = fps,
    void Function(double progress)? onProgress,
  }) async {
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final size = settings.outputSize;
    final count = logoClipFrameCount(settings, framesPerSecond);
    // ONE backdrop painter and ONE reveal factory for the
    // whole pass (the note's factory-identity rule).
    final backdrop = LogoBackdropPainter(
      backdropId: settings.backdropId,
      glowIntensity: settings.backdropGlow,
    );
    final revealFor = logoClipRevealBuilder(settings.revealStyleId);
    final files = <File>[];
    for (var i = 0; i < count; i++) {
      final timeMs = (i * 1000 / framesPerSecond).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      LogoClipPainter(
        logoImage: logoImage,
        settings: settings,
        timeMs: timeMs,
        backdropPainter: backdrop,
        revealPainterFor: revealFor,
      ).paint(canvas, size);
      final picture = recorder.endRecording();
      final frame = await picture.toImage(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      try {
        final bytes = await frame.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) {
          throw StateError('Logo clip frame $i produced no bytes.');
        }
        final file = File(
          p.join(
            outDir.path,
            'frame_${i.toString().padLeft(3, '0')}.png',
          ),
        );
        await file.writeAsBytes(bytes.buffer.asUint8List());
        files.add(file);
      } finally {
        frame.dispose();
      }
      onProgress?.call((i + 1) / count);
    }
    return files;
  }

  /// The full export: frames (progress 0..0.85) → MP4 encode
  /// (0.85..1) → frames deleted. Returns the MP4 file inside
  /// [workDir]. Throws a [StateError] with the encoder's own
  /// words when the encode fails — the caller shows it as-is;
  /// a clip export never fails silently.
  static Future<File> exportClip({
    required ui.Image logoImage,
    required LogoClipSettings settings,
    required Directory workDir,
    void Function(double progress)? onProgress,
  }) async {
    final framesDir = Directory(p.join(workDir.path, 'frames'));
    await generateClipFrames(
      logoImage: logoImage,
      settings: settings,
      outDir: framesDir,
      onProgress: (f) => onProgress?.call(f * 0.85),
    );
    final outFile = File(p.join(workDir.path, 'logo_clip.mp4'));
    final pattern = p.join(framesDir.path, 'frame_%03d.png');
    FfmpegResult result;
    try {
      result = await FfmpegService.run(
        '-y -framerate $fps -i ${FfmpegService.q(pattern)} '
        '-c:v libx264 -pix_fmt yuv420p -preset veryfast '
        '-movflags +faststart ${FfmpegService.q(outFile.path)}',
        expectedMs: settings.durationSec * 1000,
        onProgress: (f) => onProgress?.call(0.85 + f * 0.15),
      );
    } catch (e) {
      // The encoder could not even start (no FFmpegKit on
      // this device/build) — same contract as a failed
      // encode: a StateError with the reason, frames cleaned.
      try {
        await framesDir.delete(recursive: true);
      } catch (_) {}
      throw StateError(
        'The video encoder could not make the clip: $e',
      );
    }
    // The frames have done their job either way — never leave
    // a few hundred MB of PNGs behind.
    try {
      await framesDir.delete(recursive: true);
    } catch (_) {
      // A locked frame file must not fail the export itself.
    }
    if (!result.ok || !await outFile.exists()) {
      throw StateError(
        result.cancelled
            ? 'The clip export was cancelled.'
            : 'The video encoder could not make the clip: '
                '${result.logs}',
      );
    }
    onProgress?.call(1);
    return outFile;
  }
}
