/// TJ Pro v2.1.0 "Pro Editor" — FFmpeg engine additions.
///
/// Dart only, no new pub dependencies. All FFmpeg work is expressed as
/// command/filter strings, exactly like [FfmpegService]; nothing here
/// touches secrets, payouts, or AdMob.
///
/// IMPORTANT — READ BEFORE WIRING THESE UP
/// --------------------------------------
/// 1. NEVER use FFmpeg drawtext for Urdu/Arabic text: it breaks shaping
///    (disconnected letters). All text in this file is rendered to a
///    transparent PNG with dart:ui ([renderTitlePng], same RTL pattern
///    as lib/live/news_template.dart) and composited with `overlay`.
/// 2. Filter snippets returned here are filter_complex fragments only
///    (no `-i`, no `-map`). The caller builds the full command, maps
///    the labelled outputs, and encodes with libx264 veryfast crf 23,
///    matching the existing commands in ffmpeg_service.dart.
/// 3. Time-based expressions (`t`, `time`, `T`) assume the streams they
///    run on start at timestamp 0 and advance in real time. A single
///    still PNG fed without `-loop 1` has only one frame, so its `t`
///    never advances: callers MUST feed image overlays looped
///    (e.g. `-loop 1 -framerate 30 -i png`) or the keyframe/title
///    animations will render frozen at their start pose. (Mask PNGs
///    are the opposite case: they MUST be single-frame — see
///    [mainClipMaskCommand]'s termination note.)
/// 4. The existing pipeline normalizes clips to 30 fps
///    (FfmpegService.normalizeCommand). The `fps=30` baked into the
///    zoompan chains below assumes that; feeding a different frame
///    rate will duplicate/drop overlay frames (harmless, but motion
///    will not be frame-exact).
/// 5. SIMPLIFICATIONS (deliberate, see also the handoff report):
///    - Vibrance: FFmpeg has no native vibrance filter. It is
///      approximated by a gentler saturation move inside `eq`
///      (see [ProGrade.gradeFilter]).
///    - Keyframes: EXACTLY 2 (start + end), linear interpolation only.
///    - Keyframe opacity: `fade` can only ramp alpha 0 <-> 1, which
///      cannot express an arbitrary opacityA -> opacityB lerp, so
///      opacity is lerped with `geq` instead (flagged below).
///    - Keyframe scale: `zoompan` keeps its output footprint equal to
///      its input size, so "scale" animates the content zoom inside
///      the overlay box rather than growing/shrinking the box itself.
///      The overlay x/y expressions therefore use the fixed box size.
///    - Keyframe rotation: the rotated box keeps its input size
///      (`ow='iw':oh='ih'`); corners are clipped when the rotation
///      makes the content larger than the box. `fillcolor=none` keeps
///      the uncovered area transparent.
///    - Speed ramp: the audio chain is REQUIRED. There is no
///      video-only fallback that drops audio: if the ramp audio chain
///      fails, the caller must keep the un-ramped export (see
///      [rampAudioFilter]).
///    - Chromakey input layout is fixed (see [chromaFilterComplex]).
///
/// VERIFIED (Build 3, system FFmpeg 8.1.2 render tests):
///    - `geq` time variable `T` and `clip()` parse fine, but the
///      alpha plane accessor must be `alpha(X,Y)` — the shorter
///      `a(X,Y)` form is rejected ("Unknown function") and fails
///      the whole filter graph. Both keyframe builders use
///      `alpha(X,Y)`.
/// UNVERIFIED SYNTAX (no FFmpeg on this VM to test against; the parent
/// MUST run these once on a real device before shipping):
///    - `zoompan` zoom values below 1.0 (scale < 1). The zoom option
///      is a string expression with no documented lower clamp in the
///      filter code, but older docs describe the range as 1-10; a
///      build that clamps will render scale < 1 as scale 1.
///    - `curves` master-point formatting (values are clamped 0..1 and
///      formatted to 3 decimals; the point syntax itself is standard).
///    - `vidstabdetect`/`vidstabtransform` option names (see
///      [stabilizeCommands]); the deshake fallback covers a build
///      without vidstab entirely.

