/// On-device ONNX image models for v1.4.0 (package:onnxruntime).
///
/// Every processor here is a faithful Dart port of the TESTED
/// Python run script from the tool-test battery
/// (~/workspace/tj-pro-build/tool-tests/, verdicts in
/// V140-TOOL-TESTS.md) — same input sizes, same normalization, same
/// output handling:
///
///   - [enhanceEsrgan]  — Real-ESRGAN general-x4v3 (BSD-3, PASS):
///     float RGB /255 in, clip(0..1)*255 out, 4x. Photos only — the
///     model garbles small text/logos (test-battery guardrail).
///     Port of tool-tests/03-video-enhance/run_esrgan.py.
///   - [removeWithMigan] — MI-GAN pipeline (MIT, PARTIAL): image +
///     mask as UINT8 at 512x512. The model's mask convention is
///     INVERTED (255 = keep, 0 = remove), so the caller's
///     white = remove mask is flipped inside this service.
///     Port of tool-tests/02-remove-bg/work/run_migan.py.
///   - [alphaMatte] — BiRefNet_lite fp16 (MIT, PARTIAL) at fixed
///     1024x1024 with ImageNet normalization + sigmoid, or MODNet
///     (Apache-2.0, PASS) at 512x512 with (x-0.5)/0.5 normalization.
///     Both get the test battery's in-app edge fix: 1 px alpha erode
///     + blue-fringe despill. Ports of run_biref.py / run_gap1.py.
///   - [depthBokeh] — Depth Anything V2 Small int8 (Apache-2.0,
///     PASS): 518-wide input (height snapped to a multiple of 14),
///     ImageNet normalization, near = high depth; the bokeh mask is
///     the battery's ramp clip((d-0.45)/0.25) feathered with a blur
///     (edge-aware: the feather follows the depth map's own edges).
///     Port of tool-tests/04-style-depth/scripts/run_all.py.
///   - [artisticStyle] — ONNX Model Zoo fast-neural-style (Apache-2.0,
///     PARTIAL — "Artistic Styles", never "cartoon"): raw 0..255
///     float at fixed 224x224, output clipped to 0..255. Candy is
///     BANNED (eye artifact) and has no pack. Port of run_gap2.py.
///
/// Models come ONLY from [ModelPackService] packs — nothing is
/// bundled. A missing pack, a failed session, or any error returns
/// null (fail-soft); callers keep the original image. Every
/// OrtValue / OrtSession is released after each run.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'model_pack_service.dart';

class OnnxImageService {
  OnnxImageService._();

  /// Shared instance (the contract API).
  static final OnnxImageService instance = OnnxImageService._();

  /// v1.17.0 (G1, Point #37a): the model file each pack's image
  /// ops run — the single place the file names live, so the
  /// off-thread runner (onnx_isolate.dart) resolves the same file
  /// the on-thread path would. Null = not an ONNX image pack.
  static String? modelFileNameForPack(String packId) {
    switch (packId) {
      case 'birefnet_fp16':
        return 'model_fp16.onnx';
      case 'modnet':
        return 'model.onnx';
      case 'esrgan':
        return 'realesr-general-x4v3.onnx';
      case 'migan':
        return 'migan_pipeline_v2.onnx';
      case 'depth_v2_small':
        return 'model_int8.onnx';
      case 'fns_udnie':
        return 'udnie-9.onnx';
      case 'fns_mosaic':
        return 'mosaic-9.onnx';
      case 'fns_rain':
        return 'rain-princess-9.onnx';
      default:
        return null;
    }
  }

  static const List<double> _imagenetMean = <double>[0.485, 0.456, 0.406];
  static const List<double> _imagenetStd = <double>[0.229, 0.224, 0.225];

  static bool _envReady = false;

  static void _ensureEnv() {
    if (_envReady) return;
    OrtEnv.instance.init();
    _envReady = true;
  }

  // ------------------------------------------------------------------
  // ONNX plumbing
  // ------------------------------------------------------------------

  /// Flattens an OrtValueTensor payload (typed list or nested lists,
  /// depending on element type) into a fresh Float32List.
  static Float32List _flattenToFloat32(Object? value) {
    if (value is Float32List) return Float32List.fromList(value);
    if (value is Float64List) return Float32List.fromList(value);
    if (value is Uint8List) {
      final Float32List out = Float32List(value.length);
      for (int i = 0; i < value.length; i++) {
        out[i] = value[i].toDouble();
      }
      return out;
    }
    if (value is Int32List) {
      final Float32List out = Float32List(value.length);
      for (int i = 0; i < value.length; i++) {
        out[i] = value[i].toDouble();
      }
      return out;
    }
    if (value is Int64List) {
      final Float32List out = Float32List(value.length);
      for (int i = 0; i < value.length; i++) {
        out[i] = value[i].toDouble();
      }
      return out;
    }
    if (value is List) {
      final List<double> buf = <double>[];
      void walk(Object? e) {
        if (e is List) {
          for (final Object? s in e) {
            walk(s);
          }
        } else if (e is num) {
          buf.add(e.toDouble());
        }
      }

      walk(value);
      return Float32List.fromList(buf);
    }
    return Float32List(0);
  }

