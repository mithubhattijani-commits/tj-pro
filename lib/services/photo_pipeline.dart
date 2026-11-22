import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'ai_service.dart';

/// Photo filter presets (CapCut-style quick looks).
enum PhotoFilter { normal, warm, cool, blackWhite, vivid, sepia }

/// Everything the export pass needs. Filters/sliders/text are non-destructive:
/// they are applied here at export time, while crop/rotate/AI ops mutate the
/// working file directly (see the photo editor screen).
class PhotoEditParams {
  const PhotoEditParams({
    this.filter = PhotoFilter.normal,
    // Round-2 (21 Nov 2026): filter strength 0..1 (1 = full filter).
    this.filterIntensity = 1.0,
    // Round-2: selected .cube LUT ('' / null table = none). [lutTable] is
    // the parsed RGB table from [parseCubeLut], [lutSize] its edge size.
    this.lutName = '',
    this.lutSize = 0,
    this.lutTable,
    this.brightness = 0, // -100..100
    this.contrast = 1.0, // 0..2
    this.saturation = 1.0, // 0..2
    // Round-2 Adjust panel (12 sliders): the 9 controls beyond the
    // original Brightness/Contrast/Saturation trio.
    this.exposure = 0, // -100..100 (gain = 2^(v/100))
    this.highlights = 0, // -100..100, luminance-masked (bright end)
    this.shadows = 0, // -100..100, luminance-masked (dark end)
    this.vibrance = 0, // -100..100, gentle saturation move
    this.temperature = 0, // -100 (cool) .. 100 (warm)
    this.tint = 0, // -100 (magenta) .. 100 (green)
    this.sharpenDetail = 0, // 0..100, unsharp amount = v/100
    this.vignette = 0, // 0..100, radial edge darkening
    this.fade = 0, // 0..100, lifted blacks + reduced contrast
    // v1.4.0 Adjust additions: global hue rotation in degrees
    // (-180..180, applied as a uniform HSL hue shift), film grain
    // amount 0..100, and an optional per-channel tone curve as four
    // 256-entry LUTs ([rgb, r, g, b], see [applyToneCurve]).
    this.hueShift = 0,
    this.grain = 0,
    this.curveLuts,
    this.text = '',
    this.textArgb = 0xFFFFFFFF,
    this.textSize = 48.0,
    this.textOffsetX = 0.5, // normalized center of the text box
    this.textOffsetY = 0.85,
    // CapCut-style text effects (Jaani 31 Oct 2026).
    this.textShadow = true,
    this.textGlow = false,
    this.textBg = false,
    this.textBgArgb = 0x8A000000,
    this.textLineHeight = 1.0, // line spacing multiplier (daily 2026-10-31)
    // Round-2 export fix (P9): EVERY Text panel setting now reaches the
    // export — previously font/bold/italic/opacity/spacing/outline/align
    // were preview-only and silently dropped here.
    this.textFont = 'default', // font key, see _fontFamilyForKey
    this.textBold = false,
    this.textItalic = false,
    this.textOpacity = 1.0, // 0..1
    this.textLetterSpacing = 0.0,
    this.textOutline = false,
    this.textOutlineArgb = 0xFF000000,
    this.textOutlineWidth = 2.0,
    this.textAlignIndex = 1, // 0 = left, 1 = center, 2 = right
  });

  final PhotoFilter filter;
  final double filterIntensity;
  final String lutName;
  final int lutSize;
  final List<double>? lutTable;
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double highlights;
  final double shadows;
  final double vibrance;
  final double temperature;
  final double tint;
  final double sharpenDetail;
  final double vignette;
  final double fade;
  final double hueShift;
  final double grain;
  final List<List<int>>? curveLuts;
  final String text;
  final int textArgb;
  final double textSize;
  final double textOffsetX;
  final double textOffsetY;
  final bool textShadow;
  final bool textGlow;
  final bool textBg;
  final int textBgArgb;
  final double textLineHeight;
  final String textFont;
  final bool textBold;
  final bool textItalic;
  final double textOpacity;
  final double textLetterSpacing;
  final bool textOutline;
  final int textOutlineArgb;
  final double textOutlineWidth;
  final int textAlignIndex;

  /// True when any non-matrix Adjust control needs the per-pixel pass.
  bool get needsPixelAdjust =>
      highlights != 0 || shadows != 0 || vignette != 0 || sharpenDetail != 0;
}

// ---------------------------------------------------------------------------
// 4x5 color matrices (row-major, 20 values). Flutter's ColorFilter.matrix
// uses the same layout, so the preview matrix and the export matrix are the
// same numbers — preview == export.
// ---------------------------------------------------------------------------

List<double> _identity() => [
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Compose two 4x5 matrices: result = a ∘ b (b applied first, then a).
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[i * 5 + k] * b[k * 5 + j];
      }
      out[i * 5 + j] = sum;
    }
    var off = a[i * 5 + 4];
    for (var k = 0; k < 4; k++) {
      off += a[i * 5 + k] * b[k * 5 + 4];
    }
    out[i * 5 + 4] = off;
  }
  return out;
}

List<double> _diag(double r, double g, double b) => [
  r, 0, 0, 0, 0,
  0, g, 0, 0, 0,
  0, 0, b, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> _saturationMatrix(double s) {
  const lr = 0.299, lg = 0.587, lb = 0.114;
  return [
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0,
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0,
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> _filterMatrix(PhotoFilter f) {
  switch (f) {
    case PhotoFilter.normal:
      return _identity();
    case PhotoFilter.warm:
      return _diag(1.12, 1.0, 0.82);
    case PhotoFilter.cool:
      return _diag(0.85, 1.0, 1.15);
    case PhotoFilter.blackWhite:
      return [
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case PhotoFilter.vivid:
      // saturation 1.4, then contrast 1.08
      final sat = _saturationMatrix(1.4);
      final con = _diag(1.08, 1.08, 1.08);
      con[4] = 128 * (1 - 1.08);
      con[9] = 128 * (1 - 1.08);
      con[14] = 128 * (1 - 1.08);
      return _mul(con, sat);
    case PhotoFilter.sepia:
      return [
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ];
  }
}

/// Blend two matrices element-wise: [t] = 0 gives [a], 1 gives [b].
/// Used for filter intensity (identity <-> filter look).
List<double> _lerpMatrix(List<double> a, List<double> b, double t) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 20; i++) {
    out[i] = a[i] + (b[i] - a[i]) * t;
  }
  return out;
}

/// Single matrix for preview (ColorFilter.matrix) AND export.
///
/// Round-2: also carries the matrix-expressible Adjust controls —
/// [exposure] (power-of-two gain), [temperature] / [tint] (channel
/// gains), [vibrance] (gentle saturation move, same approximation as
/// the video grader) and [fade] (contrast scale-down + black lift).
/// Highlights/Shadows/Vignette/Sharpen are NOT linear and live in
/// [applyAdjustments] instead; [filterIntensity] blends the chosen
/// filter look with the untouched photo.
List<double> buildColorMatrix({
  required PhotoFilter filter,
  required double brightness, // -100..100
  required double contrast, // 0..2
  required double saturation, // 0..2
  double filterIntensity = 1.0, // 0..1
  double exposure = 0, // -100..100
  double temperature = 0, // -100 (cool) .. 100 (warm)
  double tint = 0, // -100 (magenta) .. 100 (green)
  double vibrance = 0, // -100..100
  double fade = 0, // 0..100
}) {
  final f = _lerpMatrix(
    _identity(),
    _filterMatrix(filter),
    filterIntensity.clamp(0.0, 1.0),
  );
  // Vibrance rides on the saturation matrix at half strength (it must
  // stay a matrix for the live preview; the approximation is the same
  // one the video ProGrade documents).
  final vibFactor = 1 + (vibrance.clamp(-100, 100) / 100) * 0.5;
  final satEff = (saturation * vibFactor).clamp(0.0, 3.0);
  final sat = _saturationMatrix(satEff);
  // Exposure + temperature + tint as one channel-gain matrix.
  final gain = math.pow(2, exposure.clamp(-100, 100) / 100).toDouble();
  final t = temperature.clamp(-100, 100) / 100;
  final ti = tint.clamp(-100, 100) / 100;
  final gains = _diag(
    gain * (1 + 0.15 * t) * (1 - 0.06 * ti),
    gain * (1 + 0.12 * ti),
    gain * (1 - 0.15 * t) * (1 - 0.06 * ti),
  );
  final con = _diag(contrast, contrast, contrast);
  final off = 128 * (1 - contrast);
  con[4] = off;
  con[9] = off;
  con[14] = off;
  // Fade: pull contrast toward 1.0-ish flatness and lift the blacks.
  final fd = fade.clamp(0, 100) / 100;
  final fadeM = _diag(1 - 0.25 * fd, 1 - 0.25 * fd, 1 - 0.25 * fd);
  final lift = 255 * 0.15 * fd;
  fadeM[4] = lift;
  fadeM[9] = lift;
  fadeM[14] = lift;
  final bri = _identity();
  final bo = brightness * 2.55;
  bri[4] = bo;
  bri[9] = bo;
  bri[14] = bo;
  // Apply filter -> saturation -> gains -> contrast -> fade -> brightness.
  return _mul(bri, _mul(fadeM, _mul(con, _mul(gains, _mul(sat, f)))));
}

// ---------------------------------------------------------------------------
// Isolate jobs (top-level, pure Dart, no dart:ui).
// ---------------------------------------------------------------------------

Uint8List _applyMatrixJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final m = args[1] as List<double>;
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i += 4) {
    final r = bytes[i].toDouble();
    final g = bytes[i + 1].toDouble();
    final b = bytes[i + 2].toDouble();
    final a = bytes[i + 3].toDouble();
    out[i] = (m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4])
        .clamp(0, 255)
        .round();
    out[i + 1] = (m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9])
        .clamp(0, 255)
        .round();
    out[i + 2] = (m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14])
        .clamp(0, 255)
        .round();
    out[i + 3] = (m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19])
        .clamp(0, 255)
        .round();
  }
  return out;
}

