/// MOTION GRAPHICS STUDIO — frame renderer + alpha probe
/// (Build M1, v1.11.0).
///
/// [renderMotionFramePng] records the shared painter
/// (`motion_painter.dart`) into PNG frames — the export path and
/// the test suite's parity proofs both go through here, never
/// through a second drawing implementation (Logo Cube rule).
///
/// [MotionAlphaProbe] answers, ONCE per install, which
/// transparent export formats this phone's FFmpeg build can
/// actually encode (plan §2): it renders 1 second of tiny frames
/// and runs real test encodes for WebM alpha (VP9 yuva420p) and
/// MOV ProRes 4444. The results are cached in SharedPreferences;
/// the export UI (M6) may only offer formats whose probe passed
/// — the master prompt's rule: never show an unsupported format
/// as a functional option. Every failure is fail-soft: an
/// unprobed or failed format simply reads as "not supported".
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Size;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ffmpeg_service.dart';
import 'motion_evaluator.dart';
import 'motion_painter.dart';
import 'motion_scene.dart';

/// Renders ONE frame of [scene] at scene-time [t] to PNG bytes
/// at [width]x[height] (the scene letterboxes inside, exactly as
/// the preview does).
Future<Uint8List> renderMotionFramePng(
  MotionScene scene,
  double t, {
  int width = 1280,
  int height = 720,
  Map<String, ui.Image> images = const {},
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintMotionScene(
    canvas,
    scene: scene,
    state: sceneStateAt(scene, t),
    size: Size(width.toDouble(), height.toDouble()),
    images: images,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// Renders the whole scene at [fps] into PNG frames (t = 0,
/// 1/fps, …, < duration). Frame count is capped so a long scene
/// can never explode memory in a test or a probe.
Future<List<Uint8List>> renderMotionFrames(
  MotionScene scene, {
  int fps = 12,
  int width = 1280,
  int height = 720,
  int maxFrames = 240,
  Map<String, ui.Image> images = const {},
}) async {
  final count =
      (scene.durationSec * fps).ceil().clamp(1, maxFrames);
  final frames = <Uint8List>[];
  for (var i = 0; i < count; i++) {
    frames.add(await renderMotionFramePng(
      scene,
      i / fps,
      width: width,
      height: height,
      images: images,
    ));
  }
  return frames;
}

/// On-device capability probe for transparent export formats.
class MotionAlphaProbe {
  MotionAlphaProbe._();

  static const String _webmKey = 'tjpro_motion_alpha_webm_v1';
  static const String _movKey = 'tjpro_motion_alpha_mov_v1';

  /// Probe outcomes; null = never probed on this install.
  static bool? webmAlpha;
  static bool? movAlpha;

  /// Loads the cached outcomes (fast, no encodes). Safe to call
  /// at startup; any error leaves both null (="not supported"
  /// until a probe proves otherwise).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      webmAlpha = prefs.getBool(_webmKey);
      movAlpha = prefs.getBool(_movKey);
    } catch (_) {
      // Fail-soft: formats stay unproven, hence unoffered.
    }
  }

  /// Runs the real 1-second test encodes (idempotent; later
  /// calls return the cached verdicts). Uses a plain gradient
  /// scene — the probe tests the ENCODERS, not a template.
  static Future<({bool webm, bool mov})> probe() async {
    if (webmAlpha != null && movAlpha != null) {
      return (webm: webmAlpha!, mov: movAlpha!);
    }
    var webm = false;
    var mov = false;
    Directory? work;
    try {
      final tmp = await getTemporaryDirectory();
      work = Directory(
        '${tmp.path}/motion_alpha_probe',
      );
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);
      const scene = MotionScene(
        width: 320,
        height: 180,
        durationSec: 1,
        bgColor: 0x00000000,
        layers: [
          MotionLayer(
            id: 'probe-box',
            type: MotionLayerType.shape,
            x: 160,
            y: 90,
            width: 160,
            height: 90,
            shape: 'rounded',
            cornerRadius: 18,
            fill: 0xFF2979FF,
            entrance: 'slideUp',
            entranceSec: 0.8,
          ),
        ],
      );
      final frames = await renderMotionFrames(
        scene,
        fps: 12,
        width: 320,
        height: 180,
      );
      for (var i = 0; i < frames.length; i++) {
        final name = 'f${i.toString().padLeft(3, '0')}.png';
        await File('${work.path}/$name').writeAsBytes(frames[i]);
      }
      final pattern = FfmpegService.q('${work.path}/f%03d.png');
      final webmFile = File('${work.path}/probe.webm');
      final rWebm = await FfmpegService.run(
        '-framerate 12 -i $pattern -c:v libvpx-vp9 '
        '-pix_fmt yuva420p -b:v 200k -an '
        '${FfmpegService.q(webmFile.path)}',
      );
      webm = rWebm.ok &&
          await webmFile.exists() &&
          (await webmFile.length()) > 0;
      final movFile = File('${work.path}/probe.mov');
      final rMov = await FfmpegService.run(
        '-framerate 12 -i $pattern -c:v prores_ks -profile:v 4444 '
        '-pix_fmt yuva444p10le -an '
        '${FfmpegService.q(movFile.path)}',
      );
      mov = rMov.ok &&
          await movFile.exists() &&
          (await movFile.length()) > 0;
    } catch (_) {
      // Fail-soft: whatever failed stays unsupported.
    } finally {
      try {
        if (work != null && await work.exists()) {
          await work.delete(recursive: true);
        }
      } catch (_) {}
    }
    webmAlpha = webm;
    movAlpha = mov;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_webmKey, webm);
      await prefs.setBool(_movKey, mov);
    } catch (_) {}
    return (webm: webm, mov: mov);
  }
}
