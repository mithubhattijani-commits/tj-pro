/// MOTION GRAPHICS STUDIO — preview hit testing (v1.17.0, G3).
///
/// Pure geometry: which layer is under a preview point? Uses
/// the SAME evaluator the painter uses ([sceneStateAt]) and the
/// painter's own layout rules — the scene is fit into the view
/// with a uniform scale and centred; every layer's content is
/// centred on its resolved (x, y) and scaled by its resolved
/// scale. Rotation is ignored (an approximation noted in the
/// build report); a small tolerance inflates every rect so
/// small text stays tappable.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_evaluator.dart';
import 'motion_painter.dart' show motionTextIsRtl;
import 'motion_scene.dart';

/// The layer under [point] (view coordinates, [viewSize] = the
/// preview's size), topmost first — or null when the point hits
/// only background. Layers outside their alive window at [t]
/// cannot be hit (the evaluator omits them, exactly like the
/// painter).
MotionLayer? motionLayerAtPoint({
  required MotionScene scene,
  required double t,
  required Offset point,
  required Size viewSize,
}) {
  if (viewSize.isEmpty || scene.width <= 0 || scene.height <= 0) {
    return null;
  }
  final scale = math.min(
    viewSize.width / scene.width,
    viewSize.height / scene.height,
  );
  if (scale <= 0) return null;
  final origin = Offset(
    (viewSize.width - scene.width * scale) / 2,
    (viewSize.height - scene.height * scale) / 2,
  );
  final scenePoint = (point - origin) / scale;
  final resolved = sceneStateAt(scene, t);
  const tolerance = 24.0; // scene units of fat-finger slack
  for (final r in resolved.reversed) {
    final layer = r.layer;
    final size = _layerExtent(layer);
    final rect = Rect.fromCenter(
      center: Offset(r.x, r.y),
      width: size.width * r.scale + tolerance * 2,
      height: size.height * r.scale + tolerance * 2,
    );
    if (rect.contains(scenePoint)) return layer;
  }
  return null;
}

/// The unscaled content extent of [layer] in scene units,
/// mirroring the painter: text is measured with a TextPainter
/// at the layer's font size; shapes/images/charts use their
/// width/height (with the templates' usual defaults when 0);
/// a ticker spans the scene width.
Size _layerExtent(MotionLayer layer) {
  switch (layer.type) {
    case MotionLayerType.text:
      return _measureText(layer.text ?? '', layer);
    case MotionLayerType.counter:
      return _measureText(
        '${layer.prefix}${layer.to}${layer.suffix}',
        layer,
      );
    case MotionLayerType.ticker:
      // Width is filled in by the caller path: the ticker band
      // spans the whole scene — handled via a wide extent.
      return Size(1e6, layer.fontSize * 1.8);
    case MotionLayerType.shape:
    case MotionLayerType.image:
    case MotionLayerType.chart:
      return Size(
        layer.width > 0 ? layer.width : 200,
        layer.height > 0 ? layer.height : 200,
      );
  }
}

Size _measureText(String text, MotionLayer layer) {
  if (text.isEmpty) return const Size(48, 48);
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: layer.fontSize,
        fontWeight: layer.bold ? FontWeight.w800 : FontWeight.w500,
        fontFamily: layer.fontFamily,
        letterSpacing: layer.letterSpacing,
      ),
    ),
    textDirection: motionTextIsRtl(text) ? TextDirection.rtl : TextDirection.ltr,
    textAlign: TextAlign.center,
  );
  tp.layout(maxWidth: layer.width > 0 ? layer.width : double.infinity);
  return tp.size;
}
