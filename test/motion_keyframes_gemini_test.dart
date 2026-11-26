// CHECK #8 — Gemini-supplied Motion Keyframes + Undo/Redo.
// Tests written against MASTER-PROMPT-MOTION-KEYFRAMES.txt contracts.
import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/motion/motion_keyframes.dart';

MotionTrackKeyframe kf(double t, double v, [MotionEasing e = MotionEasing.linear]) =>
    MotionTrackKeyframe(timeSec: t, value: v, easing: e);

MotionKeyframeTrack track(MotionProperty p, List<MotionTrackKeyframe> frames) =>
    MotionKeyframeTrack(property: p, keyframes: frames);

void main() {
  // ==========================================================
  // SPEC EXAMPLES — lafz-ba-lafz
  // ==========================================================
  group('SPEC EXAMPLES', () {
    test('(a) opacity track linear: valueAt(1)=0.5, (-1)=0.0, (5)=1.0', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      expect(t.valueAt(1), 0.5);
      expect(t.valueAt(-1), 0.0);
      expect(t.valueAt(5), 1.0);
    });

    test('(a2) first keyframe easing easeIn: valueAt(1)=0.25', () {
      final t = track(MotionProperty.opacity,
          [kf(0, 0.0, MotionEasing.easeIn), kf(2, 1.0)]);
      expect(t.valueAt(1), 0.25);
    });

    test('(b) moveKeyframe(2, 1) on keyframes at 0 and 2 -> times 0 and 1', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      final moved = t.moveKeyframe(2, 1);
      expect(moved.keyframes.map((k) => k.timeSec).toList(), [0.0, 1.0]);
      expect(moved.keyframes[1].value, 1.0);
    });

    test('(c) addOrReplace at an existing time replaces the value', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      final replaced = t.addOrReplace(kf(2, 0.7));
      expect(replaced.length, 2);
      expect(replaced.keyframes[1].timeSec, 2.0);
      expect(replaced.keyframes[1].value, 0.7);
    });

    test('(d) UndoHistory<int>: push 1,2 -> undo/redo sequence', () {
      final h = UndoHistory<int>();
      h.push(1);
      h.push(2);
      expect(h.undo(3), 2);
      expect(h.undo(2), 1);
      expect(h.undo(1), isNull);
      expect(h.redo(1), 2);
    });

    test('(e) bounceOut endpoints within 1e-9', () {
      expect(applyMotionEasing(MotionEasing.bounceOut, 0),
          closeTo(0.0, 1e-9));
      expect(applyMotionEasing(MotionEasing.bounceOut, 1),
          closeTo(1.0, 1e-9));
    });

    test('(e2) every easing stays inside [0,1] for t in [0,1] (sweep)', () {
      for (final easing in MotionEasing.values) {
        for (var i = 0; i <= 1000; i++) {
          final t = i / 1000;
          final out = applyMotionEasing(easing, t);
          expect(out.isFinite, isTrue, reason: '$easing at $t not finite');
          expect(out, greaterThanOrEqualTo(0.0),
              reason: '$easing at $t below 0: $out');
          expect(out, lessThanOrEqualTo(1.0),
              reason: '$easing at $t above 1: $out');
        }
      }
    });

    test('(e3) easeInOut(0.5)=0.5 and easeOut(0.5)=0.75', () {
      expect(applyMotionEasing(MotionEasing.easeInOut, 0.5), 0.5);
      expect(applyMotionEasing(MotionEasing.easeOut, 0.5), 0.75);
    });
  });

  // ==========================================================
  // PROPERTY DEFAULTS + EASING DETAILS
  // ==========================================================
  group('motionPropertyDefault', () {
    test('all five properties', () {
      expect(motionPropertyDefault(MotionProperty.opacity), 1.0);
      expect(motionPropertyDefault(MotionProperty.scale), 1.0);
      expect(motionPropertyDefault(MotionProperty.positionX), 0.0);
      expect(motionPropertyDefault(MotionProperty.positionY), 0.0);
      expect(motionPropertyDefault(MotionProperty.rotationDeg), 0.0);
    });
  });

  group('applyMotionEasing details', () {
    test('linear and easeIn values', () {
      expect(applyMotionEasing(MotionEasing.linear, 0.3), 0.3);
      expect(applyMotionEasing(MotionEasing.easeIn, 0.5), 0.25);
      expect(applyMotionEasing(MotionEasing.easeInOut, 0.25), 0.125);
    });

    test('t is clamped outside [0,1]', () {
      expect(applyMotionEasing(MotionEasing.linear, -1), 0.0);
      expect(applyMotionEasing(MotionEasing.linear, 2), 1.0);
      expect(applyMotionEasing(MotionEasing.easeIn, 5), 1.0);
    });

    test('NaN t does not throw and stays in range', () {
      final out = applyMotionEasing(MotionEasing.bounceOut, double.nan);
      expect(out.isFinite, isTrue);
      expect(out, inInclusiveRange(0.0, 1.0));
    });

    test('all easings hit exact endpoints 0 and 1', () {
      for (final easing in MotionEasing.values) {
        expect(applyMotionEasing(easing, 0), closeTo(0.0, 1e-9),
            reason: '$easing at 0');
        expect(applyMotionEasing(easing, 1), closeTo(1.0, 1e-9),
            reason: '$easing at 1');
      }
    });
  });

  // ==========================================================
  // TRACK NORMALIZATION
  // ==========================================================
  group('track normalization', () {
    test('unsorted input comes out sorted', () {
      final t = track(
          MotionProperty.opacity, [kf(2, 1.0), kf(0, 0.0), kf(1, 0.5)]);
      expect(t.keyframes.map((k) => k.timeSec).toList(), [0.0, 1.0, 2.0]);
    });

    test('duplicate time keeps the LAST in input order', () {
      final t =
          track(MotionProperty.opacity, [kf(1, 0.3), kf(0, 0.0), kf(1, 0.9)]);
      expect(t.length, 2);
      expect(t.keyframes[1].timeSec, 1.0);
      expect(t.keyframes[1].value, 0.9);
    });

    test('negative time clamps to 0', () {
      final t = track(MotionProperty.opacity, [kf(-3, 0.4)]);
      expect(t.keyframes.single.timeSec, 0.0);
      expect(t.keyframes.single.value, 0.4);
    });

    test('negative time colliding with 0: last input wins at 0', () {
      final t = track(MotionProperty.opacity, [kf(-1, 0.4), kf(0, 0.8)]);
      expect(t.length, 1);
      expect(t.keyframes.single.timeSec, 0.0);
      expect(t.keyframes.single.value, 0.8);
    });

    test('NaN / infinite keyframes are dropped', () {
      final t = track(MotionProperty.opacity, [
        kf(0, 0.0),
        kf(double.nan, 1.0),
        kf(double.infinity, 1.0),
        kf(1, double.nan),
        kf(2, double.infinity),
        kf(3, 1.0),
      ]);
      expect(t.keyframes.map((k) => k.timeSec).toList(), [0.0, 3.0]);
    });
  });

  // ==========================================================
  // TRACK OPERATIONS
  // ==========================================================
  group('addOrReplace / removeAt / moveKeyframe', () {
    test('addOrReplace inserts in sorted position', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      final added = t.addOrReplace(kf(1, 0.5));
      expect(added.keyframes.map((k) => k.timeSec).toList(), [0.0, 1.0, 2.0]);
      expect(added.keyframes[1].value, 0.5);
    });

    test('addOrReplace with non-finite time is a no-op (no throw)', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0)]);
      expect(t.addOrReplace(kf(double.nan, 1.0)), t);
      expect(t.addOrReplace(kf(double.infinity, 1.0)), t);
    });

    test('addOrReplace with NaN value must NOT delete the existing keyframe',
        () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      final result = t.addOrReplace(kf(2, double.nan));
      expect(result.length, 2);
      expect(result.keyframes[1].value, 1.0);
    });

    test('removeAt removes an existing keyframe', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      final removed = t.removeAt(0);
      expect(removed.length, 1);
      expect(removed.keyframes.single.timeSec, 2.0);
    });

    test('removeAt absent time is a no-op', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      expect(t.removeAt(7), t);
      expect(t.removeAt(double.nan), t);
    });

    test('moveKeyframe onto an occupied target replaces that keyframe', () {
      final t =
          track(MotionProperty.opacity, [kf(0, 0.0), kf(1, 0.5), kf(2, 1.0)]);
      final moved = t.moveKeyframe(0, 1);
      expect(moved.keyframes.map((k) => k.timeSec).toList(), [1.0, 2.0]);
      expect(moved.keyframes[0].value, 0.0);
    });

    test('moveKeyframe with absent from-time is a no-op', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      expect(t.moveKeyframe(9, 1), t);
      expect(t.moveKeyframe(double.nan, 1), t);
    });

    test('moveKeyframe to a negative target lands at 0', () {
      final t = track(MotionProperty.opacity, [kf(1, 0.5), kf(2, 1.0)]);
      final moved = t.moveKeyframe(2, -4);
      expect(moved.keyframes.map((k) => k.timeSec).toList(), [0.0, 1.0]);
      expect(moved.keyframes[0].value, 1.0);
    });

    test('moveKeyframe keeps the moved keyframe easing', () {
      final t = track(MotionProperty.opacity,
          [kf(0, 0.0), kf(2, 1.0, MotionEasing.easeIn)]);
      final moved = t.moveKeyframe(2, 3);
      expect(moved.keyframes[1].easing, MotionEasing.easeIn);
    });
  });

  // ==========================================================
  // valueAt
  // ==========================================================
  group('valueAt', () {
    test('empty track returns the property default', () {
      expect(track(MotionProperty.opacity, const []).valueAt(1.5), 1.0);
      expect(track(MotionProperty.scale, const []).valueAt(0), 1.0);
      expect(track(MotionProperty.positionX, const []).valueAt(0), 0.0);
      expect(track(MotionProperty.rotationDeg, const []).valueAt(3), 0.0);
    });

    test('single keyframe: its value everywhere', () {
      final t = track(MotionProperty.opacity, [kf(2, 0.4)]);
      expect(t.valueAt(0), 0.4);
      expect(t.valueAt(2), 0.4);
      expect(t.valueAt(99), 0.4);
    });

    test('exact keyframe times return exact values', () {
      final t =
          track(MotionProperty.opacity, [kf(0, 0.0), kf(1, 5.0), kf(2, 1.0)]);
      expect(t.valueAt(0), 0.0);
      expect(t.valueAt(1), 5.0);
      expect(t.valueAt(2), 1.0);
    });

    test('easing of the EARLIER keyframe applies, not the later one', () {
      // Segment 1 uses kf0.easeIn; segment 2 uses kf1.easeOut.
      final t = track(MotionProperty.opacity, [
        kf(0, 0.0, MotionEasing.easeIn),
        kf(1, 1.0, MotionEasing.easeOut),
        kf(2, 2.0, MotionEasing.linear),
      ]);
      expect(t.valueAt(0.5), 0.25); // easeIn(0.5)=0.25 -> 0 + 1*0.25
      expect(t.valueAt(1.5), 1.75); // easeOut(0.5)=0.75 -> 1 + 1*0.75
    });

    test('NaN time does not throw (observed: first keyframe value)', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.3), kf(2, 1.0)]);
      expect(t.valueAt(double.nan), 0.3);
    });
  });

  // ==========================================================
  // KEYFRAME SET
  // ==========================================================
  group('MotionKeyframeSet', () {
    test('empty set: valuesAt gives every property its default', () {
      const s = MotionKeyframeSet.empty();
      final values = s.valuesAt(1.0);
      expect(values.length, MotionProperty.values.length);
      for (final p in MotionProperty.values) {
        expect(values[p], motionPropertyDefault(p), reason: '$p');
      }
    });

    test('trackFor absent property returns an empty track for it', () {
      const s = MotionKeyframeSet.empty();
      final t = s.trackFor(MotionProperty.scale);
      expect(t.isEmpty, isTrue);
      expect(t.property, MotionProperty.scale);
    });

    test('withTrack stores a non-empty track; valuesAt uses it', () {
      const s0 = MotionKeyframeSet.empty();
      final s1 = s0.withTrack(
          track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]));
      expect(s1.trackFor(MotionProperty.opacity).length, 2);
      expect(s1.valuesAt(1)[MotionProperty.opacity], 0.5);
      expect(s1.valuesAt(1)[MotionProperty.scale], 1.0); // default
      expect(s0.trackFor(MotionProperty.opacity).isEmpty, isTrue);
    });

    test('withTrack with an empty track REMOVES the property', () {
      final s1 = const MotionKeyframeSet.empty().withTrack(
          track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]));
      final s2 =
          s1.withTrack(MotionKeyframeTrack(property: MotionProperty.opacity));
      expect(s2.tracks.containsKey(MotionProperty.opacity), isFalse);
      expect(s2, const MotionKeyframeSet.empty());
    });

    test('constructor drops empty tracks', () {
      final s = MotionKeyframeSet({
        MotionProperty.opacity: MotionKeyframeTrack(
            property: MotionProperty.opacity),
        MotionProperty.scale: track(MotionProperty.scale, [kf(0, 2.0)]),
      });
      expect(s.tracks.length, 1);
      expect(s.tracks.containsKey(MotionProperty.scale), isTrue);
    });

    test('constructor re-keys a mismatched track to the map key (observed)',
        () {
      final s = MotionKeyframeSet({
        MotionProperty.opacity: track(MotionProperty.scale, [kf(0, 0.5)]),
      });
      final stored = s.tracks[MotionProperty.opacity]!;
      expect(stored.property, MotionProperty.opacity);
      expect(stored.keyframes.single.value, 0.5);
    });

    test('set equality and hashCode ignore map insertion order', () {
      final a = MotionKeyframeSet({
        MotionProperty.opacity: track(MotionProperty.opacity, [kf(0, 0.0)]),
        MotionProperty.scale: track(MotionProperty.scale, [kf(0, 2.0)]),
      });
      final b = MotionKeyframeSet({
        MotionProperty.scale: track(MotionProperty.scale, [kf(0, 2.0)]),
        MotionProperty.opacity: track(MotionProperty.opacity, [kf(0, 0.0)]),
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('set inequality when a track differs', () {
      final a = const MotionKeyframeSet.empty()
          .withTrack(track(MotionProperty.opacity, [kf(0, 0.0)]));
      final b = const MotionKeyframeSet.empty()
          .withTrack(track(MotionProperty.opacity, [kf(0, 0.5)]));
      expect(a, isNot(b));
    });
  });

  // ==========================================================
  // JSON
  // ==========================================================
  group('JSON — MotionTrackKeyframe', () {
    test('roundtrip', () {
      final original = kf(1.5, 0.7, MotionEasing.easeInOut);
      expect(MotionTrackKeyframe.fromJson(original.toJson()), original);
    });

    test('bad input -> (0, 0, linear), never throws', () {
      const fallback = MotionTrackKeyframe(timeSec: 0, value: 0);
      expect(MotionTrackKeyframe.fromJson(null), fallback);
      expect(MotionTrackKeyframe.fromJson('garbage'), fallback);
      expect(MotionTrackKeyframe.fromJson(42), fallback);
      expect(MotionTrackKeyframe.fromJson(const []), fallback);
    });

    test('negative time clamps to 0; non-finite value -> 0', () {
      expect(MotionTrackKeyframe.fromJson({'timeSec': -5, 'value': 2}).timeSec, 0.0);
      expect(
          MotionTrackKeyframe.fromJson({'timeSec': 1, 'value': double.nan}).value,
          0.0);
      expect(
          MotionTrackKeyframe.fromJson({'timeSec': 1, 'value': double.infinity})
              .value,
          0.0);
    });

    test('wrong-typed fields fall back individually', () {
      final parsed =
          MotionTrackKeyframe.fromJson({'timeSec': 'x', 'value': 'y', 'easing': 9});
      expect(parsed, const MotionTrackKeyframe(timeSec: 0, value: 0));
    });
  });

  group('JSON — MotionKeyframeTrack', () {
    test('roundtrip', () {
      final original = track(MotionProperty.positionY,
          [kf(0, -1.0, MotionEasing.easeOut), kf(3, 2.0)]);
      final restored =
          MotionKeyframeTrack.fromJson(original.toJson(), MotionProperty.scale);
      expect(restored, original);
    });

    test('bad input -> empty track with the FALLBACK property', () {
      final restored =
          MotionKeyframeTrack.fromJson(null, MotionProperty.rotationDeg);
      expect(restored.isEmpty, isTrue);
      expect(restored.property, MotionProperty.rotationDeg);
      expect(MotionKeyframeTrack.fromJson('junk', MotionProperty.scale).property,
          MotionProperty.scale);
    });

    test('invalid property name in json -> fallback property used', () {
      final restored = MotionKeyframeTrack.fromJson(
          {'property': 'bogus', 'keyframes': []}, MotionProperty.positionX);
      expect(restored.property, MotionProperty.positionX);
    });

    test('bad frames are skipped individually, good ones survive', () {
      final restored = MotionKeyframeTrack.fromJson({
        'property': 'opacity',
        'keyframes': [
          {'timeSec': 0, 'value': 0.0, 'easing': 'linear'},
          {'timeSec': 'oops', 'value': 1.0}, // string time -> skip
          'not-a-map', // -> skip
          {'timeSec': 1, 'value': double.nan}, // NaN value -> skip
          {'timeSec': 2, 'value': 1}, // int value is a num -> keep
        ],
      }, MotionProperty.scale);
      expect(restored.property, MotionProperty.opacity);
      expect(restored.keyframes.map((k) => k.timeSec).toList(), [0.0, 2.0]);
      expect(restored.keyframes[1].value, 1.0);
    });

    test('keyframes not a list -> empty track, property still parsed', () {
      final restored = MotionKeyframeTrack.fromJson(
          {'property': 'scale', 'keyframes': 'nope'}, MotionProperty.opacity);
      expect(restored.property, MotionProperty.scale);
      expect(restored.isEmpty, isTrue);
    });
  });

  group('JSON — MotionKeyframeSet', () {
    test('roundtrip', () {
      final original = MotionKeyframeSet({
        MotionProperty.opacity: track(
            MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0, MotionEasing.easeIn)]),
        MotionProperty.rotationDeg:
            track(MotionProperty.rotationDeg, [kf(1, 45.0)]),
      });
      expect(MotionKeyframeSet.fromJson(original.toJson()), original);
    });

    test('bad input -> empty set, never throws', () {
      expect(MotionKeyframeSet.fromJson(null), const MotionKeyframeSet.empty());
      expect(MotionKeyframeSet.fromJson('junk'),
          const MotionKeyframeSet.empty());
      expect(MotionKeyframeSet.fromJson(const {}),
          const MotionKeyframeSet.empty());
      expect(MotionKeyframeSet.fromJson({'tracks': 'nope'}),
          const MotionKeyframeSet.empty());
      expect(MotionKeyframeSet.fromJson({'tracks': 42}),
          const MotionKeyframeSet.empty());
    });

    test('unknown track keys are ignored', () {
      final restored = MotionKeyframeSet.fromJson({
        'tracks': {
          'bogusProperty': {
            'property': 'bogusProperty',
            'keyframes': [
              {'timeSec': 0, 'value': 1}
            ],
          },
        },
      });
      expect(restored, const MotionKeyframeSet.empty());
    });
  });

  // ==========================================================
  // EQUALITY / HASHCODE
  // ==========================================================
  group('equality', () {
    test('keyframe equality and copyWith', () {
      expect(kf(1, 2, MotionEasing.easeIn), kf(1, 2, MotionEasing.easeIn));
      expect(kf(1, 2), isNot(kf(1, 3)));
      expect(kf(1, 2).hashCode, kf(1, 2).hashCode);
      expect(kf(1, 2).copyWith(value: 5), kf(1, 5));
      expect(kf(1, 2).copyWith(), kf(1, 2));
    });

    test('tracks built from different input orders are equal after normalize',
        () {
      final a = track(MotionProperty.opacity, [kf(2, 1.0), kf(0, 0.0)]);
      final b = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(track(MotionProperty.scale, [kf(0, 0.0), kf(2, 1.0)])));
    });
  });

  // ==========================================================
  // IMMUTABILITY
  // ==========================================================
  group('immutability', () {
    test('track keyframes list is unmodifiable', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0)]);
      expect(() => t.keyframes.add(kf(1, 1.0)), throwsUnsupportedError);
    });

    test('mutating the source list after construction does not leak in', () {
      final source = [kf(0, 0.0)];
      final t = track(MotionProperty.opacity, source);
      source.add(kf(1, 1.0));
      expect(t.length, 1);
    });

    test('addOrReplace leaves the receiver untouched', () {
      final t = track(MotionProperty.opacity, [kf(0, 0.0), kf(2, 1.0)]);
      t.addOrReplace(kf(1, 0.5));
      expect(t.length, 2);
      expect(t.keyframes.map((k) => k.timeSec).toList(), [0.0, 2.0]);
    });

    test('set tracks map is unmodifiable; source map mutation does not leak',
        () {
      final source = <MotionProperty, MotionKeyframeTrack>{
        MotionProperty.opacity: track(MotionProperty.opacity, [kf(0, 0.0)]),
      };
      final s = MotionKeyframeSet(source);
      expect(
          () => s.tracks[MotionProperty.scale] =
              track(MotionProperty.scale, [kf(0, 1.0)]),
          throwsUnsupportedError);
      source[MotionProperty.scale] =
          track(MotionProperty.scale, [kf(0, 1.0)]);
      expect(s.tracks.length, 1);
    });
  });

  // ==========================================================
  // UNDO HISTORY
  // ==========================================================
  group('UndoHistory', () {
    test('spec semantics: canRedo after undo; redo returns the current', () {
      final h = UndoHistory<String>();
      h.push('A');
      h.push('B');
      expect(h.undo('C'), 'B');
      expect(h.canRedo, isTrue);
      expect(h.redo('B'), 'C');
    });

    test('push after undo clears the redo stack', () {
      final h = UndoHistory<int>();
      h.push(1);
      h.push(2);
      expect(h.undo(3), 2);
      expect(h.canRedo, isTrue);
      h.push(9);
      expect(h.canRedo, isFalse);
      expect(h.redo(9), isNull);
    });

    test('undo/redo on empty history return null, never throw', () {
      final h = UndoHistory<int>();
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
      expect(h.undo(1), isNull);
      expect(h.redo(1), isNull);
    });

    test('capacity 2: oldest state drops after 3 pushes', () {
      final h = UndoHistory<int>(capacity: 2);
      h.push(1);
      h.push(2);
      h.push(3);
      expect(h.undoDepth, 2);
      expect(h.undo(99), 3);
      expect(h.undo(3), 2);
      expect(h.undo(2), isNull); // 1 was dropped
    });

    test('capacity 0 behaves as capacity 1', () {
      final h = UndoHistory<int>(capacity: 0);
      h.push(1);
      h.push(2);
      expect(h.undoDepth, 1);
      expect(h.undo(9), 2);
      expect(h.undo(2), isNull);
    });

    test('clear() empties both stacks', () {
      final h = UndoHistory<int>();
      h.push(1);
      h.push(2);
      h.undo(3);
      h.clear();
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
      expect(h.undoDepth, 0);
      expect(h.undo(1), isNull);
    });

    test('full round trip: undo to the bottom, redo back to the top', () {
      final h = UndoHistory<String>();
      h.push('A');
      h.push('B');
      expect(h.undo('C'), 'B');
      expect(h.undo('B'), 'A');
      expect(h.undo('A'), isNull);
      expect(h.redo('A'), 'B');
      expect(h.redo('B'), 'C');
      expect(h.canRedo, isFalse);
      expect(h.undoDepth, 2);
    });
  });
}
