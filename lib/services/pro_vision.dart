/// Pro vision + audio services for TJ Pro v2.1.0 ("Pro Editor").
///
/// NEW FILE — owned by the vision/audio workstream. No new pub dependencies:
/// everything here uses only packages the app already has (ffmpeg_kit_flutter_new
/// incl. FFprobeKit, google_mlkit_* via [AiService], and package:image).
///
/// ## What lives here
///
/// * [ProVisionService.removeVideoBackground] — per-frame ML Kit segmentation
///   -> grayscale mask video -> alphamerge composite onto a colour/image
///   background.
/// * [ProVisionService.trackObject] + [ProVisionService.trackOverlayFilter] —
///   pure-Dart normalized-cross-correlation template tracking, plus a
///   filter_complex snippet that makes an overlay follow the track.
/// * [ProVisionService.detectBeats] + [ProVisionService.beatSegments] +
///   [ProVisionService.beatCutCommand] — energy-onset beat detection and a
///   single-filter_complex hard cut at beat times.
/// * [ProVisionService.waveformPng] — showwavespic timeline strip.
///
/// ## Failure + progress contract (whole file)
///
/// * Heavy operations report live progress: [removeVideoBackground] reports
///   overall progress 0..1 through `onProgress` (segmentation drives 0–70%,
///   mask-video encoding 70–85%, compositing 85–100%) together with step text
///   via `onStep` (`'Frames…'`, `'Mask video…'`, `'Compositing…'`, in that
///   order). [trackObject] reports frames processed / total frames.
/// * Nothing here silently fakes a result. On failure these methods throw an
///   [Exception] with a plain message, so the UI can keep the previous output
///   and tell the user what went wrong. The two deliberate non-error null/empty
///   results are: [detectBeats] returns an empty list when no beats are found
///   (including inputs with no usable audio), and [waveformPng] returns null
///   when the input has no audio stream.
/// * Exports use the project baseline: libx264, preset veryfast, crf 23.
///
/// ## Honest limits — video background removal
///
/// * Processing time scales with the number of sampled frames: expect roughly
///   seconds-per-frame on a phone (per-frame segmenter setup + ML Kit
///   inference + PNG work), so a long clip takes minutes. Lower `sampleFps`
///   for long clips.
/// * The cutout pass is capped at 480 px wide (the `width` parameter is
///   clamped to at most 480 and to an even value). The final composite is
///   still full-resolution: the low-res mask is scaled up to the original
///   frame, so cutout edges are softer than a full-res pass would give.
/// * The mask video is built at the sampled frame rate and then held up to
///   the source frame rate (see [_maskVideoFpsNote] in
///   [ProVisionService.removeVideoBackground]): between two sampled frames
///   the mask does not move — it holds the last sampled mask. Fast motion
///   therefore shows a stepwise mask; raise `sampleFps` if the subject moves
///   fast (at the cost of processing time).
/// * Fast motion, fine hair/fur, and low light degrade the mask. A frame
///   whose segmentation fails reuses the previous frame's mask instead of
///   crashing the job; if the very first frame fails there is no previous
///   mask, so the job throws.
/// * The subject model may fetch once via Google Play services on first use
///   (per AiService docs); afterwards it works offline.
///
/// ## Honest limits — motion tracking
///
/// * Distinctive, slow-moving objects track well. Fast motion (the object
///   moves more than the ±40 px search window between sampled frames),
///   occlusion, and textureless/flat objects degrade tracking. The fallback
///   is: hold the last position while the match is weak, then linearly
///   interpolate between the surrounding good points, then smooth with a
///   3-point moving average. A held/interpolated point is a guess, not a
///   measurement — the UI should not present it as a confident lock.
/// * Tracking runs on frames downscaled to `width` (default 360 px), so
///   sub-pixel accuracy at full resolution is not promised; normalized
///   coordinates transfer to any output size because the aspect ratio is
///   preserved by the scale filter.
///
/// ## Honest limits — beat detection
///
/// * This is energy-onset beat detection, NOT a full beat tracker: it finds
///   sudden rises in audio energy. It works best on strong rhythmic music
///   and degrades on soft/ambient tracks, speech, and tracks with a steady
///   drone (few or no onsets, or onsets that are not the beat). Manual
///   override is supported by design: the UI may pass any subset of the
///   detected beats to [beatSegments]/[beatCutCommand].
/// * [waveformPng] renders a bright cyan waveform on a dark (black)
///   background via showwavespic, which offers no transparency option — so
///   the strip is dark-background, not transparent. It suits a dark timeline.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:image/image.dart' as img;

import 'ai_service.dart';
import 'ffmpeg_service.dart';

/// One tracked point: the object's centre at [timeSec], in normalized
/// coordinates (0..1 across the frame width/height). Normalized coordinates
/// are resolution-independent: multiply by the output size to get pixels.
class TrackPoint {
  const TrackPoint({
    required this.timeSec,
    required this.xNorm,
    required this.yNorm,
  });

  final double timeSec;
  final double xNorm;
  final double yNorm;

  @override
  String toString() =>
      'TrackPoint(t=${timeSec.toStringAsFixed(2)}, '
      'x=${xNorm.toStringAsFixed(3)}, y=${yNorm.toStringAsFixed(3)})';
}

/// One beat-cut segment: the half-open interval [start, end) in seconds.
class BeatSegment {
  const BeatSegment({required this.start, required this.end});

  final double start;
  final double end;

  double get duration => end - start;

  @override
  String toString() =>
      'BeatSegment(${start.toStringAsFixed(3)}–${end.toStringAsFixed(3)})';
}

/// Probe result for one input file. [fps] falls back to 30 when the container
/// does not report a usable frame rate; [durationSec] is null when the
/// duration cannot be determined.
class _ProbeInfo {
  const _ProbeInfo({required this.fps, required this.durationSec});

  final double fps;
  final double? durationSec;
}

