/// ONE source of truth for the v1.4.0 Adjust extras (Colour ›
/// Adjust) — tools-fix wave P1-1.
///
/// Before this file, the export's ffmpeg chain (`_adjustExtraFilter`
/// in the editor screen) was the ONLY place these ten controls
/// existed: the preview's colour matrix never read them, so the
/// Brilliance / Whites / Blacks / Hue / Fade sliders appeared
/// dead and Sharpen / Clarity / Vignette / Grain were invisible
/// until export. Now the DERIVATION lives here, pure Dart:
///
///   - [adjustExtraFilterChain] builds the export's ffmpeg chain
///     from the derived parameters (the exact chain the export
///     has always produced — same filters, same order, same
///     number formatting);
///   - [adjustPreviewMatrix] builds the preview's 4x5 colour
///     matrix from the SAME parameters: the brilliance saturation
///     exactly, the hue rotation in the standard hue-rotate
///     matrix form, and the gamma∘curves tone function as a
///     least-squares linear fit of the very function the export's
///     `curves` points are sampled from;
///   - [AdjustParams.vignetteStrength] / [AdjustParams.grainOpacity]
///     drive the stage's vignette / grain overlays, scaled from
///     the same angle / noise amount the export uses.
///
/// NOT previewable with Flutter widgets, and honestly absent
/// from the preview: the LUT (a 3D .cube lookup cannot run on a
/// live video texture through a ColorFilter) and Sharpen /
/// Clarity (unsharp is a convolution — no widget equivalent).
/// Their parameters are still derived here and still reach the
/// export exactly as before.
library;

import 'dart:math' as math;

/// The ten Adjust extra values, exactly as the editor holds them.
class AdjustValues {
  const AdjustValues({
    this.auto = false,
    this.brilliance = 0,
    this.sharpen = 0,
    this.clarity = 0,
    this.whites = 0,
    this.blacks = 0,
    this.hue = 0,
    this.fade = 0,
    this.vignette = 0,
    this.grain = 0,
  });

  /// One-tap normalize (ffmpeg `normalize` — content-dependent,
  /// export-only by nature).
  final bool auto;
  final double brilliance; // -100..100
  final double sharpen; // 0..100
  final double clarity; // 0..100
  final double whites; // -100..100
  final double blacks; // -100..100
  final double hue; // -180..180 degrees
  final double fade; // 0..100
  final double vignette; // 0..100
  final double grain; // 0..100

  bool get isNeutral =>
      !auto &&
      brilliance == 0 &&
      sharpen == 0 &&
      clarity == 0 &&
      whites == 0 &&
      blacks == 0 &&
      hue == 0 &&
      fade == 0 &&
      vignette == 0 &&
      grain == 0;
}

/// Everything derived from [AdjustValues] ONCE — the export chain
/// and the preview both read these numbers, never re-derive them.
class AdjustParams {
  const AdjustParams({
    required this.gamma,
    required this.saturation,
    required this.sharpenAmount,
    required this.clarityAmount,
    required this.curveY,
    required this.hueDeg,
    required this.vignetteAngle,
    required this.vignetteStrength,
    required this.grainAmount,
  });

  /// Brilliance → eq gamma (2^(b/200)).
  final double gamma;

  /// Brilliance → eq saturation (1 + b/400).
  final double saturation;

  /// Sharpen → unsharp 5:5 amount (value/50).
  final double sharpenAmount;

  /// Clarity → unsharp 13:13 amount (value/100).
  final double clarityAmount;

  /// Whites/Blacks/Fade → the curves tone function y(x), x,y in
  /// 0..1 — the export samples it at 5 points for `curves=master`;
  /// the preview fits a line to gamma∘curveY.
  final double Function(double) curveY;

  /// Hue rotation in degrees.
  final double hueDeg;

  /// Vignette → ffmpeg vignette angle.
  final double vignetteAngle;

  /// Vignette → preview overlay strength 0..1 (value/100).
  final double vignetteStrength;

  /// Grain → ffmpeg noise amount 0..40.
  final int grainAmount;

  /// Grain → preview overlay opacity (the amount scaled to a
  /// tasteful maximum — a preview-only presentation constant;
  /// the export amount above is untouched by it).
  double get grainOpacity => grainAmount / 40 * 0.35;
}

/// The derivation — the formulas are the ones the export chain
/// has always used, moved here verbatim so both sides share them.
AdjustParams deriveAdjustParams(AdjustValues v) {
  final b = v.brilliance.clamp(-100, 100).toDouble();
  final gamma = math.pow(2, b / 200).toDouble();
  final sat = 1 + b / 400;

  final double blackLift = (v.blacks.clamp(-100, 100) / 100 * 0.12) +
      v.fade.clamp(0, 100) / 100 * 0.15;
  final double whiteMove = v.whites.clamp(-100, 100) / 100 * 0.12;
  final fade = v.fade.clamp(0, 100).toDouble();
  double curveY(double x) {
    var out = x + blackLift * (1 - x) * (1 - x) + whiteMove * x * x;
    if (fade > 0) {
      out = out * (1 - fade / 100 * 0.3) + fade / 100 * 0.3 * 0.2;
    }
    return out.clamp(0.0, 1.0).toDouble();
  }

  return AdjustParams(
    gamma: gamma,
    saturation: sat,
    sharpenAmount: v.sharpen.clamp(0, 100) / 50,
    clarityAmount: v.clarity.clamp(0, 100) / 100,
    curveY: curveY,
    hueDeg: v.hue.clamp(-180, 180).toDouble(),
    vignetteAngle: 1.5 - v.vignette.clamp(0, 100) / 100 * 1.1,
    vignetteStrength: (v.vignette.clamp(0, 100) / 100).toDouble(),
    grainAmount: (v.grain.clamp(0, 100) / 100 * 40).round(),
  );
}

