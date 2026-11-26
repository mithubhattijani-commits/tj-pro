import 'dart:core';
import 'dart:math' as math;

// ============================================================
// MOTION PROPERTIES
// ============================================================

enum MotionProperty {
  opacity,
  scale,
  positionX,
  positionY,
  rotationDeg,
}

double motionPropertyDefault(MotionProperty p) {
  switch (p) {
    case MotionProperty.opacity:
    case MotionProperty.scale:
      return 1.0;
    case MotionProperty.positionX:
    case MotionProperty.positionY:
    case MotionProperty.rotationDeg:
      return 0.0;
  }
}

// ============================================================
// MOTION EASING
// ============================================================

enum MotionEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  bounceOut,
}

double _clamp01(double value) {
  if (!value.isFinite) return 0.0;
  return value.clamp(0.0, 1.0).toDouble();
}

double applyMotionEasing(MotionEasing easing, double t) {
  t = _clamp01(t);

  double result;

  switch (easing) {
    case MotionEasing.linear:
      result = t;
      break;

    case MotionEasing.easeIn:
      result = t * t;
      break;

    case MotionEasing.easeOut:
      result = 1.0 - (1.0 - t) * (1.0 - t);
      break;

    case MotionEasing.easeInOut:
      result = t < 0.5
          ? 2.0 * t * t
          : 1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble() / 2.0;
      break;

    case MotionEasing.bounceOut:
      const double n1 = 7.5625;
      const double d1 = 2.75;

      if (t < 1.0 / d1) {
        result = n1 * t * t;
      } else if (t < 2.0 / d1) {
        final double x = t - 1.5 / d1;
        result = n1 * x * x + 0.75;
      } else if (t < 2.5 / d1) {
        final double x = t - 2.25 / d1;
        result = n1 * x * x + 0.9375;
      } else {
        final double x = t - 2.625 / d1;
        result = n1 * x * x + 0.984375;
      }
      break;
  }

  return _clamp01(result);
}

// ============================================================
// JSON HELPERS
// ============================================================

double _safeDouble(Object? value, {double fallback = 0.0}) {
  if (value is num) {
    final double result = value.toDouble();
    return result.isFinite ? result : fallback;
  }

  return fallback;
}

MotionProperty? _parseMotionProperty(Object? value) {
  if (value is! String) return null;

  for (final property in MotionProperty.values) {
    if (property.name == value) return property;
  }

  return null;
}

MotionEasing _parseMotionEasing(
  Object? value, {
  MotionEasing fallback = MotionEasing.linear,
}) {
  if (value is! String) return fallback;

  for (final easing in MotionEasing.values) {
    if (easing.name == value) return easing;
  }

  return fallback;
}

// ============================================================
// MOTION KEYFRAME
// ============================================================

class MotionTrackKeyframe {
  final double timeSec;
  final double value;
  final MotionEasing easing;

  const MotionTrackKeyframe({
    required this.timeSec,
    required this.value,
    this.easing = MotionEasing.linear,
  });

  MotionTrackKeyframe copyWith({
    double? timeSec,
    double? value,
    MotionEasing? easing,
  }) {
    return MotionTrackKeyframe(
      timeSec: timeSec ?? this.timeSec,
      value: value ?? this.value,
      easing: easing ?? this.easing,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'timeSec': timeSec,
      'value': value,
      'easing': easing.name,
    };
  }

