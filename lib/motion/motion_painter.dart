/// MOTION GRAPHICS STUDIO — the ONE shared painter (Build M1).
///
/// `paintMotionScene` draws a resolved scene state onto any
/// canvas. It is called verbatim by:
///   * the live preview — [MotionScenePainter] (CustomPaint in
///     the Gallery cards and the full-screen preview), and
///   * the frame renderer — `motion_render.dart`, which records
///     the same calls into PNG frames for export and for the
///     parity frame proofs.
/// Same evaluator + same painter = preview and export can never
/// drift (the Logo Cube rule, Build 12).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'motion_evaluator.dart';
import 'motion_scene.dart';

/// True when [text] contains Arabic-script characters (Urdu) —
/// such text is laid out right-to-left.
bool motionTextIsRtl(String text) =>
    text.runes.any((r) => r >= 0x0600 && r <= 0x06FF);

/// Paints [scene] resolved at [state] into [size] (the scene is
/// scaled uniformly and centred — letterboxed, never cropped).
/// [images] supplies the bitmaps for image layers by
/// [MotionLayer.imageKey]; a missing image draws the layer's
/// placeholder badge instead.
void paintMotionScene(
  Canvas canvas, {
  required MotionScene scene,
  required List<ResolvedMotionLayer> state,
  required Size size,
  Map<String, ui.Image> images = const {},
}) {
  // Background (device space, before the scene transform).
  final bgPaint = Paint()..isAntiAlias = true;
  if (scene.bgColor2 != null) {
    bgPaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      [Color(scene.bgColor), Color(scene.bgColor2!)],
    );
  } else {
    bgPaint.color = Color(scene.bgColor);
  }
  canvas.drawRect(Offset.zero & size, bgPaint);

  final scale =
      math.min(size.width / scene.width, size.height / scene.height);
  canvas.save();
  canvas.translate(
    (size.width - scene.width * scale) / 2,
    (size.height - scene.height * scale) / 2,
  );
  canvas.scale(scale);
  for (final r in state) {
    _paintLayer(canvas, scene, r, images);
  }
  canvas.restore();
}

void _paintLayer(
  Canvas canvas,
  MotionScene scene,
  ResolvedMotionLayer r,
  Map<String, ui.Image> images,
) {
  final layer = r.layer;
  canvas.save();
  canvas.translate(r.x, r.y);
  if (r.rotation != 0) canvas.rotate(r.rotation);
  if (r.scale != 1) canvas.scale(r.scale);
  switch (layer.type) {
    case MotionLayerType.text:
      _paintText(canvas, layer, r);
    case MotionLayerType.shape:
      _paintShape(canvas, layer, r);
    case MotionLayerType.image:
      _paintImage(canvas, layer, r, images);
    case MotionLayerType.counter:
      _paintCounter(canvas, layer, r);
    case MotionLayerType.ticker:
      _paintTicker(canvas, scene, layer, r);
    case MotionLayerType.chart:
      _paintChart(canvas, layer, r);
  }
  canvas.restore();
}

TextPainter _textPainter({
  required String text,
  required double fontSize,
  required int color,
  required double opacity,
  String? fontFamily,
  bool bold = true,
  double letterSpacing = 0,
  double? maxWidth,
}) {
  final style = TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    color: Color(color).withValues(alpha: opacity.clamp(0.0, 1.0)),
    fontFamily: fontFamily,
    letterSpacing: letterSpacing,
  );
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection:
        motionTextIsRtl(text) ? TextDirection.rtl : TextDirection.ltr,
    textAlign: TextAlign.center,
  );
  tp.layout(maxWidth: maxWidth ?? double.infinity);
  return tp;
}

void _paintText(Canvas canvas, MotionLayer layer, ResolvedMotionLayer r) {
  var text = layer.text ?? '';
  if (r.visibleChars != null) {
    final runes = text.runes.toList();
    final n = r.visibleChars!.clamp(0, runes.length);
    text = String.fromCharCodes(runes.take(n));
  }
  if (text.isEmpty && r.visibleChars == null) return;
  final tp = _textPainter(
    text: text,
    fontSize: layer.fontSize,
    color: layer.color,
    opacity: r.opacity,
    fontFamily: layer.fontFamily,
    bold: layer.bold,
    letterSpacing: layer.letterSpacing,
    maxWidth: layer.width > 0 ? layer.width : null,
  );
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
}