/// Per-channel 2%/98% percentile stretch + mild saturation boost.
/// Algorithmic (not ML) — the UI labels it honestly as "Auto-enhance".
Uint8List _autoEnhanceJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final out = Uint8List.fromList(bytes);
  const channels = 3;
  for (var c = 0; c < channels; c++) {
    final hist = List<int>.filled(256, 0);
    for (var i = c; i < bytes.length; i += 4) {
      hist[bytes[i]]++;
    }
    final total = bytes.length ~/ 4;
    var acc = 0;
    var lo = 0;
    var hi = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.02) {
        lo = v;
        break;
      }
    }
    acc = 0;
    for (var v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= total * 0.02) {
        hi = v;
        break;
      }
    }
    if (hi <= lo) continue;
    final scale = 255.0 / (hi - lo);
    for (var i = c; i < bytes.length; i += 4) {
      out[i] = ((bytes[i] - lo) * scale).clamp(0, 255).round();
    }
  }
  // Mild saturation lift on the stretched values.
  const s = 1.15;
  for (var i = 0; i < out.length; i += 4) {
    final r = out[i].toDouble();
    final g = out[i + 1].toDouble();
    final b = out[i + 2].toDouble();
    final lum = 0.299 * r + 0.587 * g + 0.114 * b;
    out[i] = (lum + (r - lum) * s).clamp(0, 255).round();
    out[i + 1] = (lum + (g - lum) * s).clamp(0, 255).round();
    out[i + 2] = (lum + (b - lum) * s).clamp(0, 255).round();
  }
  return out;
}

Uint8List _beautifyJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final faces = args[3] as List<List<double>>; // [left, top, right, bottom]
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final srcBytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final blurred = img.gaussianBlur(rgba, radius: 8);
  final blurBytes = blurred.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List.fromList(srcBytes);
  for (final f in faces) {
    final left = (f[0] - (f[2] - f[0]) * 0.1).clamp(0, w - 1).toInt();
    final top = (f[1] - (f[3] - f[1]) * 0.1).clamp(0, h - 1).toInt();
    final right = (f[2] + (f[2] - f[0]) * 0.1).clamp(0, w - 1).toInt();
    final bottom = (f[3] + (f[3] - f[1]) * 0.1).clamp(0, h - 1).toInt();
    final fw = math.max(1, right - left);
    final fh = math.max(1, bottom - top);
    final featherX = math.max(1, fw ~/ 8);
    final featherY = math.max(1, fh ~/ 8);
    for (var y = top; y <= bottom; y++) {
      final wy = _featherWeight(y - top, bottom - y, featherY);
      for (var x = left; x <= right; x++) {
        final wx = _featherWeight(x - left, right - x, featherX);
        final weight = (wx * wy * 0.75).clamp(0.0, 0.75);
        final idx = (y * w + x) * 4;
        for (var c = 0; c < 3; c++) {
          out[idx + c] =
              (srcBytes[idx + c] * (1 - weight) + blurBytes[idx + c] * weight)
                  .round();
        }
      }
    }
  }
  return out;
}

double _featherWeight(int dNear, int dFar, int feather) {
  final d = math.min(dNear, dFar);
  if (d >= feather) return 1.0;
  return d / feather;
}

// ---------------------------------------------------------------------------
// Remini-style Enhance jobs (Priority 1, 31 Oct 2026 — Jaani).
// All algorithmic, on-device, FREE (not Premium). One-tap style.
// ---------------------------------------------------------------------------

/// Unsharp mask sharpen: out = src + amount * (src - blurred).
/// Reduces blur/softness. amount 0.5 is a safe default.
Uint8List _sharpenJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  // Note: args[1] (w) and args[2] (h) intentionally unused.
  final amount = (args[3] as num).toDouble();
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final srcBytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final blurred = img.gaussianBlur(rgba, radius: 2);
  final blurBytes = blurred.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List(srcBytes.length);
  for (var i = 0; i < srcBytes.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final s = srcBytes[i + c].toDouble();
      final b = blurBytes[i + c].toDouble();
      out[i + c] = (s + (s - b) * amount).clamp(0, 255).round();
    }
    out[i + 3] = srcBytes[i + 3]; // keep alpha
  }
  return out;
}

/// Denoise: mild gaussian blur blended back to preserve detail.
/// strength 0.0..1.0 — 0.6 is a good default (removes grain, keeps edges).
Uint8List _denoiseJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final strength = (args[1] as num).toDouble().clamp(0.0, 1.0);
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final srcBytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final blurred = img.gaussianBlur(rgba, radius: 1);
  final blurBytes = blurred.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List(srcBytes.length);
  for (var i = 0; i < srcBytes.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      out[i + c] = (srcBytes[i + c] * (1 - strength) +
              blurBytes[i + c] * strength)
          .round();
    }
    out[i + 3] = srcBytes[i + 3];
  }
  return out;
}

/// InShot-style HSL: per-color Hue/Saturation/Lightness adjustment.
/// [adjustments] is a list of 8x3 doubles: for each color range
/// (Red, Orange, Yellow, Green, Cyan, Blue, Purple, Magenta),
/// [hueShift (-180..180), satScale (0..2), lightOffset (-100..100)].
/// Pixels are weighted by how close their hue is to each range center.
Uint8List _hslJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final adj = args[1] as List<dynamic>; // 8 x List<double>(3)
  final out = Uint8List.fromList(bytes);
  // Hue range centers in degrees (0-360).
  const centers = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 280.0, 320.0];
  for (var i = 0; i < bytes.length; i += 4) {
    final r = bytes[i] / 255.0;
    final g = bytes[i + 1] / 255.0;
    final b = bytes[i + 2] / 255.0;
    final hsl = _rgbToHsl(r, g, b);
    var h = hsl[0], s = hsl[1], l = hsl[2];
    // Find the two nearest color ranges and blend.
    for (var c = 0; c < 8; c++) {
      var dh = (h - centers[c]).abs();
      if (dh > 180) dh = 360 - dh;
      // Weight falls off over 45 degrees.
      final w = (1.0 - dh / 45.0).clamp(0.0, 1.0);
      if (w <= 0) continue;
      final a = adj[c] as List<dynamic>;
      final hShift = (a[0] as num).toDouble();
      final sScale = (a[1] as num).toDouble();
      final lOff = (a[2] as num).toDouble();
      h = (h + hShift * w) % 360;
      if (h < 0) h += 360;
      s = (s * (1 + (sScale - 1) * w)).clamp(0.0, 1.0);
      l = (l + (lOff / 100) * w).clamp(0.0, 1.0);
    }
    final rgb = _hslToRgb(h, s, l);
    out[i] = (rgb[0] * 255).clamp(0, 255).round();
    out[i + 1] = (rgb[1] * 255).clamp(0, 255).round();
    out[i + 2] = (rgb[2] * 255).clamp(0, 255).round();
  }
  return out;
}

