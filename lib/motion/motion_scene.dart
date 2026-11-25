/// MOTION GRAPHICS STUDIO — scene model (Build M1, v1.11.0).
///
/// A motion graphic is DATA, not code: a [MotionScene] is a canvas
/// size + a duration + an ordered list of [MotionLayer]s, and every
/// template in the Gallery is one JSON-shaped scene (plan
/// MOTION-PLAN-2026-11-25 §3). The evaluator
/// (`motion_evaluator.dart`) resolves a scene at any time `t` into
/// plain numbers, and the ONE shared painter
/// (`motion_painter.dart`) draws those numbers — in the live
/// preview (CustomPaint) and in exported PNG frames alike, exactly
/// the Logo Cube parity pattern (Build 12): preview and export can
/// never drift because both call the same two functions.
///
/// This file is PURE Dart (no Flutter import) so the model and its
/// JSON round-trip are unit-testable with plain `dart test`
/// semantics under flutter_test, like `anim_presets.dart`.
library;

/// The layer kinds the engine knows (plan §3). Unknown kinds in
/// JSON are dropped at parse time — a template from a newer app
/// version can never crash an older one.
enum MotionLayerType { text, shape, image, counter, ticker, chart }

/// One keyframe on a layer: at time [t] (seconds, scene time) the
/// listed properties hold these values; the evaluator interpolates
/// between keyframes with [easing] (an AnimPresets curve name) on
/// the segment ENDING at this keyframe. A null property means
/// "this keyframe does not drive that property".
class MotionKeyframe {
  const MotionKeyframe({
    required this.t,
    this.x,
    this.y,
    this.scale,
    this.rotation,
    this.opacity,
    this.easing = 'easeInOut',
  });

  final double t;
  final double? x;
  final double? y;
  final double? scale;
  final double? rotation;
  final double? opacity;

  /// Curve name (see motion_evaluator's curve table).
  final String easing;

  Map<String, dynamic> toJson() => {
        't': t,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (scale != null) 'scale': scale,
        if (rotation != null) 'rotation': rotation,
        if (opacity != null) 'opacity': opacity,
        'easing': easing,
      };

  static MotionKeyframe? fromJson(Map<String, dynamic> json) {
    final t = _d(json['t']);
    if (t == null) return null;
    return MotionKeyframe(
      t: t,
      x: _d(json['x']),
      y: _d(json['y']),
      scale: _d(json['scale']),
      rotation: _d(json['rotation']),
      opacity: _d(json['opacity']),
      easing: (json['easing'] ?? 'easeInOut').toString(),
    );
  }
}

/// One layer of a [MotionScene]. Position ([x], [y]) is the
/// layer's CENTRE in design pixels; [width]/[height] are its box
/// (text wraps/centres inside it, shapes fill it, images fit it).
/// All type-specific payloads live in named fields (null when the
/// layer's type does not use them) so JSON stays flat and the
/// painter needs no map lookups.
class MotionLayer {
  const MotionLayer({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.width = 0,
    this.height = 0,
    this.start = 0,
    this.end,
    this.opacity = 1,
    this.scale = 1,
    this.rotation = 0,
    this.entrance,
    this.entranceSec = 0.6,
    this.exit,
    this.exitSec = 0.4,
    this.keyframes = const [],
    // text
    this.text,
    this.fontSize = 64,
    this.color = 0xFFFFFFFF,
    this.fontFamily,
    this.bold = true,
    this.letterSpacing = 0,
    // shape
    this.shape,
    this.fill = 0xFF2979FF,
    this.fill2,
    this.cornerRadius = 0,
    this.strokeColor,
    this.strokeWidth = 0,
    this.glowColor,
    this.glowBlur = 0,
    // image
    this.imageKey,
    this.placeholderText,
    // counter
    this.from = 0,
    this.to = 0,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.label,
    this.labelColor = 0xB3FFFFFF,
    // ticker
    this.speedPxPerSecond = 140,
    this.scrollRight = false,
    this.bandColor = 0xFF0B1026,
    this.bandHeight = 72,
    this.cyclePx = 2600,
    // chart
    this.values = const [],
    this.barColor = 0xFF00E5FF,
  });

  final String id;
  final MotionLayerType type;

  /// Centre position in design px.
  final double x;
  final double y;

