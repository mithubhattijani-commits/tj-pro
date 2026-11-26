/// Reporter (numainda) block (v1.5.1, fix #50) — the reporter's
/// photo with a name plate under it, placed on the side OPPOSITE
/// the logo in the Final template. Three surfaces share this
/// composition:
///
///  * [ReporterOverlay] — the widget the Final previews draw
///    (photo cover-fitted into its rounded rect, plate straddling
///    the photo's bottom edge).
///  * [renderReporterOverlayPng] — the dart:ui twin the reel
///    export composites over the finished template pass (a
///    full-frame transparent PNG drawn at the SAME
///    [ParityGeometry] reporter rects).
///  * The BG helpers ([reporterRemoveBackground] /
///    [reporterReplaceBackground]) — BiRefNet matting via
///    [OnnxImageService] (the Photo Editor's HQ Cutout path) plus
///    `image`-package compositing for the replacement.
///
/// Rects come from [ParityGeometry.reporterPhotoRect] /
/// [ParityGeometry.reporterPlateRect] — one source of truth for
/// preview, export and hit-testing.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../live/parity_template.dart';
import '../../services/model_pack_service.dart';
import '../../services/onnx_image_service.dart';
import '../../services/photo_pipeline.dart' show compositeMatteAlphaBytes;


/// Gold of the template furniture (#F5C542) — the photo border
/// and the plate's edge.
const int kReporterGold = 0xFFF5C542;

/// The Reporter block widget. [photoRect] / [plateRect] are
/// relative to this widget's own top-left (the block union's
/// origin); the widget fills the union.
class ReporterOverlay extends StatelessWidget {
  const ReporterOverlay({
    super.key,
    required this.photoRect,
    required this.plateRect,
    required this.photoPath,
    required this.name,
    this.fontFamily,
  });

  final Rect photoRect;
  final Rect plateRect;
  final String photoPath;
  final String name;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fromRect(
          rect: photoRect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(kReporterGold),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.file(
                  File(photoPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF20202C)),
                ),
              ),
            ),
          ),
        ),
        if (name.trim().isNotEmpty)
          Positioned.fromRect(
            rect: plateRect,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF20A0A14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(kReporterGold),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  name.trim(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: plateRect.height * 0.52,
                    fontWeight: FontWeight.bold,
                    fontFamily: fontFamily,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The export twin of [ReporterOverlay]: draws the reporter
/// composition onto a full-frame transparent PNG at the
/// [ParityGeometry] reporter rects (overrides included, via [g]).
/// Returns null when the photo cannot be decoded — the caller
/// notes the skip and exports without the block (never a failed
/// export over a decorative element).
Future<File?> renderReporterOverlayPng({
  required Directory dir,
  required ParityGeometry g,
  required String photoPath,
  required String name,
  String? fontFamily,
}) async {
  try {
    final bytes = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final photo = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final photoRect = g.reporterPhotoRect;
    final plateRect = g.reporterPlateRect;
    final radius = ui.Radius.circular(8 * g.s);

    // Photo: cover-fit (centre crop) into its rounded rect, gold
    // border over the edge.
    final srcAspect = photo.width / photo.height;
    final dstAspect = photoRect.width / photoRect.height;
    final ui.Rect srcRect;
    if (srcAspect > dstAspect) {
      final sw = photo.height * dstAspect;
      srcRect = ui.Rect.fromLTWH(
        (photo.width - sw) / 2,
        0,
        sw,
        photo.height.toDouble(),
      );
    } else {
      final sh = photo.width / dstAspect;
      srcRect = ui.Rect.fromLTWH(
        0,
        (photo.height - sh) / 2,
        photo.width.toDouble(),
        sh,
      );
    }
    canvas.save();
    canvas.clipRRect(ui.RRect.fromRectAndRadius(photoRect, radius));
    canvas.drawImageRect(photo, srcRect, photoRect, ui.Paint());
    canvas.restore();
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(photoRect, radius),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5 * g.s
        ..color = const ui.Color(kReporterGold),
    );
    photo.dispose();

    // Name plate: dark pill with a gold edge, the name centred
    // and shrunk until it fits (never truncated).
    final label = name.trim();
    if (label.isNotEmpty) {
      final plateRRect = ui.RRect.fromRectAndRadius(
        plateRect,
        ui.Radius.circular(6 * g.s),
      );
      canvas.drawRRect(
        plateRRect,
        ui.Paint()..color = const ui.Color(0xF20A0A14),
      );
      canvas.drawRRect(
        plateRRect,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1 * g.s
          ..color = const ui.Color(kReporterGold),
      );
      final maxW = plateRect.width - 12 * g.s;
      var size = plateRect.height * 0.52;
      ui.Paragraph para;
      while (true) {
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: ui.TextAlign.center,
            textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(label)
                ? ui.TextDirection.rtl
                : ui.TextDirection.ltr,
            maxLines: 1,
          ),
        );
        builder.pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFFFFFFFF),
            fontSize: size,
            fontWeight: ui.FontWeight.bold,
            fontFamily: fontFamily,
          ),
        );
        builder.addText(label);
        para = builder.build();
        para.layout(ui.ParagraphConstraints(width: maxW));
        if (para.maxIntrinsicWidth <= maxW || size <= 8 * g.s) break;
        size -= 2 * g.s;
      }
      canvas.drawParagraph(
        para,
        ui.Offset(
          plateRect.left + (plateRect.width - para.maxIntrinsicWidth) / 2,
          plateRect.top + (plateRect.height - para.height) / 2,
        ),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      g.width.round(),
      g.height.round(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    if (png == null) return null;
    final file = File(p.join(dir.path, 'reporter_overlay.png'));
    await file.writeAsBytes(png.buffer.asUint8List());
    return file;
  } catch (_) {
    return null;
  }
}

