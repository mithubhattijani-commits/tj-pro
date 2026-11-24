// Throwaway render-verification dumper (Build 3) — writes the
// exact filter graphs / commands the app builds into /tmp/build3
// so the system ffmpeg can render them for frame-grab evidence.
// Not part of the shipped test suite's assertions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/pro_editor.dart';

void main() {
  test('dump build3 graphs', () {
    final dir = Directory('/tmp/build3/graphs')..createSync(recursive: true);
    void dump(String name, String content) =>
        File('${dir.path}/$name').writeAsStringSync(content);

    // (a) Title/sticker keyframes: red PNG 360x120 over a black
    // 1280x720 base, 6 s window, bottom-right -> top-left + fade.
    dump(
      'overlay_graph.txt',
      keyframeOverlayFilter(
        baseLabel: '[0:v]',
        overlayLabel: '[1:v]',
        track: const KeyframeTrack(
          start: ProKeyframe(timeSec: 0, xNorm: 0.85, yNorm: 0.85, opacity: 1),
          end: ProKeyframe(timeSec: 6, xNorm: 0.1, yNorm: 0.1, opacity: 0.3),
        ),
        videoW: 1280,
        videoH: 720,
        overlayW: 360,
        overlayH: 120,
        outLabel: '[vout]',
      ),
    );

    // (b) PIP keyframes: blue inset 640x360 source scaled to the
    // _pipScale 0.3 box (384x216), same travel + fade.
    dump(
      'pip_graph.txt',
      keyframedPipFilter(
        baseLabel: '[0:v]',
        pipLabel: '[1:v]',
        track: const KeyframeTrack(
          start: ProKeyframe(timeSec: 0, xNorm: 0.85, yNorm: 0.85, opacity: 1),
          end: ProKeyframe(timeSec: 6, xNorm: 0.1, yNorm: 0.1, opacity: 0.4),
        ),
        videoW: 1280,
        videoH: 720,
        pipW: 384,
        pipH: 216,
        outLabel: '[vout]',
      ),
    );

    // (c) Main-clip mask: full command (paths filled for the
    // render test's own media).
    dump(
      'mask_cmd.txt',
      mainClipMaskCommand(
        input: '/tmp/build3/media/colour.mp4',
        maskPng: '/tmp/build3/media/circle_mask.png',
        width: 640,
        height: 360,
        output: '/tmp/build3/media/masked.mp4',
      ),
    );

    // (e) Frame-rate graphs (the -vf the single-clip path builds).
    for (final fps in [24, 30, 60]) {
      dump(
        'single_fps$fps.txt',
        FfmpegService.finalFilterGraph(
          speed: 1,
          filterPreset: 'Normal',
          aspect: 'Original',
          fps: fps,
        ),
      );
    }

    // (d) Custom ramp thirds 0.5 / 1 / 2 over a 6 s clip.
    dump(
      'ramp_graph.txt',
      rampSetpts(const [
        RampSegment(tStart: 0, tEnd: 2, speed: 0.5),
        RampSegment(tStart: 2, tEnd: 4, speed: 1),
        RampSegment(tStart: 4, tEnd: 6, speed: 2),
      ]),
    );

    // (g) PIP keyframes + mask: the full command exactly as the
    // editor's export builds it after the termination fix — the
    // mask PNG is a SINGLE-frame input (no `-loop 1`); the alpha
    // chain's framesync filters repeat its frame and the pass ends
    // with the base video.
    final pipMaskGraph = keyframedPipFilter(
      baseLabel: '[0:v]',
      pipLabel: '[1:v]',
      track: const KeyframeTrack(
        start: ProKeyframe(timeSec: 0, xNorm: 0.7, yNorm: 0.7, opacity: 1),
        end: ProKeyframe(timeSec: 4, xNorm: 0.05, yNorm: 0.05, opacity: 0.4),
      ),
      videoW: 640,
      videoH: 360,
      pipW: 320,
      pipH: 180,
      outLabel: '[vout]',
      hasMask: true,
    );
    dump(
      'pip_mask_cmd.txt',
      "-y -i '/tmp/build3/media/colour.mp4' "
      "-i '/tmp/build3/media/blue.mp4' "
      "-i '/tmp/build3/media/circle_mask.png' "
      '-filter_complex "$pipMaskGraph" -map "[vout]" -map 0:a? '
      '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
      "-movflags +faststart '/tmp/build3/media/pip_mask_out.mp4'",
    );

    // (f) Long-clip keyframe pass (45 s) for the timing measure.
    dump(
      'overlay_long_graph.txt',
      keyframeOverlayFilter(
        baseLabel: '[0:v]',
        overlayLabel: '[1:v]',
        track: const KeyframeTrack(
          start: ProKeyframe(timeSec: 0, xNorm: 0.85, yNorm: 0.85, opacity: 1),
          end: ProKeyframe(timeSec: 45, xNorm: 0.1, yNorm: 0.1, opacity: 0.3),
        ),
        videoW: 1280,
        videoH: 720,
        overlayW: 360,
        overlayH: 120,
        outLabel: '[vout]',
      ),
    );
  });
}