library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'ffmpeg_service.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Format a double for an FFmpeg expression: shortest form that keeps
/// up to 6 decimal places (0.5 -> "0.5", 1.0 -> "1", 0.3333333 ->
/// "0.333333"). FFmpeg expressions accept plain decimals.
String _num(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  var s = v.toStringAsFixed(6);
  while (s.contains('.') && s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  if (s == '-0' || s.isEmpty) return '0';
  return s;
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// Quote a filesystem path as a single-quoted FFmpeg filter value
/// (e.g. for `lut3d='...'` or a `result='...'` path).
String _filterQuote(String path) =>
    "'${path.replaceAll("'", "\\'")}'";

/// True when [text] contains Arabic-script characters (Urdu, Arabic,
/// Persian) — the same detection used by lib/live/news_template.dart.
bool _hasArabic(String text) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(text);

// ---------------------------------------------------------------------------
// 1. Pro grading (LUT + temperature + tint + eq + curves)
// ---------------------------------------------------------------------------

/// Professional colour grade. All ranges are clamped when the filter
/// is built; the model itself just holds the user's values.
class ProGrade {
  const ProGrade({
    this.lutName = '',
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 1,
    this.vibrance = 1,
    this.contrast = 1,
    this.shadows = 0,
    this.highlights = 0,
    this.brightness = 0,
    this.exposure = 0,
  });

  /// '' = no LUT, otherwise one of the keys of [proLuts].
  final String lutName;

  /// -100 (warm) .. 100 (cool). 0 = untouched.
  final double temperature;

  /// -100 (magenta) .. 100 (green). 0 = untouched.
  final double tint;

  /// 0..2, default 1.
  final double saturation;

  /// 0..2, default 1. See [gradeFilter] for the approximation.
  final double vibrance;

  /// 0..2, default 1.
  final double contrast;

  /// -100 (crush) .. 100 (lift). 0 = untouched.
  final double shadows;

  /// -100 (darken) .. 100 (brighten). 0 = untouched.
  final double highlights;

  /// -100 .. 100, 0 = untouched (one-build: the video editor's
  /// grading panel had NO brightness control — every competitor's
  /// Adjust panel leads with it). Applied through FFmpeg `eq`.
  final double brightness;

  /// -100 .. 100, 0 = untouched (one-build addition, see
  /// [brightness]). Modelled as a gamma move in `eq`, the standard
  /// cheap exposure approximation.
  final double exposure;

  /// Display name -> Flutter asset path. The parent MUST ship these
  /// exact files and declare them under `flutter: assets:` in
  /// pubspec.yaml; [ensureLutFile] materialises them to disk because
  /// FFmpeg cannot read Flutter assets directly.
  static const Map<String, String> proLuts = {
    'TealOrange': 'assets/luts/teal_orange.cube',
    'Vintage': 'assets/luts/vintage.cube',
    'Noir': 'assets/luts/noir.cube',
    'Golden': 'assets/luts/golden.cube',
    'CoolNight': 'assets/luts/cool_night.cube',
  };

  bool get isDefault =>
      lutName.isEmpty &&
      temperature == 0 &&
      tint == 0 &&
      saturation == 1 &&
      vibrance == 1 &&
      contrast == 1 &&
      shadows == 0 &&
      highlights == 0 &&
      brightness == 0 &&
      exposure == 0;

  /// Build the filter chain for this grade.
  ///
  /// Returns '' when every value is at its default (so callers can
  /// skip the filter entirely). Order: temperature -> tint ->
  /// saturation/contrast -> shadows/highlights -> LUT (the LUT is the
  /// final "look" applied on top of the corrections).
  ///
  /// [lutFilePath] is the on-disk .cube file produced by
  /// [ensureLutFile]. When [lutName] is set but [lutFilePath] is
  /// null, the LUT is silently skipped (the rest of the grade still
  /// applies) — callers should resolve the file first.
  ///
  /// Vibrance approximation: FFmpeg has NO native vibrance filter.
  /// True vibrance protects already-saturated colours; the closest
  /// cheap approximation is a gentler saturation move, so the
  /// effective eq saturation is
  /// `saturation * (1 + (vibrance - 1) * 0.5)` — i.e. a vibrance of
  /// 1.5 moves saturation only half as far as a saturation of 1.5
  /// would. It is not a true vibrance curve, and it is documented
  /// here rather than hidden behind the name.
  String gradeFilter({String? lutFilePath}) {
    if (isDefault && lutFilePath == null) return '';
    final parts = <String>[];

    final temp = _clamp(temperature, -100, 100);
    if (temp != 0) {
      // Map -100..100 onto 3000K (warm) .. 10000K (cool) around a
      // 6500K neutral point; mix scales with the slider distance so
      // small moves stay subtle.
      final kelvin = (6500 + temp * 35).round();
      final mix = _num(_clamp(temp.abs() / 100, 0, 1));
      parts.add('colortemperature=temperature=$kelvin:mix=$mix:pl=1');
    }

    final tintV = _clamp(tint, -100, 100);
    if (tintV != 0) {
      // colorbalance shifts are -1..1; scale the slider to +/-0.3.
      // Convention: positive tint = green, negative tint = magenta
      // (red + blue). Midtones carry the tint; shadows/highlights
      // are left alone so skin tones do not shift wholesale.
      final v = _num(_clamp(tintV.abs() / 100 * 0.3, 0, 1));
      if (tintV > 0) {
        parts.add('colorbalance=gm=$v');
      } else {
        parts.add('colorbalance=rm=$v:bm=$v');
      }
    }

    final sat = _clamp(saturation, 0, 2);
    final vib = _clamp(vibrance, 0, 2);
    final con = _clamp(contrast, 0, 2);
    // Gentler saturation curve for vibrance (see doc above).
    final effSat = _clamp(sat * (1 + (vib - 1) * 0.5), 0, 3);
    // Brightness/exposure ride the same eq instance: brightness maps
    // -100..100 -> eq's -1..1 at 1/4 strength (eq brightness is very
    // hot), exposure maps to gamma 0.5..2.0 (log-style around 1.0).
    final bri = _clamp(brightness, -100, 100) / 400;
    final gam = math.pow(2, -_clamp(exposure, -100, 100) / 100).toDouble();
    if (effSat != 1 || con != 1 || bri != 0 || gam != 1) {
      parts.add(
        'eq=saturation=${_num(effSat)}:contrast=${_num(con)}'
        ':brightness=${_num(bri)}:gamma=${_num(gam)}',
      );
    }

    final sh = _clamp(shadows, -100, 100) / 100;
    final hi = _clamp(highlights, -100, 100) / 100;
    if (sh != 0 || hi != 0) {
      // curves master points: the shadow term is weighted by
      // (1-x)^2 so it lifts/crushes the dark end most, the highlight
      // term by x^2 so it rolls off/brightens the bright end most.
      // Points are clamped to 0..1 so the curve stays monotonic for
      // the documented slider ranges.
      final points = <String>[];
      for (final x in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final y = _clamp(
          x + sh * 0.12 * (1 - x) * (1 - x) + hi * 0.12 * x * x,
          0,
          1,
        );
        points.add('${_num(x)}/${y.toStringAsFixed(3)}');
      }
      parts.add("curves=master='${points.join(';')}'");
    }

    if (lutName.isNotEmpty && lutFilePath != null) {
      parts.add('lut3d=${_filterQuote(lutFilePath)}');
    }
    return parts.join(',');
  }
}

/// Top-level convenience matching the `gradeFilter(ProGrade g, ...)`
/// call shape; identical to [ProGrade.gradeFilter].
String gradeFilter(ProGrade g, {String? lutFilePath}) =>
    g.gradeFilter(lutFilePath: lutFilePath);

/// Dropdown-shaped view of [ProGrade.proLuts] for the editor UI: each
/// entry is {'name': displayName, 'asset': flutterAssetPath}.
/// '' = None (no LUT); the UI only resolves an asset when a LUT is picked.
const proLuts = [
  {'name': '', 'asset': ''},
  {'name': 'TealOrange', 'asset': 'assets/luts/teal_orange.cube'},
  {'name': 'Vintage', 'asset': 'assets/luts/vintage.cube'},
  {'name': 'Noir', 'asset': 'assets/luts/noir.cube'},
  {'name': 'Golden', 'asset': 'assets/luts/golden.cube'},
  {'name': 'CoolNight', 'asset': 'assets/luts/cool_night.cube'},
];

/// Materialise a Flutter asset (e.g. a .cube LUT) as a real file FFmpeg
/// can read. Flutter assets are NOT filesystem files, so the bytes
/// are loaded with rootBundle and written under [dir]. Cached: if
/// the file already exists it is returned untouched, never rewritten.
/// Returns the written (or existing) file.
Future<File> ensureLutFile(String asset, Directory dir) async {
  final name = asset.split('/').last;
  final file = File('${dir.path}/$name');
  if (await file.exists()) return file;
  try {
    await dir.create(recursive: true);
  } catch (_) {}
  final data = await rootBundle.load(asset);
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return file;
}

// ---------------------------------------------------------------------------
// 2. Pro transitions (parameterised xfade)
// ---------------------------------------------------------------------------

/// A crossfade-style transition. [name] must be one of the valid
/// xfade transition names below; anything else falls back to 'fade'
/// in [proXfadeCommand] rather than emitting an invalid filter.
class ProTransition {
  const ProTransition({this.name = 'fade', this.durationSec = 0.5});

  final String name;

  /// 0.3..2.0 seconds; clamped in [proXfadeCommand].
  final double durationSec;

  static const List<String> validNames = [
    'fade',
    'slideleft',
    'slideright',
    'slideup',
    'slidedown',
    'wipeleft',
    'wiperight',
    'wipeup',
    'wipedown',
    'circlecrop',
    'dissolve',
    'pixelize',
    'smoothleft',
    'smoothright',
    'radial',
    'rectcrop',
    'hblur',
    'circleopen',
  ];
}

/// Full crossfade command for already-normalized clips, same structure
/// as FfmpegService.xfadeCommand but with a parameterised transition
/// name and duration.
///
/// Offsets accumulate clip durations minus the transition duration
/// (so consecutive transitions do not double-count the overlap), and
/// audio uses acrossfade with d = the transition duration.
/// Returns null when fewer than 2 inputs are given, like xfadeCommand.
/// With the default transition (fade, 0.5s) the output is byte-identical
/// to FfmpegService.xfadeCommand for the same inputs.
String? proXfadeCommand({
  required List<String> inputs,
  required List<int> durationsMs,
  required ProTransition transition,
  required bool hasAudio,
  required String output,
}) {
  if (inputs.length < 2) return null;
  final name =
      ProTransition.validNames.contains(transition.name)
          ? transition.name
          : 'fade';
  final durSec = _clamp(transition.durationSec, 0.3, 2.0);
  final fadeMs = (durSec * 1000).round();
  final durStr = _num(durSec);
  final buf = StringBuffer();
  for (final i in inputs) {
    buf.write('-i ${FfmpegService.q(i)} ');
  }
  buf.write('-filter_complex "');
  // Video chain.
  var prev = '[0:v]';
  var offsetMs = durationsMs[0] - fadeMs;
  for (var i = 1; i < inputs.length; i++) {
    final out = i == inputs.length - 1 ? '[vout]' : '[vx$i]';
    buf.write(
      '$prev[$i:v]xfade=transition=$name:duration=$durStr:offset=${offsetMs / 1000.0}$out;',
    );
    prev = out;
    offsetMs += durationsMs[i] - fadeMs;
  }
  // Audio chain (only when every clip has audio; acrossfade chains
  // automatically with no offset needed).
  String audioMap = '';
  if (hasAudio) {
    var aprev = '[0:a]';
    for (var i = 1; i < inputs.length; i++) {
      final out = i == inputs.length - 1 ? '[aout]' : '[ax$i]';
      buf.write('$aprev[$i:a]acrossfade=d=$durStr$out;');
      aprev = out;
    }
    audioMap = ' -map "[vout]" -map "[aout]"';
  } else {
    audioMap = ' -map "[vout]"';
  }
  buf.write('"');
  buf.write(audioMap);
  buf.write(
    ' -c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${FfmpegService.q(output)}',
  );
  return buf.toString();
}

// ---------------------------------------------------------------------------
// 3. Keyframes (exactly 2: start + end, linear interpolation)
// ---------------------------------------------------------------------------

/// One keyframe. [xNorm]/[yNorm] are the overlay's TOP-LEFT corner as
/// a fraction of the base video size (0..1); [scale] is a zoom factor
/// (0.5..2); [opacity] 0..1; [rotationDeg] -180..180, clockwise.
class ProKeyframe {
  const ProKeyframe({
    required this.timeSec,
    required this.xNorm,
    required this.yNorm,
    this.scale = 1,
    this.opacity = 1,
    this.rotationDeg = 0,
  });

  final double timeSec;
  final double xNorm;
  final double yNorm;
  final double scale;
  final double opacity;
  final double rotationDeg;
}

/// A two-keyframe track: [start] at [ProKeyframe.timeSec] lerping
/// linearly to [end] at its time. Outside the window the clamped lerp
/// holds the nearest pose (no enable window is applied here — unlike
/// titles, a keyframed sticker stays visible at its end pose).
class KeyframeTrack {
  const KeyframeTrack({required this.start, required this.end});

  final ProKeyframe start;
  final ProKeyframe end;
}

/// Easing curve presets for keyframe animation (CapCut/VN/Alight
/// Motion-style). The easing reshapes the 0..1 lerp factor inside the
/// FFmpeg filter expression, so the overlay eases between its start
/// and end poses instead of moving at a constant speed. `linear` is
/// the long-standing default and stays the default.
enum KeyframeEasing { linear, easeIn, easeOut, easeInOut }

/// Display labels for the keyframe easing dropdown in the editor UI.
String keyframeEasingLabel(KeyframeEasing e) => switch (e) {
      KeyframeEasing.linear => 'Linear (constant speed)',
      KeyframeEasing.easeIn => 'Ease in (slow start)',
      KeyframeEasing.easeOut => 'Ease out (slow end)',
      KeyframeEasing.easeInOut => 'Ease in-out (smooth both ends)',
    };

/// Lerp factor expression for a filter whose time variable is [tVar]
/// ('t' for overlay/rotate, 'time' for zoompan): 0 before the window,
/// ramping linearly to 1 across it, holding 1 after it.
String _lerpFactor(String tVar, double t0, double dur) {
  if (dur <= 0) return '1';
  return 'clip(($tVar-${_num(t0)})/${_num(dur)},0,1)';
}

/// Eased lerp factor: the linear [_lerpFactor] reshaped by an easing
/// curve. All shapes are plain algebra over the linear factor so any
/// FFmpeg expression evaluator handles them (no special functions
/// beyond pow): ease-in squares the factor, ease-out is the mirrored
/// curve 1-(1-f)^2, ease-in-out is the smoothstep 3f^2-2f^3.
String _easedFactor(
    String tVar, double t0, double dur, KeyframeEasing easing) {
  final String f = _lerpFactor(tVar, t0, dur);
  return switch (easing) {
    KeyframeEasing.linear => f,
    KeyframeEasing.easeIn => 'pow(($f),2)',
    KeyframeEasing.easeOut => '(1-pow(1-($f),2))',
    KeyframeEasing.easeInOut => '(($f)*($f)*(3-2*($f)))',
  };
}

/// Linear lerp expression between [a] and [b] over the track window,
/// using time variable [tVar]; [easing] reshapes the interpolation
/// curve (default linear = the long-standing behaviour).
String _lerp(String tVar, double t0, double dur, double a, double b,
    [KeyframeEasing easing = KeyframeEasing.linear]) {
  if (dur <= 0 || a == b) return _num(b);
  final String f = _easedFactor(tVar, t0, dur, easing);
  return '(${_num(a)}+(${_num(b)}-${_num(a)})*$f)';
}

/// Filter_complex snippet (no -i/-map, no trailing ';') that overlays
/// [overlayLabel] onto [baseLabel] with the track applied.
/// [easing] selects the keyframe motion curve (default linear =
/// constant speed; ease presets reshape the interpolation in the
/// FFmpeg expression).
///
/// Chain on the overlay input, in order:
///   format=rgba -> zoompan (scale lerp) -> format=rgba -> rotate
///   (rotation lerp, output size kept = input size, transparent fill)
///   -> geq (opacity lerp) -> overlay (position lerp).
///
/// DEVIATION, DOCUMENTED: opacity uses `geq`, NOT `fade`. `fade`
/// with alpha can only ramp 0 <-> 1; it cannot express an arbitrary
/// startOpacity -> endOpacity lerp, so `geq` multiplies the overlay's
/// own alpha plane by the lerped opacity.
/// VERIFIED (Build 3 render tests, system FFmpeg 8.1.2): the geq
/// alpha accessor is `alpha(X,Y)` — the shorter `a(X,Y)` form is
/// REJECTED ("Unknown function") and would fail the whole pass;
/// the `T` variable and `clip()` parse fine. Both keyframe
/// builders use `alpha(X,Y)`.
/// Position uses the overlay filter's `t` (base-stream time); scale
/// uses zoompan's `time` and rotation/opacity use their own stream's
/// `t`/`T`, so the overlay stream must be timestamp-aligned with the
/// base (looped from 0, or trimmed from the same origin).
String keyframeOverlayFilter({
  required String baseLabel,
  required String overlayLabel,
  required KeyframeTrack track,
  required int videoW,
  required int videoH,
  required int overlayW,
  required int overlayH,
  required String outLabel,
  KeyframeEasing easing = KeyframeEasing.linear,
}) {
  final s = track.start;
  final e = track.end;
  final t0 = s.timeSec;
  final dur = e.timeSec - s.timeSec;

  // Position lerp (overlay filter, time variable 't').
  final xLerp = _lerp('t', t0, dur, s.xNorm, e.xNorm, easing);
  final yLerp = _lerp('t', t0, dur, s.yNorm, e.yNorm, easing);
  final xExpr = '($xLerp)*$videoW';
  final yExpr = '($yLerp)*$videoH';

  // Scale lerp (zoompan, time variable 'time'). zoompan keeps its
  // output footprint equal to its input size, so this animates the
  // content zoom inside the overlay box (see header note).
  final zoomLerp = _lerp('time', t0, dur, s.scale, e.scale, easing);

  // Rotation lerp in radians (rotate filter, time variable 't').
  final rotLerp =
      '(${_lerp('t', t0, dur, s.rotationDeg, e.rotationDeg, easing)})*${_num(math.pi)}/180';

  // Opacity lerp (geq, time variable 'T').
  final opLerp = _lerp('T', t0, dur, s.opacity, e.opacity, easing);

  final buf = StringBuffer();
  buf.write(
    '$overlayLabel format=rgba,'
    "zoompan=z='$zoomLerp':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${overlayW}x$overlayH:fps=30[ovz];",
  );
  buf.write(
    '[ovz]format=rgba,'
    "rotate=a='$rotLerp':ow='iw':oh='ih':fillcolor=none[ovr];",
  );
  buf.write(
    '[ovr]geq=r=\'r(X,Y)\':g=\'g(X,Y)\':b=\'b(X,Y)\':a=\'alpha(X,Y)*($opLerp)\'[ovf];',
  );
  // shortest=1 is load-bearing: the overlay image is fed with
  // `-loop 1` (infinite), and overlay's framesync repeats the base's
  // last frame forever once the base ends — without it this pass NEVER
  // terminates (proven in the Build 3 render tests: 2,228 frames for a
  // 180-frame clip before the test timeout killed it; fixed graph
  // finishes in seconds at exactly the base duration).
  buf.write(
    "$baseLabel[ovf]overlay=x='$xExpr':y='$yExpr':shortest=1$outLabel",
  );
  return buf.toString();
}

/// Build 3 (Phase 3): the Dart-side mirror of the keyframe lerp the
/// FFmpeg expressions compute — same window, same easing shapes, in
/// plain doubles. The editor's stage uses it to interpolate a
/// keyframed layer's pose at the playhead, so the preview shows the
/// SAME motion the export renders (position / scale / opacity /
/// rotation all included). [tSec] is measured on the track's own
/// time base ([KeyframeTrack.start.timeSec]..[end.timeSec]).
ProKeyframe keyframePoseAt(
  KeyframeTrack track,
  double tSec,
  KeyframeEasing easing,
) {
  final s = track.start;
  final e = track.end;
  final dur = e.timeSec - s.timeSec;
  var f = dur <= 0 ? 1.0 : (tSec - s.timeSec) / dur;
  f = f.clamp(0.0, 1.0);
  final g = switch (easing) {
    KeyframeEasing.linear => f,
    KeyframeEasing.easeIn => f * f,
    KeyframeEasing.easeOut => 1 - (1 - f) * (1 - f),
    KeyframeEasing.easeInOut => f * f * (3 - 2 * f),
  };
  double lerp(double a, double b) => a + (b - a) * g;
  return ProKeyframe(
    timeSec: tSec,
    xNorm: lerp(s.xNorm, e.xNorm),
    yNorm: lerp(s.yNorm, e.yNorm),
    scale: lerp(s.scale, e.scale),
    opacity: lerp(s.opacity, e.opacity),
    rotationDeg: lerp(s.rotationDeg, e.rotationDeg),
  );
}

/// Build 3 (Phase 3): keyframed PIP snippet — the PIP video inset
/// ([pipLabel], already the SECOND input) animated between the
/// track's two poses over the base ([baseLabel], the FIRST input).
/// Position + opacity keyframes only (the v1 scope for video
/// layers); the inset box size stays [pipW]x[pipH] (from the PIP
/// scale setting), exactly like [keyframeOverlayFilter] keeps its
/// box. When [hasMask] is true a THIRD input (the mask PNG, looped)
/// multiplies the inset's alpha first — the same alpha chain the
/// editor's advanced PIP graph uses (alphaextract → multiply with
/// the mask's gray → alphamerge), so mask + feather + invert compose
/// with the keyframes. The opacity lerp itself is the geq multiply
/// from [keyframeOverlayFilter], applied while the stream is still
/// RGBA. Blend modes are NOT part of this graph: the caller falls
/// back to the static advanced graph when a blend is chosen.
String keyframedPipFilter({
  required String baseLabel,
  required String pipLabel,
  required KeyframeTrack track,
  required int videoW,
  required int videoH,
  required int pipW,
  required int pipH,
  required String outLabel,
  KeyframeEasing easing = KeyframeEasing.linear,
  bool hasMask = false,
  String maskLabel = '[2:v]',
}) {
  final s = track.start;
  final e = track.end;
  final t0 = s.timeSec;
  final dur = e.timeSec - s.timeSec;

  // Position lerp (overlay filter, time variable 't').
  final xExpr = '(${_lerp('t', t0, dur, s.xNorm, e.xNorm, easing)})*$videoW';
  final yExpr = '(${_lerp('t', t0, dur, s.yNorm, e.yNorm, easing)})*$videoH';

  // Opacity lerp (geq, time variable 'T') — same construction as
  // keyframeOverlayFilter.
  final opLerp = _lerp('T', t0, dur, s.opacity, e.opacity, easing);

  final buf = StringBuffer();
  buf.write(
    '$pipLabel scale=$pipW:$pipH,format=rgba,'
    "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($opLerp)'[pvG];",
  );
  buf.write('[pvG]split=2[pv1][pv2];');
  buf.write('[pv2]alphaextract[pa0];');
  if (hasMask) {
    buf.write('$maskLabel scale=$pipW:$pipH,format=gray[mg];');
    buf.write('[pa0][mg]blend=all_mode=multiply[pa];');
  } else {
    buf.write('[pa0]null[pa];');
  }
  buf.write('[pv1][pa]alphamerge[pipA];');
  buf.write("$baseLabel[pipA]overlay=x='$xExpr':y='$yExpr'$outLabel");
  return buf.toString();
}

/// Build 3 (Phase 3): main-clip mask pass — the generated mask PNG
/// (white = visible, transparent = masked out; feather/invert are
/// already baked into the PNG by the editor's mask renderer, the
/// SAME renderer the PIP mask uses) is multiplied into the main
/// video's alpha and the result composited over black, the stage's
/// backdrop colour. Full command (input 0 = the video, input 1 =
/// the mask PNG).
///
/// TERMINATION (Build 3 render-test fix): the mask image is fed as
/// a SINGLE frame, never `-loop 1`. The framesync filters in the
/// chain (blend / alphamerge) repeat an ended stream's last frame,
/// so the one mask frame covers the whole video and the chain ends
/// when the video ends. A looped mask input never reaches EOF, and
/// blend then pairs it with the video alpha's repeated last frame
/// FOREVER — the first render test generated 1,022,101 frames in
/// 97 minutes before being killed. (Overlay is exempt from this:
/// it ends with its main input, which is why the title/sticker
/// passes may loop their PNGs.)
String mainClipMaskCommand({
  required String input,
  required String maskPng,
  required int width,
  required int height,
  required String output,
}) {
  final graph = '[0:v]format=yuva420p,split=2[fgc][fga];'
      '[fgc]null[fg];'
      '[fga]alphaextract[aa];'
      '[1:v]scale=$width:$height,format=gray[mg];'
      '[aa][mg]blend=all_mode=multiply[ma];'
      '[fg][ma]alphamerge[m];'
      // The colour source must run at the pipeline's 30 fps: it is
      // the overlay's MAIN input, so the composited stream takes
      // its rate — at the source's 25 fps default the masked pass
      // silently re-timed a 30 fps clip to 25 fps (render test:
      // 100 frames instead of 120 over 4 s).
      'color=c=black:s=${width}x$height:r=30[bg];'
      '[bg][m]overlay=0:0:shortest=1,format=yuv420p[vout]';
  return '-y -i ${FfmpegService.q(input)} '
      '-i ${FfmpegService.q(maskPng)} '
      '-filter_complex "$graph" -map "[vout]" -map 0:a? '
      '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
      '-movflags +faststart ${FfmpegService.q(output)}';
}

// ---------------------------------------------------------------------------
// 4. Motion graphics titles (dart:ui PNG + animated overlay)
// ---------------------------------------------------------------------------

/// An animated title card. [text] may also hold an emoji (emoji and
/// sticker overlays reuse this same renderer + presets).
/// [position] is applied by [animatedTitleFilter], NOT baked into the
/// PNG: [renderTitlePng] returns a tightly cropped transparent PNG of
/// just the text (plus its readability pill), and the filter places it.
class ProMotionTitle {
  const ProMotionTitle({
    required this.text,
    this.preset = 'fadeIn',
    this.fontSize = 56,
    this.colorArgb = 0xFFFFFFFF,
    this.position = 'center',
    this.startSec = 0,
    this.durationSec = 3,
  });

  final String text;

  /// 'fadeIn' | 'slideLeft' | 'slideRight' | 'slideUp' | 'zoomPop'.
  final String preset;

  final double fontSize;

  /// ARGB, e.g. 0xFFFFFFFF for white.
  final int colorArgb;

  /// 'topCenter' | 'center' | 'bottomCenter'.
  final String position;

  final double startSec;
  final double durationSec;
}

/// Render [t] to a transparent PNG with dart:ui (PictureRecorder +
/// ParagraphBuilder), exactly the shaping-safe path used by
/// lib/live/news_template.dart: Arabic-script text lays out RTL, all
/// other text LTR, so Urdu shapes correctly. Bold text with a shadow
/// stack (readability outline) over a semi-transparent dark pill.
///
/// [canvasW]/[canvasH] are LAYOUT BOUNDS (the paragraph wraps at
/// canvasW minus padding); the returned PNG is tightly cropped to the
/// text plus padding, not canvas-sized. The caller places it with
/// [animatedTitleFilter], which honours [ProMotionTitle.position].
Future<File> renderTitlePng(
  ProMotionTitle t, {
  required Directory dir,
  int canvasW = 720,
  int canvasH = 1280,
}) async {
  const pad = 32.0;
  final text = t.text;
  // Measure first: build the paragraph at the layout width so the
  // pill can be sized to the real text box.
  ui.Paragraph buildParagraph() {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection:
            _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        textAlign: ui.TextAlign.center,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: ui.Color(t.colorArgb),
        fontSize: t.fontSize,
        fontWeight: ui.FontWeight.bold,
        shadows: [
          ui.Shadow(
            color: const ui.Color(0xFF000000),
            offset: const ui.Offset(2, 2),
            blurRadius: 4,
          ),
          ui.Shadow(
            color: const ui.Color(0xFF000000),
            offset: const ui.Offset(-1, -1),
            blurRadius: 2,
          ),
        ],
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(
      ui.ParagraphConstraints(width: (canvasW - pad * 2).toDouble()),
    );
    return para;
  }

  final para = buildParagraph();
  final outW = (para.longestLine + pad * 2).ceil();
  // canvasH is a layout hint only; a tall wrapped paragraph may grow
  // past it rather than clip (clipping would cut the text).
  final outH = (para.height + pad * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
  );
  // Readability pill behind the text.
  canvas.drawRRect(
    ui.RRect.fromLTRBR(
      0,
      0,
      outW.toDouble(),
      outH.toDouble(),
      const ui.Radius.circular(24),
    ),
    ui.Paint()..color = const ui.Color(0xAA000000),
  );
  canvas.drawParagraph(para, const ui.Offset(pad, pad));
  para.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage(outW, outH);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  try {
    await dir.create(recursive: true);
  } catch (_) {}
  final file = File(
    '${dir.path}/motion_title_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Final (resting) top-left position of the title inside the video,
/// from [ProMotionTitle.position] and the two frame sizes.
(int, int) _titleFinalPos(
  ProMotionTitle t,
  int videoW,
  int videoH,
  int overlayW,
  int overlayH,
) {
  final fx = ((videoW - overlayW) / 2).round();
  switch (t.position) {
    case 'topCenter':
      return (fx, (videoH * 0.08).round());
    case 'bottomCenter':
      return (fx, (videoH - overlayH - videoH * 0.10).round());
    case 'center':
    default:
      return (fx, ((videoH - overlayH) / 2).round());
  }
}

/// Filter_complex snippet (no -i/-map, no trailing ';') animating a
/// title PNG ([overlayLabel], [overlayW]x[overlayH], produced by
/// [renderTitlePng]) over [baseLabel].
///
/// The title is visible ONLY within [startSec, startSec+durationSec]
/// (overlay `enable='between(t,start,end)'`); outside the window it
/// is hidden, not held.
///   - fadeIn: alpha fade-in over the first 0.5s, then held (no
///     fade-out; the enable window cuts it at the end).
///   - slideLeft/slideRight/slideUp/slideDown: the overlay slides
///     from off-screen (slideLeft: from -overlayW; slideRight: from
///     videoW; slideUp: from videoH, i.e. rising; slideDown: from
///     -overlayH) to its final position over the first 0.5s of the
///     window, then holds.
///   - zoomPop: zoompan zoom lerps 1.4 -> 1.0 over the first 0.5s,
///     then holds at 1.0 (zoom stays >= 1.0, so no build can clamp
///     the pop away).
/// Unknown presets fall back to fadeIn.
String animatedTitleFilter({
  required String baseLabel,
  required String overlayLabel,
  required ProMotionTitle t,
  required int videoW,
  required int videoH,
  required int overlayW,
  required int overlayH,
  required String outLabel,
}) {
  final start = t.startSec;
  final end = start + t.durationSec;
  final animEnd = start + 0.5;
  final (fx, fy) = _titleFinalPos(t, videoW, videoH, overlayW, overlayH);
  final enable = "between(t,${_num(start)},${_num(end)})";
  final buf = StringBuffer();
  switch (t.preset) {
    case 'slideLeft':
    case 'slideRight':
    case 'slideUp':
    case 'slideDown':
      // Slide expression: from the off-screen start to the final
      // position across the first 0.5s, then hold at final.
      String xExpr;
      String yExpr;
      if (t.preset == 'slideLeft') {
        xExpr =
            "if(lt(t,${_num(animEnd)}),${-overlayW}+(${fx + overlayW})*(t-${_num(start)})/0.5,$fx)";
        yExpr = '$fy';
      } else if (t.preset == 'slideRight') {
        xExpr =
            "if(lt(t,${_num(animEnd)}),$videoW+(${fx - videoW})*(t-${_num(start)})/0.5,$fx)";
        yExpr = '$fy';
      } else if (t.preset == 'slideUp') {
        xExpr = '$fx';
        yExpr =
            "if(lt(t,${_num(animEnd)}),$videoH+(${fy - videoH})*(t-${_num(start)})/0.5,$fy)";
      } else {
        xExpr = '$fx';
        yExpr =
            "if(lt(t,${_num(animEnd)}),${-overlayH}+(${fy + overlayH})*(t-${_num(start)})/0.5,$fy)";
      }
      buf.write(
        '$overlayLabel format=rgba[ov];'
        "$baseLabel[ov]overlay=x='$xExpr':y='$yExpr':enable='$enable':shortest=1$outLabel",
      );
    case 'zoomPop':
      final zoomExpr =
          "if(lt(time,${_num(start)}),1.4,if(lt(time,${_num(animEnd)}),1.4-0.4*(time-${_num(start)})/0.5,1.0))";
      buf.write(
        '$overlayLabel format=rgba,'
        "zoompan=z='$zoomExpr':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${overlayW}x$overlayH:fps=30[ov];"
        "$baseLabel[ov]overlay=$fx:$fy:enable='$enable':shortest=1$outLabel",
      );
    case 'fadeIn':
    default:
      buf.write(
        '$overlayLabel format=rgba,'
        'fade=t=in:st=${_num(start)}:duration=0.5:alpha=1[ov];'
        "$baseLabel[ov]overlay=$fx:$fy:enable='$enable':shortest=1$outLabel",
      );
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// 5. Chromakey
// ---------------------------------------------------------------------------

/// Chromakey setup. [color] is 'green' or 'blue' for the two
/// presets, or ANY colour as '#RRGGBB' when it was sampled with the
/// editor's eyedropper (one-build chroma upgrade). [similarity] and
/// [blend] are 0..1. [backgroundKind] 'color' uses [backgroundColor]
/// (hex like '#00FF00'); 'image' uses [backgroundImagePath].
///
/// One-build additions (addendum §B.3): [spill] 0..1 runs FFmpeg's
/// `despill` after the key (green-fringe cleanup; 0 = off), [edge]
/// -1..1 shrinks (< 0) or grows (> 0) the keyed alpha via
/// erosion/dilation + a light alpha blur (0 = off).
class ProChroma {
  const ProChroma({
    this.color = 'green',
    this.similarity = 0.3,
    this.blend = 0.1,
    this.backgroundKind = 'color',
    this.backgroundColor = '#00FF00',
    this.backgroundImagePath,
    this.spill = 0,
    this.edge = 0,
  });

  final String color;
  final double similarity;
  final double blend;
  final String backgroundKind;
  final String backgroundColor;
  final String? backgroundImagePath;

  /// Despill strength 0..1 (0 = off). Default 0 keeps every existing
  /// caller's graph byte-identical to before the upgrade.
  final double spill;

  /// Alpha edge adjust -1..1 (0 = off): negative erodes (shrinks)
  /// the keyed subject edge, positive dilates (grows) it.
  final double edge;
}

/// Resolve a [ProChroma.color] value to the 6-hex-digit string
/// FFmpeg wants: the 'green'/'blue' presets, or a sampled '#RRGGBB'
/// (a malformed sample falls back to green rather than breaking the
/// graph).
String chromaKeyHex(String color) {
  if (color == 'blue') return '0000FF';
  if (color.startsWith('#') && color.length == 7) {
    final hex = color.substring(1);
    if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      return hex.toUpperCase();
    }
  }
  return '00FF00';
}

/// Filter_complex snippet (no -i/-map, no trailing ';') that keys out
/// the green/blue background and composites the foreground over a new
/// background.
///
/// CALLER INPUT LAYOUT (exact — the graph references these indices):
///   - [0:v] is ALWAYS the foreground video (the keyed subject).
///   - When [ProChroma.backgroundKind] is 'image', [1:v] MUST be the
///     background image input (a still: feed it looped, or as a
///     single image — scale2ref sizes it to the foreground).
///   - When backgroundKind is 'color', NO second input is needed: the
///     background is generated inside the graph by the `color` source
///     and stretched to the foreground size with scale2ref, so the
///     graph never references [1:v].
///
/// Chain: foreground -> chromakey -> format=yuva420p (so the keyed
/// alpha survives) [keyed]; background -> scale2ref against [keyed]
/// [bg][k2]; [bg][k2]overlay=0:0 -> [outLabel]. The chromakey colour
/// hex is emitted without '#', as FFmpeg requires (0x00FF00).
String chromaFilterComplex({
  required ProChroma c,
  required String outLabel,
}) {
  final keyHex = chromaKeyHex(c.color);
  final sim = _num(_clamp(c.similarity, 0, 1));
  final blend = _num(_clamp(c.blend, 0, 1));
  final buf = StringBuffer();
  buf.write(
    '[0:v]chromakey=color=0x$keyHex:similarity=$sim:blend=$blend,'
    'format=yuva420p',
  );
  // Despill (one-build): remove the key colour's fringe from the
  // subject's edges. `type` names the colour family the sampled key
  // belongs to: blue-dominant samples use the blue despill, every
  // other sample the green one (despill only ships these families).
  final spill = _clamp(c.spill, 0, 1);
  if (spill > 0) {
    final keyR = int.parse(keyHex.substring(0, 2), radix: 16);
    final keyG = int.parse(keyHex.substring(2, 4), radix: 16);
    final keyB = int.parse(keyHex.substring(4, 6), radix: 16);
    final despillType = (keyB > keyR && keyB > keyG) ? 'blue' : 'green';
    buf.write(',despill=type=$despillType:mix=${_num(spill)}');
  }
  // Edge adjust (one-build): erode/dilate the ALPHA plane only,
  // then a light alpha blur so the edge stays soft. Split the planes
  // so the colour planes pass through untouched.
  final edge = _clamp(c.edge, -1, 1);
  if (edge != 0) {
    final steps = math.max(1, (edge.abs() * 3).round());
    final op = edge < 0 ? 'erosion' : 'dilation';
    final chain = List<String>.filled(steps, op).join(',');
    buf.write(
      ',split[a1][a2];[a1]alphaextract,$chain,'
      'gblur=sigma=1[alpha];[a2][alpha]alphamerge',
    );
  }
  buf.write('[keyed];');
  if (c.backgroundKind == 'image') {
    buf.write('[1:v][keyed]scale2ref[bg][k2];');
  } else {
    var bgHex = c.backgroundColor.replaceAll('#', '');
    if (bgHex.length != 6) bgHex = keyHex == '0000FF' ? '0000FF' : '00FF00';
    buf.write('color=c=0x$bgHex[bgraw];');
    buf.write('[bgraw][keyed]scale2ref[bg][k2];');
  }
  buf.write('[bg][k2]overlay=0:0$outLabel');
  return buf.toString();
}

/// Single-frame chroma preview command (one-build, addendum §B.3):
/// runs ONE frame of [input] (at [atSec]) through the EXACT export
/// graph ([chromaFilterComplex]) and writes a PNG, so the Background
/// panel can show the keyed result live — what you see is what the
/// export produces. The output PNG keeps the keyed alpha over the
/// chosen background, same as the export composite.
String chromaPreviewFrameCommand({
  required String input,
  required ProChroma c,
  required String output,
  double atSec = 0.5,
}) {
  final buf = StringBuffer();
  buf.write('-y -ss ${_num(atSec)} -i ${FfmpegService.q(input)} ');
  if (c.backgroundKind == 'image' && c.backgroundImagePath != null) {
    buf.write('-i ${FfmpegService.q(c.backgroundImagePath!)} ');
  }
  final snippet = chromaFilterComplex(c: c, outLabel: '[vout]');
  buf.write(
    '-filter_complex "$snippet" -map "[vout]" -frames:v 1 '
    '${FfmpegService.q(output)}',
  );
  return buf.toString();
}

/// Chroma-key post-pass over an already-exported file (Phase 7):
/// keys out the green/blue background (via [chromaFilterComplex])
/// and composites the foreground over the new background. When the
/// background is an image, [c.backgroundImagePath] is fed as input
/// [1:v] (the exact layout [chromaFilterComplex] requires); a solid
/// colour background needs no second input. Audio is copied
/// untouched. This is the ONE builder both the reel export and the
/// video editor's chroma post-pass use, so the persisted preset
/// sensitivity + background (Template Studio) and the editor's own
/// chroma controls apply through the same graph. Returns the full
/// command string.
String chromaPassCommand({
  required String input,
  required ProChroma c,
  required String output,
}) {
  final buf = StringBuffer();
  buf.write('-y -i ${FfmpegService.q(input)} ');
  if (c.backgroundKind == 'image' && c.backgroundImagePath != null) {
    buf.write('-i ${FfmpegService.q(c.backgroundImagePath!)} ');
  }
  final snippet = chromaFilterComplex(c: c, outLabel: '[vout]');
  buf.write(
    '-filter_complex "$snippet" -map "[vout]" -map 0:a? '
    '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
    '-movflags +faststart ${FfmpegService.q(output)}',
  );
  return buf.toString();
}

// ---------------------------------------------------------------------------
// 6. Stabilization (vidstab two-pass, deshake fallback)
// ---------------------------------------------------------------------------

/// Result of [runStabilized]. [engine] is 'vidstab' or 'deshake'
/// (the fallback actually used); [logs] carries the last pass's
/// output (plus the failed detect log when falling back).
class StabilizeResult {
  const StabilizeResult({
    required this.ok,
    required this.engine,
    required this.logs,
  });

  final bool ok;
  final String engine;
  final String logs;
}

String _trfPath(Directory workDir) => '${workDir.path}/vidstab.trf';

/// Detect-pass command: analyses motion and writes the transform file.
/// Output is `-f null -` (no video is written); audio is dropped
/// with -an because detection needs video only.
String _vidstabDetectCommand({
  required String input,
  required String trfPath,
  int shakiness = 5,
}) {
  return '-y -i ${FfmpegService.q(input)} '
      '-vf "vidstabdetect=shakiness=$shakiness:accuracy=15:stepsize=6:mincontrast=0.3:result=${_filterQuote(trfPath)}" '
      '-an -f null -';
}

/// Transform-pass command: applies the transform file, re-encodes
/// video (libx264 veryfast crf 23 baseline) and audio (aac).
String _vidstabTransformCommand({
  required String input,
  required String trfPath,
  required String output,
  int smoothing = 30,
}) {
  return '-y -i ${FfmpegService.q(input)} '
      '-vf "vidstabtransform=input=${_filterQuote(trfPath)}:smoothing=$smoothing" '
      '-c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${FfmpegService.q(output)}';
}

/// Single-pass deshake fallback command (used only when the vidstab
/// detect pass fails with 'No such filter', i.e. the build was
/// compiled without libvidstab).
String deshakeCommand({
  required String input,
  required String output,
}) {
  return '-y -i ${FfmpegService.q(input)} '
      '-vf "deshake" '
      '-c:v libx264 -preset veryfast -crf 23 -c:a aac -movflags +faststart ${FfmpegService.q(output)}';
}

/// Ordered commands for stabilization, FIRST choice first: the vidstab
/// two-pass sequence [detect, transform]. Run them in order with
/// [runStabilized] (which adds the deshake fallback); running them
/// raw requires [workDir] to exist before the detect pass.
/// NOTE on vidstab options (unverified on this VM — no FFmpeg here):
/// `vidstabdetect` result/shakiness/accuracy/stepsize/mincontrast and
/// `vidstabtransform` input/smoothing are the documented option
/// names; `smoothing=30` frames is a common, conservative value and
/// the transform's other options are left at build defaults (auto
/// zoom/crop) rather than guessed.
List<String> stabilizeCommands({
  required String input,
  required String output,
  required Directory workDir,
  // v1.5.0: stabilizer LEVELS (Low / Standard / Most Stable). The
  // defaults ARE the pre-v1.5.0 values (shakiness 5, smoothing 30),
  // so an unlevelled call renders byte-identical commands.
  int shakiness = 5,
  int smoothing = 30,
}) {
  final trf = _trfPath(workDir);
  return [
    _vidstabDetectCommand(input: input, trfPath: trf, shakiness: shakiness),
    _vidstabTransformCommand(
      input: input,
      trfPath: trf,
      output: output,
      smoothing: smoothing,
    ),
  ];
}

/// Run the vidstab two-pass sequence from [stabilizeCommands].
///
/// Progress contract: the detect pass reports only step text via
/// [onStep] (its output is discarded, so statistics % would be
/// meaningless); the transform pass — or the deshake fallback pass —
/// reports real % via statistics against [expectedMs].
///
/// Fallback rule (exact): ONLY when the detect pass fails AND its
/// logs contain 'No such filter' (case-insensitive, i.e. the build
/// lacks libvidstab) is a single deshake pass run instead, and the
/// result reports engine='deshake'. Any other detect failure returns
/// ok=false with engine='vidstab' and no fallback, so a real error
/// is never masked as a "different engine success".
Future<StabilizeResult> runStabilized({
  required String input,
  required String output,
  required Directory workDir,
  int? expectedMs,
  void Function(double progress)? onProgress,
  void Function(String step)? onStep,
  int shakiness = 5,
  int smoothing = 30,
}) async {
  try {
    await workDir.create(recursive: true);
  } catch (_) {}
  final commands = stabilizeCommands(
    input: input,
    output: output,
    workDir: workDir,
    shakiness: shakiness,
    smoothing: smoothing,
  );
  onStep?.call('Stabilization: analysing motion (pass 1 of 2)…');
  final detect = await FfmpegService.run(commands[0]);
  if (detect.ok) {
    onStep?.call('Stabilization: applying correction (pass 2 of 2)…');
    final transform = await FfmpegService.run(
      commands[1],
      expectedMs: expectedMs,
      onProgress: onProgress,
    );
    return StabilizeResult(
      ok: transform.ok,
      engine: 'vidstab',
      logs: transform.logs,
    );
  }
  final logsLower = detect.logs.toLowerCase();
  if (logsLower.contains('no such filter')) {
    onStep?.call('Stabilization: vidstab not in this build, using deshake…');
    final fallback = await FfmpegService.run(
      deshakeCommand(input: input, output: output),
      expectedMs: expectedMs,
      onProgress: onProgress,
    );
    return StabilizeResult(
      ok: fallback.ok,
      engine: 'deshake',
      logs: 'vidstab detect failed (No such filter), fell back to deshake.\n'
          '${detect.logs}\n${fallback.logs}',
    );
  }
  return StabilizeResult(ok: false, engine: 'vidstab', logs: detect.logs);
}

// ---------------------------------------------------------------------------
// 7. Speed ramping
// ---------------------------------------------------------------------------

/// One constant-speed stretch of the clip: input time
/// [tStart]..[tEnd] plays at [speed]x (0.5 = half speed / slow motion,
/// 1 = normal). Segments must tile [0, duration] with no gaps.
class RampSegment {
  const RampSegment({
    required this.tStart,
    required this.tEnd,
    required this.speed,
  });

  final double tStart;
  final double tEnd;
  final double speed;
}

enum RampPreset { slowMiddle, slowStart, slowEnd, pulse }

/// Build the segment list for [p] covering [0, clipDurationSec]
/// exactly (each segment's tStart equals the previous tEnd).
///   - slowMiddle: normal, slow middle half (0.5x), normal.
///   - slowStart: slow first third (0.5x), then normal.
///   - slowEnd: normal, then slow last third (0.5x).
///   - pulse: alternating normal/slow fifths (1, 0.5, 1, 0.5, 1).
List<RampSegment> rampSegments(
  RampPreset p,
  double clipDurationSec,
) {
  final d = clipDurationSec;
  switch (p) {
    case RampPreset.slowMiddle:
      return [
        RampSegment(tStart: 0, tEnd: d * 0.25, speed: 1),
        RampSegment(tStart: d * 0.25, tEnd: d * 0.75, speed: 0.5),
        RampSegment(tStart: d * 0.75, tEnd: d, speed: 1),
      ];
    case RampPreset.slowStart:
      return [
        RampSegment(tStart: 0, tEnd: d / 3, speed: 0.5),
        RampSegment(tStart: d / 3, tEnd: d, speed: 1),
      ];
    case RampPreset.slowEnd:
      return [
        RampSegment(tStart: 0, tEnd: d * 2 / 3, speed: 1),
        RampSegment(tStart: d * 2 / 3, tEnd: d, speed: 0.5),
      ];
    case RampPreset.pulse:
      return [
        RampSegment(tStart: 0, tEnd: d * 0.2, speed: 1),
        RampSegment(tStart: d * 0.2, tEnd: d * 0.4, speed: 0.5),
        RampSegment(tStart: d * 0.4, tEnd: d * 0.6, speed: 1),
        RampSegment(tStart: d * 0.6, tEnd: d * 0.8, speed: 0.5),
        RampSegment(tStart: d * 0.8, tEnd: d, speed: 1),
      ];
  }
}

/// Video filter `setpts='...'` implementing the ramp.
///
/// Mapping: output time = (sum over completed segments of
/// segDur/speed) + (T - segStart)/speed for the segment containing
/// input time T. Built as nested `if(lt(...),...)` expressions. The
/// expression is single-quoted because it contains commas, which
/// would otherwise split the filter chain. For an empty segment
/// list this returns the identity `setpts=PTS`.
/// NOTE: the result is continuous at segment boundaries by
/// construction (each segment's offset is the previous segments'
/// stretched durations), so there is no jump or freeze at joins.
///
/// UNITS (verified by render test, Build 3): setpts hands the
/// expression PTS in INPUT TIMEBASE units, not seconds — the
/// segment boundaries/offsets here are seconds, so the expression
/// reads the input time as (PTS*TB) and converts the result back
/// with /TB. The earlier form compared raw PTS against second
/// constants: every frame fell into the last branch and a
/// 0.5/1/2 ramp over 6 s rendered 3.07 s instead of 7 s. (The
/// plain `setpts=PTS/speed` usage elsewhere is a pure ratio and
/// is unit-independent — which is how the wrong assumption
/// survived.) The audio side ([rampAudioFilter]) uses atrim
/// windows, which ARE in seconds, and was never affected.
String rampSetpts(List<RampSegment> segs) {
  if (segs.isEmpty) return 'setpts=PTS';
  // Build from the last segment backwards: the last segment's plain
  // expression is the innermost else-branch. `t` is the input time
  // in SECONDS ((PTS*TB)); the whole result is converted back to
  // timebase units by the /TB wrapper at the end.
  const t = '(PTS*TB)';
  var expr = '';
  var offset = 0.0;
  // Precompute each segment's stretched offset (start time in the
  // OUTPUT timeline).
  final offsets = <double>[];
  for (final s in segs) {
    offsets.add(offset);
    offset += (s.tEnd - s.tStart) / s.speed;
  }
  for (var i = segs.length - 1; i >= 0; i--) {
    final s = segs[i];
    final here =
        '(${_num(offsets[i])}+($t-${_num(s.tStart)})/${_num(s.speed)})';
    if (i == segs.length - 1) {
      expr = here;
    } else {
      expr = "if(lt($t,${_num(s.tEnd)}),$here,$expr)";
    }
  }
  return "setpts='($expr)/TB'";
}

/// Audio filter_complex snippet (no trailing ';') that keeps audio
/// in sync with [rampSetpts]: [0:a] is split into one branch per
/// segment, each branch is trimmed to its window, timestamp-reset,
/// and tempo-shifted with atempo, then all branches are concatenated
/// back into [aout]. The caller embeds this in a -filter_complex
/// alongside the video chain and maps "[aout]".
///
/// CHOICE, STATED CLEARLY: the ramp REQUIRES this audio chain.
/// There is deliberately NO video-only fallback that drops audio —
/// silently losing the clip's audio would be worse than failing.
/// If this chain fails at export time, the caller must keep the
/// UN-RAMPED export (original speed, original audio) and report the
/// ramp as failed. Exception: a clip with no audio track at all
/// simply skips this chain and uses [rampSetpts] alone (nothing is
/// being dropped — there was no audio to keep).
/// atempo accepts 0.5..100, so the 0.5x slow segments are in range;
/// segments at speed 1 still pass through atempo=1 to keep the chain
/// uniform (atempo=1 is a no-op resample, not a quality loss of note).
String rampAudioFilter(List<RampSegment> segs) {
  if (segs.isEmpty) return '';
  final buf = StringBuffer();
  buf.write('[0:a]asplit=${segs.length}');
  for (var i = 0; i < segs.length; i++) {
    buf.write('[a$i]');
  }
  buf.write(';');
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    buf.write(
      '[a$i]atrim=start=${_num(s.tStart)}:end=${_num(s.tEnd)},'
      'asetpts=PTS-STARTPTS,atempo=${_num(s.speed)}[s$i];',
    );
  }
  for (var i = 0; i < segs.length; i++) {
    buf.write('[s$i]');
  }
  buf.write('concat=n=${segs.length}:v=0:a=1[aout]');
  return buf.toString();
}
