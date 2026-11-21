/// Channel watermark + branding end card (Phase 8, master prompt §9).
///
/// The watermark is the channel mark — the preset's logo file when
/// set, else the channel-initial tile in the preset's brand colour —
/// drawn semi-transparent into a full-frame transparent PNG by
/// [renderWatermarkImage] and overlaid in the export graph by
/// `FfmpegService.watermarkOverlayCommand` (see
/// `ReelExportService.exportReel`, step 5b). It is toggleable per
/// preset, with position + size settings on the preset — the geometry
/// in [watermarkRect] is the single source of truth for the PNG
/// renderer, the FFmpeg overlay (full-frame PNG, overlay 0:0) and
/// the live preview mark ([WatermarkMark]).
///
/// The end card ([renderBrandingEndCardImage]) is the 3 s outro
/// frame: channel name + the preset's real social handles, one per
/// line. No handle = no line — never a placeholder handle
/// ([endCardLines] is the pure, unit-tested source for the lines).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'channel_preset.dart';

/// Watermark geometry: the mark is a square, [sizeFraction] of the
/// frame width (clamped 0.05–0.30), 16 px from the chosen corner.
/// Pure — unit-tested. Returns the rect in output pixels.
ui.Rect watermarkRect({
  required double width,
  required double height,
  required String position,
  required double sizeFraction,
}) {
  final size = width * sizeFraction.clamp(0.05, 0.30);
  const margin = 16.0;
  final double x;
  final double y;
  switch (position) {
    case 'topLeft':
      x = margin;
      y = margin;
      break;
    case 'topRight':
      x = width - size - margin;
      y = margin;
      break;
    case 'bottomLeft':
      x = margin;
      y = height - size - margin;
      break;
    case 'bottomRight':
    default:
      x = width - size - margin;
      y = height - size - margin;
      break;
  }
  return ui.Rect.fromLTWH(x, y, size, size);
}

/// End-card lines for [preset]: the channel name first, then one
/// line per real social handle ('YouTube: @nigraantvxyz', …).
/// Empty handles produce NO line — never a placeholder.
List<String> endCardLines(ChannelPreset preset) {
  return [preset.name.trim().isEmpty ? 'Channel' : preset.name.trim()]
      .followedBy(preset.socialHandleLines())
      .toList();
}

