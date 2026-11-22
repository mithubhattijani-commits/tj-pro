/// Model packs — downloadable AI models for v1.4.0 (NEVER bundled).
///
/// Every v1.4.0 AI model (captions, matting, enhance, depth, style,
/// denoise) ships as a downloadable pack, following the app's
/// standing rule (user order 20 Nov 2026: keep the app as small as
/// possible — the same rule that made the Kasheeda font and the
/// Nigraan intro on-demand downloads). Packs live in the app SUPPORT
/// directory (not documents — they are re-downloadable caches, not
/// user data):
///
///   `<app support>/model_packs/<packId>/<fileName>`
///
/// This service is the single registry + downloader every workstream
/// consumes (API fixed by V140-BUILD-PLAN.md):
///   - [ensurePack] downloads any missing files with progress and
///     returns true only when the whole pack is present and sane.
///   - [isReady] is a pure on-disk check (no network).
///   - [packFile] returns one downloaded file, or null.
///
/// URLs live in [AppConfig.modelPackUrls] (keyed
/// `<packId>/<fileName>`); a file with no URL is "not hosted yet"
/// and [ensurePack] fails soft with false — never a placeholder
/// download. Expected sizes below are the byte counts verified in
/// the tool-test battery (V140-TOOL-TESTS.md); a downloaded file
/// must be at least 90% of its expected size to count as sane
/// (guards against error pages / truncated mirrors) and a streamed
/// download must match its Content-Length exactly when one is sent.
///
/// FAIL-SOFT everywhere: no method throws. Any error (offline, 404,
/// disk full, unknown pack) returns false / null and the caller
/// falls back to its non-AI path.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';

/// One file inside a [ModelPack].
class ModelPackFile {
  const ModelPackFile(this.name, {this.expectedBytes = 0});

  /// File name inside the pack directory (also the URL key suffix).
  final String name;

  /// Verified size in bytes from the tool-test battery (0 = unknown,
  /// e.g. small text/config files whose mirror size is not pinned).
  /// When > 0, a file smaller than 90% of this is treated as broken.
  final int expectedBytes;
}

/// A named set of model files downloaded together.
class ModelPack {
  const ModelPack(this.id, this.files);

  final String id;
  final List<ModelPackFile> files;
}

class ModelPackService {
  ModelPackService._();

  /// Shared instance (the contract API).
  static final ModelPackService instance = ModelPackService._();

  /// The pack registry (ids + files fixed by V140-BUILD-PLAN.md).
  static const List<ModelPack> packs = <ModelPack>[
    // Shruti Urdu sherpa-onnx Moonshine pack (Apache-2.0, 53.9 MB) —
    // Urdu auto captions (UrduCaptionService).
    ModelPack('shruti_ur', <ModelPackFile>[
      ModelPackFile('preprocess.onnx', expectedBytes: 912310),
      ModelPackFile('encode.onnx', expectedBytes: 19637087),
      ModelPackFile('uncached_decode.onnx', expectedBytes: 421454),
      ModelPackFile('cached_decode.onnx', expectedBytes: 32801767),
      ModelPackFile('tokens.txt', expectedBytes: 118676),
    ]),
    // MI-GAN (MIT) — photo object remove.
    ModelPack('migan', <ModelPackFile>[
      ModelPackFile('migan_pipeline_v2.onnx', expectedBytes: 28079181),
    ]),
    // BiRefNet_lite fp16 (MIT) — photo BG matte at fixed 1024x1024.
    ModelPack('birefnet_fp16', <ModelPackFile>[
      ModelPackFile('model_fp16.onnx', expectedBytes: 114538221),
    ]),
    // Real-ESRGAN general-x4v3 (BSD-3) — photo enhance.
    ModelPack('esrgan', <ModelPackFile>[
      ModelPackFile('realesr-general-x4v3.onnx', expectedBytes: 4866417),
    ]),
    // Depth Anything V2 Small int8 (Apache-2.0) — depth/bokeh.
    ModelPack('depth_v2_small', <ModelPackFile>[
      ModelPackFile('model_int8.onnx', expectedBytes: 27258801),
    ]),
    // MODNet (Apache-2.0) — portrait matte at 512x512.
    ModelPack('modnet', <ModelPackFile>[
      ModelPackFile('model.onnx', expectedBytes: 25888640),
    ]),
    // RIFE v4.6 (MIT) — export-time slow-mo interpolation. Registered
    // for the export workstream; no single-file host yet (the tested
    // file came out of the vs-mlrt 7z package), so ensurePack fails
    // soft until a URL is added to AppConfig.modelPackUrls.
    ModelPack('rife_v46', <ModelPackFile>[
      ModelPackFile('rife_v4.6.onnx', expectedBytes: 21297017),
    ]),
    // Fast-neural-style (ONNX Model Zoo, Apache-2.0) — "Artistic
    // Styles", fixed 224x224. Candy is BANNED (eye artifact).
    ModelPack('fns_udnie', <ModelPackFile>[
      ModelPackFile('udnie-9.onnx', expectedBytes: 6728029),
    ]),
    ModelPack('fns_mosaic', <ModelPackFile>[
      ModelPackFile('mosaic-9.onnx', expectedBytes: 6728029),
    ]),
    ModelPack('fns_rain', <ModelPackFile>[
      ModelPackFile('rain-princess-9.onnx', expectedBytes: 6728029),
    ]),
    // DeepFilterNet3 (MIT/Apache-2.0) — HD voice enhance. Registered
    // per the contract; upstream ships only a release tar.gz, so no
    // per-file URLs exist yet and the pack stays unhosted in v1.4.0
    // (AudioEnhanceService ships its ffmpeg chain meanwhile).
    ModelPack('dfn3', <ModelPackFile>[
      ModelPackFile('enc.onnx'),
      ModelPackFile('erb_dec.onnx'),
      ModelPackFile('df_dec.onnx'),
      ModelPackFile('config.ini'),
    ]),
    // RNNoise .rnnn model(s) for ffmpeg's arnndn filter — reduce
    // noise (AudioEnhanceService). cb.rnnn is the general-purpose
    // speech model from the official xiph model set.
    ModelPack('rnnoise_models', <ModelPackFile>[
      ModelPackFile('cb.rnnn'),
    ]),
  ];

