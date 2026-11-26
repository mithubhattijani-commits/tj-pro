/// MOTION GRAPHICS STUDIO — scene ⇄ track keyframe converter
/// (Build M5, v1.26.0).
///
/// The Gemini keyframe model ([MotionKeyframeSet], per-property
/// dense tracks) is an EDITING surface only. Storage stays the
/// scene's sparse multi-property keyframes, and rendering stays
/// the evaluator's `sceneStateAt` — this file is the only bridge
/// between the two, and it exists to absorb their three semantic
/// differences in ONE tested place:
///
///  1. EASING DIRECTION. The evaluator takes a segment's easing
///     from its END keyframe; the track model takes it from the
///     segment's START keyframe. Converting scene→tracks, each
///     track keyframe inherits the NEXT scene keyframe's easing;
///     converting back, each scene keyframe takes the easing of
///     the segment that ends on it (the previous track
///     keyframe's easing).
///  2. CURVE SHAPES. The evaluator's easeIn/easeOut/easeInOut
///     are CUBIC; the track model's same-named easings are
///     QUADRATIC. Names map 1:1, shapes differ — which is
///     exactly why nothing renders from the track model: the
///     Creator's preview runs the CONVERTED scene through
///     `sceneStateAt`, like every other surface. (linear and
///     bounceOut are identical on both sides.)
///  3. ROTATION UNITS. Scene rotation is RADIANS; the track
///     property is `rotationDeg` (DEGREES). Every crossing
///     converts ×π/180 or ×180/π.
///
/// Exotic scene curve names with no enum twin (easeInCubic,
/// easeOutBack, …) flatten to the nearest enum easing when a
/// scene enters the Creator — no shipped template uses them in
/// keyframes today, and the flattening is one-way (saving from
/// the Creator writes the enum's name back).
///
/// One scene keyframe carries ONE easing string for every
/// property's segment ending at that time, while tracks ease
/// per property. When two tracks disagree about the segment
/// ending at the same timestamp, the scene write takes the
/// first property's easing in [MotionProperty] order — the
/// scene format's own constraint, not a converter choice.
library;

import 'dart:math' as math;

import 'motion_evaluator.dart';
import 'motion_keyframes.dart';
import 'motion_scene.dart';

/// Scene curve name → track easing (see header point 2 + the
/// exotic-name flattening rule). Unknown names land on easeOut,
/// the evaluator's own fallback for unknown curve names.
MotionEasing motionEasingFromCurveName(String name) {
  switch (name) {
    case 'linear':
      return MotionEasing.linear;
    case 'easeIn':
    case 'easeInCubic':
      return MotionEasing.easeIn;
    case 'easeOut':
    case 'easeOutCubic':
    case 'easeOutBack':
      return MotionEasing.easeOut;
    case 'easeInOut':
    case 'easeInOutCubic':
      return MotionEasing.easeInOut;
    case 'bounceOut':
      return MotionEasing.bounceOut;
    default:
      return MotionEasing.easeOut;
  }
}

/// Track easing → the scene curve name written back on save.
String motionCurveNameForEasing(MotionEasing easing) {
  switch (easing) {
    case MotionEasing.linear:
      return 'linear';
    case MotionEasing.easeIn:
      return 'easeIn';
    case MotionEasing.easeOut:
      return 'easeOut';
    case MotionEasing.easeInOut:
      return 'easeInOut';
    case MotionEasing.bounceOut:
      return 'bounceOut';
  }
}

/// The layer's BASE value for [property] — what the evaluator
/// uses when the property has no keyframe track. Rotation is
/// returned in DEGREES (the track model's unit).
double motionBaseValue(MotionLayer layer, MotionProperty property) {
  switch (property) {
    case MotionProperty.opacity:
      return layer.opacity;
    case MotionProperty.scale:
      return layer.scale;
    case MotionProperty.positionX:
      return layer.x;
    case MotionProperty.positionY:
      return layer.y;
    case MotionProperty.rotationDeg:
      return layer.rotation * 180.0 / math.pi;
  }
}

double? _sceneField(MotionKeyframe k, MotionProperty property) {
  switch (property) {
    case MotionProperty.opacity:
      return k.opacity;
    case MotionProperty.scale:
      return k.scale;
    case MotionProperty.positionX:
      return k.x;
    case MotionProperty.positionY:
      return k.y;
    case MotionProperty.rotationDeg:
      return k.rotation;
  }
}

double _toTrackValue(MotionProperty property, double sceneValue) =>
    property == MotionProperty.rotationDeg
        ? sceneValue * 180.0 / math.pi
        : sceneValue;

double _toSceneValue(MotionProperty property, double trackValue) =>
    property == MotionProperty.rotationDeg
        ? trackValue * math.pi / 180.0
        : trackValue;

/// The value the EVALUATOR would give [property] of [layer] at
/// scene time [t] — an exact mirror of the evaluator's `_track`
/// (END-keyframe easing, cubic curves), falling back to the
/// layer's base value when the property has no track. The
/// Creator uses this to capture "the current value" when a
/// keyframe is added, so a captured value never disagrees with
/// what the preview/export actually shows. Rotation is returned
/// in DEGREES.
double scenePropertyValueAt(
  MotionLayer layer,
  MotionProperty property,
  double t,
) {
  final keys = layer.keyframes
      .where((k) => _sceneField(k, property) != null)
      .toList()
    ..sort((a, b) => a.t.compareTo(b.t));
  if (keys.isEmpty) return motionBaseValue(layer, property);
  if (t <= keys.first.t) {
    return _toTrackValue(property, _sceneField(keys.first, property)!);
  }
  if (t >= keys.last.t) {
    return _toTrackValue(property, _sceneField(keys.last, property)!);
  }
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (t >= a.t && t <= b.t) {
      final span = b.t - a.t;
      final p = span <= 0 ? 1.0 : motionCurve(b.easing, (t - a.t) / span);
      final va = _sceneField(a, property)!;
      final vb = _sceneField(b, property)!;
      return _toTrackValue(property, va + (vb - va) * p);
    }
  }
  return _toTrackValue(property, _sceneField(keys.last, property)!);
}

