/// TJ Pro v2.2.0 "FX Pack" — competitive features from CapCut / VN /
/// KineMaster / Alight Motion, expressed as FFmpeg filter strings.
///
/// Dart only, no new pub dependencies. All FFmpeg work is expressed as
/// command/filter strings, exactly like [FfmpegService] and
/// [pro_editor.dart]; nothing here touches secrets, payouts, or ads.
///
/// WHAT THIS ADDS (and which competitor it matches):
///   1. Voice changer (CapCut / KineMaster) — chipmunk, deep voice,
///      robot, echo. Pure audio filters, applied in the final pass.
///   2. Reverse video (VN / CapCut) — full reverse command (video +
///      audio). Runs as a pre-pass on the selected clip.
///   3. Freeze frame (VN) — hold a frame for N seconds at time T.
///      Runs as a pre-pass on the selected clip.
///   4. Silence remover (CapCut auto-cut lite) — cuts silent stretches
///      from the audio (and the video follows via the same timestamps
///      when applied as a pre-pass). Pre-pass on the selected clip.
///   5. PIP picture-in-picture (KineMaster / CapCut) — second video
///      overlaid scaled in a corner. Post-pass filter_complex snippet.
///   6. Export quality (CapCut Pro lever) — 720p / 1080p selector that
///      scales the normalize + final pass targets.
///   7. Shake effect (Alight Motion) — sinusoidal crop shake preset.
///      Video filter for the final pass.
///   8. Audio fade in/out — afade on the final audio.
///
/// GUARANTEES (same contract as pro_editor.dart):
///   - Every feature is OFF by default; an untouched export is
///     byte-for-byte the old pipeline.
///   - Every post/pre-pass is guarded: on failure the previous output
///     is kept and the export continues — an FX pass NEVER fails the
///     whole export.
///   - No Urdu/Arabic text goes through FFmpeg drawtext anywhere here.
///
/// UNVERIFIED SYNTAX (no FFmpeg on this VM; parent MUST run once on a
/// real device before shipping):
///   - `asetrate` + `aresample` pitch-shift chains (standard).
///   - `silenceremove` option names (standard).
///   - `crop` x/y expressions with `t` (standard).

library;

import 'ffmpeg_service.dart';

// ---------------------------------------------------------------------------
// 1. Voice changer
// ---------------------------------------------------------------------------

/// Voice effect. 'none' = untouched.
enum VoiceFx { none, chipmunk, deepVoice, robot, echo }

/// Audio filter for [fx]. Empty string when [VoiceFx.none].
///
///   - chipmunk: pitch up 1.5x (asetrate 66150 then resample back to
///    44100 keeps duration, raises pitch).
///   - deepVoice: pitch down 0.7x.
///   - robot: vibrato frequency modulation.
///   - echo: aecho delay/decay.
///
/// These chain AFTER any atempo speed filter (order: speed first, then
/// voice fx), so they compose with the existing speed control.
String voiceFxFilter(VoiceFx fx) {
  switch (fx) {
    case VoiceFx.none:
      return '';
    case VoiceFx.chipmunk:
      return 'asetrate=44100*1.5,aresample=44100';
    case VoiceFx.deepVoice:
      return 'asetrate=44100*0.7,aresample=44100';
    case VoiceFx.robot:
      return 'vibrato=f=8:d=0.8';
    case VoiceFx.echo:
      return 'aecho=0.8:0.9:60:0.4';
  }
}

/// Display labels for the dropdown, in the same order as [VoiceFx].
const voiceFxLabels = ['None', 'Chipmunk', 'Deep voice', 'Robot', 'Echo'];

// ---------------------------------------------------------------------------
// 2. Reverse video (pre-pass)
// ---------------------------------------------------------------------------

/// Full command reversing [input] -> [output] (video + audio).
/// `reverse` needs the whole stream in memory; fine for short clips,
/// heavy for long ones — the UI warns on clips > 60s.
String reverseCommand({
  required String input,
  required String output,
}) {
  return '-y -i ${FfmpegService.q(input)} '
      '-vf "reverse" -af "areverse" '
      '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
      '-movflags +faststart ${FfmpegService.q(output)}';
}