/// Directory (app documents) holding the reporter's processed
/// photos (picked copies, cutouts, composites).
Future<Directory> reporterDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'news_reporter'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Copies a picked photo into [reporterDir] (picker cache paths
/// can be cleaned by the OS; the project must own its file).
/// Returns the copy's path, or null on failure.
Future<String?> copyReporterPhoto(String sourcePath) async {
  try {
    final dir = await reporterDir();
    final ext = p.extension(sourcePath).toLowerCase();
    final dest = p.join(
      dir.path,
      'reporter_${DateTime.now().millisecondsSinceEpoch}'
      '${ext.isEmpty ? '.jpg' : ext}',
    );
    await File(sourcePath).copy(dest);
    return dest;
  } catch (_) {
    return null;
  }
}

/// Runs the BiRefNet matte on the photo at [photoPath] and
/// returns the matted image (photo size), ensuring the
/// 'birefnet_fp16' pack first (download with progress via
/// [onProgress]). Throws a [ReporterBgException] carrying the
/// TRUE reason (the pack service's typed failure text — a hosting
/// problem is never reported as the user's internet).
class ReporterBgException implements Exception {
  ReporterBgException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// v1.17.0 (G1, Point #37a): the matte + composite now runs in
/// ONE background isolate. The old path decoded the photo, ran
/// the synchronous ONNX inference, composited and PNG-encoded
/// the full-res result ALL on the UI isolate — the app froze
/// past Android's ANR threshold and the system killed it. Only
/// the pack download (async I/O with progress) and the model
/// file lookup stay on the calling isolate.

/// Pure composite: the photo's RGB with the matted image's
/// alpha — byte-for-byte the semantics photo_pipeline's
/// applyAlphaMatte has always applied (alpha channel wins; if
/// a matte ever arrives with alpha pinned at 255 everywhere,
/// its red channel is the matte). Synchronous + top-level so
/// the isolate job and the host tests run the same code.
img.Image reporterCutoutFromMatte(img.Image photo, img.Image matted) {
  final m = matted.width == photo.width && matted.height == photo.height
      ? matted
      : img.copyResize(
          matted,
          width: photo.width,
          height: photo.height,
          interpolation: img.Interpolation.linear,
        );
  final rgba = photo.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final mBytes = m.convert(numChannels: 4).getBytes(
        order: img.ChannelOrder.rgba,
      );
  final out = compositeMatteAlphaBytes(bytes, mBytes);
  return img.Image.fromBytes(
    width: photo.width,
    height: photo.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Pure replace composite: the cutout over a solid [colorArgb]
/// canvas OR over [bg] cover-fitted into the photo's frame —
/// the exact geometry the old on-thread path used.
img.Image reporterReplaceComposite(
  img.Image cutout, {
  int? colorArgb,
  img.Image? bg,
}) {
  final img.Image canvas;
  if (bg != null) {
    final scale = (cutout.width / bg.width) > (cutout.height / bg.height)
        ? cutout.width / bg.width
        : cutout.height / bg.height;
    final resized = img.copyResize(
      bg,
      width: (bg.width * scale).ceil(),
      height: (bg.height * scale).ceil(),
      interpolation: img.Interpolation.linear,
    );
    canvas = img.copyCrop(
      resized,
      x: ((resized.width - cutout.width) / 2).floor(),
      y: ((resized.height - cutout.height) / 2).floor(),
      width: cutout.width,
      height: cutout.height,
    );
  } else {
    canvas = img.Image(width: cutout.width, height: cutout.height);
    img.fill(
      canvas,
      color: img.ColorRgba8(
        (colorArgb! >> 16) & 0xFF,
        (colorArgb >> 8) & 0xFF,
        colorArgb & 0xFF,
        0xFF,
      ),
    );
  }
  return img.compositeImage(canvas, cutout);
}

/// The isolate job: [photoBytes, modelPath, mode, colorArgb,
/// bgBytesOrNull] → PNG bytes ('remove') or JPG bytes
/// ('replace'), null on any failure. Pure Dart + FFI only.
Uint8List? reporterBgIsolateJob(List<dynamic> args) {
  try {
    final photoBytes = args[0] as Uint8List;
    final model = File(args[1] as String);
    final mode = args[2] as String;
    final colorArgb = args[3] as int;
    final bgBytes = args.length > 4 ? args[4] as Uint8List? : null;
    final photo = img.decodeImage(photoBytes);
    if (photo == null) return null;
    final matted = OnnxImageService.alphaMatteWithModelSync(
      model,
      isBiref: true,
      input: photo,
    );
    if (matted == null) return null;
    final cutout = reporterCutoutFromMatte(photo, matted);
    if (mode == 'remove') {
      return img.encodePng(cutout);
    }
    img.Image? bg;
    if (bgBytes != null) {
      bg = img.decodeImage(bgBytes);
      if (bg == null) return null;
    }
    final out = reporterReplaceComposite(
      cutout,
      colorArgb: colorArgb < 0 ? null : colorArgb,
      bg: bg,
    );
    return img.encodeJpg(out, quality: 92);
  } catch (_) {
    return null;
  }
}

/// Shared driver for the two public BG ops: ensure the pack
/// (progress flows to the caller — the first-use download is
/// VISIBLE now, never a silent stall), resolve the model file,
/// run the isolate job with a hard timeout, write the result.
/// Every failure is a [ReporterBgException] with the TRUE
/// reason; nothing here can block the UI thread.
Future<String> _reporterBgRun(
  String photoPath, {
  required String mode,
  int? colorArgb,
  String? bgImagePath,
  void Function(double progress)? onProgress,
}) async {
  final ready = await ModelPackService.instance.ensurePack(
    'birefnet_fp16',
    onProgress: onProgress,
  );
  if (!ready) {
    throw ReporterBgException(
      ModelPackService.describeFailure(
        ModelPackService.instance.lastFailure,
      ),
    );
  }
  final model = await ModelPackService.instance.packFile(
    'birefnet_fp16',
    'model_fp16.onnx',
  );
  if (model == null) {
    throw ReporterBgException('The AI model file is missing.');
  }
  final bytes = await File(photoPath).readAsBytes();
  Uint8List? bgBytes;
  if (bgImagePath != null) {
    bgBytes = await File(bgImagePath).readAsBytes();
  }
  final Uint8List? out;
  try {
    out = await compute(
      reporterBgIsolateJob,
      <dynamic>[bytes, model.path, mode, colorArgb ?? -1, bgBytes],
    ).timeout(const Duration(minutes: 5));
  } on TimeoutException {
    throw ReporterBgException(
      'Background remove took too long and was stopped. '
      'Try a smaller photo.',
    );
  }
  if (out == null) {
    throw ReporterBgException(
      'No result from the AI model — the photo could not be processed.',
    );
  }
  final dir = await reporterDir();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dest = mode == 'remove'
      ? p.join(dir.path, 'reporter_cutout_$stamp.png')
      : p.join(dir.path, 'reporter_bg_$stamp.jpg');
  await File(dest).writeAsBytes(out);
  return dest;
}

/// BG Remove: the photo with its background matted away, saved
/// as a transparent PNG in [reporterDir]. Returns the new path.
/// Runs off the UI thread (v1.17.0 G1) — see [_reporterBgRun].
Future<String> reporterRemoveBackground(
  String photoPath, {
  void Function(double progress)? onProgress,
}) {
  return _reporterBgRun(photoPath, mode: 'remove', onProgress: onProgress);
}

/// BG Replace: the matted subject composited over a solid
/// [colorArgb] OR over the image at [bgImagePath] (cover-fitted).
/// Saved as a JPG in [reporterDir]. Returns the new path.
Future<String> reporterReplaceBackground(
  String photoPath, {
  int? colorArgb,
  String? bgImagePath,
  void Function(double progress)? onProgress,
}) {
  if (colorArgb == null && bgImagePath == null) {
    throw ReporterBgException('Choose a background colour or photo.');
  }
  return _reporterBgRun(
    photoPath,
    mode: 'replace',
    colorArgb: colorArgb,
    bgImagePath: bgImagePath,
    onProgress: onProgress,
  );
}
