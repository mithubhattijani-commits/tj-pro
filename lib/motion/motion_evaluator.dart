/// MOTION GRAPHICS STUDIO — evaluator (Build M1, v1.11.0).
///
/// The pure heart of the engine: `sceneStateAt(scene, t)` turns a
/// [MotionScene] into the resolved numbers for one instant —
/// every alive layer's position, scale, rotation and opacity,
/// plus its type-specific state (counter value, typewriter
/// character count, ticker scroll offset, chart bar fractions).
///
/// The painter (`motion_painter.dart`) draws EXACTLY these
/// numbers in both render paths (live preview + exported PNG
/// frames), so the two can never disagree. This file is pure Dart
/// (dart:math only) and fully deterministic — the same (scene, t)
/// always yields the same state, which is what makes the parity
/// frame proofs in the M1 test suite meaningful.
///
/// Motion sources, in order of application per layer:
///   1. base values (x / y / scale / rotation / opacity),
///   2. keyframe tracks (per property; the segment's END
///      keyframe supplies the easing),
///   3. entrance preset (AnimPresets data — offsets/scale/opacity
///      over the layer's entrance window; 'typewriter' reveals
///      characters, 'pulse' loops for the layer's whole life),
///   4. exit preset (the mirror over the exit window).
library;

import 'dart:math' as math;

import '../services/anim_presets.dart';
import 'motion_scene.dart';

/// One layer resolved at one instant. [layer] is the source data;
/// everything else is the evaluated state the painter consumes.
class ResolvedMotionLayer {
  const ResolvedMotionLayer({
    required this.layer,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.opacity,
    this.visibleChars,
    this.counterValue = 0,
    this.tickerOffsetPx = 0,
    this.chartFractions = const [],
  });

  final MotionLayer layer;
  final double x;
  final double y;
  final double scale;
  final double rotation;

  /// 0..1, already multiplied by entrance/exit factors.
  final double opacity;

  /// Typewriter reveal: how many characters of the text are
  /// visible (null = the whole text).
  final int? visibleChars;

  /// Counter layers: the number to show at this instant.
  final double counterValue;

  /// Ticker layers: the horizontal scroll offset in design px
  /// (the painter draws the text at x + offset and x + offset ±
  /// cyclePx for the seamless wrap).
  final double tickerOffsetPx;

  /// Chart layers: one grown fraction per bar (0..value).
  final List<double> chartFractions;
}

/// The easing table — mathematical twins of the Flutter curves
/// the AnimPresets registry names, so preview (evaluator) and any
/// widget-side motion agree. Unknown names fall back to easeOut.
double motionCurve(String name, double t) {
  final x = t.clamp(0.0, 1.0);
  switch (name) {
    case 'linear':
      return x;
    case 'easeIn':
      return x * x * x;
    case 'easeOut':
      return 1 - math.pow(1 - x, 3).toDouble();
    case 'easeInOut':
      return x < 0.5
          ? 4 * x * x * x
          : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
    case 'easeInCubic':
      return x * x * x;
    case 'easeOutCubic':
      return 1 - math.pow(1 - x, 3).toDouble();
    case 'easeInOutCubic':
      return x < 0.5
          ? 4 * x * x * x
          : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
    case 'easeOutBack':
      const c1 = 1.70158;
      const c3 = c1 + 1;
      return 1 + c3 * math.pow(x - 1, 3).toDouble() +
          c1 * math.pow(x - 1, 2).toDouble();
    case 'bounceOut':
      const n1 = 7.5625;
      const d1 = 2.75;
      if (x < 1 / d1) return n1 * x * x;
      if (x < 2 / d1) {
        final y = x - 1.5 / d1;
        return n1 * y * y + 0.75;
      }
      if (x < 2.5 / d1) {
        final y = x - 2.25 / d1;
        return n1 * y * y + 0.9375;
      }
      final y = x - 2.625 / d1;
      return n1 * y * y + 0.984375;
    default:
      return 1 - math.pow(1 - x, 3).toDouble();
  }
}

/// Resolves [scene] at scene-time [t] (seconds). Layers outside
/// their alive window are omitted entirely.
List<ResolvedMotionLayer> sceneStateAt(MotionScene scene, double t) {
  final out = <ResolvedMotionLayer>[];
  for (final layer in scene.layers) {
    final r = _resolveLayer(scene, layer, t);
    if (r != null) out.add(r);
  }
  return out;
}