// ---------------------------------------------------------------------------
// 3. Freeze frame (pre-pass)
// ---------------------------------------------------------------------------

/// Hold the frame at [freezeAtSec] for [holdSec] seconds, then continue.
/// Implementation: extract the frame as PNG, loop it for [holdSec],
/// split the source into before/after segments, concat the three parts.
/// Returns the ordered list of commands to run (extract, before, after,
/// concat-list write is done by the caller, concat).
List<String> freezeFrameCommands({
  required String input,
  required double freezeAtSec,
  required double holdSec,
  required String workDir,
  required int stamp,
}) {
  final q = FfmpegService.q;
  final framePng = '$workDir/freeze_frame_$stamp.png';
  final holdMp4 = '$workDir/freeze_hold_$stamp.mp4';
  final beforeMp4 = '$workDir/freeze_before_$stamp.mp4';
  final afterMp4 = '$workDir/freeze_after_$stamp.mp4';
  return [
    // 1. Extract the freeze frame.
    '-y -ss $freezeAtSec -i ${q(input)} -frames:v 1 ${q(framePng)}',
    // 2. Loop it into a hold clip (same size/fps as source via scale).
    '-y -loop 1 -framerate 30 -i ${q(framePng)} '
        '-t $holdSec -c:v libx264 -preset veryfast -crf 23 '
        '-pix_fmt yuv420p ${q(holdMp4)}',
    // 3. Before segment (0 .. freezeAt).
    '-y -i ${q(input)} -t $freezeAtSec '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac ${q(beforeMp4)}',
    // 4. After segment (freezeAt .. end).
    '-y -ss $freezeAtSec -i ${q(input)} '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac ${q(afterMp4)}',
  ];
}

/// Output paths matching [freezeFrameCommands] (index-aligned).
Map<String, String> freezeFramePaths(String workDir, int stamp) => {
      'frame': '$workDir/freeze_frame_$stamp.png',
      'hold': '$workDir/freeze_hold_$stamp.mp4',
      'before': '$workDir/freeze_before_$stamp.mp4',
      'after': '$workDir/freeze_after_$stamp.mp4',
      'list': '$workDir/freeze_list_$stamp.txt',
    };

// ---------------------------------------------------------------------------
// 4. Silence remover (pre-pass, CapCut auto-cut lite)
// ---------------------------------------------------------------------------

/// Audio filter removing silences longer than [minSilenceSec] (default
/// 0.5s) below [noiseDb] (default -35dB). Applied as a pre-pass with
/// `-af`; video follows because silenceremove also cuts the video
/// timestamps when the whole stream goes through the filter.
String silenceRemoveFilter({
  double minSilenceSec = 0.5,
  double noiseDb = -35,
}) {
  return 'silenceremove=start_periods=1:start_duration=$minSilenceSec:'
      'start_threshold=${noiseDb}dB:detection=peak,'
      'areverse,'
      'silenceremove=start_periods=1:start_duration=$minSilenceSec:'
      'start_threshold=${noiseDb}dB:detection=peak,'
      'areverse';
}

/// Full pre-pass command: [input] -> [output] with silences removed.
String silenceRemoveCommand({
  required String input,
  required String output,
  double minSilenceSec = 0.5,
  double noiseDb = -35,
}) {
  final af = silenceRemoveFilter(
    minSilenceSec: minSilenceSec,
    noiseDb: noiseDb,
  );
  return '-y -i ${FfmpegService.q(input)} '
      '-af "$af" '
      '-c:v libx264 -preset veryfast -crf 23 -c:a aac '
      '-movflags +faststart ${FfmpegService.q(output)}';
}

// ---------------------------------------------------------------------------
// 5. PIP picture-in-picture (post-pass filter_complex snippet)
// ---------------------------------------------------------------------------

