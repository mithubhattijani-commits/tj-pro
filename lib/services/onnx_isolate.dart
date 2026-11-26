/// Off-thread ONNX image runner (v1.17.0, G1 — Point #37a).
///
/// WHY THIS FILE EXISTS — the ANR root cause, proven from code:
/// every ONNX image op used to run on the UI isolate. The matte
/// path alone (NS Reporter BG Remove, Photo Editor HQ Cutout)
/// chained, all on the UI thread: a full-res `img.decodeImage`,
/// a 1024×1024 `copyResize`, 3.1M `getPixel` tensor-conversion
/// calls, `OrtSession.run` — a SYNCHRONOUS FFI call in the
/// onnxruntime package, so BiRefNet fp16 inference blocked the
/// UI thread for its whole duration — a 1M-element sigmoid, a
/// 9.4M-op 3×3 erode, a full-res per-pixel composite loop and a
/// full-res PNG encode. Android raises the "app isn't
/// responding" dialog after ~5 s of input blockage; any one of
/// those steps can cross it on a phone CPU, together they made
/// the ANR deterministic. (Dart CrashGuard cannot see a native
/// input ANR — same blind spot as Point #24.)
///
/// THE FIX: the whole op — decode, inference, pixel post-work,
/// encode — runs in ONE background isolate via [compute]. Only
/// plain data crosses: the model file's PATH (resolved on the
/// calling isolate, because path_provider is a platform channel
/// and cannot run in a background isolate), the input bytes and,
/// for MI-GAN, the painted strokes. The onnxruntime package is
/// pure FFI (DynamicLibrary), which loads per-isolate, so the
/// session is created inside the job isolate; the *WithModelSync
/// cores in onnx_image_service.dart are the single
/// implementation both paths share.
///
/// Fail-soft contract, unchanged from the on-thread path: any
/// failure (missing pack, bad model file, inference error)
/// returns null and the caller keeps the original image and
/// shows the honest reason.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'model_pack_service.dart';
import 'onnx_image_service.dart';
import 'photo_pipeline.dart'
    show StrokePath, compositeMatteAlphaBytes, maskFromStrokes;

/// Op names understood by [onnxImageIsolateJob].
const String kOnnxOpMatte = 'matte';
const String kOnnxOpEsrgan = 'esrgan';
const String kOnnxOpMigan = 'migan';
const String kOnnxOpBokeh = 'bokeh';
const String kOnnxOpStyle = 'style';

/// The isolate entry point. Args (List, compute convention):
/// `[op, modelPath, inputBytes, strokesOrNull]`.
/// Returns the result as PNG bytes, or null on any failure.
/// Pure Dart + FFI only — no platform channels in here.
Uint8List? onnxImageIsolateJob(List<dynamic> args) {
  try {
    final op = args[0] as String;
    final model = File(args[1] as String);
    final inputBytes = args[2] as Uint8List;
    final strokes = args.length > 3 ? args[3] as List<StrokePath>? : null;
    final input = img.decodeImage(inputBytes);
    if (input == null) return null;
    img.Image? out;
    switch (op) {
      case kOnnxOpMatteBiref:
        out = OnnxImageService.alphaMatteWithModelSync(
          model,
          isBiref: true,
          input: input,
        );
        break;
      case kOnnxOpMatteCutout:
        // HQ Cutout: matte + the alpha composite in ONE job —
        // the Photo Editor's old flow ran both on the UI
        // isolate (the same ANR class as the Reporter path).
        final matted = OnnxImageService.alphaMatteWithModelSync(
          model,
          isBiref: true,
          input: input,
        );
        if (matted == null) return null;
        final srcBytes = input
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.rgba);
        final matteBytes = matted
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.rgba);
        final composited = compositeMatteAlphaBytes(srcBytes, matteBytes);
        out = img.Image.fromBytes(
          width: input.width,
          height: input.height,
          bytes: composited.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
        break;
      case kOnnxOpMatte:
        out = OnnxImageService.alphaMatteWithModelSync(
          model,
          isBiref: false,
          input: input,
        );
        break;
      case kOnnxOpEsrgan:
        out = OnnxImageService.enhanceEsrganWithModelSync(model, input);
        break;
      case kOnnxOpMigan:
        if (strokes == null) return null;
        final mask = maskFromStrokes(input.width, input.height, strokes);
        out = OnnxImageService.removeWithMiganWithModelSync(
          model,
          input,
          mask,
        );
        break;
      case kOnnxOpBokeh:
        out = OnnxImageService.depthBokehWithModelSync(model, input);
        break;
      case kOnnxOpStyle:
        out = OnnxImageService.artisticStyleWithModelSync(model, input);
        break;
      default:
        return null;
    }
    if (out == null) return null;
    return img.encodePng(out);
  } catch (_) {
    return null;
  }
}

/// BiRefNet variant of the matte op (1024², sigmoid) — MODNet
/// ('matte') runs at 512² with raw alpha. Kept as separate op
/// names so the job needs no extra flag argument.
const String kOnnxOpMatteBiref = 'matteBiref';

/// BiRefNet matte + alpha composite in one job (Photo Editor
/// HQ Cutout's full pipeline).
const String kOnnxOpMatteCutout = 'matteCutout';

/// Runs one ONNX image op OFF the UI thread.
///
/// [packId] selects the model pack (its file is resolved via
/// [ModelPackService.packFile] here, on the calling isolate);
/// [op] is one of the kOnnxOp* names — for mattes pass
/// [kOnnxOpMatteBiref] for 'birefnet_fp16' and [kOnnxOpMatte]
/// for 'modnet' (see [matteOpForPack]). [strokes] is required
/// for the MI-GAN op only. Returns PNG bytes, or null when the
/// pack is missing or the op failed (fail-soft, as before).
Future<Uint8List?> runOnnxOpOffThread({
  required String op,
  required String packId,
  required Uint8List inputBytes,
  List<StrokePath>? strokes,
}) async {
  try {
    final fileName = OnnxImageService.modelFileNameForPack(packId);
    if (fileName == null) return null;
    final model = await ModelPackService.instance.packFile(packId, fileName);
    if (model == null) return null;
    return await compute(
      onnxImageIsolateJob,
      <dynamic>[op, model.path, inputBytes, strokes],
    );
  } catch (_) {
    return null;
  }
}

/// The matte op name for a matting pack id.
String matteOpForPack(String packId) =>
    packId == 'birefnet_fp16' ? kOnnxOpMatteBiref : kOnnxOpMatte;