  /// Box size in design px (0 = intrinsic / full-bleed per type).
  final double width;
  final double height;

  /// Alive window in scene seconds: [start] <= t < [end]
  /// (null [end] = the scene's end).
  final double start;
  final double? end;

  /// Base transform/opacity (keyframes override per property).
  final double opacity;
  final double scale;
  final double rotation;

  /// Entrance/exit AnimPresets ids ('fadeIn', 'slideUp',
  /// 'typewriter', 'pulse', 'scrollLeft', …) + their windows.
  final String? entrance;
  final double entranceSec;
  final String? exit;
  final double exitSec;

  final List<MotionKeyframe> keyframes;

  // --- text payload ---
  final String? text;
  final double fontSize;

  /// ARGB colour int.
  final int color;
  final String? fontFamily;
  final bool bold;
  final double letterSpacing;

  // --- shape payload ---
  /// 'rect' | 'rounded' | 'circle' | 'ring' | 'pill' | 'line'.
  final String? shape;
  final int fill;

  /// Gradient end colour (vertical gradient fill -> fill2).
  final int? fill2;
  final double cornerRadius;
  final int? strokeColor;
  final double strokeWidth;

  /// Neon glow (the reference look): a blurred copy of the shape
  /// drawn beneath it in this colour.
  final int? glowColor;
  final double glowBlur;

  // --- image payload ---
  /// Key into the painter's image map (the user's logo etc.).
  /// Absent image = a drawn placeholder badge ([placeholderText]).
  final String? imageKey;
  final String? placeholderText;

  // --- counter payload ---
  final double from;
  final double to;
  final String prefix;
  final String suffix;
  final int decimals;

  /// Small caption under the number.
  final String? label;
  final int labelColor;

  // --- ticker payload ---
  final double speedPxPerSecond;

  /// Urdu tickers scroll right (the approved template rule);
  /// Latin tickers scroll left.
  final bool scrollRight;
  final int bandColor;
  final double bandHeight;

  /// Estimated full scroll cycle in design px (text width +
  /// canvas width), set by the template author; the painter draws
  /// the text twice per cycle so the loop is seamless.
  final double cyclePx;