List<double> _rgbToHsl(double r, double g, double b) {
  final maxC = [r, g, b].reduce((a, v) => a > v ? a : v);
  final minC = [r, g, b].reduce((a, v) => a < v ? a : v);
  final l = (maxC + minC) / 2;
  if (maxC == minC) return [0.0, 0.0, l];
  final d = maxC - minC;
  final s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
  double h;
  if (maxC == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (maxC == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return [h * 60, s, l];
}

List<double> _hslToRgb(double h, double s, double l) {
  h = h % 360;
  if (h < 0) h += 360;
  if (s == 0) return [l, l, l];
  double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  double p = 2 * l - q;
  double hk = h / 360;
  double tr = (hk + 1 / 3) % 1;
  double tg = hk % 1;
  double tb = (hk - 1 / 3) % 1;
  if (tb < 0) tb += 1;
  double conv(double t) {
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }
  return [conv(tr), conv(tg), conv(tb)];
}

/// Gray-world white balance + per-channel levels stretch.
/// Fixes color casts (too yellow/blue) and dull contrast.
Uint8List _colorFixJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final out = Uint8List.fromList(bytes);
  final n = bytes.length ~/ 4;
  // Gray-world: scale channels so their means are equal.
  var sumR = 0.0, sumG = 0.0, sumB = 0.0;
  for (var i = 0; i < bytes.length; i += 4) {
    sumR += bytes[i];
    sumG += bytes[i + 1];
    sumB += bytes[i + 2];
  }
  final meanR = sumR / n, meanG = sumG / n, meanB = sumB / n;
  final meanAll = (meanR + meanG + meanB) / 3;
  final sR = meanR > 1 ? meanAll / meanR : 1.0;
  final sG = meanG > 1 ? meanAll / meanG : 1.0;
  final sB = meanB > 1 ? meanAll / meanB : 1.0;
  // Clamp the correction so it never goes extreme.
  final cR = sR.clamp(0.7, 1.4);
  final cG = sG.clamp(0.7, 1.4);
  final cB = sB.clamp(0.7, 1.4);
  for (var i = 0; i < bytes.length; i += 4) {
    out[i] = (bytes[i] * cR).clamp(0, 255).round();
    out[i + 1] = (bytes[i + 1] * cG).clamp(0, 255).round();
    out[i + 2] = (bytes[i + 2] * cB).clamp(0, 255).round();
  }
  return out;
}

Uint8List _maskJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final mask = args[3] as List<double>;
  final maskW = args[4] as int;
  final maskH = args[5] as int;
  final remove = args[6] as bool;
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final srcBytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List.fromList(srcBytes);
  Uint8List? blurBytes;
  if (!remove) {
    final blurred = img.gaussianBlur(rgba, radius: 10);
    blurBytes = blurred.getBytes(order: img.ChannelOrder.rgba);
  }
  for (var y = 0; y < h; y++) {
    final my = (y * maskH ~/ h).clamp(0, maskH - 1);
    for (var x = 0; x < w; x++) {
      final mx = (x * maskW ~/ w).clamp(0, maskW - 1);
      final conf = mask[my * maskW + mx].clamp(0.0, 1.0);
      final idx = (y * w + x) * 4;
      if (remove) {
        // Feathered alpha cutout: fully opaque above 0.6, transparent below.
        final a = ((conf - 0.4) / 0.2).clamp(0.0, 1.0);
        out[idx + 3] = (a * 255).round();
      } else {
        for (var c = 0; c < 3; c++) {
          out[idx + c] =
              (srcBytes[idx + c] * conf + blurBytes![idx + c] * (1 - conf))
                  .round();
        }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Public pipeline API.
// ---------------------------------------------------------------------------

/// Apply the preview matrix to [src] (export pass).
Future<img.Image> applyColorMatrix(
  img.Image src,
  List<double> matrix,
) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_applyMatrixJob, [bytes, matrix]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

// ---------------------------------------------------------------------------
// Round-2 Adjust pass: the non-linear controls a 4x5 matrix cannot
// express — Highlights / Shadows (luminance-masked), Vignette (radial).
// Sharpen (Detail) reuses the unsharp job via [applyAdjustments].
// ---------------------------------------------------------------------------

Uint8List _adjustJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final highlights = (args[3] as num).toDouble().clamp(-100, 100);
  final shadows = (args[4] as num).toDouble().clamp(-100, 100);
  final vignette = (args[5] as num).toDouble().clamp(0, 100);
  final out = Uint8List.fromList(bytes);
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  final maxDist = math.sqrt(cx * cx + cy * cy);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = bytes[i] / 255.0;
      final g = bytes[i + 1] / 255.0;
      final b = bytes[i + 2] / 255.0;
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      // Luminance-masked: highlights move only the bright end, shadows
      // only the dark end; mid-tones stay (nearly) untouched.
      final hiW = lum * lum;
      final shW = (1 - lum) * (1 - lum);
      var delta = (highlights / 100) * 0.35 * hiW +
          (shadows / 100) * 0.35 * shW;
      var nr = r + delta;
      var ng = g + delta;
      var nb = b + delta;
      if (vignette > 0 && maxDist > 0) {
        final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) /
            maxDist; // 0 center .. 1 corner
        // Start darkening past 55% of the radius, full strength at the
        // corners; max darkening 55% at slider 100.
        final edge = ((d - 0.55) / 0.45).clamp(0.0, 1.0);
        final dark = 1 - (vignette / 100) * 0.55 * edge * edge;
        nr *= dark;
        ng *= dark;
        nb *= dark;
      }
      out[i] = (nr * 255).clamp(0, 255).round();
      out[i + 1] = (ng * 255).clamp(0, 255).round();
      out[i + 2] = (nb * 255).clamp(0, 255).round();
    }
  }
  return out;
}

