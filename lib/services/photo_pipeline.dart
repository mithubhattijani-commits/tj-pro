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
    this.brightness = 0, // -100..100
    this.contrast = 1.0, // 0..2
    this.saturation = 1.0, // 0..2
    this.text = '',
    this.textArgb = 0xFFFFFFFF,
    this.textSize = 48.0,
    this.textOffsetX = 0.5, // normalized center of the text box
    this.textOffsetY = 0.85,
  });

  final PhotoFilter filter;
  final double brightness;
  final double contrast;
  final double saturation;
  final String text;
  final int textArgb;
  final double textSize;
  final double textOffsetX;
  final double textOffsetY;
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

/// Single matrix for preview (ColorFilter.matrix) AND export.
List<double> buildColorMatrix({
  required PhotoFilter filter,
  required double brightness, // -100..100
  required double contrast, // 0..2
  required double saturation, // 0..2
}) {
  final f = _filterMatrix(filter);
  final sat = _saturationMatrix(saturation);
  final con = _diag(contrast, contrast, contrast);
  final off = 128 * (1 - contrast);
  con[4] = off;
  con[9] = off;
  con[14] = off;
  final bri = _identity();
  final bo = brightness * 2.55;
  bri[4] = bo;
  bri[9] = bo;
  bri[14] = bo;
  // Apply filter -> saturation -> contrast -> brightness.
  return _mul(bri, _mul(con, _mul(sat, f)));
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
  final w = args[1] as int;
  final h = args[2] as int;
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

/// Rasterize overlay text to PNG bytes. MUST run on the main isolate
/// (dart:ui). [argb] is a Flutter Color value.
Future<Uint8List> rasterizeText({
  required String text,
  required int argb,
  required double size,
}) async {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      textAlign: ui.TextAlign.center,
    ),
  )
    ..pushStyle(
      ui.TextStyle(
        color: ui.Color(argb),
        fontSize: size,
        fontWeight: ui.FontWeight.bold,
      ),
    )
    ..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 4000));
  final w = paragraph.longestLine.ceil() + 32;
  final h = paragraph.height.ceil() + 24;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawParagraph(paragraph, const ui.Offset(16, 12));
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
  );
  image = await applyColorMatrix(image, matrix);
  if (params.text.trim().isNotEmpty) {
    final textPng = await rasterizeText(
      text: params.text,
      argb: params.textArgb,
      size: params.textSize,
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