Paint _fillPaint(MotionLayer layer, Rect rect, double opacity) {
  final paint = Paint()..isAntiAlias = true;
  if (layer.fill2 != null) {
    paint.shader = ui.Gradient.linear(
      rect.topCenter,
      rect.bottomCenter,
      [
        Color(layer.fill).withValues(alpha: opacity),
        Color(layer.fill2!).withValues(alpha: opacity),
      ],
    );
  } else {
    paint.color = Color(layer.fill).withValues(alpha: opacity);
  }
  return paint;
}

Path _shapePath(MotionLayer layer, Rect rect) {
  switch (layer.shape ?? 'rect') {
    case 'circle':
    case 'ring':
      return Path()..addOval(rect);
    case 'rounded':
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
          rect,
          Radius.circular(layer.cornerRadius),
        ));
    case 'pill':
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.height / 2),
        ));
    case 'line':
      final h = layer.strokeWidth > 0 ? layer.strokeWidth : 6.0;
      return Path()
        ..addRect(Rect.fromCenter(
          center: rect.center,
          width: rect.width,
          height: h,
        ));
    default:
      return Path()..addRect(rect);
  }
}

void _paintShape(Canvas canvas, MotionLayer layer, ResolvedMotionLayer r) {
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: layer.width,
    height: layer.height,
  );
  final path = _shapePath(layer, rect);
  // Neon glow first (the reference look): a blurred copy beneath.
  if (layer.glowColor != null && layer.glowBlur > 0) {
    final glow = Paint()
      ..isAntiAlias = true
      ..color =
          Color(layer.glowColor!).withValues(alpha: 0.55 * r.opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, layer.glowBlur);
    canvas.drawPath(path, glow);
  }
  if ((layer.shape ?? 'rect') == 'ring') {
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = layer.strokeWidth > 0 ? layer.strokeWidth : 8
      ..color = Color(layer.fill).withValues(alpha: r.opacity);
    canvas.drawPath(path, stroke);
    return;
  }
  canvas.drawPath(path, _fillPaint(layer, rect, r.opacity));
  if (layer.strokeColor != null && layer.strokeWidth > 0) {
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = layer.strokeWidth
      ..color =
          Color(layer.strokeColor!).withValues(alpha: r.opacity);
    canvas.drawPath(path, stroke);
  }
}

void _paintImage(
  Canvas canvas,
  MotionLayer layer,
  ResolvedMotionLayer r,
  Map<String, ui.Image> images,
) {
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: layer.width,
    height: layer.height,
  );
  final img = layer.imageKey == null ? null : images[layer.imageKey];
  if (img != null) {
    // Contain-fit the bitmap inside the layer box.
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final fitted = _containRect(src.size, rect);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      fitted,
      Radius.circular(layer.cornerRadius),
    ));
    canvas.drawImageRect(
      img,
      src,
      fitted,
      Paint()
        ..isAntiAlias = true
        ..color = Color.fromRGBO(255, 255, 255, r.opacity),
    );
    canvas.restore();
    return;
  }
  // Placeholder badge (no user logo yet): the reference's globe-
  // badge read — a navy→purple disc with the channel initials.
  final badge = Path()
    ..addRRect(RRect.fromRectAndRadius(
      rect,
      Radius.circular(layer.cornerRadius > 0
          ? layer.cornerRadius
          : layer.height / 2),
    ));
  final paint = Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      rect.topLeft,
      rect.bottomRight,
      [
        const Color(0xFF14265C).withValues(alpha: r.opacity),
        const Color(0xFF3B1D6E).withValues(alpha: r.opacity),
      ],
    );
  canvas.drawPath(badge, paint);
  final stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = const Color(0xFF00E5FF).withValues(alpha: r.opacity);
  canvas.drawPath(badge, stroke);
  final label = layer.placeholderText ?? 'LOGO';
  final tp = _textPainter(
    text: label,
    fontSize: layer.height * 0.34,
    color: 0xFFFFFFFF,
    opacity: r.opacity,
    maxWidth: layer.width * 0.9,
  );
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
}

Rect _containRect(Size src, Rect box) {
  final scale = math.min(box.width / src.width, box.height / src.height);
  final w = src.width * scale;
  final h = src.height * scale;
  return Rect.fromCenter(center: box.center, width: w, height: h);
}