  factory MotionTrackKeyframe.fromJson(Object? json) {
    if (json is! Map) {
      return const MotionTrackKeyframe(timeSec: 0, value: 0);
    }

    final double rawTime = _safeDouble(json['timeSec']);
    final double rawValue = _safeDouble(json['value']);

    return MotionTrackKeyframe(
      timeSec: math.max(0.0, rawTime),
      value: rawValue,
      easing: _parseMotionEasing(json['easing']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MotionTrackKeyframe &&
        other.timeSec == timeSec &&
        other.value == value &&
        other.easing == easing;
  }

  @override
  int get hashCode => Object.hash(timeSec, value, easing);

  @override
  String toString() {
    return 'MotionTrackKeyframe(timeSec: $timeSec, value: $value, easing: ${easing.name})';
  }
}

// ============================================================
// MOTION KEYFRAME TRACK
// ============================================================

class MotionKeyframeTrack {
  final MotionProperty property;
  final List<MotionTrackKeyframe> keyframes;

  MotionKeyframeTrack({
    required this.property,
    List<MotionTrackKeyframe> keyframes = const [],
  }) : keyframes = List<MotionTrackKeyframe>.unmodifiable(
          _normalizeKeyframes(keyframes),
        );

  static List<MotionTrackKeyframe> _normalizeKeyframes(
    List<MotionTrackKeyframe> input,
  ) {
    // Preserve the LAST input occurrence for duplicate times.
    final Map<double, MotionTrackKeyframe> byTime = {};

    for (final keyframe in input) {
      if (!keyframe.timeSec.isFinite ||
          !keyframe.value.isFinite) {
        continue;
      }

      final double safeTime = math.max(0.0, keyframe.timeSec);

      byTime[safeTime] = keyframe.copyWith(
        timeSec: safeTime,
      );
    }

    final result = byTime.values.toList();

    result.sort(
      (a, b) => a.timeSec.compareTo(b.timeSec),
    );

    return result;
  }

  bool get isEmpty => keyframes.isEmpty;

  int get length => keyframes.length;

  MotionKeyframeTrack addOrReplace(MotionTrackKeyframe kf) {
    // CHECK #8 FIX: a non-finite VALUE must also be a no-op. Without this
    // guard the existing keyframe at that time was removed first and the
    // invalid replacement then dropped by normalization — silently
    // DELETING the keyframe. Mirrors the time guard below.
    if (!kf.timeSec.isFinite || !kf.value.isFinite) return this;

    final double safeTime = math.max(0.0, kf.timeSec);

    final updated = keyframes
        .where((item) => item.timeSec != safeTime)
        .toList();

    updated.add(kf.copyWith(timeSec: safeTime));

    return MotionKeyframeTrack(
      property: property,
      keyframes: updated,
    );
  }

  MotionKeyframeTrack removeAt(double timeSec) {
    if (!timeSec.isFinite) return this;

    final updated = keyframes
        .where((item) => item.timeSec != timeSec)
        .toList();

    if (updated.length == keyframes.length) {
      return this;
    }

    return MotionKeyframeTrack(
      property: property,
      keyframes: updated,
    );
  }

  MotionKeyframeTrack moveKeyframe(
    double fromTimeSec,
    double toTimeSec,
  ) {
    if (!fromTimeSec.isFinite || !toTimeSec.isFinite) {
      return this;
    }

    final int index = keyframes.indexWhere(
      (item) => item.timeSec == fromTimeSec,
    );

    if (index == -1) return this;

    final MotionTrackKeyframe original = keyframes[index];

    final double targetTime = math.max(0.0, toTimeSec);

    final moved = original.copyWith(
      timeSec: targetTime,
    );

    final updated = keyframes
        .where((item) =>
            item.timeSec != fromTimeSec &&
            item.timeSec != targetTime)
        .toList();

    updated.add(moved);

    return MotionKeyframeTrack(
      property: property,
      keyframes: updated,
    );
  }

  double valueAt(double timeSec) {
    if (keyframes.isEmpty) {
      return motionPropertyDefault(property);
    }

    if (timeSec.isNaN) {
      return keyframes.first.value;
    }

    if (timeSec <= keyframes.first.timeSec) {
      return keyframes.first.value;
    }

    if (timeSec >= keyframes.last.timeSec) {
      return keyframes.last.value;
    }

    for (int i = 0; i < keyframes.length - 1; i++) {
      final MotionTrackKeyframe a = keyframes[i];
      final MotionTrackKeyframe b = keyframes[i + 1];

      if (timeSec >= a.timeSec && timeSec <= b.timeSec) {
        final double duration = b.timeSec - a.timeSec;

        if (duration <= 0.0) return b.value;

        final double localT =
            (timeSec - a.timeSec) / duration;

        final double eased = applyMotionEasing(
          a.easing,
          localT,
        );

        return a.value + (b.value - a.value) * eased;
      }
    }

    return keyframes.last.value;
  }

  Map<String, Object?> toJson() {
    return {
      'property': property.name,
      'keyframes': keyframes
          .map((keyframe) => keyframe.toJson())
          .toList(),
    };
  }

  factory MotionKeyframeTrack.fromJson(
    Object? json,
    MotionProperty fallbackProperty,
  ) {
    if (json is! Map) {
      return MotionKeyframeTrack(
        property: fallbackProperty,
      );
    }

    final MotionProperty property =
        _parseMotionProperty(json['property']) ??
            fallbackProperty;

    final List<MotionTrackKeyframe> frames = [];

    final Object? rawFrames = json['keyframes'];

    if (rawFrames is List) {
      for (final item in rawFrames) {
        if (item is! Map) continue;

        // Invalid frame entries are skipped individually.
        final Object? rawTime = item['timeSec'];
        final Object? rawValue = item['value'];

        if (rawTime is! num || rawValue is! num) {
          continue;
        }

        final double time = rawTime.toDouble();
        final double value = rawValue.toDouble();

        if (!time.isFinite || !value.isFinite) {
          continue;
        }

        frames.add(MotionTrackKeyframe.fromJson(item));
      }
    }

    return MotionKeyframeTrack(
      property: property,
      keyframes: frames,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! MotionKeyframeTrack) return false;

    if (property != other.property ||
        keyframes.length != other.keyframes.length) {
      return false;
    }

    for (int i = 0; i < keyframes.length; i++) {
      if (keyframes[i] != other.keyframes[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      property,
      Object.hashAll(keyframes),
    );
  }

  @override
  String toString() {
    return 'MotionKeyframeTrack(property: ${property.name}, keyframes: $keyframes)';
  }
}

// ============================================================
// MOTION KEYFRAME SET
// ============================================================

class MotionKeyframeSet {
  final Map<MotionProperty, MotionKeyframeTrack> tracks;

  const MotionKeyframeSet.empty()
      : tracks = const {};

  MotionKeyframeSet([
    Map<MotionProperty, MotionKeyframeTrack> tracks = const {},
  ]) : tracks = Map<MotionProperty, MotionKeyframeTrack>.unmodifiable(
          _normalizeTracks(tracks),
        );

  static Map<MotionProperty, MotionKeyframeTrack> _normalizeTracks(
    Map<MotionProperty, MotionKeyframeTrack> input,
  ) {
    final Map<MotionProperty, MotionKeyframeTrack> result = {};

    for (final entry in input.entries) {
      if (entry.value.isEmpty) continue;

      result[entry.key] = MotionKeyframeTrack(
        property: entry.key,
        keyframes: entry.value.keyframes,
      );
    }

    return result;
  }

  MotionKeyframeTrack trackFor(MotionProperty p) {
    return tracks[p] ??
        MotionKeyframeTrack(property: p);
  }

  MotionKeyframeSet withTrack(MotionKeyframeTrack track) {
    final updated = Map<MotionProperty, MotionKeyframeTrack>.from(
      tracks,
    );

    if (track.isEmpty) {
      updated.remove(track.property);
    } else {
      updated[track.property] = MotionKeyframeTrack(
        property: track.property,
        keyframes: track.keyframes,
      );
    }

    return MotionKeyframeSet(updated);
  }

  Map<MotionProperty, double> valuesAt(double timeSec) {
    final Map<MotionProperty, double> result = {};

    for (final property in MotionProperty.values) {
      result[property] = trackFor(property).valueAt(timeSec);
    }

    return Map<MotionProperty, double>.unmodifiable(result);
  }

  Map<String, Object?> toJson() {
    final serialized = <String, Object?>{};

    for (final property in MotionProperty.values) {
      final track = tracks[property];

      if (track != null && !track.isEmpty) {
        serialized[property.name] = track.toJson();
      }
    }

    return {
      'tracks': serialized,
    };
  }

  factory MotionKeyframeSet.fromJson(Object? json) {
    if (json is! Map) {
      return const MotionKeyframeSet.empty();
    }

    final Object? rawTracks = json['tracks'];

    if (rawTracks is! Map) {
      return const MotionKeyframeSet.empty();
    }

    final Map<MotionProperty, MotionKeyframeTrack> parsed = {};

    for (final property in MotionProperty.values) {
      final Object? rawTrack = rawTracks[property.name];

      if (rawTrack == null) continue;

      final track = MotionKeyframeTrack.fromJson(
        rawTrack,
        property,
      );

      if (!track.isEmpty) {
        parsed[property] = track;
      }
    }

    return MotionKeyframeSet(parsed);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! MotionKeyframeSet) return false;

    if (tracks.length != other.tracks.length) {
      return false;
    }

    for (final entry in tracks.entries) {
      if (entry.value != other.tracks[entry.key]) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    final entries = tracks.entries.toList()
      ..sort(
        (a, b) => a.key.index.compareTo(b.key.index),
      );

    return Object.hashAll(
      entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    );
  }

  @override
  String toString() {
    return 'MotionKeyframeSet(tracks: $tracks)';
  }
}

// ============================================================
// GENERIC UNDO / REDO HISTORY
// ============================================================

class UndoHistory<T> {
  final int capacity;

  final List<T> _undoStack = [];
  final List<T> _redoStack = [];

  UndoHistory({
    int capacity = 100,
  }) : capacity = math.max(1, capacity);

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoDepth => _undoStack.length;

  int get redoDepth => _redoStack.length;

  void push(T state) {
    _undoStack.add(state);

    _redoStack.clear();

    while (_undoStack.length > capacity) {
      _undoStack.removeAt(0);
    }
  }

  T? undo(T current) {
    if (_undoStack.isEmpty) return null;

    _redoStack.add(current);

    return _undoStack.removeLast();
  }

  T? redo(T current) {
    if (_redoStack.isEmpty) return null;

    _undoStack.add(current);

    while (_undoStack.length > capacity) {
      _undoStack.removeAt(0);
    }

    return _redoStack.removeLast();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