/// Apply the non-linear Adjust controls. Highlights/Shadows in
/// -100..100, Vignette 0..100, Sharpen (Detail) 0..100 mapped onto the
/// unsharp-mask amount 0..1. Returns [src] untouched when all are 0.
Future<img.Image> applyAdjustments(
  img.Image src, {
  double highlights = 0,
  double shadows = 0,
  double vignette = 0,
  double sharpenDetail = 0,
}) async {
  var out = src;
  if (highlights != 0 || shadows != 0 || vignette != 0) {
    final rgba = out.convert(numChannels: 4);
    final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
    final res = await compute(
      _adjustJob,
      [bytes, src.width, src.height, highlights, shadows, vignette],
    );
    out = img.Image.fromBytes(
      width: src.width,
      height: src.height,
      bytes: res.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  }
  if (sharpenDetail > 0) {
    out = await sharpenImage(
      out,
      amount: (sharpenDetail.clamp(0, 100) / 100).toDouble(),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Round-2 LUTs: the same 5 .cube looks the video editor ships
// (assets/luts/*.cube, LUT_3D_SIZE 32). Minimal parser + trilinear
// per-pixel apply — used at FULL resolution for export, never just on
// a preview downscale.
// ---------------------------------------------------------------------------

/// The photo editor's LUT row: display name -> Flutter asset path.
/// Mirrors ProGrade.proLuts in pro_editor.dart (same files).
const photoLuts = [
  {'name': 'TealOrange', 'asset': 'assets/luts/teal_orange.cube'},
  {'name': 'Vintage', 'asset': 'assets/luts/vintage.cube'},
  {'name': 'Noir', 'asset': 'assets/luts/noir.cube'},
  {'name': 'Golden', 'asset': 'assets/luts/golden.cube'},
  {'name': 'CoolNight', 'asset': 'assets/luts/cool_night.cube'},
];

/// A parsed 3D .cube LUT. [table] holds size^3 * 3 floats in .cube
/// order (red fastest): index = ((b * size) + g) * size + r.
class CubeLut {
  const CubeLut(this.size, this.table);
  final int size;
  final List<double> table;
}

/// Parse .cube text: reads LUT_3D_SIZE and the RGB table that follows.
/// Returns null when the file is malformed or incomplete.
CubeLut? parseCubeLut(String source) {
  var size = 0;
  final values = <double>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('LUT_3D_SIZE')) {
      size = int.tryParse(line.split(RegExp(r'\s+')).last) ?? 0;
      continue;
    }
    // Skip the other header keywords (TITLE / DOMAIN_MIN / DOMAIN_MAX /
    // LUT_1D_SIZE ...): only bare "r g b" data lines remain.
    final first = line[0];
    final isData = (first.codeUnitAt(0) >= 0x30 && first.codeUnitAt(0) <= 0x39) ||
        first == '-' ||
        first == '.';
    if (!isData) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final r = double.tryParse(parts[0]);
    final g = double.tryParse(parts[1]);
    final b = double.tryParse(parts[2]);
    if (r == null || g == null || b == null) continue;
    values.addAll([r, g, b]);
  }
  if (size <= 1 || values.length != size * size * size * 3) return null;
  return CubeLut(size, values);
}

Uint8List _lutJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final size = args[1] as int;
  final table = args[2] as List<double>;
  final intensity = (args[3] as num).toDouble().clamp(0.0, 1.0);
  final out = Uint8List(bytes.length);
  final maxIdx = size - 1;
  double sample(int r, int g, int b, int c) =>
      table[(((b * size) + g) * size + r) * 3 + c];
  for (var i = 0; i < bytes.length; i += 4) {
    final rf = (bytes[i] / 255.0) * maxIdx;
    final gf = (bytes[i + 1] / 255.0) * maxIdx;
    final bf = (bytes[i + 2] / 255.0) * maxIdx;
    final r0 = rf.floor().clamp(0, maxIdx);
    final g0 = gf.floor().clamp(0, maxIdx);
    final b0 = bf.floor().clamp(0, maxIdx);
    final r1 = math.min(r0 + 1, maxIdx);
    final g1 = math.min(g0 + 1, maxIdx);
    final b1 = math.min(b0 + 1, maxIdx);
    final fr = rf - r0;
    final fg = gf - g0;
    final fb = bf - b0;
    for (var c = 0; c < 3; c++) {
      // Trilinear interpolation between the 8 lattice corners.
      final c000 = sample(r0, g0, b0, c);
      final c100 = sample(r1, g0, b0, c);
      final c010 = sample(r0, g1, b0, c);
      final c110 = sample(r1, g1, b0, c);
      final c001 = sample(r0, g0, b1, c);
      final c101 = sample(r1, g0, b1, c);
      final c011 = sample(r0, g1, b1, c);
      final c111 = sample(r1, g1, b1, c);
      final x00 = c000 + (c100 - c000) * fr;
      final x10 = c010 + (c110 - c010) * fr;
      final x01 = c001 + (c101 - c001) * fr;
      final x11 = c011 + (c111 - c011) * fr;
      final y0 = x00 + (x10 - x00) * fg;
      final y1 = x01 + (x11 - x01) * fg;
      final lutVal = y0 + (y1 - y0) * fb;
      final orig = bytes[i + c] / 255.0;
      out[i + c] =
          ((orig + (lutVal - orig) * intensity) * 255).clamp(0, 255).round();
    }
    out[i + 3] = bytes[i + 3]; // keep alpha
  }
  return out;
}

/// Apply a parsed .cube LUT per-pixel (trilinear). [intensity] 0..1
/// blends the look with the untouched photo.
Future<img.Image> applyLut(
  img.Image src,
  CubeLut lut, {
  double intensity = 1.0,
}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _lutJob,
    [bytes, lut.size, lut.table, intensity.clamp(0.0, 1.0)],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

// ---------------------------------------------------------------------------
// Round-2 geometry + background-replace helpers.
// ---------------------------------------------------------------------------

/// Mirror the photo left<->right (the image package already ships the
/// maths; this is the pipeline's named entry point for the Crop panel).
img.Image flipHorizontalPhoto(img.Image src) => img.flipHorizontal(src);

/// Straighten by a fine angle in degrees (-45..45). The image package
/// rotates around the centre and expands the canvas; the exposed
/// corners are filled with black (kept simple and correct on purpose).
img.Image straightenPhoto(img.Image src, double degrees) {
  final a = degrees.clamp(-45, 45).toDouble();
  if (a == 0) return src;
  return img.copyRotate(src, angle: a);
}

Uint8List _replaceBgJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final mask = args[3] as List<double>;
  final maskW = args[4] as int;
  final maskH = args[5] as int;
  final bgBytes = args[6] as Uint8List?; // pre-resized RGBA, w*h*4
  final bgR = args[7] as int;
  final bgG = args[8] as int;
  final bgB = args[9] as int;
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final srcBytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List.fromList(srcBytes);
  for (var y = 0; y < h; y++) {
    final my = (y * maskH ~/ h).clamp(0, maskH - 1);
    for (var x = 0; x < w; x++) {
      final mx = (x * maskW ~/ w).clamp(0, maskW - 1);
      final conf = mask[my * maskW + mx].clamp(0.0, 1.0);
      // Same feather band as the cutout so edges don't stair-step.
      final a = ((conf - 0.35) / 0.3).clamp(0.0, 1.0);
      final idx = (y * w + x) * 4;
      final br = bgBytes != null ? bgBytes[idx] : bgR;
      final bg = bgBytes != null ? bgBytes[idx + 1] : bgG;
      final bb = bgBytes != null ? bgBytes[idx + 2] : bgB;
      out[idx] = (srcBytes[idx] * a + br * (1 - a)).round();
      out[idx + 1] = (srcBytes[idx + 1] * a + bg * (1 - a)).round();
      out[idx + 2] = (srcBytes[idx + 2] * a + bb * (1 - a)).round();
      out[idx + 3] = 255; // replaced background = fully opaque photo
    }
  }
  return out;
}

/// Replace everything behind the segmented subject: either a solid
/// [bgArgb] colour or a [bgImage] (resized to cover the photo's size).
/// The segmentation mask already supports this — it is the same
/// confidence data the cutout/blur paths use, composited the other way.
Future<img.Image> replaceBackground(
  img.Image src,
  MaskResult mask, {
  int bgArgb = 0xFFFFFFFF,
  img.Image? bgImage,
}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  Uint8List? bgBytes;
  if (bgImage != null) {
    final resized = img.copyResize(
      bgImage.convert(numChannels: 4),
      width: src.width,
      height: src.height,
      interpolation: img.Interpolation.linear,
    );
    bgBytes = resized.getBytes(order: img.ChannelOrder.rgba);
  }
  final out = await compute(
    _replaceBgJob,
    [
      bytes,
      src.width,
      src.height,
      mask.confidences,
      mask.width,
      mask.height,
      bgBytes,
      (bgArgb >> 16) & 0xFF,
      (bgArgb >> 8) & 0xFF,
      bgArgb & 0xFF,
    ],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Algorithmic auto-enhance (histogram stretch + saturation). Returns a new
/// image; the caller writes it back to the working file.
Future<img.Image> autoEnhance(img.Image src) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_autoEnhanceJob, [bytes]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Remini-style Sharpen (unsharp mask). [amount] 0.0..2.0, default 0.8.
/// Algorithmic, on-device, FREE. Reduces blur/softness.
Future<img.Image> sharpenImage(img.Image src, {double amount = 0.8}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _sharpenJob,
    [bytes, src.width, src.height, amount.clamp(0.0, 2.0)],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Remini-style Denoise (grain/noise reduction). [strength] 0.0..1.0,
/// default 0.6. Algorithmic, on-device, FREE.
Future<img.Image> denoiseImage(img.Image src, {double strength = 0.6}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_denoiseJob, [bytes, strength.clamp(0.0, 1.0)]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Remini-style Enlarge: 2x upscale with cubic interpolation.
/// [scale] 1.0..4.0, default 2.0. Algorithmic, on-device, FREE.
Future<img.Image> enlargeImage(img.Image src, {double scale = 2.0}) async {
  final s = scale.clamp(1.0, 4.0);
  final newW = (src.width * s).round();
  final newH = (src.height * s).round();
  // copyResize is fast enough on the main isolate for typical photo sizes;
  // run in compute for very large images via a simple sync call here.
  return img.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.cubic,
  );
}

/// Remini-style Color Fix: gray-world white balance.
/// Fixes yellow/blue casts. Algorithmic, on-device, FREE.
Future<img.Image> colorFixImage(img.Image src) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_colorFixJob, [bytes]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// InShot-style HSL: per-color Hue/Saturation/Lightness.
/// [adjustments]: 8 colors (Red, Orange, Yellow, Green, Cyan, Blue,
/// Purple, Magenta) × [hueShift (-180..180), satScale (0..2),
/// lightOffset (-100..100)]. Algorithmic, on-device, FREE.
Future<img.Image> adjustHSL(
  img.Image src,
  List<List<double>> adjustments,
) async {
  assert(adjustments.length == 8);
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_hslJob, [bytes, adjustments]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Skin smoothing inside detected face rects. [faces] are pixel rects in the
/// image's own coordinate space.
Future<img.Image> beautifyFaces(
  img.Image src,
  List<Rect> faces,
) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final flat = faces
      .map((r) => [r.left, r.top, r.right, r.bottom])
      .toList();
  final out = await compute(
    _beautifyJob,
    [bytes, src.width, src.height, flat],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Apply a segmentation mask. If [removeBackground] is true the background
/// becomes transparent (caller must save as PNG); otherwise the background
/// is blurred (portrait-style) and the result stays opaque.
Future<img.Image> applySegmentationMask(
  img.Image src,
  MaskResult mask, {
  required bool removeBackground,
}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _maskJob,
    [
      bytes,
      src.width,
      src.height,
      mask.confidences,
      mask.width,
      mask.height,
      removeBackground,
    ],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Map a Text-panel font key onto the family name the app loads via
/// google_fonts. When that family is loaded it is used for the export;
/// when it is not (offline first run), dart:ui falls back to the system
/// font — the one param the rasterizer can only honor best-effort.
String? _fontFamilyForKey(String key) {
  switch (key) {
    // v1.4.0: font_registry.dart ids (UrduFonts) map onto the same
    // family names google_fonts registers when the preview loads them.
    case 'jameel_kasheeda':
      return 'JameelNooriNastaleeqKasheeda';
    case 'noto_nastaliq_urdu':
      return 'Noto Nastaliq Urdu';
    case 'noto_naskh_arabic':
      return 'Noto Naskh Arabic';
    case 'scheherazade_new':
      return 'Scheherazade New';
    case 'amiri':
      return 'Amiri';
    case 'lateef':
      return 'Lateef';
    case 'harmattan':
      return 'Harmattan';
    case 'mirza':
      return 'Mirza';
    case 'katibeh':
      return 'Katibeh';
    case 'nastaliq':
      return 'Noto Nastaliq Urdu';
    case 'naskh':
      return 'Noto Naskh Arabic';
    case 'kufi':
      return 'Noto Kufi Arabic';
    case 'gulzar':
      return 'Gulzar';
    case 'roboto':
      return 'Roboto';
    case 'merriweather':
      return 'Merriweather';
    case 'dancing':
      return 'Dancing Script';
    case 'bebas':
      return 'Bebas Neue';
    case 'pacifico':
      return 'Pacifico';
    default:
      return null; // 'default' = system font
  }
}

/// Rasterize overlay text to PNG bytes. MUST run on the main isolate
/// (dart:ui). [argb] is a Flutter Color value.
/// Supports CapCut-style effects: shadow, glow, background ribbon
/// (Jaani 31 Oct 2026). Round-2 (P9): font family, bold, italic,
/// opacity, letter spacing, outline (multi-offset draws in the outline
/// colour) and alignment are all honored here, so export == preview.
Future<Uint8List> rasterizeText({
  required String text,
  required int argb,
  required double size,
  bool shadow = true,
  bool glow = false,
  bool bg = false,
  int bgArgb = 0x8A000000,
  double height = 1.0, // line spacing multiplier (daily upgrade 2026-10-31)
  String fontKey = 'default',
  bool bold = true,
  bool italic = false,
  double opacity = 1.0, // 0..1, folded into the text colour's alpha
  double letterSpacing = 0.0,
  bool outline = false,
  int outlineArgb = 0xFF000000,
  double outlineWidth = 2.0,
  ui.TextAlign textAlign = ui.TextAlign.center,
  // v1.4.0 Text system: full shadow/glow control + an optional wrap
  // width (the on-canvas text box width, in image pixels). Defaults
  // reproduce the pre-v1.4.0 rendering exactly.
  int shadowArgb = 0xDD000000,
  double shadowDx = 2,
  double shadowDy = 3,
  double shadowBlur = 6,
  int? glowArgb,
  double glowBlur = 16,
  double? maxWidthPx,
}) async {
  // Opacity: scale the colour's own alpha (ARGB int maths, no reliance
  // on newer Color APIs).
  final alpha = (((argb >> 24) & 0xFF) * opacity.clamp(0.0, 1.0)).round();
  final effArgb = (argb & 0x00FFFFFF) | (alpha << 24);
  final oAlpha = (((outlineArgb >> 24) & 0xFF) * opacity.clamp(0.0, 1.0))
      .round();
  final effOutlineArgb = (outlineArgb & 0x00FFFFFF) | (oAlpha << 24);
  final List<ui.Shadow> shadows = [];
  if (glow) {
    final gAlpha = (((glowArgb ?? argb) >> 24) & 0xFF);
    final effGlowArgb = glowArgb == null
        ? effArgb
        : (((gAlpha * opacity.clamp(0.0, 1.0)).round() << 24) |
            (glowArgb & 0x00FFFFFF));
    shadows.add(ui.Shadow(
      color: ui.Color(effGlowArgb).withValues(alpha: 0.9),
      blurRadius: glowBlur,
    ));
  }
  if (shadow) {
    final sAlpha =
        (((shadowArgb >> 24) & 0xFF) * opacity.clamp(0.0, 1.0)).round();
    final effShadowArgb =
        (shadowArgb & 0x00FFFFFF) | (sAlpha << 24);
    shadows.add(ui.Shadow(
      color: ui.Color(effShadowArgb),
      offset: ui.Offset(shadowDx, shadowDy),
      blurRadius: shadowBlur,
    ));
  }

  ui.Paragraph buildPara(int colorArgb, {bool withShadows = true}) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        textAlign: textAlign,
        height: height,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: ui.Color(colorArgb),
          fontSize: size,
          fontFamily: _fontFamilyForKey(fontKey),
          fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
          fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal,
          letterSpacing: letterSpacing,
          shadows: withShadows ? shadows : const [],
        ),
      )
      ..addText(text);
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidthPx ?? 4000));
  }

  final paragraph = buildPara(effArgb);
  final tw = paragraph.longestLine.ceil();
  final th = paragraph.height.ceil();
  // Extra padding so outline strokes at max width never clip.
  final pad = 32 + (outline ? outlineWidth.ceil() : 0);
  final w = tw + pad * 2;
  final h = th + pad * 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (bg) {
    // Ribbon: rounded rect behind the text.
    final bgPaint = ui.Paint()..color = ui.Color(bgArgb);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(8, 8, w - 16.0, h - 16.0),
        const ui.Radius.circular(16),
      ),
      bgPaint,
    );
  }
  if (outline) {
    // Outline via multi-offset draws of the same paragraph in the
    // outline colour (dart:ui text has no stroke fill for paragraphs):
    // 8 compass offsets at full width + 4 diagonal at 0.7 width.
    final outlinePara = buildPara(effOutlineArgb, withShadows: false);
    final ow = outlineWidth.clamp(0.5, 12.0);
    final offsets = <ui.Offset>[
      ui.Offset(-ow, 0), ui.Offset(ow, 0),
      ui.Offset(0, -ow), ui.Offset(0, ow),
      ui.Offset(-ow * 0.7, -ow * 0.7), ui.Offset(ow * 0.7, -ow * 0.7),
      ui.Offset(-ow * 0.7, ow * 0.7), ui.Offset(ow * 0.7, ow * 0.7),
    ];
    for (final o in offsets) {
      canvas.drawParagraph(
        outlinePara,
        ui.Offset(pad + o.dx, pad + o.dy),
      );
    }
  }
  canvas.drawParagraph(paragraph, ui.Offset(pad.toDouble(), pad.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Composite rasterized text onto [base]. ([nx], [ny]) is the normalized
/// center of the text box (0..1).
img.Image compositeText(
  img.Image base,
  Uint8List textPng,
  double nx,
  double ny, {
  // v1.4.0: the on-canvas rotate/scale handle's angle, in degrees
  // (clockwise, matching the preview's Transform.rotate).
  double rotationDegrees = 0,
}) {
  var textImg = img.decodeImage(textPng);
  if (textImg == null) return base;
  if (rotationDegrees != 0) {
    textImg = img.copyRotate(textImg, angle: rotationDegrees);
  }
  final dstX =
      (nx * base.width - textImg.width / 2).round().clamp(0, base.width - 1);
  final dstY =
      (ny * base.height - textImg.height / 2).round().clamp(0, base.height - 1);
  return img.compositeImage(base, textImg, dstX: dstX, dstY: dstY);
}

/// One text layer for the v1.4.0 multi-layer export. Mirrors the
/// single-text fields of [PhotoEditParams] and adds the on-canvas box
/// geometry (centre, width fraction, rotation) the new Text system
/// edits live.
class PhotoTextLayerParams {
  const PhotoTextLayerParams({
    required this.text,
    required this.argb,
    required this.size,
    required this.centerX,
    required this.centerY,
    this.boxWidthFrac = 0.7,
    this.rotationDegrees = 0,
    this.shadow = true,
    this.shadowArgb = 0xDD000000,
    this.shadowDx = 2,
    this.shadowDy = 3,
    this.shadowBlur = 6,
    this.glow = false,
    this.glowArgb,
    this.glowBlur = 16,
    this.bg = false,
    this.bgArgb = 0x8A000000,
    this.lineHeight = 1.0,
    this.fontKey = 'default',
    this.bold = true,
    this.italic = false,
    this.opacity = 1.0,
    this.letterSpacing = 0.0,
    this.outline = false,
    this.outlineArgb = 0xFF000000,
    this.outlineWidth = 2.0,
    this.textAlign = ui.TextAlign.center,
  });

  final String text;
  final int argb;
  final double size;
  final double centerX;
  final double centerY;
  final double boxWidthFrac;
  final double rotationDegrees;
  final bool shadow;
  final int shadowArgb;
  final double shadowDx;
  final double shadowDy;
  final double shadowBlur;
  final bool glow;
  final int? glowArgb;
  final double glowBlur;
  final bool bg;
  final int bgArgb;
  final double lineHeight;
  final String fontKey;
  final bool bold;
  final bool italic;
  final double opacity;
  final double letterSpacing;
  final bool outline;
  final int outlineArgb;
  final double outlineWidth;
  final ui.TextAlign textAlign;
}

/// One image/glyph overlay (PIP photo or sticker) for the export.
/// Exactly one of [imagePath] / [pngBytes] is set. [scaleFrac] is the
/// overlay width as a fraction of the photo width.
class PhotoOverlayLayerParams {
  const PhotoOverlayLayerParams({
    this.imagePath,
    this.pngBytes,
    required this.centerX,
    required this.centerY,
    this.scaleFrac = 0.35,
    this.rotationDegrees = 0,
  });

  final String? imagePath;
  final Uint8List? pngBytes;
  final double centerX;
  final double centerY;
  final double scaleFrac;
  final double rotationDegrees;
}

PhotoTextLayerParams _layerFromParams(PhotoEditParams params) {
  return PhotoTextLayerParams(
    text: params.text,
    argb: params.textArgb,
    size: params.textSize,
    centerX: params.textOffsetX,
    centerY: params.textOffsetY,
    shadow: params.textShadow,
    glow: params.textGlow,
    bg: params.textBg,
    bgArgb: params.textBgArgb,
    lineHeight: params.textLineHeight,
    fontKey: params.textFont,
    bold: params.textBold,
    italic: params.textItalic,
    opacity: params.textOpacity,
    letterSpacing: params.textLetterSpacing,
    outline: params.textOutline,
    outlineArgb: params.textOutlineArgb,
    outlineWidth: params.textOutlineWidth,
    textAlign: params.textAlignIndex == 0
        ? ui.TextAlign.left
        : params.textAlignIndex == 2
            ? ui.TextAlign.right
            : ui.TextAlign.center,
  );
}

/// Full export: decode the working file, apply the preview matrix, composite
/// text, and write the result. PNG when [keepAlpha] is true (background
/// removed), otherwise JPG.
Future<File> exportPhoto({
  required File workingFile,
  required PhotoEditParams params,
  required String outPath,
  required bool keepAlpha,
}) async {
  return _exportCore(
    workingFile: workingFile,
    params: params,
    layers: params.text.trim().isEmpty
        ? const []
        : [_layerFromParams(params)],
    overlays: const [],
    outPath: outPath,
    keepAlpha: keepAlpha,
  );
}

/// v1.4.0 export: same colour/LUT/Adjust pass as [exportPhoto], then
/// every overlay (PIP/sticker) and EVERY text layer composited in
/// order — the multi-layer Text system reaches the saved photo.
Future<File> exportPhotoWithLayers({
  required File workingFile,
  required PhotoEditParams params,
  required List<PhotoTextLayerParams> layers,
  List<PhotoOverlayLayerParams> overlays = const [],
  required String outPath,
  required bool keepAlpha,
}) async {
  return _exportCore(
    workingFile: workingFile,
    params: params,
    layers: layers,
    overlays: overlays,
    outPath: outPath,
    keepAlpha: keepAlpha,
  );
}

Future<File> _exportCore({
  required File workingFile,
  required PhotoEditParams params,
  required List<PhotoTextLayerParams> layers,
  required List<PhotoOverlayLayerParams> overlays,
  required String outPath,
  required bool keepAlpha,
}) async {
  final bytes = await workingFile.readAsBytes();
  final decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) {
    throw Exception('Could not read the edited photo.');
  }
  var image = decodedImage;
  final matrix = buildColorMatrix(
    filter: params.filter,
    brightness: params.brightness,
    contrast: params.contrast,
    saturation: params.saturation,
    filterIntensity: params.filterIntensity,
    exposure: params.exposure,
    temperature: params.temperature,
    tint: params.tint,
    vibrance: params.vibrance,
    fade: params.fade,
  );
  image = await applyColorMatrix(image, matrix);
  // LUT look (Round-2): applied after the corrections, like the video
  // grader — the LUT is the final "look" layer before pixel Adjust.
  if (params.lutTable != null && params.lutSize > 1) {
    image = await applyLut(
      image,
      CubeLut(params.lutSize, params.lutTable!),
    );
  }
  if (params.needsPixelAdjust) {
    image = await applyAdjustments(
      image,
      highlights: params.highlights,
      shadows: params.shadows,
      vignette: params.vignette,
      sharpenDetail: params.sharpenDetail,
    );
  }
  // v1.4.0 Adjust additions, in pipeline order after the classic
  // pass: tone curve -> global hue -> grain.
  if (params.curveLuts != null && params.curveLuts!.length == 4) {
    image = await applyToneCurve(image, params.curveLuts!);
  }
  if (params.hueShift != 0) {
    image = await adjustHSL(
      image,
      List.generate(8, (_) => [params.hueShift, 1.0, 0.0]),
    );
  }
  if (params.grain > 0) {
    image = await applyGrain(image, params.grain);
  }
  // Overlays (PIP photos / sticker glyphs) sit under the text layers.
  for (final o in overlays) {
    image = await compositeOverlayLayer(image, o);
  }
  for (final layer in layers) {
    if (layer.text.trim().isEmpty) continue;
    final textPng = await rasterizeText(
      text: layer.text,
      argb: layer.argb,
      size: layer.size,
      shadow: layer.shadow,
      shadowArgb: layer.shadowArgb,
      shadowDx: layer.shadowDx,
      shadowDy: layer.shadowDy,
      shadowBlur: layer.shadowBlur,
      glow: layer.glow,
      glowArgb: layer.glowArgb,
      glowBlur: layer.glowBlur,
      bg: layer.bg,
      bgArgb: layer.bgArgb,
      height: layer.lineHeight,
      fontKey: layer.fontKey,
      bold: layer.bold,
      italic: layer.italic,
      opacity: layer.opacity,
      letterSpacing: layer.letterSpacing,
      outline: layer.outline,
      outlineArgb: layer.outlineArgb,
      outlineWidth: layer.outlineWidth,
      textAlign: layer.textAlign,
      maxWidthPx: layer.boxWidthFrac * image.width,
    );
    image = compositeText(
      image,
      textPng,
      layer.centerX,
      layer.centerY,
      rotationDegrees: layer.rotationDegrees,
    );
  }
  final out = File(outPath);
  if (keepAlpha) {
    await out.writeAsBytes(img.encodePng(image));
  } else {
    await out.writeAsBytes(img.encodeJpg(image, quality: 92));
  }
  return out;
}

// ---------------------------------------------------------------------------
// v1.4.0 additions: tone curve, grain, classic effects, doodle, overlays,
// canvas expand, frame border, alpha (cutout) ops and makeup tint.
// All algorithmic, on-device, FREE — same discipline as the rest of
// this file (heavy per-pixel work runs in a compute isolate).
// ---------------------------------------------------------------------------

/// Mirror the photo top<->bottom (Rotate tool's second flip).
img.Image flipVerticalPhoto(img.Image src) => img.flipVertical(src);

Uint8List _curveJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  // Flattened [rgb, r, g, b] LUTs, 256 entries each.
  final luts = args[1] as List<int>;
  final out = Uint8List.fromList(bytes);
  for (var i = 0; i < bytes.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final v = bytes[i + c];
      final per = luts[(c + 1) * 256 + v];
      out[i + c] = luts[per];
    }
  }
  return out;
}

