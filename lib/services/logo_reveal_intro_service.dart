/// Logo Maker REVEAL INTRO for the news export (v1.25.0, G1).
///
/// v1.21.0 shipped the maker's reveal styles + backdrop
/// scenes as a preview presentation only, and said so
/// honestly: the news export had no intro segment for them.
/// This service closes that gap the same way the export
/// already assembles its other intro/outro segments:
///
/// * When the channel's maker settings exist (the v1.20.0
///   export gate) AND name a reveal style, the reveal is
///   rendered ONCE, full-frame at the export's own dims and
///   fps: the chosen backdrop fills the frame and the styled
///   logo (depth/material render, lighting pass included when
///   set) reveals over it with the v1.21.0 painters — the
///   same two painters the maker's Reveal preview composes,
///   so the intro frame IS the preview frame at that
///   progress.
/// * The frames encode to a segment with a SILENT stereo
///   track, in the exact codec/dims/fps discipline of
///   `FfmpegService.stillSegmentCommand`, so the existing
///   `_assembleIntroOutro` concat joins it directly. The
///   segment goes FIRST: the main video — with its own audio
///   completely untouched — starts right after the sting.
///   Nothing of the news audio is cut; it simply begins
///   after the intro, exactly like the channel intro the
///   export already supports.
/// * Every failure returns null: the export then proceeds
///   WITHOUT the intro and notes the substitution. The intro
///   can never fail an export.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../logo/logo_lighting_pass.dart';
import '../logo/logo_maker_section.dart';
import '../logo/logo_reveal_backdrops.dart';
import '../news/channel_preset.dart';
import 'ffmpeg_service.dart';
import 'logo_maker_export_service.dart';

class LogoRevealIntroService {
  /// The gate: maker settings resolved for export AND a
  /// reveal style actually chosen ('' is the maker's None)
  /// AND the style still exists. Anything else — no maker
  /// payload, default payload, no style — means no intro and
  /// the export runs its historic assembly untouched.
  static bool revealIntroApplies(LogoMakerSettings? settings) {
    if (settings == null) return false;
    return revealStyleFor(settings) != null;
  }

  /// The style the settings name, or null when none is
  /// chosen / the id is unknown.
  static LogoRevealStyle? revealStyleFor(LogoMakerSettings settings) {
    if (settings.revealStyleId.isEmpty) return null;
    for (final style in kLogoRevealStyles) {
      if (style.id == settings.revealStyleId) return style;
    }
    return null;
  }

  /// Frames in the intro at [fps]: the style's own duration,
  /// at least 2 (the first frame is progress 0, the last is
  /// the settled logo at progress 1).
  static int frameCountFor(LogoRevealStyle style, int fps) {
    final frames = (style.durationMs / 1000.0 * fps).round();
    return frames < 2 ? 2 : frames;
  }

  /// The segment encode command (pure — golden-tested). The
  /// frames are already at the export dims, so the chain only
  /// pins fps + pixel format; the audio is a silent stereo
  /// track of the segment's length, and the codec arguments
  /// mirror `stillSegmentCommand` so the concat demuxer joins
  /// the segment with the main video.
  static String segmentCommand({
    required String framesPattern,
    required int fps,
    required double durationSec,
    required String output,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
  }) {
    final dur = durationSec.clamp(0.1, 3600.0);
    final videoArgs = videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${videoBitrateKbps}k '
            '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
            '-bufsize ${videoBitrateKbps * 2}k';
    final audioArgs = audioBitrateKbps == null
        ? '-c:a aac -ar 48000 -ac 2'
        : '-c:a aac -b:a ${audioBitrateKbps}k -ar 48000 -ac 2';
    return '-y -framerate $fps -i ${FfmpegService.q(framesPattern)} '
        '-f lavfi -t $dur -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "fps=$fps,format=yuv420p" '
        '-map 0:v -map 1:a -shortest '
        '$videoArgs $audioArgs ${FfmpegService.q(output)}';
  }

