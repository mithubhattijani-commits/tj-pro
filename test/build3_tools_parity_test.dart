// Build 3 (Master Plan Phase 3) — tools parity tests.
//
// Pins the Phase 3 contracts:
//  * keyframePoseAt is the exact Dart mirror of the FFmpeg keyframe
//    lerp (window clamp + the four easing shapes), so the stage
//    preview and the export render the SAME motion.
//  * keyframedPipFilter builds the PIP keyframe graph (position +
//    opacity lerps, mask composed through the alpha chain).
//  * mainClipMaskCommand builds the main-clip mask pass.
//  * The export frame rate threads through finalFilterGraph /
//    singleClipCommand / finalPassCommand — and the default graph
//    stays byte-identical for every pre-Build-3 caller.
//  * SpeedRampMath is the one geometry behind the ramp graph's
//    painter and its drag handler.

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/pro_editor.dart';
import 'package:tj_pro/services/pro_vision.dart';
import 'package:tj_pro/video/editor_stage.dart';

void main() {
  group('keyframePoseAt — preview mirror of the export lerp', () {
    const track = KeyframeTrack(
      start: ProKeyframe(
        timeSec: 2,
        xNorm: 0.1,
        yNorm: 0.2,
        scale: 0.5,
        opacity: 0.25,
        rotationDeg: -90,
      ),
      end: ProKeyframe(
        timeSec: 6,
        xNorm: 0.9,
        yNorm: 0.8,
        scale: 2,
        opacity: 1,
        rotationDeg: 90,
      ),
    );

    test('endpoints return the two poses exactly', () {
      final a = keyframePoseAt(track, 2, KeyframeEasing.linear);
      expect(a.xNorm, 0.1);
      expect(a.yNorm, 0.2);
      expect(a.scale, 0.5);
      expect(a.opacity, 0.25);
      expect(a.rotationDeg, -90);
      final b = keyframePoseAt(track, 6, KeyframeEasing.linear);
      expect(b.xNorm, 0.9);
      expect(b.yNorm, 0.8);
      expect(b.scale, 2);
      expect(b.opacity, 1);
      expect(b.rotationDeg, 90);
    });

    test('outside the window the nearest pose holds', () {
      expect(keyframePoseAt(track, 0, KeyframeEasing.linear).xNorm, 0.1);
      expect(keyframePoseAt(track, 99, KeyframeEasing.linear).xNorm, 0.9);
    });

    test('linear midpoint is the plain average of every field', () {
      final m = keyframePoseAt(track, 4, KeyframeEasing.linear);
      expect(m.xNorm, closeTo(0.5, 1e-9));
      expect(m.yNorm, closeTo(0.5, 1e-9));
      expect(m.scale, closeTo(1.25, 1e-9));
      expect(m.opacity, closeTo(0.625, 1e-9));
      expect(m.rotationDeg, closeTo(0, 1e-9));
    });

    test('easing shapes match the FFmpeg factor algebra', () {
      // f = 0.5 at t = 4: easeIn squares it, easeOut mirrors it,
      // easeInOut smoothsteps it — the same shapes _easedFactor
      // emits for the export expressions.
      expect(
        keyframePoseAt(track, 4, KeyframeEasing.easeIn).xNorm,
        closeTo(0.1 + 0.8 * 0.25, 1e-9),
      );
      expect(
        keyframePoseAt(track, 4, KeyframeEasing.easeOut).xNorm,
        closeTo(0.1 + 0.8 * 0.75, 1e-9),
      );
      expect(
        keyframePoseAt(track, 4, KeyframeEasing.easeInOut).xNorm,
        closeTo(0.1 + 0.8 * 0.5, 1e-9),
      );
    });

    test('zero-duration track resolves to the end pose', () {
      const flat = KeyframeTrack(
        start: ProKeyframe(timeSec: 3, xNorm: 0.2, yNorm: 0.2),
        end: ProKeyframe(timeSec: 3, xNorm: 0.8, yNorm: 0.8),
      );
      expect(keyframePoseAt(flat, 3, KeyframeEasing.linear).xNorm, 0.8);
    });
  });

  group('keyframedPipFilter — the PIP keyframe graph', () {
    const track = KeyframeTrack(
      start: ProKeyframe(timeSec: 0, xNorm: 0.7, yNorm: 0.7, opacity: 1),
      end: ProKeyframe(timeSec: 8, xNorm: 0.05, yNorm: 0.05, opacity: 0.4),
    );
    final plain = keyframedPipFilter(
      baseLabel: '[0:v]',
      pipLabel: '[1:v]',
      track: track,
      videoW: 1280,
      videoH: 720,
      pipW: 384,
      pipH: 216,
      outLabel: '[vout]',
    );

    test('scales the inset and lerps position over the base size', () {
      expect(plain, contains('scale=384:216'));
      expect(plain, contains("overlay=x='"));
      expect(plain, contains(')*1280'));
      expect(plain, contains(')*720'));
      expect(plain, contains('[vout]'));
    });

    test('opacity rides the geq alpha multiply (arbitrary lerp)', () {
      expect(plain, contains("geq=r='r(X,Y)'"));
      // alpha(X,Y) is the accessor FFmpeg accepts (verified by the
      // Build 3 render tests; the a(X,Y) short form is rejected).
      expect(plain, contains("a='alpha(X,Y)*("));
    });

    test('without a mask the alpha passes straight through', () {
      expect(plain, contains('[pa0]null[pa]'));
      expect(plain, contains('alphamerge'));
    });

    test('with a mask the mask gray multiplies the alpha', () {
      final masked = keyframedPipFilter(
        baseLabel: '[0:v]',
        pipLabel: '[1:v]',
        track: track,
        videoW: 1280,
        videoH: 720,
        pipW: 384,
        pipH: 216,
        outLabel: '[vout]',
        hasMask: true,
      );
      expect(masked, contains('[2:v] scale=384:216,format=gray[mg]'));
      expect(masked, contains('blend=all_mode=multiply'));
    });

    test('easing reshapes the position factor', () {
      final eased = keyframedPipFilter(
        baseLabel: '[0:v]',
        pipLabel: '[1:v]',
        track: track,
        videoW: 1280,
        videoH: 720,
        pipW: 384,
        pipH: 216,
        outLabel: '[vout]',
        easing: KeyframeEasing.easeInOut,
      );
      // smoothstep 3f^2-2f^3 appears in the expression.
      expect(eased, contains('(3-2*('));
    });
  });

  group('mainClipMaskCommand — the main-clip mask pass', () {
    final cmd = mainClipMaskCommand(
      input: '/tmp/in.mp4',
      maskPng: '/tmp/mask.png',
      width: 640,
      height: 360,
      output: '/tmp/out.mp4',
    );

    test('mask single-frame in, multiplied into alpha, over black', () {
      // Termination contract (Build 3 render-test fix): a looped
      // mask input never reaches EOF and the framesync blend then
      // generates frames forever — the command must NOT loop it.
      expect(cmd.contains('-loop 1'), isFalse);
      expect(cmd, contains('alphaextract'));
      expect(cmd, contains('blend=all_mode=multiply'));
      expect(cmd, contains('alphamerge'));
      expect(cmd, contains('color=c=black:s=640x360:r=30'));
      expect(cmd, contains('format=yuv420p[vout]'));
      expect(cmd, contains('/tmp/out.mp4'));
    });
  });

  group('export frame rate threading', () {
    test('default graph is unchanged (no fps filter)', () {
      final g = FfmpegService.finalFilterGraph(
        speed: 1,
        filterPreset: 'Normal',
        aspect: 'Original',
      );
      expect(g.contains('fps='), isFalse);
      expect(g.endsWith('format=yuv420p'), isTrue);
    });

    test('fps lands just before the format conversion', () {
      for (final fps in [24, 30, 60]) {
        final g = FfmpegService.finalFilterGraph(
          speed: 1,
          filterPreset: 'Normal',
          aspect: 'Original',
          fps: fps,
        );
        expect(g, contains('fps=$fps,format=yuv420p'));
      }
    });

    test('single-clip and final-pass commands pass fps through', () {
      final single = FfmpegService.singleClipCommand(
        input: 'in.mp4',
        trimStart: 0,
        trimEnd: 5,
        speed: 1,
        filterPreset: 'Normal',
        aspect: 'Original',
        output: 'out.mp4',
        fps: 60,
      );
      expect(single, contains('fps=60'));
      final fin = FfmpegService.finalPassCommand(
        input: 'in.mp4',
        speed: 1,
        filterPreset: 'Normal',
        aspect: 'Original',
        output: 'out.mp4',
        fps: 24,
      );
      expect(fin, contains('fps=24'));
      final legacy = FfmpegService.finalPassCommand(
        input: 'in.mp4',
        speed: 1,
        filterPreset: 'Normal',
        aspect: 'Original',
        output: 'out.mp4',
      );
      expect(legacy.contains('fps='), isFalse);
    });
  });

  group('SpeedRampMath — painter/drag shared geometry', () {
    test('y round-trips through speed at the graph height', () {
      for (final s in [0.25, 0.5, 1.0, 1.5, 2.0]) {
        final y = SpeedRampMath.yForSpeed(s, 72);
        expect(SpeedRampMath.speedForY(y, 72), closeTo(s, 1e-9));
      }
    });

    test('drag speeds clamp to the point range', () {
      expect(SpeedRampMath.speedForY(-100, 72), SpeedRampMath.maxSpeed);
      expect(SpeedRampMath.speedForY(1000, 72), SpeedRampMath.minSpeed);
    });

    test('thirds split the width; centres sit mid-plateau', () {
      expect(SpeedRampMath.thirdForX(0, 300), 0);
      expect(SpeedRampMath.thirdForX(100, 300), 1);
      expect(SpeedRampMath.thirdForX(299, 300), 2);
      expect(SpeedRampMath.thirdForX(-5, 300), 0);
      expect(SpeedRampMath.centreX(0, 300), 50);
      expect(SpeedRampMath.centreX(1, 300), 150);
      expect(SpeedRampMath.centreX(2, 300), 250);
    });
  });

  group('rampSetpts — seconds math over timebase PTS', () {
    test('expression reads PTS*TB and converts back with /TB', () {
      // Render-verified (Build 3): setpts receives PTS in input
      // timebase units; comparing raw PTS against second constants
      // sent every frame into the last branch (a 0.5/1/2 ramp over
      // 6 s rendered 3.07 s instead of 7 s).
      final g = rampSetpts(const [
        RampSegment(tStart: 0, tEnd: 2, speed: 0.5),
        RampSegment(tStart: 2, tEnd: 4, speed: 1),
        RampSegment(tStart: 4, tEnd: 6, speed: 2),
      ]);
      expect(g, startsWith("setpts='("));
      expect(g, contains('(PTS*TB)'));
      expect(g, endsWith(")/TB'"));
      expect(g, contains('if(lt((PTS*TB),2)'));
      expect(g, contains('if(lt((PTS*TB),4)'));
    });

    test('empty segment list stays the identity', () {
      expect(rampSetpts(const []), 'setpts=PTS');
    });
  });

  group('keyframeOverlayFilter — the mechanism Phase 3 builds on', () {
    test('the title/sticker graph keeps its documented shape', () {
      final f = keyframeOverlayFilter(
        baseLabel: '[0:v]',
        overlayLabel: '[1:v]',
        track: const KeyframeTrack(
          start: ProKeyframe(timeSec: 0, xNorm: 0.5, yNorm: 0.5),
          end: ProKeyframe(timeSec: 5, xNorm: 0.1, yNorm: 0.1, opacity: 0.5),
        ),
        videoW: 720,
        videoH: 1280,
        overlayW: 360,
        overlayH: 120,
        outLabel: '[vout]',
      );
      expect(f, contains('zoompan'));
      expect(f, contains('rotate'));
      expect(f, contains("geq=r='r(X,Y)'"));
      expect(f, contains("overlay=x='"));
      expect(f, contains('[vout]'));
      // The overlay image is looped (-loop 1, infinite): without
      // shortest=1 the pass never terminates (Build 3 render tests).
      expect(f, contains(':shortest=1[vout]'));
    });

    test('every looped-image overlay graph carries shortest=1', () {
      // Motion titles — all three graph shapes.
      for (final preset in ['fadeIn', 'slideLeft', 'zoomPop']) {
        final f = animatedTitleFilter(
          baseLabel: '[0:v]',
          overlayLabel: '[1:v]',
          t: ProMotionTitle(text: 'T', preset: preset),
          videoW: 1280,
          videoH: 720,
          overlayW: 360,
          overlayH: 120,
          outLabel: '[vout]',
        );
        expect(f, contains(':shortest=1[vout]'), reason: preset);
      }
      // Tracked sticker — centred, single-point and lerped shapes.
      for (final track in <List<TrackPoint>>[
        const [],
        const [TrackPoint(timeSec: 0, xNorm: 0.5, yNorm: 0.5)],
        const [
          TrackPoint(timeSec: 0, xNorm: 0.2, yNorm: 0.2),
          TrackPoint(timeSec: 4, xNorm: 0.8, yNorm: 0.8),
        ],
      ]) {
        final f = trackOverlayFilter(
          track: track,
          baseLabel: '[0:v]',
          overlayLabel: '[1:v]',
          videoW: 1280,
          videoH: 720,
          overlayW: 100,
          overlayH: 100,
          outLabel: '[vout]',
        );
        expect(f, contains(':shortest=1[vout]'));
      }
    });
  });
}