/// Apply a per-channel tone curve. [channelLuts] is [rgb, r, g, b],
/// each a 256-entry table (0..255). A pixel channel first passes its
/// own channel LUT, then the shared RGB LUT — the same composition
/// order classic curve editors use.
Future<img.Image> applyToneCurve(
  img.Image src,
  List<List<int>> channelLuts,
) async {
  assert(channelLuts.length == 4);
  final flat = <int>[];
  for (final lut in channelLuts) {
    assert(lut.length == 256);
    flat.addAll(lut.map((v) => v.clamp(0, 255)));
  }
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_curveJob, [bytes, flat]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Deterministic pseudo-random value 0..1 for pixel [seed] — an LCG,
/// so preview and export grain agree and no dart:math Random state
/// leaks between isolates.
double _lcg(int seed) {
  var s = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
  s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
  return (s % 10000) / 10000.0;
}

Uint8List _grainJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final amount = (args[1] as num).toDouble().clamp(0, 100) / 100;
  final out = Uint8List.fromList(bytes);
  final amp = amount * 46;
  for (var i = 0; i < bytes.length; i += 4) {
    final n = (_lcg(i ~/ 4 + 7) - 0.5) * 2 * amp;
    for (var c = 0; c < 3; c++) {
      out[i + c] = (bytes[i + c] + n).clamp(0, 255).round();
    }
  }
  return out;
}