  /// One intro frame at [progress]: the backdrop fills the
  /// frame, the reveal painter animates [styledLogo] over it
  /// — the maker's Reveal preview composition, at export
  /// size. [backdrop] is ONE painter instance for the whole
  /// pass (the clip export's factory discipline).
  static Future<ui.Image> renderIntroFrame({
    required ui.Image styledLogo,
    required LogoMakerSettings settings,
    required LogoBackdropPainter backdrop,
    required double progress,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width.toDouble(), height.toDouble());
    backdrop.paint(canvas, size);
    LogoRevealPainter(
      image: styledLogo,
      styleId: settings.revealStyleId,
      progress: progress,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final frame = await picture.toImage(width, height);
    picture.dispose();
    return frame;
  }

  /// Builds the intro segment MP4 inside [dir], or null on
  /// ANY failure (the caller notes it and exports without
  /// the intro). Frames are streamed to disk one at a time
  /// and deleted after the encode either way. [runFfmpeg]
  /// is the encode seam (the reel export's own injection
  /// pattern): production passes nothing and gets
  /// [FfmpegService.run]; tests pass a stand-in.
  static Future<File?> buildSegment({
    required ChannelPreset preset,
    required LogoMakerSettings settings,
    required Directory dir,
    required int stamp,
    required int width,
    required int height,
    required int fps,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    Future<FfmpegResult> Function(
      String command, {
      int? expectedMs,
      void Function(double)? onProgress,
    })? runFfmpeg,
  }) async {
    final style = revealStyleFor(settings);
    if (style == null) return null;
    ui.Image? base;
    ui.Image? styled;
    ui.Image? lit;
    final framesDir = Directory(p.join(dir.path, 'reveal_intro_$stamp'));
    try {
      base = await LogoMakerExportService.resolveBaseImage(preset);
      // The styled logo ONCE (the clip export's pattern): the
      // depth static at 1024², then the lighting pass when
      // the maker's lighting is non-neutral — the reveal
      // animates that one image, exactly like the preview.
      styled = await renderLogoDepthStatic(
        image: base,
        settings: settings,
        backFacing: false,
        size: const ui.Size(1024, 1024),
      );
      var logoImage = styled;
      if (!settings.lightingCamera.isNeutral) {
        lit = await renderLogoLightingPass(
          image: styled,
          settings: settings.lightingCamera,
        );
        logoImage = lit;
      }
      if (!await framesDir.exists()) {
        await framesDir.create(recursive: true);
      }
      final backdrop = LogoBackdropPainter(
        backdropId: settings.backdropId,
        glowIntensity: settings.backdropGlow,
      );
      final count = frameCountFor(style, fps);
      for (var i = 0; i < count; i++) {
        final frame = await renderIntroFrame(
          styledLogo: logoImage,
          settings: settings,
          backdrop: backdrop,
          progress: count == 1 ? 1.0 : i / (count - 1),
          width: width,
          height: height,
        );
        try {
          final bytes =
              await frame.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) {
            throw StateError('Reveal intro frame produced no bytes.');
          }
          await File(
            p.join(
              framesDir.path,
              'frame_${i.toString().padLeft(3, '0')}.png',
            ),
          ).writeAsBytes(bytes.buffer.asUint8List());
        } finally {
          frame.dispose();
        }
      }
      final outFile = File(p.join(dir.path, 'reel_reveal_intro_$stamp.mp4'));
      final result = await (runFfmpeg ?? FfmpegService.run)(
        segmentCommand(
          framesPattern: p.join(framesDir.path, 'frame_%03d.png'),
          fps: fps,
          durationSec: style.durationMs / 1000.0,
          output: outFile.path,
          videoBitrateKbps: videoBitrateKbps,
          audioBitrateKbps: audioBitrateKbps,
        ),
        expectedMs: style.durationMs,
      );
      if (!result.ok || !await outFile.exists()) return null;
      return outFile;
    } catch (_) {
      return null;
    } finally {
      base?.dispose();
      styled?.dispose();
      lit?.dispose();
      try {
        await framesDir.delete(recursive: true);
      } catch (_) {
        // A locked frame file must not fail the export.
      }
    }
  }
}
