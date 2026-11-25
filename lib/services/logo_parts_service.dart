/// Build 13 (point 6) — LOGO PARTS SERVICE: the device-side
/// half of the Logo Parts Engine (the pure split lives in
/// lib/news/logo_parts.dart).
///
/// - [splitLogoFile] decodes a logo file, runs the automatic
///   split and writes each part as an alpha PNG.
/// - [mergePartFiles] composites two part PNGs into one (the
///   user's split adjustment).
/// - [generatePartsFrames] renders the export loop frames —
///   every part rotating independently around its own centre —
///   through the same 12 fps frame-sequence contract the cube
///   loop uses, so preview (LogoPartsView) and export agree.
/// - [renderGreenScreenFrames] renders the same animation on a
///   solid green background for the Permanent Logo export.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../news/logo_parts.dart';
import 'logo_loop_service.dart' show kLogoLoopFps;

class LogoPartsService {
  LogoPartsService._();

  /// Decodes [logoFile], splits it automatically and writes the
  /// part PNGs under the app's logo-parts folder. Returns the
  /// working parts list (empty when the split found nothing —
  /// the caller says so honestly).
  static Future<List<LogoPart>> splitLogoFile(
    File logoFile, {
    int maxParts = 6,
  }) async {
    final bytes = await logoFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return const [];
    final detected = splitLogoRgba(
      rgba: bd.buffer.asUint8List(),
      width: image.width,
      height: image.height,
      maxParts: maxParts,
    );
    image.dispose();
    if (detected.isEmpty) return const [];
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(
        docs.path,
        'news_logos',
        'parts_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    final parts = <LogoPart>[];
    for (var i = 0; i < detected.length; i++) {
      final d = detected[i];
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        d.rgba,
        d.width,
        d.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final partImage = await done.future;
      final png = await partImage.toByteData(format: ui.ImageByteFormat.png);
      partImage.dispose();
      if (png == null) continue;
      final file = File(p.join(dir.path, 'part_$i.png'));
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      parts.add(
        LogoPart(
          id: 'part$i',
          name: 'Part ${i + 1}',
          imagePath: file.path,
          centreX: d.centreX,
          centreY: d.centreY,
        ),
      );
    }
    return parts;
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

  /// Composites two part PNGs into one PNG at [outPath] (the
  /// merge adjustment). Both parts are full-frame images, so
  /// the merge is a plain stack. Returns false on any failure.
  static Future<bool> mergePartFiles(
    File a,
    File b,
    File outPath,
  ) async {
    final ia = await _decodeFile(a);
    final ib = await _decodeFile(b);
    if (ia == null || ib == null) {
      ia?.dispose();
      ib?.dispose();
      return false;
    }
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(ia, ui.Offset.zero, ui.Paint());
      canvas.drawImage(ib, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final img = await picture.toImage(ia.width, ia.height);
      picture.dispose();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (png == null) return false;
      await outPath.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return true;
    } finally {
      ia.dispose();
      ib.dispose();
    }
  }

  /// Loads every part's texture (fail-soft: a part whose file
  /// is gone is skipped, never a crash).
  static Future<Map<String, ui.Image>> loadPartTextures(
    List<LogoPart> parts,
  ) async {
    final out = <String, ui.Image>{};
    for (final part in parts) {
      final img = await _decodeFile(File(part.imagePath));
      if (img != null) out[part.id] = img;
    }
    return out;
  }

  /// The rotation angle (radians) of [part] at loop time [tSec]
  /// — shared by the preview painter and the frame renderer so
  /// both show the same motion.
  static double partAngleAt(LogoPart part, double tSec) {
    if (!part.rotate) return 0;
    final turns = tSec / part.speedSec;
    final angle = turns * 2 * 3.141592653589793;
    return part.direction == 'ccw' ? -angle : angle;
  }

  /// Paints all parts at loop time [tSec] into [canvas] inside
  /// the [size] square (parts are full-frame images; each
  /// rotating part turns around its own centroid).
  static void paintParts(
    ui.Canvas canvas,
    ui.Size size,
    List<LogoPart> parts,
    Map<String, ui.Image> textures,
    double tSec,
  ) {
    for (final part in parts) {
      final tex = textures[part.id];
      if (tex == null) continue;
      final angle = partAngleAt(part, tSec);
      if (angle == 0) {
        canvas.drawImageRect(
          tex,
          ui.Rect.fromLTWH(
            0,
            0,
            tex.width.toDouble(),
            tex.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, size.width, size.height),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        continue;
      }
      canvas.save();
      final cx = part.centreX * size.width;
      final cy = part.centreY * size.height;
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      canvas.translate(-cx, -cy);
      canvas.drawImageRect(
        tex,
        ui.Rect.fromLTWH(
          0,
          0,
          tex.width.toDouble(),
          tex.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, size.width, size.height),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
    }
  }

  /// Renders ONE parts frame at [size] px.
  static Future<ui.Image> renderPartsFrame({
    required List<LogoPart> parts,
    required Map<String, ui.Image> textures,
    required int size,
    required double tSec,
    bool greenScreen = false,
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
    paintParts(canvas, sz, parts, textures, tSec);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    picture.dispose();
    return img;
  }

  /// Generates the full seamless loop of frame PNGs
  /// (frame_%02d.png, 12 fps, [kLogoPartsLoopSec] seconds) into
  /// [outDir] — the export contract. [greenScreen] fills the
  /// background with solid green (Permanent Logo export).
  static Future<void> generatePartsFrames({
    required List<LogoPart> parts,
    required Directory outDir,
    int size = 512,
    bool greenScreen = false,
  }) async {
    final textures = await loadPartTextures(parts);
    try {
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final total = (kLogoPartsLoopSec * kLogoLoopFps).round();
      for (var i = 0; i < total; i++) {
        final tSec = i / kLogoLoopFps;
        final img = await renderPartsFrame(
          parts: parts,
          textures: textures,
          size: size,
          tSec: tSec,
          greenScreen: greenScreen,
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
      for (final img in textures.values) {
        img.dispose();
      }
    }
  }
}