String formatMotionCounter(MotionLayer layer, double value) {
  final fixed = value.toStringAsFixed(layer.decimals);
  // Thousands separators for whole-number counters (100,000).
  var out = fixed;
  if (layer.decimals == 0) {
    final neg = fixed.startsWith('-');
    final digits = neg ? fixed.substring(1) : fixed;
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buf.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    out = (neg ? '-' : '') + buf.toString();
  }
  return '${layer.prefix}$out${layer.suffix}';
}

void _paintCounter(Canvas canvas, MotionLayer layer, ResolvedMotionLayer r) {
  final text = formatMotionCounter(layer, r.counterValue);
  final tp = _textPainter(
    text: text,
    fontSize: layer.fontSize,
    color: layer.color,
    opacity: r.opacity,
    fontFamily: layer.fontFamily,
    maxWidth: layer.width > 0 ? layer.width : null,
  );
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  final label = layer.label;
  if (label != null && label.isNotEmpty) {
    final lp = _textPainter(
      text: label,
      fontSize: layer.fontSize * 0.32,
      color: layer.labelColor,
      opacity: r.opacity,
      bold: false,
      maxWidth: layer.width > 0 ? layer.width : null,
    );
    lp.paint(canvas, Offset(-lp.width / 2, tp.height / 2 + 10));
  }
}

void _paintTicker(
  Canvas canvas,
  MotionScene scene,
  MotionLayer layer,
  ResolvedMotionLayer r,
) {
  final band = Rect.fromCenter(
    center: Offset.zero,
    width: scene.width,
    height: layer.bandHeight,
  );
  canvas.drawRect(
    band,
    Paint()
      ..isAntiAlias = true
      ..color = Color(layer.bandColor).withValues(alpha: r.opacity),
  );
  canvas.save();
  canvas.clipRect(band);
  final text = layer.text ?? '';
  if (text.isNotEmpty) {
    final tp = _textPainter(
      text: text,
      fontSize: layer.fontSize,
      color: layer.color,
      opacity: r.opacity,
      fontFamily: layer.fontFamily,
    );
    final tw = tp.width;
    // Copies at -cycle / 0 / +cycle around the live offset: with
    // cyclePx >= scene width + text width (the template author's
    // contract) the band is covered at every instant.
    final left0 = -scene.width / 2 + r.tickerOffsetPx - tw / 2;
    for (var k = -1; k <= 1; k++) {
      tp.paint(
        canvas,
        Offset(left0 + k * layer.cyclePx, -tp.height / 2),
      );
    }
  }
  canvas.restore();
}

void _paintChart(Canvas canvas, MotionLayer layer, ResolvedMotionLayer r) {
  final w = layer.width;
  final h = layer.height;
  final baseline = h / 2;
  // Baseline rule.
  canvas.drawRect(
    Rect.fromLTWH(-w / 2, baseline - 1.5, w, 3),
    Paint()
      ..color = const Color(0x55FFFFFF).withValues(alpha: r.opacity),
  );
  final n = layer.values.length;
  if (n == 0) return;
  final slot = w / n;
  final barW = slot * 0.52;
  for (var i = 0; i < n; i++) {
    final frac = i < r.chartFractions.length ? r.chartFractions[i] : 0.0;
    final bh = frac.clamp(0.0, 1.0) * h;
    final left = -w / 2 + slot * i + (slot - barW) / 2;
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, baseline - bh, barW, bh),
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        Offset(0, baseline - bh),
        Offset(0, baseline),
        [
          Color(layer.barColor).withValues(alpha: r.opacity),
          Color(layer.fill).withValues(alpha: r.opacity),
        ],
      );
    canvas.drawRRect(rect, paint);
  }
}

/// CustomPainter binding for the live preview: resolves the
/// scene at [t] through the evaluator and paints it with
/// [paintMotionScene] — the identical path the frame renderer
/// uses.
class MotionScenePainter extends CustomPainter {
  MotionScenePainter({
    required this.scene,
    required this.t,
    this.images = const {},
  });

  final MotionScene scene;
  final double t;
  final Map<String, ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    paintMotionScene(
      canvas,
      scene: scene,
      state: sceneStateAt(scene, t),
      size: size,
      images: images,
    );
  }

  @override
  bool shouldRepaint(MotionScenePainter old) =>
      old.t != t || old.scene != scene || old.images != images;
}
