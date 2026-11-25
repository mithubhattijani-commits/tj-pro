/// LOGO VIDEO background removal (Build 12, v1.9.0 —
/// fix-list point #13).
///
/// The Logo tool also accepts a logo VIDEO. This service:
///
///   1. DETECTS the background colour automatically — it
///      samples one frame's edges/corners and takes the
///      median border colour. Green screen or ANY solid
///      colour works; a non-solid background is reported
///      honestly (null) instead of keying garbage.
///   2. KEYS the detected colour out into alpha PNG frames
///      (FFmpeg `chromakey`, the same filter family the
///      bundled green-screen logo uses in the parity graph).
///      The frames drive BOTH the preview flipbook
///      (`KeyedLogoFlipbook`) and the export overlay (the
///      existing image2 frames pipeline), so preview and
///      export show the same keyed result.
///   3. Extracts stills (keyed or plain) for the panel
///      thumbnail and the export's fail-soft fallbacks.
///
/// Detection sampling is a pure function over raw RGBA bytes
/// ([sampleBorderColor]) so it is unit-testable without
/// FFmpeg; the FFmpeg steps fail soft (null / empty list),
/// never throw.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import 'ffmpeg_service.dart';
import 'video_export_service.dart';

/// Result of a successful background detection.
class LogoKeyDetection {
  const LogoKeyDetection({
    required this.argb,
    required this.solidity,
    required this.frameFile,
  });

  /// Detected background colour (ARGB, alpha forced opaque).
  final int argb;

  /// Fraction of border samples within tolerance of the
  /// median colour (0..1). Detection requires ≥ [minSolidity].
  final double solidity;

  /// The frame the colour was sampled from (PNG).
  final File frameFile;

  /// Minimum border solidity for a colour to count as a
  /// solid background.
  static const double minSolidity = 0.85;
}

/// Frame size of the generated keyed frames (square canvas,
/// the logo letterboxed inside — the overlay scales it to the
/// logo block, exactly like the generated cube frames).
const int kLogoKeyFrameSize = 512;

/// Frame rate of the keyed frames (matches the logo loops).
const int kLogoKeyFps = 12;

/// Longest logo-video span converted to frames (8 s × 12 fps
/// = 96 frames max — a logo loop longer than that is a video,
/// not a bug).
const double kLogoKeyMaxSeconds = 8;

class LogoKeyService {
  /// Pure border sampling: given raw RGBA [bytes] of a
  /// [width]×[height] frame, returns the median border colour
  /// and the fraction of border samples within [tolerance]
  /// (per-channel) of it — or null when the frame is too small
  /// to judge. Border samples are taken along all four edges
  /// (2% inset) plus the corners, ~128 points.
  static ({int argb, double solidity})? sampleBorderColor(
    Uint8List bytes,
    int width,
    int height, {
    int tolerance = 28,
  }) {
    if (width < 8 || height < 8) return null;
    if (bytes.length < width * height * 4) return null;
    final samples = <int>[];
    final insetX = (width * 0.02).round().clamp(1, width ~/ 4);
    final insetY = (height * 0.02).round().clamp(1, height ~/ 4);
    const steps = 32;
    void addSample(int x, int y) {
      final i = (y * width + x) * 4;
      samples.add(
        0xFF000000 |
            (bytes[i] << 16) |
            (bytes[i + 1] << 8) |
            bytes[i + 2],
      );
    }

    for (var s = 0; s <= steps; s++) {
      final x = (s / steps * (width - 1)).round();
      final y = (s / steps * (height - 1)).round();
      addSample(x, insetY);
      addSample(x, height - 1 - insetY);
      addSample(insetX, y);
      addSample(width - 1 - insetX, y);
    }
    if (samples.isEmpty) return null;
    int channel(int argb, int shift) => (argb >> shift) & 0xFF;
    int medianOf(int shift) {
      final values = samples.map((c) => channel(c, shift)).toList()
        ..sort();
      return values[values.length ~/ 2];
    }

    final median = 0xFF000000 |
        (medianOf(16) << 16) |
        (medianOf(8) << 8) |
        medianOf(0);
    var within = 0;
    for (final c in samples) {
      final dr = (channel(c, 16) - channel(median, 16)).abs();
      final dg = (channel(c, 8) - channel(median, 8)).abs();
      final db = (channel(c, 0) - channel(median, 0)).abs();
      if (dr <= tolerance && dg <= tolerance && db <= tolerance) {
        within++;
      }
    }
    return (argb: median, solidity: within / samples.length);
  }