/// Renders the watermark as ONE full-frame transparent PNG sized
/// [width]x[height] — the mark sits in its [watermarkRect], the rest
/// is transparent, so the export overlays it at 0:0. The mark is the
/// preset's logo file when it reads, else the channel-initial tile
/// in the preset's brand colour (never a blank slot, never a static
/// circular image — the rotating logo bug is a separate pass).
/// Writes `watermark.png` (never the template overlay files).
Future<File> renderWatermarkImage({
  required ChannelPreset preset,
  required Directory dir,
  int width = 720,
  int height = 1280,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final rect = watermarkRect(
    width: width.toDouble(),
    height: height.toDouble(),
    position: preset.watermarkPosition,
    sizeFraction: preset.watermarkSize,
  );
  var drewImage = false;
  final logoPath = preset.logoPath;
  if (logoPath != null) {
    try {
      final bytes = await File(logoPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final logo = frame.image;
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(
          0,
          0,
          logo.width.toDouble(),
          logo.height.toDouble(),
        ),
        rect,
        ui.Paint()..color = const ui.Color(0xD9FFFFFF),
      );
      logo.dispose();
      drewImage = true;
    } catch (_) {
      // Bad logo file: fall through to the initial tile below.
    }
  }
  if (!drewImage) {
    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(12)),
      ui.Paint()
        ..color = ui.Color(preset.brandColor).withValues(alpha: 0.85),
    );
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: rect.width * 0.45,
        fontWeight: ui.FontWeight.bold,
      ),
    );
    builder.addText(initial);
    final para = builder.build();
    para.layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(
      para,
      ui.Offset(rect.left, rect.top + (rect.height - para.height) / 2),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'watermark.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Renders the branding end card as ONE opaque 720×1280 PNG: brand
/// colour band on top, the channel-initial tile, the channel name,
/// then one line per real social handle (see [endCardLines]).
/// The reel export uses this as the 3 s outro still when the preset
/// has handles; without handles it uses the template PNG instead.
/// Writes `branding_end_card.png`.
Future<File> renderBrandingEndCardImage({
  required ChannelPreset preset,
  required Directory dir,
  int width = 720,
  int height = 1280,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final w = width.toDouble();
  final h = height.toDouble();
  const white = ui.Color(0xFFFFFFFF);

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = const ui.Color(0xFF101018),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h * 0.012),
    ui.Paint()..color = ui.Color(preset.brandColor),
  );

  final tileSize = w * 0.22;
  final tileRect = ui.Rect.fromLTWH(
    (w - tileSize) / 2,
    h * 0.30,
    tileSize,
    tileSize,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(tileRect, const ui.Radius.circular(16)),
    ui.Paint()..color = ui.Color(preset.brandColor),
  );
  final initial = preset.name.trim().isEmpty
      ? 'N'
      : preset.name.trim()[0].toUpperCase();
  final initialBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  initialBuilder.pushStyle(
    ui.TextStyle(
      color: white,
      fontSize: tileSize * 0.45,
      fontWeight: ui.FontWeight.bold,
    ),
  );
  initialBuilder.addText(initial);
  final initialPara = initialBuilder.build();
  initialPara.layout(ui.ParagraphConstraints(width: tileSize));
  canvas.drawParagraph(
    initialPara,
    ui.Offset(
      tileRect.left,
      tileRect.top + (tileRect.height - initialPara.height) / 2,
    ),
  );

  ui.Paragraph centredLine(
    String text,
    double fontSize, {
    bool bold = true,
    ui.Color color = white,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(ui.ParagraphConstraints(width: w - 48));
    return para;
  }

  final lines = endCardLines(preset);
  var y = tileRect.bottom + h * 0.04;
  final namePara = centredLine(lines.first, h * 0.032);
  canvas.drawParagraph(namePara, ui.Offset(24, y));
  y += namePara.height + h * 0.03;
  for (final line in lines.skip(1)) {
    final para = centredLine(line, h * 0.020, bold: false);
    canvas.drawParagraph(para, ui.Offset(24, y));
    y += para.height + h * 0.012;
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'branding_end_card.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Live preview mark: the watermark as it will sit on the export —
/// same corner + relative size as [watermarkRect], drawn inside the
/// template preview Stack. Returns a [Positioned] (key
/// 'preview-watermark') so widget tests can find it.
class WatermarkMark extends StatelessWidget {
  const WatermarkMark({
    super.key,
    required this.preset,
    required this.frameWidth,
    required this.frameHeight,
  });

  final ChannelPreset preset;
  final double frameWidth;
  final double frameHeight;

  @override
  Widget build(BuildContext context) {
    final size =
        (frameWidth * preset.watermarkSize.clamp(0.05, 0.30)).clamp(24.0, 72.0);
    const margin = 8.0;
    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();
    Widget mark;
    if (preset.logoPath != null) {
      mark = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(preset.logoPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialTile(initial, size),
        ),
      );
    } else {
      mark = _initialTile(initial, size);
    }
    final child = Opacity(opacity: 0.85, child: mark);
    final pos = preset.watermarkPosition;
    return Positioned(
      key: const Key('preview-watermark'),
      left: pos == 'topLeft' || pos == 'bottomLeft' ? margin : null,
      right: pos == 'topRight' || pos == 'bottomRight' ? margin : null,
      top: pos == 'topLeft' || pos == 'topRight' ? margin : null,
      bottom: pos == 'bottomLeft' || pos == 'bottomRight' ? margin : null,
      child: child,
    );
  }

  Widget _initialTile(String initial, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(preset.brandColor),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