ResolvedMotionLayer? _resolveLayer(
  MotionScene scene,
  MotionLayer layer,
  double t,
) {
  final double end = layer.end ?? scene.durationSec;
  if (t < layer.start || t >= end) return null;
  final double elapsed = t - layer.start;
  final double life = math.max(0.001, end - layer.start);

  // 1+2: base values, overridden by keyframe tracks.
  double x = _track(layer, t, (k) => k.x) ?? layer.x;
  double y = _track(layer, t, (k) => k.y) ?? layer.y;
  double scale = _track(layer, t, (k) => k.scale) ?? layer.scale;
  double rotation =
      _track(layer, t, (k) => k.rotation) ?? layer.rotation;
  double opacity = _track(layer, t, (k) => k.opacity) ?? layer.opacity;

  int? visibleChars;
  double tickerOffset = 0;

  // Ticker layers scroll intrinsically for their whole life
  // (direction from the layer: Urdu right, Latin left) — the
  // painter wraps the text by cyclePx for a seamless loop.
  if (layer.type == MotionLayerType.ticker) {
    final cycle = math.max(1.0, layer.cyclePx);
    final travelled = (elapsed * layer.speedPxPerSecond) % cycle;
    tickerOffset = layer.scrollRight ? travelled : -travelled;
  }

  // 3: entrance.
  final entranceId = layer.entrance;
  if (entranceId != null && entranceId != 'none') {
    final preset = AnimPresets.byId(entranceId);
    final double window = layer.entranceSec > 0
        ? layer.entranceSec
        : preset.duration.inMilliseconds / 1000.0;
    if (entranceId == 'pulse') {
      // Continuous emphasis for the layer's whole life: scale
      // breathes between fromScale and toScale, `cycles` times.
      final from = preset.params['fromScale'] ?? 1.0;
      final to = preset.params['toScale'] ?? 1.08;
      final cycles = preset.params['cycles'] ?? 3;
      final phase = (elapsed / life * cycles) % 1.0;
      final tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
      scale *= from + (to - from) * tri;
    } else if (entranceId == 'scrollLeft' || entranceId == 'scrollRight') {
      final speed = layer.speedPxPerSecond;
      final cycle = math.max(1.0, layer.cyclePx);
      final travelled = (elapsed * speed) % cycle;
      tickerOffset = entranceId == 'scrollLeft' ? -travelled : travelled;
    } else if (window > 0 && elapsed < window) {
      final double p = motionCurve(preset.curveName, elapsed / window);
      final dx = preset.params['dx'] ?? 0;
      final dy = preset.params['dy'] ?? 0;
      x += dx * (1 - p);
      y += dy * (1 - p);
      final fromScale = preset.params['fromScale'];
      final toScale = preset.params['toScale'];
      if (fromScale != null && toScale != null) {
        scale *= fromScale + (toScale - fromScale) * p;
      }
      final fromOp = preset.params['fromOpacity'];
      final toOp = preset.params['toOpacity'];
      if (entranceId == 'flashLabel') {
        // Broadcast blink: hard on/off flashes, settling solid.
        final flashes = preset.params['flashes'] ?? 3;
        final seg = (elapsed / window * flashes * 2).floor();
        opacity *= seg.isEven ? 0.1 : 1.0;
      } else if (fromOp != null || toOp != null) {
        opacity *= (fromOp ?? 1) + ((toOp ?? 1) - (fromOp ?? 1)) * p;
      }
      if (entranceId == 'typewriter') {
        final cps = preset.params['charsPerSecond'] ?? 14;
        final len = (layer.text ?? '').runes.length;
        visibleChars = math.min(len, (elapsed * cps).floor());
      }
    } else if (entranceId == 'typewriter') {
      visibleChars = (layer.text ?? '').runes.length;
    }
  }

  // 4: exit — the mirror window at the end of the layer's life.
  final exitId = layer.exit;
  if (exitId != null && exitId != 'none') {
    final preset = AnimPresets.byId(exitId);
    final double window = layer.exitSec > 0
        ? layer.exitSec
        : preset.duration.inMilliseconds / 1000.0;
    final double remaining = end - t;
    if (window > 0 && remaining < window) {
      final double r = motionCurve(preset.curveName, 1 - remaining / window);
      final dx = preset.params['dx'] ?? 0;
      final dy = preset.params['dy'] ?? 0;
      x += dx * r;
      y += dy * r;
      final fromScale = preset.params['fromScale'];
      final toScale = preset.params['toScale'];
      if (fromScale != null && toScale != null) {
        scale *= fromScale + (toScale - fromScale) * r;
      }
      final fromOp = preset.params['fromOpacity'];
      final toOp = preset.params['toOpacity'];
      if (fromOp != null || toOp != null) {
        opacity *= (fromOp ?? 1) + ((toOp ?? 1) - (fromOp ?? 1)) * r;
      }
    }
  }

  // Type-specific state.
  double counterValue = layer.from;
  if (layer.type == MotionLayerType.counter) {
    final p = motionCurve('easeOutCubic', elapsed / life);
    counterValue = layer.from + (layer.to - layer.from) * p;
  }
  var chartFractions = const <double>[];
  if (layer.type == MotionLayerType.chart && layer.values.isNotEmpty) {
    final n = layer.values.length;
    chartFractions = List<double>.generate(n, (i) {
      // Bars stagger in: bar i starts at i*10% of the life.
      final local = ((elapsed / life) - i * 0.1) / 0.9;
      return layer.values[i] * motionCurve('easeOutCubic', local);
    }, growable: false);
  }

  return ResolvedMotionLayer(
    layer: layer,
    x: x,
    y: y,
    scale: scale,
    rotation: rotation,
    opacity: opacity.clamp(0.0, 1.0),
    visibleChars: visibleChars,
    counterValue: counterValue,
    tickerOffsetPx: tickerOffset,
    chartFractions: chartFractions,
  );
}

/// One property's keyframe track at time [t]: before the first
/// keyframe the first value holds; after the last, the last
/// value; between two, eased interpolation (the END keyframe's
/// easing drives its incoming segment).
double? _track(
  MotionLayer layer,
  double t,
  double? Function(MotionKeyframe) pick,
) {
  final keys = layer.keyframes.where((k) => pick(k) != null).toList()
    ..sort((a, b) => a.t.compareTo(b.t));
  if (keys.isEmpty) return null;
  if (t <= keys.first.t) return pick(keys.first);
  if (t >= keys.last.t) return pick(keys.last);
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (t >= a.t && t <= b.t) {
      final span = b.t - a.t;
      final p = span <= 0 ? 1.0 : motionCurve(b.easing, (t - a.t) / span);
      final va = pick(a)!;
      final vb = pick(b)!;
      return va + (vb - va) * p;
    }
  }
  return pick(keys.last);
}