/// Scene → tracks: builds the editing model for one layer.
/// Each track keyframe's easing is the easing of the segment
/// STARTING there — which the scene stores on the segment's
/// END keyframe (header point 1). The last keyframe of a track
/// starts no segment; it gets `linear`.
MotionKeyframeSet keyframeSetFromLayer(MotionLayer layer) {
  final tracks = <MotionProperty, MotionKeyframeTrack>{};
  for (final property in MotionProperty.values) {
    // Sparse scene keyframes carrying this property, in time
    // order; a repeated timestamp keeps its LAST entry (the
    // evaluator's span-0 rule resolves to the later value too).
    final byTime = <double, MotionKeyframe>{};
    for (final k in layer.keyframes) {
      if (_sceneField(k, property) != null) byTime[k.t] = k;
    }
    if (byTime.isEmpty) continue;
    final times = byTime.keys.toList()..sort();
    final frames = <MotionTrackKeyframe>[];
    for (var i = 0; i < times.length; i++) {
      final sceneKf = byTime[times[i]]!;
      final easing = i + 1 < times.length
          ? motionEasingFromCurveName(byTime[times[i + 1]]!.easing)
          : MotionEasing.linear;
      frames.add(MotionTrackKeyframe(
        timeSec: times[i],
        value: _toTrackValue(property, _sceneField(sceneKf, property)!),
        easing: easing,
      ));
    }
    tracks[property] =
        MotionKeyframeTrack(property: property, keyframes: frames);
  }
  return MotionKeyframeSet(tracks);
}

/// Tracks → scene: the sparse keyframe list for one layer —
/// one scene keyframe per union timestamp, carrying exactly
/// the properties that have a track keyframe at that time.
/// The scene keyframe's easing is the easing of the segment
/// ENDING at that time (the previous track keyframe's easing;
/// header point 1) — first in [MotionProperty] order when
/// several tracks end a segment there (header note).
List<MotionKeyframe> sceneKeyframesFromSet(MotionKeyframeSet set) {
  final times = <double>{};
  for (final track in set.tracks.values) {
    for (final kf in track.keyframes) {
      times.add(kf.timeSec);
    }
  }
  final sorted = times.toList()..sort();
  final out = <MotionKeyframe>[];
  for (final t in sorted) {
    double? x, y, scale, rotation, opacity;
    String? segmentEasing;
    String? firstEasing;
    for (final property in MotionProperty.values) {
      final track = set.tracks[property];
      if (track == null) continue;
      for (var i = 0; i < track.keyframes.length; i++) {
        final kf = track.keyframes[i];
        if (kf.timeSec != t) continue;
        final sceneValue = _toSceneValue(property, kf.value);
        switch (property) {
          case MotionProperty.opacity:
            opacity = sceneValue;
          case MotionProperty.scale:
            scale = sceneValue;
          case MotionProperty.positionX:
            x = sceneValue;
          case MotionProperty.positionY:
            y = sceneValue;
          case MotionProperty.rotationDeg:
            rotation = sceneValue;
        }
        firstEasing ??= motionCurveNameForEasing(kf.easing);
        if (i > 0) {
          segmentEasing ??= motionCurveNameForEasing(
            track.keyframes[i - 1].easing,
          );
        }
      }
    }
    out.add(MotionKeyframe(
      t: t,
      x: x,
      y: y,
      scale: scale,
      rotation: rotation,
      opacity: opacity,
      easing: segmentEasing ?? firstEasing ?? 'easeInOut',
    ));
  }
  return out;
}

/// [layer] with its keyframes replaced by [set]'s conversion —
/// the only way the Creator writes keyframes back to a scene.
MotionLayer layerWithKeyframeSet(
  MotionLayer layer,
  MotionKeyframeSet set,
) =>
    layer.copyWith(keyframes: sceneKeyframesFromSet(set));

/// Adds (or replaces) a keyframe on [property]'s track at [t],
/// honouring the base-seeding rule: when the property has NO
/// track yet, a keyframe holding the layer's BASE value is
/// seeded at the layer's start first — without it, the single
/// new keyframe would hold its value across the layer's whole
/// life and the property would visibly jump the moment the
/// first keyframe is placed.
MotionKeyframeSet addKeyframeSeeded(
  MotionKeyframeSet set,
  MotionLayer layer,
  MotionProperty property,
  double t,
  double value, {
  MotionEasing easing = MotionEasing.linear,
}) {
  final track = set.trackFor(property);
  if (track.isEmpty) {
    final start = layer.start;
    final frames = <MotionTrackKeyframe>[
      if (t != start)
        MotionTrackKeyframe(
          timeSec: start,
          value: motionBaseValue(layer, property),
        ),
      MotionTrackKeyframe(timeSec: t, value: value, easing: easing),
    ];
    return set.withTrack(
      MotionKeyframeTrack(property: property, keyframes: frames),
    );
  }
  return set.withTrack(
    track.addOrReplace(
      MotionTrackKeyframe(timeSec: t, value: value, easing: easing),
    ),
  );
}