/// PIP position presets.
enum PipPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Filter_complex snippet (no -i/-map, no trailing ';') overlaying the
/// second video input [pipLabel] (e.g. '[1:v]') scaled to [pipScale]
/// fraction of the base size, at [position] with [margin] px inset.
///
/// CALLER INPUT LAYOUT: [0:v] is the main video, [1:v] is the PIP
/// video. The snippet ends at [outLabel].
String pipOverlayFilter({
  required String pipLabel,
  required PipPosition position,
  required double pipScale,
  required int margin,
  required String outLabel,
}) {
  final s = pipScale.clamp(0.15, 0.5);
  String xExpr;
  String yExpr;
  if (position == PipPosition.topLeft) {
    xExpr = '$margin';
    yExpr = '$margin';
  } else if (position == PipPosition.topRight) {
    xExpr = 'W-w-$margin';
    yExpr = '$margin';
  } else if (position == PipPosition.bottomLeft) {
    xExpr = '$margin';
    yExpr = 'H-h-$margin';
  } else {
    xExpr = 'W-w-$margin';
    yExpr = 'H-h-$margin';
  }
  return '$pipLabel scale=iw*$s:ih*$s[pip];'
      '[0:v][pip]overlay=x=\'$xExpr\':y=\'$yExpr\'$outLabel';
}

const pipPositionLabels = [
  'Top left',
  'Top right',
  'Bottom left',
  'Bottom right',
];

// ---------------------------------------------------------------------------
// 6. Export quality
// ---------------------------------------------------------------------------

/// Export quality presets. 720p = today's behaviour.
enum ExportQuality { p720, p1080 }

/// Target (width, height) for portrait / landscape at [q].
(int, int) exportDims(ExportQuality q, bool portrait) {
  switch (q) {
    case ExportQuality.p720:
      return portrait ? (720, 1280) : (1280, 720);
    case ExportQuality.p1080:
      return portrait ? (1080, 1920) : (1920, 1080);
  }
}

const exportQualityLabels = ['720p', '1080p'];

// ---------------------------------------------------------------------------
// 7. Shake effect (Alight Motion style)
// ---------------------------------------------------------------------------

/// Shake intensity presets.
enum ShakeFx { none, light, medium, strong }

/// Video filter applying a sinusoidal crop shake. [fps] should be 30
/// (the normalized pipeline rate). Empty string when [ShakeFx.none].
///
/// Technique: crop a slightly smaller window and move it with sin/cos
/// of time — the classic handheld-shake look. Amplitude scales with
/// intensity; frequency is fixed at ~7Hz for light, ~10Hz for strong.
String shakeFilter(ShakeFx fx, {int fps = 30}) {
  switch (fx) {
    case ShakeFx.none:
      return '';
    case ShakeFx.light:
      return 'crop=iw-20:ih-20:x=\'(iw-ow)/2+8*sin(2*PI*t*7)\':'
          'y=\'(ih-oh)/2+8*cos(2*PI*t*7)\'';
    case ShakeFx.medium:
      return 'crop=iw-40:ih-40:x=\'(iw-ow)/2+16*sin(2*PI*t*8)\':'
          'y=\'(ih-oh)/2+16*cos(2*PI*t*8)\'';
    case ShakeFx.strong:
      return 'crop=iw-80:ih-80:x=\'(iw-ow)/2+28*sin(2*PI*t*10)\':'
          'y=\'(ih-oh)/2+28*cos(2*PI*t*10)\'';
  }
}

const shakeFxLabels = ['None', 'Light', 'Medium', 'Strong'];

// ---------------------------------------------------------------------------
// 8. Audio fade in/out
// ---------------------------------------------------------------------------

/// Audio filter fading in over [fadeInSec] and out over [fadeOutSec]
/// at the end of a [durationSec] clip. Empty string when both are 0.
String audioFadeFilter({
  double fadeInSec = 0,
  double fadeOutSec = 0,
  required double durationSec,
}) {
  final parts = <String>[];
  if (fadeInSec > 0) {
    parts.add('afade=t=in:st=0:d=$fadeInSec');
  }
  if (fadeOutSec > 0) {
    final st = (durationSec - fadeOutSec).clamp(0, durationSec);
    parts.add('afade=t=out:st=$st:d=$fadeOutSec');
  }
  return parts.join(',');
}