/// Film grain: monochrome noise, [amount] 0..100.
Future<img.Image> applyGrain(img.Image src, double amount) async {
  if (amount <= 0) return src;
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_grainJob, [bytes, amount.clamp(0, 100)]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

Uint8List _effectJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final mode = args[3] as String;
  final t = (args[4] as num).toDouble().clamp(0.0, 1.0);
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final rgba = src.convert(numChannels: 4);
  final sb = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List.fromList(sb);
  int idx(int x, int y) =>
      (y.clamp(0, h - 1) * w + x.clamp(0, w - 1)) * 4;
  switch (mode) {
    case 'rgb':
      final d = (2 + t * 10).round();
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          out[o] = sb[idx(x + d, y)];
          out[o + 2] = sb[idx(x - d, y)];
        }
      }
    case 'glitch':
      for (var y = 0; y < h; y++) {
        final band = _lcg(y * 31 + 5);
        final shift = band > 0.72 ? ((band - 0.72) * 220 * t).round() : 0;
        final split = band > 0.86;
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          final s = idx(x + shift, y);
          out[o] = sb[s];
          out[o + 1] = sb[s + 1];
          out[o + 2] = sb[s + 2];
          if (split) {
            out[o] = sb[idx(x + shift + 6, y)];
            out[o + 2] = sb[idx(x + shift - 6, y) + 2];
          }
        }
      }
    case 'noise':
      final amp = t * 90;
      for (var i = 0; i < sb.length; i += 4) {
        final n = (_lcg(i ~/ 4 + 13) - 0.5) * 2 * amp;
        for (var c = 0; c < 3; c++) {
          out[i + c] = (sb[i + c] + n).clamp(0, 255).round();
        }
      }
    case 'tv':
      for (var y = 0; y < h; y++) {
        final dark = (y % 3 == 0) ? 1 - 0.38 * t : 1.0;
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          for (var c = 0; c < 3; c++) {
            out[o + c] = (sb[o + c] * dark).round();
          }
        }
      }
    case 'ghost':
      final d = (6 + t * 42).round();
      final a = 0.45 * t;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          final s = idx(x + d, y);
          for (var c = 0; c < 3; c++) {
            out[o + c] = (sb[o + c] * (1 - a) + sb[s + c] * a).round();
          }
        }
      }
    case 'strobe':
      for (var y = 0; y < h; y++) {
        final invert = (y ~/ 14) % 2 == 0;
        if (!invert) continue;
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          for (var c = 0; c < 3; c++) {
            out[o + c] =
                (sb[o + c] * (1 - t) + (255 - sb[o + c]) * t).round();
          }
        }
      }
    case 'tilt':
      final blurred = img.gaussianBlur(rgba, radius: 6);
      final bb = blurred.getBytes(order: img.ChannelOrder.rgba);
      final cy = h / 2;
      for (var y = 0; y < h; y++) {
        final d = (y - cy).abs() / cy; // 0 centre .. 1 edge
        final bw = ((d - 0.35) / 0.65).clamp(0.0, 1.0) * t;
        if (bw <= 0) continue;
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          for (var c = 0; c < 3; c++) {
            out[o + c] = (sb[o + c] * (1 - bw) + bb[o + c] * bw).round();
          }
        }
      }
    case 'warp':
      final amp = t * 22;
      for (var y = 0; y < h; y++) {
        final dx = (math.sin(y / 26.0) * amp).round();
        for (var x = 0; x < w; x++) {
          final o = idx(x, y);
          final s = idx(x + dx, y);
          for (var c = 0; c < 4; c++) {
            out[o + c] = sb[s + c];
          }
        }
      }
  }
  return out;
}