  // --- chart payload ---
  /// Bar fractions 0..1 (also the bar labels' values source).
  final List<double> values;
  final int barColor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
        'start': start,
        if (end != null) 'end': end,
        'opacity': opacity,
        'scale': scale,
        'rotation': rotation,
        if (entrance != null) 'entrance': entrance,
        'entranceSec': entranceSec,
        if (exit != null) 'exit': exit,
        'exitSec': exitSec,
        if (keyframes.isNotEmpty)
          'keyframes': keyframes.map((k) => k.toJson()).toList(),
        if (text != null) 'text': text,
        'fontSize': fontSize,
        'color': color,
        if (fontFamily != null) 'fontFamily': fontFamily,
        'bold': bold,
        'letterSpacing': letterSpacing,
        if (shape != null) 'shape': shape,
        'fill': fill,
        if (fill2 != null) 'fill2': fill2,
        'cornerRadius': cornerRadius,
        if (strokeColor != null) 'strokeColor': strokeColor,
        'strokeWidth': strokeWidth,
        if (glowColor != null) 'glowColor': glowColor,
        'glowBlur': glowBlur,
        if (imageKey != null) 'imageKey': imageKey,
        if (placeholderText != null) 'placeholderText': placeholderText,
        'from': from,
        'to': to,
        'prefix': prefix,
        'suffix': suffix,
        'decimals': decimals,
        if (label != null) 'label': label,
        'labelColor': labelColor,
        'speedPxPerSecond': speedPxPerSecond,
        'scrollRight': scrollRight,
        'bandColor': bandColor,
        'bandHeight': bandHeight,
        'cyclePx': cyclePx,
        if (values.isNotEmpty) 'values': values,
        'barColor': barColor,
      };

  static MotionLayer? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final typeName = (json['type'] ?? '').toString();
    final type = MotionLayerType.values
        .where((e) => e.name == typeName)
        .firstOrNull;
    if (id.isEmpty || type == null) return null;
    final rawKf = json['keyframes'];
    return MotionLayer(
      id: id,
      type: type,
      x: _d(json['x']) ?? 0,
      y: _d(json['y']) ?? 0,
      width: _d(json['w']) ?? 0,
      height: _d(json['h']) ?? 0,
      start: _d(json['start']) ?? 0,
      end: _d(json['end']),
      opacity: _d(json['opacity']) ?? 1,
      scale: _d(json['scale']) ?? 1,
      rotation: _d(json['rotation']) ?? 0,
      entrance: json['entrance']?.toString(),
      entranceSec: _d(json['entranceSec']) ?? 0.6,
      exit: json['exit']?.toString(),
      exitSec: _d(json['exitSec']) ?? 0.4,
      keyframes: rawKf is List
          ? rawKf
              .whereType<Map>()
              .map((m) => MotionKeyframe.fromJson(m.cast<String, dynamic>()))
              .whereType<MotionKeyframe>()
              .toList()
          : const [],
      text: json['text']?.toString(),
      fontSize: _d(json['fontSize']) ?? 64,
      color: _i(json['color']) ?? 0xFFFFFFFF,
      fontFamily: json['fontFamily']?.toString(),
      bold: json['bold'] != false,
      letterSpacing: _d(json['letterSpacing']) ?? 0,
      shape: json['shape']?.toString(),
      fill: _i(json['fill']) ?? 0xFF2979FF,
      fill2: _i(json['fill2']),
      cornerRadius: _d(json['cornerRadius']) ?? 0,
      strokeColor: _i(json['strokeColor']),
      strokeWidth: _d(json['strokeWidth']) ?? 0,
      glowColor: _i(json['glowColor']),
      glowBlur: _d(json['glowBlur']) ?? 0,
      imageKey: json['imageKey']?.toString(),
      placeholderText: json['placeholderText']?.toString(),
      from: _d(json['from']) ?? 0,
      to: _d(json['to']) ?? 0,
      prefix: (json['prefix'] ?? '').toString(),
      suffix: (json['suffix'] ?? '').toString(),
      decimals: _i(json['decimals']) ?? 0,
      label: json['label']?.toString(),
      labelColor: _i(json['labelColor']) ?? 0xB3FFFFFF,
      speedPxPerSecond: _d(json['speedPxPerSecond']) ?? 140,
      scrollRight: json['scrollRight'] == true,
      bandColor: _i(json['bandColor']) ?? 0xFF0B1026,
      bandHeight: _d(json['bandHeight']) ?? 72,
      cyclePx: _d(json['cyclePx']) ?? 2600,
      values: json['values'] is List
          ? (json['values'] as List)
              .map((v) => _d(v) ?? 0)
              .toList(growable: false)
          : const [],
      barColor: _i(json['barColor']) ?? 0xFF00E5FF,
    );
  }
}

/// A complete motion graphic: canvas + duration + layers, plus
/// the background the painter fills before the first layer.
class MotionScene {
  const MotionScene({
    required this.width,
    required this.height,
    required this.durationSec,
    required this.layers,
    this.bgColor = 0xFF050914,
    this.bgColor2,
  });

  /// Design canvas size in px (1280x720 for the v1 templates).
  final double width;
  final double height;

  final double durationSec;
  final List<MotionLayer> layers;

  /// Background fill; [bgColor2] (optional) makes a vertical
  /// gradient — the reference's deep-navy falloff.
  final int bgColor;
  final int? bgColor2;

  Map<String, dynamic> toJson() => {
        'w': width,
        'h': height,
        'duration': durationSec,
        'bg': bgColor,
        if (bgColor2 != null) 'bg2': bgColor2,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  static MotionScene? fromJson(Map<String, dynamic> json) {
    final w = _d(json['w']);
    final h = _d(json['h']);
    final dur = _d(json['duration']);
    final rawLayers = json['layers'];
    if (w == null || h == null || dur == null || rawLayers is! List) {
      return null;
    }
    return MotionScene(
      width: w,
      height: h,
      durationSec: dur,
      bgColor: _i(json['bg']) ?? 0xFF050914,
      bgColor2: _i(json['bg2']),
      layers: rawLayers
          .whereType<Map>()
          .map((m) => MotionLayer.fromJson(m.cast<String, dynamic>()))
          .whereType<MotionLayer>()
          .toList(),
    );
  }
}

double? _d(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