  /// Registry lookup (null for an unknown pack id).
  static ModelPack? packById(String packId) {
    for (final pack in packs) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  Future<Directory> _packDir(String packId) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'model_packs', packId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// On-disk sanity for one pack file: exists, non-empty, and (when
  /// the verified size is known) at least 90% of it.
  Future<bool> _fileOk(File file, ModelPackFile spec) async {
    try {
      if (!await file.exists()) return false;
      final int len = await file.length();
      if (len <= 0) return false;
      if (spec.expectedBytes > 0 &&
          len < (spec.expectedBytes * 0.9).round()) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when every file of [packId] is downloaded and sane.
  /// Pure disk check — never touches the network, never throws.
  Future<bool> isReady(String packId) async {
    final pack = packById(packId);
    if (pack == null) return false;
    try {
      final dir = await _packDir(packId);
      for (final spec in pack.files) {
        if (!await _fileOk(File(p.join(dir.path, spec.name)), spec)) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// One downloaded pack file, or null when the pack (or that file)
  /// is not on disk. Never throws.
  Future<File?> packFile(String packId, String fileName) async {
    try {
      final dir = await _packDir(packId);
      final file = File(p.join(dir.path, fileName));
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads any missing files of [packId] and returns true only
  /// when the complete pack is present and sane afterwards.
  ///
  /// [onProgress] reports overall 0..1 across the pack's known-size
  /// files (files with unknown size count as done once downloaded).
  /// Already-sane files are reused with no network use. Fail-soft:
  /// any error (unknown pack, missing URL, HTTP failure, truncated
  /// body, disk error) returns false and leaves no partial file
  /// behind (downloads land in `<name>.part` first and are renamed
  /// only after the size sanity check passes).
  Future<bool> ensurePack(
    String packId, {
    void Function(double progress)? onProgress,
  }) async {
    final pack = packById(packId);
    if (pack == null) return false;
    try {
      if (await isReady(packId)) {
        onProgress?.call(1.0);
        return true;
      }
      final dir = await _packDir(packId);
      final int totalBytes =
          pack.files.fold<int>(0, (sum, f) => sum + f.expectedBytes);
      int doneBytes = 0;
      final client = http.Client();
      try {
        for (final spec in pack.files) {
          final target = File(p.join(dir.path, spec.name));
          if (await _fileOk(target, spec)) {
            doneBytes += spec.expectedBytes;
            continue;
          }
          final String url =
              AppConfig.modelPackUrls['$packId/${spec.name}'] ?? '';
          if (url.trim().isEmpty) return false;
          final bool ok = await _download(
            client,
            url: url,
            target: target,
            spec: spec,
            onFraction: onProgress == null || totalBytes <= 0
                ? null
                : (fraction) {
                    onProgress(
                      ((doneBytes + spec.expectedBytes * fraction) /
                              totalBytes)
                          .clamp(0.0, 1.0),
                    );
                  },
          );
          if (!ok) return false;
          doneBytes += spec.expectedBytes;
        }
      } finally {
        client.close();
      }
      onProgress?.call(1.0);
      return await isReady(packId);
    } catch (_) {
      return false;
    }
  }

  /// Streams [url] into `<target>.part`, verifies the byte count
  /// (Content-Length when sent + the registry sanity floor), then
  /// renames it onto [target]. Returns false on any failure and
  /// removes the partial file.
  Future<bool> _download(
    http.Client client, {
    required String url,
    required File target,
    required ModelPackFile spec,
    void Function(double fraction)? onFraction,
  }) async {
    final File part = File('${target.path}.part');
    try {
      final http.StreamedResponse response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 15));
      if (response.statusCode != 200) return false;
      final int total = response.contentLength ?? -1;
      final IOSink sink = part.openWrite();
      int received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (onFraction != null && total > 0) {
            onFraction((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        await _deleteQuiet(part);
        return false;
      }
      if (!await _fileOk(part, spec)) {
        await _deleteQuiet(part);
        return false;
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return true;
    } catch (_) {
      await _deleteQuiet(part);
      return false;
    }
  }

  Future<void> _deleteQuiet(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}