/// The classic (non-AI) Effect set: 'glitch', 'rgb', 'noise', 'tv',
/// 'ghost', 'strobe', 'tilt', 'warp'. [intensity] 0..1.
Future<img.Image> applyClassicEffect(
  img.Image src,
  String effect, {
  double intensity = 0.7,
}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _effectJob,
    [bytes, src.width, src.height, effect, intensity.clamp(0.0, 1.0)],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// One freehand stroke for the Doodle tool / mask painting. Points
/// are normalized 0..1 in image space; [widthFrac] is the brush
/// diameter as a fraction of the image width.
class StrokePath {
  const StrokePath({
    required this.argb,
    required this.widthFrac,
    required this.points,
  });

  final int argb;
  final double widthFrac;
  final List<ui.Offset> points;
}

/// Stamp [strokes] onto [image] with round brush dabs along every
/// segment. [alphaOnly] writes alpha=0 dabs instead of colour (the
/// Cutout eraser). Mutates and returns [image].
img.Image stampStrokes(
  img.Image image,
  List<StrokePath> strokes, {
  bool alphaOnly = false,
}) {
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final radius =
        math.max(1, (s.widthFrac * image.width / 2).round());
    final color = img.ColorRgba8(
      (s.argb >> 16) & 0xFF,
      (s.argb >> 8) & 0xFF,
      s.argb & 0xFF,
      alphaOnly ? 0 : (s.argb >> 24) & 0xFF,
    );
    void dab(double nx, double ny) {
      final cx = (nx * image.width).round();
      final cy = (ny * image.height).round();
      if (alphaOnly) {
        // img.fillCircle blends colour; for a true alpha erase, set
        // the pixels directly inside the dab circle.
        for (var y = cy - radius; y <= cy + radius; y++) {
          if (y < 0 || y >= image.height) continue;
          for (var x = cx - radius; x <= cx + radius; x++) {
            if (x < 0 || x >= image.width) continue;
            final dx = x - cx;
            final dy = y - cy;
            if (dx * dx + dy * dy > radius * radius) continue;
            final px = image.getPixel(x, y);
            image.setPixelRgba(x, y, px.r, px.g, px.b, 0);
          }
        }
      } else {
        img.fillCircle(image, x: cx, y: cy, radius: radius, color: color);
      }
    }

    for (var i = 0; i < s.points.length; i++) {
      final a = s.points[i];
      if (i == 0) {
        dab(a.dx, a.dy);
        continue;
      }
      final b = s.points[i - 1];
      final dist = (a - b).distance;
      final steps = math.max(1, (dist * image.width / (radius / 2)).ceil());
      for (var k = 1; k <= steps; k++) {
        final t = k / steps;
        dab(b.dx + (a.dx - b.dx) * t, b.dy + (a.dy - b.dy) * t);
      }
    }
  }
  return image;
}

/// Bake Doodle strokes into the photo (Doodle tool's Apply).
img.Image drawDoodle(img.Image src, List<StrokePath> strokes) =>
    stampStrokes(src, strokes);

/// Build the Mi-GAN remove mask: black image, WHITE dabs where the
/// user painted (the OnnxImageService flips to the model's
/// 255=keep convention internally, per the build contract).
img.Image maskFromStrokes(
  int width,
  int height,
  List<StrokePath> strokes,
) {
  final mask = img.Image(width: width, height: height, numChannels: 4);
  img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
  final white = strokes
      .map((s) => StrokePath(
            argb: 0xFFFFFFFF,
            widthFrac: s.widthFrac,
            points: s.points,
          ))
      .toList();
  return stampStrokes(mask, white);
}

/// Composite one PIP/sticker overlay onto [base]: resized to
/// [PhotoOverlayLayerParams.scaleFrac] of the base width, optionally
/// rotated, centred at the normalized position (clamped so at least
/// part of it stays on canvas).
Future<img.Image> compositeOverlayLayer(
  img.Image base,
  PhotoOverlayLayerParams o,
) async {
  img.Image? ov;
  if (o.pngBytes != null) {
    ov = img.decodeImage(o.pngBytes!);
  } else if (o.imagePath != null) {
    final b = await File(o.imagePath!).readAsBytes();
    ov = img.decodeImage(b);
  }
  if (ov == null) return base;
  final targetW =
      math.max(8, (o.scaleFrac.clamp(0.05, 1.5) * base.width).round());
  var resized = img.copyResize(
    ov.convert(numChannels: 4),
    width: targetW,
    interpolation: img.Interpolation.linear,
  );
  if (o.rotationDegrees != 0) {
    resized = img.copyRotate(resized, angle: o.rotationDegrees);
  }
  final dstX = (o.centerX * base.width - resized.width / 2)
      .round()
      .clamp(-resized.width ~/ 2, base.width - resized.width ~/ 2);
  final dstY = (o.centerY * base.height - resized.height / 2)
      .round()
      .clamp(-resized.height ~/ 2, base.height - resized.height ~/ 2);
  return img.compositeImage(base, resized, dstX: dstX, dstY: dstY);
}