  /// FFmpeg hex form of a colour for the chromakey filter.
  static String keyHex(int argb) =>
      '0x${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Display hex ('#RRGGBB') for the panel status line.
  static String displayHex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Extracts one frame of [video] (at ~0.3 s, or the first
  /// frame for very short clips) into [workDir] and samples
  /// its border. Returns a [LogoKeyDetection] when the border
  /// is a solid colour (≥ [LogoKeyDetection.minSolidity]);
  /// null when the background is not solid or any step fails.
  static Future<LogoKeyDetection?> detectBackground({
    required File video,
    required Directory workDir,
  }) async {
    try {
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final frameFile = File(p.join(workDir.path, 'detect_frame.png'));
      final res = await FfmpegService.run(
        '-y -ss 0.3 -i ${FfmpegService.q(video.path)} '
        '-frames:v 1 ${FfmpegService.q(frameFile.path)}',
      );
      if (!res.ok || !await frameFile.exists()) return null;
      final bytes = await frameFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return null;
        final sampled = sampleBorderColor(
          data.buffer.asUint8List(),
          image.width,
          image.height,
        );
        if (sampled == null) return null;
        if (sampled.solidity < LogoKeyDetection.minSolidity) {
          return null;
        }
        return LogoKeyDetection(
          argb: sampled.argb,
          solidity: sampled.solidity,
          frameFile: frameFile,
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// The chromakey filter chain shared by the frames + still
  /// generation: fps + square letterbox + key + RGBA out.
  static String _keyFilter(int keyArgb, {required bool withFps}) {
    final hex = keyHex(keyArgb);
    return '${withFps ? 'fps=$kLogoKeyFps,' : ''}'
        'scale=$kLogoKeyFrameSize:$kLogoKeyFrameSize:'
        'force_original_aspect_ratio=decrease,'
        'pad=$kLogoKeyFrameSize:$kLogoKeyFrameSize:'
        '(ow-iw)/2:(oh-ih)/2:color=black@0,'
        'chromakey=$hex:0.28:0.10,format=rgba';
  }

  /// Keys [video]'s [keyArgb] background out into alpha PNG
  /// frames in [outDir] (`frame_00.png` …). At most
  /// [kLogoKeyMaxSeconds] of the video is converted. Returns
  /// the frame files in order; an empty list on any failure
  /// (callers fall back — the export never dies on the logo).
  static Future<List<File>> generateKeyedFrames({
    required File video,
    required Directory outDir,
    required int keyArgb,
  }) async {
    try {
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
      final probe = await VideoExportService.probeVideoSize(video);
      final duration = probe?.durationSeconds ?? 0;
      final seconds = duration <= 0
          ? kLogoKeyMaxSeconds
          : duration.clamp(0.5, kLogoKeyMaxSeconds).toDouble();
      final frameCount = (seconds * kLogoKeyFps).round().clamp(12, 96);
      final res = await FfmpegService.run(
        '-y -i ${FfmpegService.q(video.path)} '
        '-vf "${_keyFilter(keyArgb, withFps: true)}" '
        '-frames:v $frameCount '
        '${FfmpegService.q(p.join(outDir.path, 'frame_%02d.png'))}',
      );
      if (!res.ok) return const [];
      final files = <File>[];
      for (var i = 0; i < frameCount; i++) {
        final f = File(
          p.join(
            outDir.path,
            'frame_${i.toString().padLeft(2, '0')}.png',
          ),
        );
        if (await f.exists()) files.add(f);
      }
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// One KEYED still of [video] (frame at ~0.3 s, background
  /// removed) — the panel thumbnail + the parity export's
  /// fail-soft logo when frame generation is unavailable.
  static Future<File?> extractKeyedStill({
    required File video,
    required Directory workDir,
    required int keyArgb,
    String name = 'keyed_still.png',
  }) async {
    try {
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final out = File(p.join(workDir.path, name));
      final res = await FfmpegService.run(
        '-y -ss 0.3 -i ${FfmpegService.q(video.path)} '
        '-vf "${_keyFilter(keyArgb, withFps: false)}" '
        '-frames:v 1 ${FfmpegService.q(out.path)}',
      );
      if (res.ok && await out.exists()) return out;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// One PLAIN still of [video] (no keying) — the honest
  /// fallback thumbnail/fallback logo when no solid
  /// background could be detected.
  static Future<File?> extractStill({
    required File video,
    required Directory workDir,
    String name = 'still.png',
  }) async {
    try {
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final out = File(p.join(workDir.path, name));
      final res = await FfmpegService.run(
        '-y -ss 0.3 -i ${FfmpegService.q(video.path)} '
        '-frames:v 1 ${FfmpegService.q(out.path)}',
      );
      if (res.ok && await out.exists()) return out;
      return null;
    } catch (_) {
      return null;
    }
  }
}