/// Pro vision + audio operations. All methods are static so callers never
/// construct state; every method validates its arguments and throws a plain
/// [Exception] on failure (see the file header for the contract).
class ProVisionService {
  // -------------------------------------------------------------------------
  // 1. Video auto background remover
  // -------------------------------------------------------------------------

  /// Remove the background of [input] video and composite the subject onto
  /// a new background. Returns the output mp4 path inside [workDir].
  ///
  /// [backgroundKind] is `'color'` or `'image'`:
  /// * `'color'` — [backgroundColor] is required, a hex colour such as
  ///   `'#00FF00'`, `'00FF00'`, or `'0x00FF00'`.
  /// * `'image'` — [backgroundImagePath] is required and must exist; it is
  ///   scaled to cover the video frame.
  ///
  /// Pipeline: (a) FFmpeg extracts frames at [sampleFps] scaled to [width]
  /// (clamped to at most 480 and to an even value); (b) each frame is
  /// segmented with [AiService.segmentSubject] and turned into a grayscale
  /// mask PNG (white = foreground) with a manual 3x3 box-blur feather — a
  /// frame that fails segmentation reuses the previous frame's mask, and
  /// only a first-frame failure throws; (c) the mask PNGs are encoded to a
  /// mask video at the source frame rate (see the fps note below); (d) the
  /// original video + mask video are combined with alphamerge and overlaid
  /// onto the background. Original audio is copied untouched.
  ///
  /// Fps note (mask video): the mask PNGs exist only at [sampleFps], but
  /// alphamerge needs a mask frame for every source frame, so the mask
  /// video is encoded from the sampled images at [sampleFps] and then run
  /// through an `fps=<sourceFps>` filter, which *holds* each mask frame
  /// until the next sampled mask. The mask therefore steps, rather than
  /// interpolating, between samples. The final output is additionally
  /// capped to the probed source duration (or `-shortest` when the duration
  /// is unknown) so an infinite colour/image background cannot make the
  /// encode run forever.
  static Future<String> removeVideoBackground({
    required String input,
    required String backgroundKind,
    String? backgroundColor,
    String? backgroundImagePath,
    required Directory workDir,
    double sampleFps = 2.0,
    int width = 480,
    void Function(double progress)? onProgress,
    void Function(String step)? onStep,
  }) async {
    if (sampleFps <= 0) {
      throw Exception('Sample rate must be above 0 (got $sampleFps).');
    }
    if (width < 2) {
      throw Exception('Cutout width must be at least 2 (got $width).');
    }
    // Cutout pass capped at 480 px wide, even value (libx264 yuv420p needs
    // even dimensions for the mask video).
    var cutW = math.min(width, 480);
    cutW -= cutW % 2;
    if (cutW < 2) {
      throw Exception('Cutout width must be at least 2 (got $width).');
    }
    final kind = backgroundKind.trim().toLowerCase();
    String? colorSpec;
    if (kind == 'color') {
      if (backgroundColor == null || backgroundColor.trim().isEmpty) {
        throw Exception(
          'A background colour is required for backgroundKind "color".',
        );
      }
      colorSpec = _normalizeHexColor(backgroundColor);
    } else if (kind == 'image') {
      if (backgroundImagePath == null || backgroundImagePath.isEmpty) {
        throw Exception(
          'A background image path is required for backgroundKind "image".',
        );
      }
      if (!File(backgroundImagePath).existsSync()) {
        throw Exception(
          'Background image not found: $backgroundImagePath',
        );
      }
    } else {
      throw Exception(
        'Unknown backgroundKind "$backgroundKind" '
        '(expected "color" or "image").',
      );
    }

    if (!workDir.existsSync()) workDir.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final jobDir = Directory('${workDir.path}/pro_vision_bg_$stamp');
    jobDir.createSync(recursive: true);
    final framesDir = Directory('${jobDir.path}/frames')..createSync();
    final masksDir = Directory('${jobDir.path}/masks')..createSync();
    final outputPath = '${workDir.path}/bg_removed_$stamp.mp4';

    try {
      // Source frame rate + duration drive the mask-video fps filter, the
      // FFmpeg progress mapping, and the output duration cap.
      final probe = await _probeVideo(input);
      final sourceFps = probe.fps;
      final durationMs = probe.durationSec == null
          ? null
          : (probe.durationSec! * 1000).round();

      // (a) Extract sampled frames.
      onStep?.call('Frames…');
      final framePattern = '${framesDir.path}/frame_%05d.png';
      final extractCmd = '-y -i ${FfmpegService.q(input)} '
          '-vf "fps=$sampleFps,scale=$cutW:-2" '
          '${FfmpegService.q(framePattern)}';
      final extract = await FfmpegService.run(extractCmd);
      if (!extract.ok) {
        throw Exception(
          'Could not extract frames from this video. ${extract.logs}',
        );
      }
      final frames = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (frames.isEmpty) {
        throw Exception('Could not extract any frames from this video.');
      }

      // (b) Segment each frame -> feathered grayscale mask PNG. A failed
      // frame reuses the previous mask file's bytes; only a first-frame
      // failure throws (there is nothing honest to reuse).
      Uint8List? previousMaskBytes;
      for (var i = 0; i < frames.length; i++) {
        Uint8List maskBytes;
        try {
          final mask = await AiService.segmentSubject(frames[i]);
          final frameBytes = await frames[i].readAsBytes();
          final frameImg = img.decodeImage(frameBytes);
          if (frameImg == null) {
            throw Exception('Could not read frame ${i + 1}.');
          }
          maskBytes = _maskPngBytes(
            mask: mask,
            frameWidth: frameImg.width,
            frameHeight: frameImg.height,
          );
        } catch (e) {
          if (previousMaskBytes == null) {
            throw Exception(
              'Background removal failed on the first frame: $e '
              'Try a clip with a clearer subject.',
            );
          }
          maskBytes = previousMaskBytes;
        }
        previousMaskBytes = maskBytes;
        final maskFile = File(
          '${masksDir.path}/mask_${i.toString().padLeft(5, '0')}.png',
        );
        await maskFile.writeAsBytes(maskBytes);
        // Segmentation drives 0–70% of overall progress.
        onProgress?.call(0.70 * (i + 1) / frames.length);
      }

      // (c) Mask PNGs -> mask video at the source frame rate. The PNGs are
      // numbered from 0 by us, so -start_number 0 is explicit (image2
      // numbering defaults are easy to get wrong). The fps filter holds
      // each sampled mask until the next sample.
      onStep?.call('Mask video…');
      final maskVideoPath = '${jobDir.path}/mask.mp4';
      final maskPattern = '${masksDir.path}/mask_%05d.png';
      final maskCmd = '-y -start_number 0 -framerate $sampleFps '
          '-i ${FfmpegService.q(maskPattern)} '
          '-vf "fps=$sourceFps,format=yuv420p" '
          '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p '
          '${FfmpegService.q(maskVideoPath)}';
      final maskRun = await FfmpegService.run(
        maskCmd,
        expectedMs: durationMs,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(0.70 + 0.15 * p),
      );
      if (!maskRun.ok) {
        throw Exception('Could not build the mask video. ${maskRun.logs}');
      }

      // (d) Composite: scale the mask up to the original frame (scale2ref),
      // cut the subject out with alphamerge, scale the background to the
      // cutout, overlay. Audio is copied; the output is capped to the
      // source duration when known, else -shortest.
      onStep?.call('Compositing…');
      final bgInput = kind == 'color'
          ? '-f lavfi -i color=c=$colorSpec:s=1280x720 '
          : '-loop 1 -i ${FfmpegService.q(backgroundImagePath!)} ';
      final durationArg = probe.durationSec == null
          ? '-shortest '
          : '-t ${probe.durationSec!.toStringAsFixed(3)} ';
      final compositeCmd = '-y -i ${FfmpegService.q(input)} '
          '-i ${FfmpegService.q(maskVideoPath)} '
          '$bgInput'
          '-filter_complex "'
          '[0:v]format=yuv420p[main];'
          '[1:v][main]scale2ref[maskS][mainS];'
          '[mainS][maskS]alphamerge[cut];'
          '[2:v][cut]scale2ref[bgS][cutS];'
          '[bgS][cutS]overlay=0:0[vtmp];'
          '[vtmp]format=yuv420p[vout]" '
          '-map "[vout]" -map 0:a? '
          '$durationArg'
          '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p '
          '-c:a copy -movflags +faststart ${FfmpegService.q(outputPath)}';
      final composite = await FfmpegService.run(
        compositeCmd,
        expectedMs: durationMs,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(0.85 + 0.15 * p),
      );
      if (!composite.ok) {
        throw Exception(
          'Could not composite the new background. ${composite.logs}',
        );
      }
      final outFile = File(outputPath);
      if (!outFile.existsSync() || outFile.lengthSync() == 0) {
        throw Exception('Background removal finished but produced no file.');
      }
      onProgress?.call(1.0);
      // Intermediates are phone storage; remove them on success. On failure
      // they are left in place for diagnosis (the exception above skips this).
      try {
        jobDir.deleteSync(recursive: true);
      } catch (_) {}
      return outputPath;
    } catch (_) {
      // No output file is produced on failure, so the UI keeps the previous
      // output. Intermediates are left under workDir/pro_vision_bg_*.
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // 2. Motion tracking (template matching, no new dependency)
  // -------------------------------------------------------------------------

  /// Track the object under the tap point ([startXNorm], [startYNorm],
  /// normalized 0..1) through [videoPath] and return one [TrackPoint] per
  /// sampled frame (time = frame index / [sampleFps]).
  ///
  /// Method: FFmpeg extracts frames at [sampleFps] scaled to [width]
  /// (default 360 px); a 48x48 px template patch is cut from the first frame
  /// around the tap point; each later frame is searched with normalized
  /// cross-correlation (NCC) in a ±40 px window around the last position, on
  /// grayscale frames, using summed-area tables for the window mean/variance
  /// and a coarse step-2 pass refined at step 1 around the coarse best. The
  /// best match is accepted only at NCC >= 0.7, otherwise the last position
  /// is held. Afterwards, held runs between two good points are linearly
  /// interpolated, and all positions are smoothed with a 3-point moving
  /// average. Coordinates are normalized by the sampled frame size, which
  /// equals the full-video aspect ratio.
  static Future<List<TrackPoint>> trackObject({
    required String videoPath,
    required double startXNorm,
    required double startYNorm,
    required Directory workDir,
    double sampleFps = 2.0,
    int width = 360,
    void Function(double progress)? onProgress,
  }) async {
    if (sampleFps <= 0) {
      throw Exception('Sample rate must be above 0 (got $sampleFps).');
    }
    if (width < 16) {
      throw Exception('Tracking width must be at least 16 (got $width).');
    }
    if (!workDir.existsSync()) workDir.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final framesDir =
        Directory('${workDir.path}/pro_vision_track_$stamp')..createSync();

    try {
      final extractCmd = '-y -i ${FfmpegService.q(videoPath)} '
          '-vf "fps=$sampleFps,scale=$width:-1" '
          '${FfmpegService.q('${framesDir.path}/frame_%05d.png')}';
      final extract = await FfmpegService.run(extractCmd);
      if (!extract.ok) {
        throw Exception(
          'Could not extract frames for tracking. ${extract.logs}',
        );
      }
      final frames = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (frames.isEmpty) {
        throw Exception('Could not extract any frames for tracking.');
      }

      // First frame: grayscale + template patch around the tap point.
      final first = _decodeGray(await frames[0].readAsBytes());
      if (first == null) {
        throw Exception('Could not read the first frame for tracking.');
      }
      final fw = first.width;
      final fh = first.height;
      const patchSize = 48;
      final patchW = math.min(patchSize, fw);
      final patchH = math.min(patchSize, fh);
      var centerX = (startXNorm.clamp(0.0, 1.0) * fw).round();
      var centerY = (startYNorm.clamp(0.0, 1.0) * fh).round();
      var tplLeft = (centerX - patchW ~/ 2).clamp(0, fw - patchW);
      var tplTop = (centerY - patchH ~/ 2).clamp(0, fh - patchH);
      final template = _cropGray(first, tplLeft, tplTop, patchW, patchH);
      final templateStats = _meanStd(template);
      final templateFlat = templateStats.$2 < 1e-3;

      // Raw positions (template top-left) + whether each is a good match.
      final lefts = <int>[tplLeft];
      final tops = <int>[tplTop];
      final good = <bool>[true];
      var lastLeft = tplLeft;
      var lastTop = tplTop;

      for (var i = 1; i < frames.length; i++) {
        final gray = _decodeGray(await frames[i].readAsBytes());
        if (gray == null || templateFlat) {
          // Unreadable frame, or a textureless template (NCC undefined):
          // hold the last position, per the documented fallback.
          lefts.add(lastLeft);
          tops.add(lastTop);
          good.add(false);
        } else {
          final found = _nccSearchWithDims(
            gray: gray,
            template: template,
            patchW: patchW,
            patchH: patchH,
            templateMean: templateStats.$1,
            templateStd: templateStats.$2,
            lastLeft: lastLeft,
            lastTop: lastTop,
            window: 40,
          );
          if (found != null && found.$3 >= 0.7) {
            lastLeft = found.$1;
            lastTop = found.$2;
            good.add(true);
          } else {
            good.add(false);
          }
          lefts.add(lastLeft);
          tops.add(lastTop);
        }
        onProgress?.call((i + 1) / frames.length);
      }

      // Linear interpolation across held runs bounded by good points.
      // (Leading/trailing holds stay held — there is nothing to
      // interpolate from.)
      final interpX = List<double>.generate(
        lefts.length,
        (i) => lefts[i] + patchW / 2,
      );
      final interpY = List<double>.generate(
        tops.length,
        (i) => tops[i] + patchH / 2,
      );
      var i = 0;
      while (i < lefts.length) {
        if (good[i]) {
          i++;
          continue;
        }
        final runStart = i;
        while (i < lefts.length && !good[i]) {
          i++;
        }
        final runEnd = i; // first good index after the run, or length.
        if (runStart > 0 && runEnd < lefts.length) {
          final x0 = interpX[runStart - 1];
          final x1 = interpX[runEnd];
          final y0 = interpY[runStart - 1];
          final y1 = interpY[runEnd];
          final span = runEnd - runStart + 1;
          for (var k = runStart; k < runEnd; k++) {
            final t = (k - runStart + 1) / span;
            interpX[k] = x0 + (x1 - x0) * t;
            interpY[k] = y0 + (y1 - y0) * t;
          }
        }
      }

      // 3-point moving average smoothing (endpoints use their neighbours).
      final smoothX = List<double>.filled(interpX.length, 0);
      final smoothY = List<double>.filled(interpY.length, 0);
      for (var k = 0; k < interpX.length; k++) {
        final a = interpX[k > 0 ? k - 1 : k];
        final b = interpX[k];
        final c = interpX[k < interpX.length - 1 ? k + 1 : k];
        smoothX[k] = (a + b + c) / 3;
        final ay = interpY[k > 0 ? k - 1 : k];
        final by = interpY[k];
        final cy = interpY[k < interpY.length - 1 ? k + 1 : k];
        smoothY[k] = (ay + by + cy) / 3;
      }

      final track = <TrackPoint>[];
      for (var k = 0; k < smoothX.length; k++) {
        track.add(TrackPoint(
          timeSec: k / sampleFps,
          xNorm: (smoothX[k] / fw).clamp(0.0, 1.0),
          yNorm: (smoothY[k] / fh).clamp(0.0, 1.0),
        ));
      }
      onProgress?.call(1.0);
      try {
        framesDir.deleteSync(recursive: true);
      } catch (_) {}
      return track;
    } catch (_) {
      rethrow;
    }
  }

  /// Build a filter_complex snippet that overlays the overlay input on top
  /// of the base input so the overlay *follows* [track].
  ///
  /// Label convention: [baseLabel], [overlayLabel], and [outLabel] are the
  /// bare label names WITHOUT brackets (for example `'0:v'`, `'1:v'`,
  /// `'vout'`); brackets are added here. [videoW]/[videoH] are the base
  /// video size in pixels; [overlayW]/[overlayH] are the overlay's size in
  /// pixels *after any scaling the caller applied* (the overlay is centred
  /// on each track point, then clamped inside the frame).
  ///
  /// Between two consecutive track points the position is linearly
  /// interpolated with nested `if(lt(t, …), …, …)` expressions on `t`
  /// (FFmpeg's timeline time in seconds); before the first point the first
  /// position is used, after the last point the last position is used.
  /// The x/y expressions are single-quoted inside the snippet, so the
  /// snippet must sit inside a double-quoted `-filter_complex` argument.
  /// When [track] is empty, a plain centred overlay snippet is returned.
  static String trackOverlayFilter({
    required List<TrackPoint> track,
    required String baseLabel,
    required String overlayLabel,
    required int videoW,
    required int videoH,
    required int overlayW,
    required int overlayH,
    required String outLabel,
  }) {
    // The editor passes bracketed labels ('[0:v]'); this builder adds
    // its own brackets, so strip any the caller already added.
    String bare(String l) => l.startsWith('[') && l.endsWith(']')
        ? l.substring(1, l.length - 1)
        : l;
    final base = bare(baseLabel);
    final ov = bare(overlayLabel);
    final out = bare(outLabel);
    String centred() =>
        '[$base][$ov]overlay=x=(W-w)/2:y=(H-h)/2[$out]';
    if (track.isEmpty) return centred();
    if (track.length == 1) {
      final x = _clampPos(
        track[0].xNorm * videoW - overlayW / 2,
        videoW - overlayW,
      );
      final y = _clampPos(
        track[0].yNorm * videoH - overlayH / 2,
        videoH - overlayH,
      );
      return '[$base][$ov]overlay='
          "x='${_num(x)}':y='${_num(y)}'[$out]";
    }
    // Pixel centres for each track point.
    final xs = track
        .map((p) => p.xNorm * videoW - overlayW / 2)
        .toList(growable: false);
    final ys = track
        .map((p) => p.yNorm * videoH - overlayH / 2)
        .toList(growable: false);
    final times =
        track.map((p) => p.timeSec).toList(growable: false);
    String lerpExpr(List<double> values) {
      // innermost else = last value; wrap outwards so each segment is
      // if(lt(t, t[i+1]), lerp(i -> i+1), <rest>).
      var expr = _num(values.last);
      for (var idx = times.length - 2; idx >= 0; idx--) {
        final t0 = times[idx];
        final t1 = times[idx + 1];
        final v0 = values[idx];
        final v1 = values[idx + 1];
        final dt = t1 - t0;
        final seg = dt <= 0
            ? _num(v0)
            : '${_num(v0)}+(${_num(v1)}-${_num(v0)})'
                '*(t-${_num(t0)})/${_num(dt)}';
        expr = 'if(lt(t,${_num(t1)}),$seg,$expr)';
      }
      return expr;
    }

    final maxX = math.max(0, videoW - overlayW).toDouble();
    final maxY = math.max(0, videoH - overlayH).toDouble();
    final xExpr = 'min(max(${lerpExpr(xs)},0),${_num(maxX)})';
    final yExpr = 'min(max(${lerpExpr(ys)},0),${_num(maxY)})';
    return '[$base][$ov]overlay='
        "x='$xExpr':y='$yExpr'[$out]";
  }

  // -------------------------------------------------------------------------
  // 3. Beat detection + beat-cut
  // -------------------------------------------------------------------------

  /// Detect beat times (seconds) in [input]'s audio. Returns an empty list
  /// when no beats are found — including inputs with no usable audio stream
  /// — never an error for that case.
  ///
  /// Method: FFmpeg decodes the audio to 16 kHz mono raw s16le PCM; Dart
  /// computes an RMS energy envelope (100 ms window, 50 ms hop); an onset
  /// is the positive part of the energy difference between consecutive
  /// windows; beats are local onset maxima above
  /// `median + 2 * MAD` (median absolute deviation), with a minimum
  /// distance of 0.25 s between beats (forward greedy scan). This is
  /// energy-onset detection, not a full beat tracker — see the file header.
  static Future<List<double>> detectBeats({
    required String input,
    required Directory workDir,
  }) async {
    if (!workDir.existsSync()) workDir.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final pcmPath = '${workDir.path}/pro_vision_beats_$stamp.pcm';
    try {
      final decodeCmd = '-y -i ${FfmpegService.q(input)} '
          '-vn -ac 1 -ar 16000 -f s16le ${FfmpegService.q(pcmPath)}';
      final decoded = await FfmpegService.run(decodeCmd);
      final pcmFile = File(pcmPath);
      if (!decoded.ok || !pcmFile.existsSync()) return <double>[];
      final bytes = await pcmFile.readAsBytes();
      if (bytes.length < 2) return <double>[];
      final sampleCount = bytes.length ~/ 2;
      final pcm = ByteData.sublistView(bytes);

      const sampleRate = 16000;
      const window = 1600; // 100 ms.
      const hop = 800; // 50 ms.
      if (sampleCount < window) return <double>[];
      final windowCount = (sampleCount - window) ~/ hop + 1;
      final energy = List<double>.filled(windowCount, 0);
      for (var w = 0; w < windowCount; w++) {
        final start = w * hop;
        var sumSq = 0.0;
        for (var s = 0; s < window; s++) {
          final v = pcm.getInt16((start + s) * 2, Endian.little) / 32768.0;
          sumSq += v * v;
        }
        energy[w] = math.sqrt(sumSq / window);
      }
      // Onsets: positive energy differences (onset[0] = 0 by definition).
      final onset = List<double>.filled(windowCount, 0);
      for (var w = 1; w < windowCount; w++) {
        onset[w] = math.max(0.0, energy[w] - energy[w - 1]);
      }
      final median = _median(onset);
      final deviations = onset.map((o) => (o - median).abs()).toList();
      final mad = _median(deviations);
      const k = 2.0;
      final threshold = median + k * mad;

      const minDistanceSec = 0.25;
      final beats = <double>[];
      var lastBeat = -minDistanceSec;
      for (var w = 1; w < windowCount - 1; w++) {
        final o = onset[w];
        if (o <= threshold) continue;
        if (o < onset[w - 1] || o < onset[w + 1]) continue; // local max.
        final t = (w * hop + window ~/ 2) / sampleRate;
        if (t - lastBeat < minDistanceSec) continue;
        beats.add(t);
        lastBeat = t;
      }
      return beats;
    } finally {
      try {
        final f = File(pcmPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Segment boundaries for [beats] inside a clip of [duration] seconds:
  /// `[0, beat1, beat2, …, duration]`, with beats outside (0, duration)
  /// dropped, sorted, and de-duplicated so no segment is shorter than
  /// 0.05 s. With no usable beats this returns the single segment
  /// `[0, duration]`. Accepts any subset of detected beats (manual override).
  static List<BeatSegment> beatSegments(
    List<double> beats,
    double duration,
  ) {
    if (duration <= 0) {
      throw Exception('Clip duration must be above 0 (got $duration).');
    }
    final bounds = <double>[0.0];
    final sorted = beats.where((b) => b > 0 && b < duration).toList()
      ..sort();
    for (final b in sorted) {
      if (b - bounds.last >= 0.05) bounds.add(b);
    }
    if (duration - bounds.last >= 0.05) {
      bounds.add(duration);
    } else {
      bounds[bounds.length - 1] = duration;
    }
    final segments = <BeatSegment>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      segments.add(BeatSegment(start: bounds[i], end: bounds[i + 1]));
    }
    return segments;
  }

  /// Full FFmpeg command string that hard-cuts [input] at [beats] inside a
  /// clip of [clipDurationSec] seconds and writes [output].
  ///
  /// CHOSEN APPROACH: a single filter_complex command on one input
  /// (split/trim/setpts/concat for video, asplit/atrim/asetpts/concat for
  /// audio), exactly as specified — no intermediate segment files for the
  /// caller to trim and re-concat. Segment boundaries come from
  /// [beatSegments], so any subset of beats (manual override) works.
  /// With no usable beats the command is a plain single-pass re-encode of
  /// the whole clip (same codec settings), not a filter graph.
  ///
  /// Precondition: the input must have an audio stream, because the audio
  /// chain maps `0:a`. Beat-cutting is a music-sync operation, so in
  /// practice the input that produced beats satisfies this; a silent input
  /// fails at FFmpeg with its own error, surfaced by the caller's
  /// [FfmpegService.run] result.
  static String beatCutCommand({
    required String input,
    required List<double> beats,
    required double clipDurationSec,
    required String output,
  }) {
    final segments = beatSegments(beats, clipDurationSec);
    final encode =
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
        '-movflags +faststart ${FfmpegService.q(output)}';
    if (segments.length == 1) {
      return '-y -i ${FfmpegService.q(input)} $encode';
    }
    final n = segments.length;
    final buf = StringBuffer();
    buf.write('-y -i ${FfmpegService.q(input)} -filter_complex "');
    buf.write('[0:v]split=$n');
    for (var i = 0; i < n; i++) {
      buf.write('[v$i]');
    }
    buf.write(';');
    for (var i = 0; i < n; i++) {
      final s = segments[i];
      buf.write(
        '[v$i]trim=start=${_num(s.start)}:end=${_num(s.end)},'
        'setpts=PTS-STARTPTS[vs$i];',
      );
    }
    buf.write('[0:a]asplit=$n');
    for (var i = 0; i < n; i++) {
      buf.write('[a$i]');
    }
    buf.write(';');
    for (var i = 0; i < n; i++) {
      final s = segments[i];
      buf.write(
        '[a$i]atrim=start=${_num(s.start)}:end=${_num(s.end)},'
        'asetpts=PTS-STARTPTS[as$i];',
      );
    }
    for (var i = 0; i < n; i++) {
      buf.write('[vs$i]');
    }
    buf.write('concat=n=$n:v=1:a=0[vc];');
    for (var i = 0; i < n; i++) {
      buf.write('[as$i]');
    }
    buf.write('concat=n=$n:v=0:a=1[ac];');
    buf.write('[vc]format=yuv420p[vout]" ');
    buf.write('-map "[vout]" -map "[ac]" ');
    buf.write(encode);
    return buf.toString();
  }

  // -------------------------------------------------------------------------
  // 4. Waveform
  // -------------------------------------------------------------------------

  /// Render a waveform PNG strip of [input]'s audio to [output] with
  /// FFmpeg showwavespic (bright cyan `0x00E5FF` on a dark/black background,
  /// suited to a dark timeline strip). Returns the [output] path, or null
  /// when the input has no audio stream (not an error). When the probe
  /// cannot determine the streams, a render is attempted and any failure
  /// also yields null; when the probe confirms audio exists but rendering
  /// fails, an [Exception] is thrown so a real failure is not hidden.
  static Future<String?> waveformPng({
    required String input,
    required String output,
    int width = 720,
    int height = 120,
  }) async {
    if (width <= 0 || height <= 0) {
      throw Exception('Waveform size must be positive (got $width x $height).');
    }
    var hasAudio = true;
    var probeCertain = false;
    try {
      final session = await FFprobeKit.getMediaInformation(input);
      final info = session.getMediaInformation();
      if (info != null) {
        probeCertain = true;
        hasAudio = info.getStreams().any((s) => s.getType() == 'audio');
      }
    } catch (_) {
      // Probe unavailable: fall through and attempt the render.
    }
    if (probeCertain && !hasAudio) return null;
    final cmd = '-y -i ${FfmpegService.q(input)} '
        '-filter_complex "[0:a]showwavespic=s=${width}x$height:colors=0x00E5FF[waves]" '
        '-map "[waves]" -frames:v 1 ${FfmpegService.q(output)}';
    final run = await FfmpegService.run(cmd);
    final outFile = File(output);
    if (!run.ok || !outFile.existsSync() || outFile.lengthSync() == 0) {
      if (probeCertain && hasAudio) {
        throw Exception('Could not render the waveform. ${run.logs}');
      }
      return null;
    }
    return output;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Probe [input] for its video frame rate and duration. Never throws:
  /// any probe failure yields 30 fps and an unknown duration, and callers
  /// degrade gracefully (mask video at 30 fps, `-shortest` output cap).
  static Future<_ProbeInfo> _probeVideo(String input) async {
    try {
      final session = await FFprobeKit.getMediaInformation(input);
      final info = session.getMediaInformation();
      if (info == null) return const _ProbeInfo(fps: 30, durationSec: null);
      final durationSec = double.tryParse(info.getDuration() ?? '');
      double fps = 30;
      for (final stream in info.getStreams()) {
        if (stream.getType() != 'video') continue;
        final parsed = _parseFps(stream.getAverageFrameRate());
        if (parsed != null && parsed > 0) fps = parsed;
        break;
      }
      return _ProbeInfo(fps: fps, durationSec: durationSec);
    } catch (_) {
      return const _ProbeInfo(fps: 30, durationSec: null);
    }
  }

  /// Parse an FFmpeg frame-rate string such as `'30/1'` or `'30000/1001'`.
  /// Returns null for `'0/0'`, unparsable, or non-positive values.
  static double? _parseFps(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den != 0) {
        final fps = num / den;
        if (fps > 0 && fps.isFinite) return fps;
      }
      return null;
    }
    final fps = double.tryParse(raw);
    if (fps != null && fps > 0 && fps.isFinite) return fps;
    return null;
  }

  /// Normalize a user hex colour to FFmpeg's `0xRRGGBB` form. Accepts
  /// `'#RRGGBB'`, `'RRGGBB'`, `'0xRRGGBB'`, and 3-digit `'RGB'` (expanded).
  static String _normalizeHexColor(String raw) {
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.toLowerCase().startsWith('0x')) hex = hex.substring(2);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex);
    if (!valid) {
      throw Exception(
        'Invalid background colour "$raw" (expected hex like #00FF00).',
      );
    }
    return '0x${hex.toUpperCase()}';
  }

  /// Build a feathered grayscale mask PNG (RGBA bytes: grey in RGB, opaque
  /// alpha; white = foreground) for [mask] mapped onto a frame of
  /// [frameWidth] x [frameHeight]. Mapping is nearest-neighbour, mirroring
  /// photo_pipeline's applySegmentationMask pattern, so a mask whose
  /// dimensions differ from the frame (selfie fallback) still lands on the
  /// right pixels. Feathering is a manual 3x3 box blur (no blur API
  /// assumed): each pixel becomes the mean of its 3x3 neighbourhood with
  /// edge pixels replicated.
  static Uint8List _maskPngBytes({
    required MaskResult mask,
    required int frameWidth,
    required int frameHeight,
  }) {
    if (mask.confidences.length != mask.width * mask.height ||
        mask.width <= 0 ||
        mask.height <= 0) {
      throw Exception('Segmentation mask has an unexpected size.');
    }
    final gray = List<int>.filled(frameWidth * frameHeight, 0);
    for (var y = 0; y < frameHeight; y++) {
      final my = (y * mask.height ~/ frameHeight).clamp(0, mask.height - 1);
      for (var x = 0; x < frameWidth; x++) {
        final mx = (x * mask.width ~/ frameWidth).clamp(0, mask.width - 1);
        final conf = mask.confidences[my * mask.width + mx].clamp(0.0, 1.0);
        gray[y * frameWidth + x] = (conf * 255).round();
      }
    }
    final feathered = _boxBlur3x3(gray, frameWidth, frameHeight);
    final rgba = Uint8List(frameWidth * frameHeight * 4);
    for (var i = 0; i < feathered.length; i++) {
      final v = feathered[i];
      rgba[i * 4] = v;
      rgba[i * 4 + 1] = v;
      rgba[i * 4 + 2] = v;
      rgba[i * 4 + 3] = 255;
    }
    final image = img.Image.fromBytes(
      width: frameWidth,
      height: frameHeight,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodePng(image);
  }

  /// Manual 3x3 box blur over row-major grayscale ints, edge-replicated.
  /// Pure Dart, no image-package blur API assumed.
  static List<int> _boxBlur3x3(List<int> src, int w, int h) {
    final out = List<int>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0;
        // Always 9 samples: out-of-range neighbours replicate the edge
        // pixel (clamped indices), so edges are not darkened.
        for (var yy = y - 1; yy <= y + 1; yy++) {
          final sy = yy.clamp(0, h - 1);
          final row = sy * w;
          for (var xx = x - 1; xx <= x + 1; xx++) {
            sum += src[row + xx.clamp(0, w - 1)];
          }
        }
        out[y * w + x] = sum ~/ 9;
      }
    }
    return out;
  }

  /// Decode an image file's bytes to a grayscale image, or null when the
  /// bytes do not decode. Uses the same decode/convert/getBytes pattern as
  /// photo_pipeline (proven in this repo).
  static _GrayImage? _decodeGray(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final rgba = decoded.convert(numChannels: 4);
    final data = rgba.getBytes(order: img.ChannelOrder.rgba);
    final gray = Float64List(decoded.width * decoded.height);
    for (var i = 0; i < gray.length; i++) {
      final r = data[i * 4].toDouble();
      final g = data[i * 4 + 1].toDouble();
      final b = data[i * 4 + 2].toDouble();
      gray[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }
    return _GrayImage(
      gray: gray,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static List<double> _cropGray(
    _GrayImage src,
    int left,
    int top,
    int w,
    int h,
  ) {
    final out = List<double>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[y * w + x] = src.gray[(top + y) * src.width + (left + x)];
      }
    }
    return out;
  }

  /// Mean + population standard deviation of [values].
  static (double, double) _meanStd(List<double> values) {
    if (values.isEmpty) return (0.0, 0.0);
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    var varSum = 0.0;
    for (final v in values) {
      final d = v - mean;
      varSum += d * d;
    }
    return (mean, math.sqrt(varSum / values.length));
  }

  /// NCC template search. Returns (left, top, score) of the best match, or
  /// null when no candidate position is valid. Coarse step-2 scan in the
  /// ±[window] px box around ([lastLeft], [lastTop]), then a step-1
  /// refinement within ±2 px of the coarse best. Window mean/variance come
  /// from summed-area tables, so each candidate costs one patch
  /// cross-correlation, not a full patch mean/variance recomputation.
  static (int, int, double)? _nccSearchWithDims({
    required _GrayImage gray,
    required List<double> template,
    required int patchW,
    required int patchH,
    required double templateMean,
    required double templateStd,
    required int lastLeft,
    required int lastTop,
    required int window,
  }) {
    final w = gray.width;
    final h = gray.height;
    if (patchW > w || patchH > h || template.length != patchW * patchH) {
      return null;
    }
    // Summed-area tables for gray and gray^2 (size (w+1) x (h+1)).
    final stride = w + 1;
    final sum = Float64List(stride * (h + 1));
    final sumSq = Float64List(stride * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0;
      var rowSumSq = 0.0;
      for (var x = 0; x < w; x++) {
        final v = gray.gray[y * w + x];
        rowSum += v;
        rowSumSq += v * v;
        final idx = (y + 1) * stride + (x + 1);
        sum[idx] = sum[y * stride + (x + 1)] + rowSum;
        sumSq[idx] = sumSq[y * stride + (x + 1)] + rowSumSq;
      }
    }

    double windowSum(Float64List table, int left, int top) {
      final x0 = left;
      final y0 = top;
      final x1 = left + patchW;
      final y1 = top + patchH;
      return table[y1 * stride + x1] -
          table[y0 * stride + x1] -
          table[y1 * stride + x0] +
          table[y0 * stride + x0];
    }

    double nccAt(int left, int top) {
      final n = patchW * patchH;
      final mean = windowSum(sum, left, top) / n;
      final meanSq = windowSum(sumSq, left, top) / n;
      var variance = meanSq - mean * mean;
      if (variance < 0) variance = 0;
      final std = math.sqrt(variance);
      if (std < 1e-3) return -1; // Flat candidate: undefined correlation.
      var cross = 0.0;
      for (var y = 0; y < patchH; y++) {
        final row = (top + y) * w + left;
        final tRow = y * patchW;
        for (var x = 0; x < patchW; x++) {
          cross += (template[tRow + x] - templateMean) *
              (gray.gray[row + x] - mean);
        }
      }
      return cross / (n * templateStd * std);
    }

    (int, int, double) scan(int cx, int cy, int radius, int step) {
      var bestLeft = cx;
      var bestTop = cy;
      var bestScore = -2.0;
      final minLeft = math.max(0, cx - radius);
      final maxLeft = math.min(w - patchW, cx + radius);
      final minTop = math.max(0, cy - radius);
      final maxTop = math.min(h - patchH, cy + radius);
      for (var top = minTop; top <= maxTop; top += step) {
        for (var left = minLeft; left <= maxLeft; left += step) {
          final score = nccAt(left, top);
          if (score > bestScore) {
            bestScore = score;
            bestLeft = left;
            bestTop = top;
          }
        }
      }
      // Step-2 scans can skip the exact centre; always evaluate it too.
      if (step > 1) {
        final score = nccAt(cx.clamp(0, w - patchW), cy.clamp(0, h - patchH));
        if (score > bestScore) {
          bestScore = score;
          bestLeft = cx.clamp(0, w - patchW);
          bestTop = cy.clamp(0, h - patchH);
        }
      }
      return (bestLeft, bestTop, bestScore);
    }

    final coarse = scan(lastLeft, lastTop, window, 2);
    final refined = scan(coarse.$1, coarse.$2, 2, 1);
    return refined;
  }

  /// Median of [values] (0 for an empty list). Sorts a copy.
  static double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Clamp a pixel position into [0, max] (max already floored at 0 by the
  /// caller where the overlay can exceed the frame).
  static double _clampPos(double value, int max) =>
      value.clamp(0.0, math.max(0, max).toDouble());

  /// Short FFmpeg-expression number: up to 3 decimals, no trailing zeros.
  static String _num(double value) {
    if (value == value.truncateToDouble()) return value.truncate().toString();
    var text = value.toStringAsFixed(3);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }
}

/// Grayscale frame for tracking: row-major [gray] values 0..255.
class _GrayImage {
  const _GrayImage({
    required this.gray,
    required this.width,
    required this.height,
  });

  final Float64List gray;
  final int width;
  final int height;
}

// ---------------------------------------------------------------------------
// Top-level forwarders (added at assembly). The editor screen calls these
// unqualified, matching the style of pro_editor.dart; the implementations
// live on [ProVisionService] above.
// ---------------------------------------------------------------------------

/// See [ProVisionService.removeVideoBackground].
Future<String> removeVideoBackground({
  required String input,
  required String backgroundKind,
  String? backgroundColor,
  String? backgroundImagePath,
  required Directory workDir,
  double sampleFps = 2.0,
  int width = 480,
  void Function(double progress)? onProgress,
  void Function(String step)? onStep,
}) =>
    ProVisionService.removeVideoBackground(
      input: input,
      backgroundKind: backgroundKind,
      backgroundColor: backgroundColor,
      backgroundImagePath: backgroundImagePath,
      workDir: workDir,
      sampleFps: sampleFps,
      width: width,
      onProgress: onProgress,
      onStep: onStep,
    );

/// See [ProVisionService.trackObject].
Future<List<TrackPoint>> trackObject({
  required String videoPath,
  required double startXNorm,
  required double startYNorm,
  required Directory workDir,
  double sampleFps = 2.0,
  int width = 360,
  void Function(double progress)? onProgress,
}) =>
    ProVisionService.trackObject(
      videoPath: videoPath,
      startXNorm: startXNorm,
      startYNorm: startYNorm,
      workDir: workDir,
      sampleFps: sampleFps,
      width: width,
      onProgress: onProgress,
    );

/// See [ProVisionService.trackOverlayFilter].
String trackOverlayFilter({
  required List<TrackPoint> track,
  required String baseLabel,
  required String overlayLabel,
  required int videoW,
  required int videoH,
  required int overlayW,
  required int overlayH,
  required String outLabel,
}) =>
    ProVisionService.trackOverlayFilter(
      track: track,
      baseLabel: baseLabel,
      overlayLabel: overlayLabel,
      videoW: videoW,
      videoH: videoH,
      overlayW: overlayW,
      overlayH: overlayH,
      outLabel: outLabel,
    );

/// See [ProVisionService.detectBeats].
Future<List<double>> detectBeats({
  required String input,
  required Directory workDir,
}) =>
    ProVisionService.detectBeats(input: input, workDir: workDir);

/// See [ProVisionService.beatSegments].
List<BeatSegment> beatSegments(List<double> beats, double duration) =>
    ProVisionService.beatSegments(beats, duration);

/// See [ProVisionService.beatCutCommand].
String beatCutCommand({
  required String input,
  required List<double> beats,
  required double clipDurationSec,
  required String output,
}) =>
    ProVisionService.beatCutCommand(
      input: input,
      beats: beats,
      clipDurationSec: clipDurationSec,
      output: output,
    );

/// See [ProVisionService.waveformPng].
Future<String?> waveformPng({
  required String input,
  required String output,
  int width = 720,
  int height = 120,
}) =>
    ProVisionService.waveformPng(
      input: input,
      output: output,
      width: width,
      height: height,
    );