/// Extend the canvas to [ratioW]:[ratioH] WITHOUT cropping the
/// photo (Canvas / Expand tools). The new area is filled by a
/// cover-scaled copy of the photo itself: blurred ('blur'), flipped
/// ('mirror') or a solid [fillArgb] ('color'). [scale] shrinks the
/// photo inside the new canvas (1 = it touches the short sides).
/// This is plain compositing — NOT generative AI outpainting, and
/// the UI labels it that way.
img.Image expandCanvas(
  img.Image src,
  int ratioW,
  int ratioH, {
  String fill = 'blur',
  int fillArgb = 0xFF000000,
  double scale = 1.0,
}) {
  final target = ratioW / ratioH;
  final current = src.width / src.height;
  if ((target - current).abs() < 0.01 && scale >= 1.0) return src;
  int cw = src.width;
  int ch = src.height;
  if (target > current) {
    cw = (src.height * target).round();
  } else {
    ch = (src.width / target).round();
  }
  final canvas = img.Image(width: cw, height: ch, numChannels: 4);
  if (fill == 'color') {
    img.fill(
      canvas,
      color: img.ColorRgba8(
        (fillArgb >> 16) & 0xFF,
        (fillArgb >> 8) & 0xFF,
        fillArgb & 0xFF,
        (fillArgb >> 24) & 0xFF,
      ),
    );
  } else {
    // Cover-fill: scale the photo to cover the canvas, centre-crop.
    final s = math.max(cw / src.width, ch / src.height);
    var cover = img.copyResize(
      src.convert(numChannels: 4),
      width: (src.width * s).round(),
      height: (src.height * s).round(),
      interpolation: img.Interpolation.linear,
    );
    cover = img.copyCrop(
      cover,
      x: (cover.width - cw) ~/ 2,
      y: (cover.height - ch) ~/ 2,
      width: cw,
      height: ch,
    );
    if (fill == 'mirror') cover = img.flipHorizontal(cover);
    if (fill == 'blur') cover = img.gaussianBlur(cover, radius: 14);
    img.compositeImage(canvas, cover);
  }
  final fgScale = scale.clamp(0.3, 1.0);
  var fg = src.convert(numChannels: 4);
  if (fgScale < 1.0) {
    fg = img.copyResize(
      fg,
      width: (src.width * fgScale).round(),
      height: (src.height * fgScale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return img.compositeImage(
    canvas,
    fg,
    dstX: (cw - fg.width) ~/ 2,
    dstY: (ch - fg.height) ~/ 2,
  );
}

/// Flatten a transparent (cutout) photo onto a solid colour.
img.Image flattenOnColor(img.Image src, int argb) {
  final canvas = img.Image(
    width: src.width,
    height: src.height,
    numChannels: 4,
  );
  img.fill(
    canvas,
    color: img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    ),
  );
  return img.compositeImage(canvas, src.convert(numChannels: 4));
}

/// Frame tool: a solid border of [widthPx] around the photo.
img.Image addBorder(img.Image src, int widthPx, int argb) {
  final b = widthPx.clamp(1, 400);
  final canvas = img.Image(
    width: src.width + b * 2,
    height: src.height + b * 2,
    numChannels: 4,
  );
  img.fill(
    canvas,
    color: img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    ),
  );
  return img.compositeImage(
    canvas,
    src.convert(numChannels: 4),
    dstX: b,
    dstY: b,
  );
}

Uint8List _alphaMatteJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final matteBytes = args[1] as Uint8List;
  final out = Uint8List.fromList(bytes);
  // The contract matte carries its values in the ALPHA channel. If
  // a model build ever ships alpha=255 everywhere, fall back to the
  // red channel so the cutout still works.
  var alphaVaries = false;
  for (var i = 3; i < matteBytes.length; i += 4) {
    if (matteBytes[i] < 250) {
      alphaVaries = true;
      break;
    }
  }
  for (var i = 0; i < bytes.length; i += 4) {
    out[i + 3] = alphaVaries ? matteBytes[i + 3] : matteBytes[i];
  }
  return out;
}

/// Apply an AI alpha matte (OnnxImageService.alphaMatte result) to
/// the photo: the matte becomes the photo's alpha channel.
Future<img.Image> applyAlphaMatte(img.Image src, img.Image matte) async {
  final m = matte.width == src.width && matte.height == src.height
      ? matte
      : img.copyResize(
          matte,
          width: src.width,
          height: src.height,
          interpolation: img.Interpolation.linear,
        );
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final mBytes =
      m.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(_alphaMatteJob, [bytes, mBytes]);
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Cutout Eraser: paint alpha away along [strokes].
img.Image applyAlphaErase(img.Image src, List<StrokePath> strokes) =>
    stampStrokes(src.convert(numChannels: 4), strokes, alphaOnly: true);

Uint8List _outlineJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  final widthPx = (args[3] as num).round().clamp(1, 40);
  final argb = args[4] as int;
  final out = Uint8List.fromList(bytes);
  bool opaque(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    return bytes[(y * w + x) * 4 + 3] > 24;
  }

  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (opaque(x, y)) continue;
      var near = false;
      for (var dy = -widthPx; dy <= widthPx && !near; dy += 2) {
        for (var dx = -widthPx; dx <= widthPx && !near; dx += 2) {
          if (dx * dx + dy * dy > widthPx * widthPx) continue;
          if (opaque(x + dx, y + dy)) near = true;
        }
      }
      if (near) {
        final i = (y * w + x) * 4;
        out[i] = r;
        out[i + 1] = g;
        out[i + 2] = b;
        out[i + 3] = 255;
      }
    }
  }
  return out;
}

/// Cutout Outline: stroke of [widthPx] in [argb] drawn on the
/// transparent side of the subject's alpha edge.
Future<img.Image> outlineFromAlpha(
  img.Image src, {
  required int widthPx,
  required int argb,
}) async {
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _outlineJob,
    [bytes, src.width, src.height, widthPx, argb],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

Uint8List _tintJob(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final w = args[1] as int;
  final h = args[2] as int;
  // Ellipses as [cx, cy, rx, ry] in normalized image space.
  final ellipses = args[3] as List<List<double>>;
  final argb = args[4] as int;
  final strength = (args[5] as num).toDouble().clamp(0.0, 1.0);
  final out = Uint8List.fromList(bytes);
  final tr = ((argb >> 16) & 0xFF).toDouble();
  final tg = ((argb >> 8) & 0xFF).toDouble();
  final tb = (argb & 0xFF).toDouble();
  for (final e in ellipses) {
    final cx = e[0] * w;
    final cy = e[1] * h;
    final rx = math.max(2.0, e[2] * w);
    final ry = math.max(2.0, e[3] * h);
    final x0 = math.max(0, (cx - rx).floor());
    final x1 = math.min(w - 1, (cx + rx).ceil());
    final y0 = math.max(0, (cy - ry).floor());
    final y1 = math.min(h - 1, (cy + ry).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = (x - cx) / rx;
        final dy = (y - cy) / ry;
        final d2 = dx * dx + dy * dy;
        if (d2 > 1) continue;
        // Feathered edge: full strength in the middle 60%.
        final weight = ((1 - d2) / 0.4).clamp(0.0, 1.0) * strength;
        final i = (y * w + x) * 4;
        out[i] = (bytes[i] * (1 - weight) + tr * weight).round();
        out[i + 1] = (bytes[i + 1] * (1 - weight) + tg * weight).round();
        out[i + 2] = (bytes[i + 2] * (1 - weight) + tb * weight).round();
      }
    }
  }
  return out;
}

/// Makeup tint: blend [argb] into elliptical regions (lips / cheeks)
/// with a feathered edge. The caller derives the ellipses from face
/// bounds — see the photo editor's Makeup panel, which documents
/// that these are approximations (the face detector in use returns
/// bounds, not landmarks).
Future<img.Image> tintEllipses(
  img.Image src,
  List<List<double>> ellipses, {
  required int argb,
  required double strength,
}) async {
  if (ellipses.isEmpty) return src;
  final rgba = src.convert(numChannels: 4);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  final out = await compute(
    _tintJob,
    [bytes, src.width, src.height, ellipses, argb, strength],
  );
  return img.Image.fromBytes(
    width: src.width,
    height: src.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}
