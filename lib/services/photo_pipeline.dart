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
    shadows.add(ui.Shadow(
      color: ui.Color(effArgb).withValues(alpha: 0.9),
      blurRadius: 16,
    ));
  }
  if (shadow) {
    shadows.add(const ui.Shadow(
      color: ui.Color(0xDD000000),
      offset: ui.Offset(2, 3),
      blurRadius: 6,
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
      ..layout(const ui.ParagraphConstraints(width: 4000));
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
  double ny,
) {
  final textImg = img.decodeImage(textPng);
  if (textImg == null) return base;
  final dstX =
      (nx * base.width - textImg.width / 2).round().clamp(0, base.width - 1);
  final dstY =
      (ny * base.height - textImg.height / 2).round().clamp(0, base.height - 1);
  return img.compositeImage(base, textImg, dstX: dstX, dstY: dstY);
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
  final bytes = await workingFile.readAsBytes();
  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('Could not read the edited photo.');
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
  if (params.text.trim().isNotEmpty) {
    final textPng = await rasterizeText(
      text: params.text,
      argb: params.textArgb,
      size: params.textSize,
      shadow: params.textShadow,
      glow: params.textGlow,
      bg: params.textBg,
      bgArgb: params.textBgArgb,
      height: params.textLineHeight,
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
    image = compositeText(
      image,
      textPng,
      params.textOffsetX,
      params.textOffsetY,
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