/// The export's ffmpeg chain for the Adjust extras ('' = nothing
/// set). Byte-for-byte the chain the editor has always produced:
/// normalize (auto), eq gamma/saturation (brilliance), unsharp
/// (sharpen/clarity), curves endpoints (whites/blacks/fade), hue,
/// vignette, noise (grain).
String adjustExtraFilterChain(AdjustValues v) {
  final p = deriveAdjustParams(v);
  final parts = <String>[];
  String n(double x) {
    var s = x.toStringAsFixed(3);
    while (s.contains('.') && s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s.isEmpty || s == '-0' ? '0' : s;
  }

  if (v.auto) parts.add('normalize');
  if (v.brilliance != 0) {
    parts.add('eq=gamma=${n(p.gamma)}:saturation=${n(p.saturation)}');
  }
  if (v.sharpen != 0) {
    parts.add('unsharp=5:5:${n(p.sharpenAmount)}');
  }
  if (v.clarity != 0) {
    parts.add('unsharp=13:13:${n(p.clarityAmount)}');
  }
  if (v.whites != 0 || v.blacks != 0 || v.fade != 0) {
    final pts = [0.0, 0.25, 0.5, 0.75, 1.0]
        .map((x) => '${n(x)}/${p.curveY(x).toStringAsFixed(3)}')
        .join(';');
    parts.add("curves=master='$pts'");
  }
  if (v.hue != 0) {
    parts.add('hue=h=${n(p.hueDeg)}');
  }
  if (v.vignette != 0) {
    parts.add('vignette=angle=${n(p.vignetteAngle)}');
  }
  if (v.grain != 0) {
    parts.add('noise=alls=${p.grainAmount}:allf=t');
  }
  return parts.join(',');
}

/// Compose two 4x5 colour matrices: the result applies [b] first,
/// then [a] (the ColorFilter convention).
List<double> multiplyColorMatrices(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) sum += a[row * 5 + 4];
      out[row * 5 + col] = sum;
    }
  }
  return out;
}

List<double> _saturationMatrix(double s) {
  return [
    0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
    0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
    0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// The standard hue-rotate matrix (the SVG feColorMatrix form) —
/// the matrix counterpart of the export's `hue=h=` rotation.
List<double> _hueRotateMatrix(double deg) {
  final rad = deg * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  return [
    0.213 + c * 0.787 - s * 0.213,
    0.715 - c * 0.715 - s * 0.715,
    0.072 - c * 0.072 + s * 0.928,
    0, 0,
    0.213 - c * 0.213 + s * 0.143,
    0.715 + c * 0.285 + s * 0.140,
    0.072 - c * 0.072 - s * 0.283,
    0, 0,
    0.213 - c * 0.213 - s * 0.787,
    0.715 - c * 0.715 + s * 0.715,
    0.072 + c * 0.928 + s * 0.072,
    0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// The preview's colour matrix for the Adjust extras, built from
/// the SAME derived parameters as the export chain: saturation
/// (exact), the gamma∘curves tone function as a least-squares
/// linear fit (a matrix cannot bend, so the fit tracks the real
/// curve's gain + lift), and the hue rotation. Neutral values
/// give the identity matrix.
List<double> adjustPreviewMatrix(AdjustValues v) {
  final p = deriveAdjustParams(v);
  // Compose the tone function exactly as the export orders it:
  // eq gamma first, then the curves function.
  double tone(double x) {
    final g = math.pow(x, 1 / p.gamma).toDouble();
    return p.curveY(g);
  }

  // Least-squares line fit y ≈ a·x + b over 0..1.
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  const samples = 20;
  for (var i = 0; i <= samples; i++) {
    final x = i / samples;
    final y = tone(x);
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
  }
  final n = (samples + 1).toDouble();
  final denom = n * sxx - sx * sx;
  final a = denom == 0 ? 1.0 : (n * sxy - sx * sy) / denom;
  final bIntercept = (sy - a * sx) / n;
  final toneM = <double>[
    a, 0, 0, 0, 255 * bIntercept,
    0, a, 0, 0, 255 * bIntercept,
    0, 0, a, 0, 255 * bIntercept,
    0, 0, 0, 1, 0,
  ];
  final satM = _saturationMatrix(p.saturation);
  final hueM = _hueRotateMatrix(p.hueDeg);
  // Export order: eq (gamma+sat) → curves → hue. The tone fit
  // already contains gamma+curves; saturation is linear, so the
  // composition hue ∘ tone ∘ sat tracks it.
  return multiplyColorMatrices(hueM, multiplyColorMatrices(toneM, satM));
}