  /// Image -> CHW float tensor data, applying [transform] to each
  /// 0..1 channel value (channel index 0=R, 1=G, 2=B).
  static Float32List _toChwFloat(
    img.Image image,
    double Function(double v01, int channel) transform,
  ) {
    final int w = image.width;
    final int h = image.height;
    final int plane = w * h;
    final Float32List out = Float32List(3 * plane);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel px = image.getPixel(x, y);
        final int i = y * w + x;
        out[i] = transform(px.r / 255.0, 0);
        out[plane + i] = transform(px.g / 255.0, 1);
        out[2 * plane + i] = transform(px.b / 255.0, 2);
      }
    }
    return out;
  }

  /// Image -> CHW uint8 tensor data (MI-GAN's image input).
  static Uint8List _toChwUint8(img.Image image) {
    final int w = image.width;
    final int h = image.height;
    final int plane = w * h;
    final Uint8List out = Uint8List(3 * plane);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel px = image.getPixel(x, y);
        final int i = y * w + x;
        out[i] = px.r.toInt().clamp(0, 255);
        out[plane + i] = px.g.toInt().clamp(0, 255);
        out[2 * plane + i] = px.b.toInt().clamp(0, 255);
      }
    }
    return out;
  }

  /// Builds an RGB image from CHW float data already in 0..255
  /// range (callers scale 0..1 model outputs before calling).
  static img.Image _imageFromChw(Float32List data, int w, int h) {
    final int plane = w * h;
    final img.Image out = img.Image(width: w, height: h, numChannels: 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = y * w + x;
        out.setPixelRgb(
          x,
          y,
          data[i].clamp(0.0, 255.0).round(),
          data[plane + i].clamp(0.0, 255.0).round(),
          data[2 * plane + i].clamp(0.0, 255.0).round(),
        );
      }
    }
    return out;
  }

  // Static + synchronous (v1.17.0 G1): the *WithModel cores run
  // in background isolates, so the shared plumbing must not need
  // an instance, and the FFI run itself is a blocking call — it
  // is only ever invoked from a background isolate now.
  static Float32List? _runSingleInputSync(File model, Float32List data,
      List<int> shape) {
    _ensureEnv();
    OrtSession? session;
    final OrtRunOptions runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    OrtValueTensor? inputTensor;
    try {
      session = OrtSession.fromFile(model, OrtSessionOptions());
      if (session.inputNames.isEmpty) return null;
      inputTensor = OrtValueTensor.createTensorWithDataList(data, shape);
      outputs = session.run(runOptions, <String, OrtValue>{
        session.inputNames.first: inputTensor,
      });
      if (outputs.isEmpty) return null;
      final OrtValue? first = outputs.first;
      return first is OrtValueTensor
          ? _flattenToFloat32(first.value)
          : null;
    } catch (_) {
      return null;
    } finally {
      if (outputs != null) {
        for (final OrtValue? out in outputs) {
          out?.release();
        }
      }
      inputTensor?.release();
      runOptions.release();
      session?.release();
    }
  }

  // ------------------------------------------------------------------
  // Real-ESRGAN — photo enhance (4x)
  // ------------------------------------------------------------------

  /// Upscales [input] 4x with Real-ESRGAN general-x4v3. The model is
  /// a small-crop enhancer (the battery tested 64–75 px inputs), so
  /// an input whose long edge exceeds 512 px is first resized down
  /// to 512 — the output is then at most 2048 px on the long edge.
  /// Returns null when the pack is missing or inference fails.
  Future<img.Image?> enhanceEsrgan(img.Image input) async {
    final File? model = await ModelPackService.instance
        .packFile('esrgan', 'realesr-general-x4v3.onnx');
    if (model == null) return null;
    return enhanceEsrganWithModelSync(model, input);
  }

  /// The ESRGAN core with the model file already resolved —
  /// static + isolate-safe (no platform channels inside), so the
  /// off-thread runner (onnx_isolate.dart) executes the SAME math
  /// in a background isolate (v1.17.0 G1, Point #37a).
  static img.Image? enhanceEsrganWithModelSync(
    File model,
    img.Image input,
  ) {
    try {
      img.Image work = input;
      final int longEdge = math.max(input.width, input.height);
      if (longEdge > 512) {
        final double s = 512 / longEdge;
        work = img.copyResize(
          input,
          width: (input.width * s).round(),
          height: (input.height * s).round(),
          interpolation: img.Interpolation.cubic,
        );
      }
      final int w = work.width;
      final int h = work.height;
      final Float32List data =
          _toChwFloat(work, (double v, int c) => v);
      final Float32List? out =
          _runSingleInputSync(model, data, <int>[1, 3, h, w]);
      if (out == null) return null;
      final int ow = w * 4;
      final int oh = h * 4;
      if (out.length < 3 * ow * oh) return null;
      final Float32List scaled = Float32List(out.length);
      for (int i = 0; i < out.length; i++) {
        scaled[i] = out[i] * 255.0;
      }
      return _imageFromChw(scaled, ow, oh);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // MI-GAN — photo object remove
  // ------------------------------------------------------------------

  /// Inpaints the region marked in [removeMask] (WHITE = remove)
  /// with MI-GAN at 512x512 and returns the result at the input's
  /// original size. The tested model wants the OPPOSITE mask
  /// convention (255 = keep), so the mask is flipped here — callers
  /// always pass white = remove. Returns null on any failure.
  Future<img.Image?> removeWithMigan(
    img.Image input,
    img.Image removeMask,
  ) async {
    final File? model = await ModelPackService.instance
        .packFile('migan', 'migan_pipeline_v2.onnx');
    if (model == null) return null;
    return removeWithMiganWithModelSync(model, input, removeMask);
  }

  /// The MI-GAN core with the model file already resolved —
  /// static + isolate-safe, see [enhanceEsrganWithModel].
  static img.Image? removeWithMiganWithModelSync(
    File model,
    img.Image input,
    img.Image removeMask,
  ) {
    try {
      const int size = 512;
      final img.Image work = img.copyResize(
        input,
        width: size,
        height: size,
        interpolation: img.Interpolation.cubic,
      );
      final img.Image maskWork = img.copyResize(
        removeMask,
        width: size,
        height: size,
        interpolation: img.Interpolation.linear,
      );
      // Model mask: 255 = keep, 0 = remove (flip of the caller's
      // white = remove luminance).
      final Uint8List maskData = Uint8List(size * size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final img.Pixel px = maskWork.getPixel(x, y);
          final double lum =
              (0.299 * px.r + 0.587 * px.g + 0.114 * px.b) / 255.0;
          maskData[y * size + x] = ((1.0 - lum) * 255).round();
        }
      }
      _ensureEnv();
      OrtSession? session;
      final OrtRunOptions runOptions = OrtRunOptions();
      List<OrtValue?>? outputs;
      OrtValueTensor? imageTensor;
      OrtValueTensor? maskTensor;
      try {
        session = OrtSession.fromFile(model, OrtSessionOptions());
        if (session.inputNames.length < 2) return null;
        imageTensor = OrtValueTensor.createTensorWithDataList(
          _toChwUint8(work),
          <int>[1, 3, size, size],
        );
        maskTensor = OrtValueTensor.createTensorWithDataList(
          maskData,
          <int>[1, 1, size, size],
        );
        outputs = session.run(runOptions, <String, OrtValue>{
          session.inputNames[0]: imageTensor,
          session.inputNames[1]: maskTensor,
        });
        if (outputs.isEmpty) return null;
        final OrtValue? first = outputs.first;
        if (first is! OrtValueTensor) return null;
        final Float32List outData = _flattenToFloat32(first.value);
        if (outData.length < 3 * size * size) return null;
        final img.Image filled = _imageFromChw(outData, size, size);
        return img.copyResize(
          filled,
          width: input.width,
          height: input.height,
          interpolation: img.Interpolation.cubic,
        );
      } finally {
        if (outputs != null) {
          for (final OrtValue? out in outputs) {
            out?.release();
          }
        }
        imageTensor?.release();
        maskTensor?.release();
        runOptions.release();
        session?.release();
      }
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Alpha matting — BiRefNet fp16 / MODNet
  // ------------------------------------------------------------------

  /// Runs the matting model of [packId] ('birefnet_fp16' at 1024 or
  /// 'modnet' at 512) over [input] and returns an RGBA copy of the
  /// input whose alpha channel is the predicted matte, with the
  /// battery's edge fix applied (1 px erode + blue-fringe despill).
  /// Returns null for any other pack id / on any failure.
  Future<img.Image?> alphaMatte(String packId, img.Image input) async {
    final bool isBiref = packId == 'birefnet_fp16';
    if (!isBiref && packId != 'modnet') return null;
    final File? model = await ModelPackService.instance.packFile(
      packId,
      isBiref ? 'model_fp16.onnx' : 'model.onnx',
    );
    if (model == null) return null;
    return alphaMatteWithModelSync(model, isBiref: isBiref, input: input);
  }

  /// The matting core with the model file already resolved —
  /// static + isolate-safe, see [enhanceEsrganWithModel]. This is
  /// the function whose synchronous ONNX run + per-pixel loops
  /// froze the whole app on the UI isolate (Point #37a ANR); it
  /// must only ever be awaited from a background isolate or from
  /// a context where a multi-second block is acceptable (the
  /// export matte loop now uses the off-thread runner too).
  static img.Image? alphaMatteWithModelSync(
    File model, {
    required bool isBiref,
    required img.Image input,
  }) {
    try {
      final int size = isBiref ? 1024 : 512;
      final img.Image work = img.copyResize(
        input,
        width: size,
        height: size,
        interpolation: img.Interpolation.linear,
      );
      final Float32List data = isBiref
          ? _toChwFloat(
              work,
              (double v, int c) =>
                  (v - _imagenetMean[c]) / _imagenetStd[c],
            )
          : _toChwFloat(work, (double v, int c) => (v - 0.5) / 0.5);
      final Float32List? raw =
          _runSingleInputSync(model, data, <int>[1, 3, size, size]);
      if (raw == null || raw.length < size * size) return null;
      // Matte at model resolution (BiRefNet logits need a sigmoid;
      // MODNet already outputs 0..1 alpha).
      final Float32List matte = Float32List(size * size);
      for (int i = 0; i < size * size; i++) {
        final double v = raw[i];
        matte[i] = isBiref
            ? 1.0 / (1.0 + math.exp(-v))
            : v.clamp(0.0, 1.0);
      }
      final Float32List eroded = _erode3x3(matte, size, size);
      // Matte image at the input's own size for the composite.
      final img.Image matteSmall =
          img.Image(width: size, height: size, numChannels: 3);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final int v = (eroded[y * size + x] * 255).round();
          matteSmall.setPixelRgb(x, y, v, v, v);
        }
      }
      final img.Image matteFull = img.copyResize(
        matteSmall,
        width: input.width,
        height: input.height,
        interpolation: img.Interpolation.linear,
      );
      final img.Image out = img.Image(
        width: input.width,
        height: input.height,
        numChannels: 4,
      );
      for (int y = 0; y < input.height; y++) {
        for (int x = 0; x < input.width; x++) {
          final img.Pixel px = input.getPixel(x, y);
          final int r = px.r.toInt().clamp(0, 255);
          final int g = px.g.toInt().clamp(0, 255);
          int b = px.b.toInt().clamp(0, 255);
          final int a =
              matteFull.getPixel(x, y).r.toInt().clamp(0, 255);
          // Despill: on semi-transparent edge pixels, pull a dominant
          // blue channel back toward max(r, g) in proportion to the
          // transparency (the battery's bright-blue fringe fix).
          if (a < 255) {
            final int maxRg = math.max(r, g);
            if (b > maxRg) {
              b = maxRg + ((b - maxRg) * (a / 255.0)).round();
            }
          }
          out.setPixelRgba(x, y, r, g, b, a);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 1 px erosion (3x3 minimum) of a single-channel float map.
  static Float32List _erode3x3(Float32List src, int w, int h) {
    final Float32List out = Float32List(src.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double m = src[y * w + x];
        for (int dy = -1; dy <= 1; dy++) {
          final int yy = (y + dy).clamp(0, h - 1);
          for (int dx = -1; dx <= 1; dx++) {
            final int xx = (x + dx).clamp(0, w - 1);
            final double v = src[yy * w + xx];
            if (v < m) m = v;
          }
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Depth Anything V2 — depth-guided bokeh
  // ------------------------------------------------------------------

  /// Portrait bokeh: estimates depth with Depth Anything V2 Small,
  /// keeps near subjects sharp and blurs the far field, exactly like
  /// the battery's composite (mask = clip((d-0.45)/0.25), feathered
  /// by a blur so the transition follows the depth edges).
  /// Returns null on any failure.
  Future<img.Image?> depthBokeh(img.Image input) async {
    final File? model = await ModelPackService.instance
        .packFile('depth_v2_small', 'model_int8.onnx');
    if (model == null) return null;
    return depthBokehWithModelSync(model, input);
  }

  /// The depth-bokeh core with the model file already resolved —
  /// static + isolate-safe, see [enhanceEsrganWithModel].
  static img.Image? depthBokehWithModelSync(
    File model,
    img.Image input,
  ) {
    try {
      const int inW = 518;
      int inH = ((input.height * inW / input.width) / 14).floor() * 14;
      if (inH < 14) inH = 14;
      final img.Image work = img.copyResize(
        input,
        width: inW,
        height: inH,
        interpolation: img.Interpolation.cubic,
      );
      final Float32List data = _toChwFloat(
        work,
        (double v, int c) => (v - _imagenetMean[c]) / _imagenetStd[c],
      );
      final Float32List? raw =
          _runSingleInputSync(model, data, <int>[1, 3, inH, inW]);
      if (raw == null || raw.length < inW * inH) return null;
      double dMin = raw[0];
      double dMax = raw[0];
      for (int i = 0; i < inW * inH; i++) {
        if (raw[i] < dMin) dMin = raw[i];
        if (raw[i] > dMax) dMax = raw[i];
      }
      final double span = (dMax - dMin).abs() < 1e-9 ? 1.0 : dMax - dMin;
      // Sharpness mask at model resolution: 1 = near (sharp).
      final img.Image maskSmall =
          img.Image(width: inW, height: inH, numChannels: 3);
      for (int y = 0; y < inH; y++) {
        for (int x = 0; x < inW; x++) {
          final double dn = (raw[y * inW + x] - dMin) / span;
          final double m = ((dn - 0.45) / 0.25).clamp(0.0, 1.0);
          final int v = (m * 255).round();
          maskSmall.setPixelRgb(x, y, v, v, v);
        }
      }
      final int w = input.width;
      final int h = input.height;
      img.Image mask = img.copyResize(
        maskSmall,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      );
      // Feather the mask (the battery used a Gaussian sigma ~6–8 at
      // 518–768 px wide; scaled here to the working width).
      final int feather = (w * 0.01).round().clamp(2, 16);
      mask = img.gaussianBlur(mask, radius: feather);
      final int blurRadius = (w * 0.03).round().clamp(8, 48);
      final img.Image blurred = img.gaussianBlur(input, radius: blurRadius);
      final img.Image out =
          img.Image(width: w, height: h, numChannels: 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final double m = mask.getPixel(x, y).r / 255.0;
          final img.Pixel s = input.getPixel(x, y);
          final img.Pixel b = blurred.getPixel(x, y);
          out.setPixelRgb(
            x,
            y,
            (s.r * m + b.r * (1 - m)).round(),
            (s.g * m + b.g * (1 - m)).round(),
            (s.b * m + b.b * (1 - m)).round(),
          );
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Fast-neural-style — "Artistic Styles"
  // ------------------------------------------------------------------

  /// Applies one fast-neural-style pack ('fns_udnie', 'fns_mosaic'
  /// or 'fns_rain') to [input]: raw 0..255 float at the models'
  /// fixed 224x224, output clipped to 0..255 and resized back to the
  /// input size. Labelled "Artistic Styles" in the UI — these are
  /// painterly transfers, not a cartoonizer. Null on any failure.
  Future<img.Image?> artisticStyle(String packId, img.Image input) async {
    final String? fileName = switch (packId) {
      'fns_udnie' => 'udnie-9.onnx',
      'fns_mosaic' => 'mosaic-9.onnx',
      'fns_rain' => 'rain-princess-9.onnx',
      _ => null,
    };
    if (fileName == null) return null;
    final File? model =
        await ModelPackService.instance.packFile(packId, fileName);
    if (model == null) return null;
    return artisticStyleWithModelSync(model, input);
  }

  /// The style core with the model file already resolved —
  /// static + isolate-safe, see [enhanceEsrganWithModel].
  static img.Image? artisticStyleWithModelSync(
    File model,
    img.Image input,
  ) {
    try {
      const int size = 224;
      final img.Image work = img.copyResize(
        input,
        width: size,
        height: size,
        interpolation: img.Interpolation.cubic,
      );
      final Float32List data =
          _toChwFloat(work, (double v, int c) => v * 255.0);
      final Float32List? out =
          _runSingleInputSync(model, data, <int>[1, 3, size, size]);
      if (out == null || out.length < 3 * size * size) return null;
      final img.Image styled = _imageFromChw(out, size, size);
      return img.copyResize(
        styled,
        width: input.width,
        height: input.height,
        interpolation: img.Interpolation.cubic,
      );
    } catch (_) {
      return null;
    }
  }
}
