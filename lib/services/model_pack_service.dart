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
  const ModelPack(this.id, this.files, {this.vaultVersion = 1});

  final String id;
  final List<ModelPackFile> files;

  /// Engine Vault version of THIS pack (v1.23.0). Bump it ONLY
  /// when this pack's files change on the server — the vault then
  /// refreshes exactly this pack on each device, once. App version
  /// bumps must never touch it: the vault planner has no
  /// app-version input, so an app update alone can never trigger
  /// a re-download (the user's Engine Vault rule).
  final int vaultVersion;
}

/// WHY a pack download failed (v1.5.0, fix #27). v1.4.0 collapsed
/// every failure into one boolean, and callers translated it into
/// "internet check karein" — even when the real cause was a broken
/// URL serving a 132-byte LFS pointer. [ModelPackService.ensurePack]
/// now records the typed reason in [ModelPackService.lastFailure],
/// and callers surface [ModelPackService.describeFailure] so the
/// user is told the TRUE cause (and a working internet is never
/// blamed for a hosting problem).
enum PackFailure {
  /// Pack id is not in the registry.
  unknownPack,

  /// A pack file has no download URL yet (not hosted).
  notHosted,

  /// The server answered with a non-200 HTTP status.
  httpError,

  /// The download finished but the file is incomplete or fails the
  /// size sanity check (truncated body, wrong file served, …).
  incomplete,

  /// The request itself failed (offline, DNS, timeout, TLS).
  network,

  /// A local file operation failed (disk full, rename, …).
  storage,
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
    // RIFE v4.6 (MIT) — export-time slow-mo interpolation. From
    // v1.5.0 the tested file is mirrored on nigraantv.xyz (see
    // AppConfig.modelPackUrls), so the pack downloads for real.
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
    // DeepFilterNet3 (MIT/Apache-2.0) — HD voice enhance. Upstream
    // ships only a release tar.gz; from v1.5.0 the four files are
    // mirrored on nigraantv.xyz (sizes below = the extracted files,
    // pinned so the sanity check covers them too). The pack is
    // downloadable, but the DFN3 DSP pipeline is NOT ported yet —
    // AudioEnhanceService ships its ffmpeg chain meanwhile and
    // never claims this pack.
    ModelPack('dfn3', <ModelPackFile>[
      ModelPackFile('enc.onnx', expectedBytes: 1954042),
      ModelPackFile('erb_dec.onnx', expectedBytes: 3292397),
      ModelPackFile('df_dec.onnx', expectedBytes: 3340803),
      ModelPackFile('config.ini', expectedBytes: 2067),
    ]),
    // RNNoise .rnnn model(s) for ffmpeg's arnndn filter — reduce
    // noise (AudioEnhanceService). cb.rnnn is the general-purpose
    // speech model from the official xiph model set.
    ModelPack('rnnoise_models', <ModelPackFile>[
      // Size pinned v1.23.0 for the Engine Vault's exact-size
      // check: measured from the served file itself (GregorR/
      // rnnoise-models, conjoined-burgers cb.rnnn) — body length
      // and the server's Content-Length both 299741 bytes, header
      // "rnnoise-nu model file version 1" verified.
      ModelPackFile('cb.rnnn', expectedBytes: 299741),
    ]),
  ];

  /// Registry lookup (null for an unknown pack id).
  static ModelPack? packById(String packId) {
    for (final pack in packs) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  /// The Engine Vault root: `<app support>/model_packs` — every
  /// pack directory and the vault manifest live directly inside
  /// it (v1.23.0). Created when missing. Never throws.
  Future<Directory> packsRoot() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'model_packs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _packDir(String packId) async {
    final root = await packsRoot();
    final dir = Directory(p.join(root.path, packId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes the named files of [packId] from disk (fail-soft,
  /// never throws). Engine Vault repair/refresh support: the
  /// planner names the exact files that are missing/mismatched
  /// (repair) or the whole pack (refresh); they are removed here
  /// and [ensurePack] then re-downloads exactly those — every
  /// other file of every other pack stays untouched.
  Future<void> deletePackFiles(String packId, List<String> names) async {
    try {
      final dir = await _packDir(packId);
      for (final name in names) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Best-effort: ensurePack's own sanity checks decide what
      // still needs downloading afterwards.
    }
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

  /// The typed reason the most recent [ensurePack] call failed, or
  /// null when it succeeded (v1.5.0, fix #27). Callers read this
  /// right after a false return and show [describeFailure].
  PackFailure? lastFailure;

  /// The honest user-facing line for a [PackFailure] — each reason
  /// names its TRUE cause; only [PackFailure.network] mentions the
  /// internet, because only that one is the user's connection.
  static String describeFailure(PackFailure? failure) {
    switch (failure) {
      case PackFailure.unknownPack:
        return 'This AI pack is not present in this app version.';
      case PackFailure.notHosted:
        return 'This AI pack is not hosted yet — this feature cannot '
            'be downloaded at this time.';
      case PackFailure.httpError:
        return 'The AI pack server returned an error — try again '
            'try again.';
      case PackFailure.incomplete:
        return 'The AI pack download was incomplete or the wrong file arrived — '
            'try again.';
      case PackFailure.network:
        return 'The AI pack could not download — check the internet '
            'and try again.';
      case PackFailure.storage:
        return 'There is a problem with the phone storage — check the space '
            'and try again.';
      case null:
        return 'The AI pack could not download — try again.';
    }
  }

  /// Downloads any missing files of [packId] and returns true only
  /// when the complete pack is present and sane afterwards. On a
  /// false return, [lastFailure] carries the typed reason.
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
    lastFailure = null;
    final pack = packById(packId);
    if (pack == null) {
      lastFailure = PackFailure.unknownPack;
      return false;
    }
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
          if (url.trim().isEmpty) {
            lastFailure = PackFailure.notHosted;
            return false;
          }
          final PackFailure? failure = await _download(
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
          if (failure != null) {
            lastFailure = failure;
            return false;
          }
          doneBytes += spec.expectedBytes;
        }
      } finally {
        client.close();
      }
      onProgress?.call(1.0);
      final ready = await isReady(packId);
      if (!ready) lastFailure = PackFailure.incomplete;
      return ready;
    } catch (_) {
      lastFailure ??= PackFailure.network;
      return false;
    }
  }

  /// Streams [url] into `<target>.part`, verifies the byte count
  /// (Content-Length when sent + the registry sanity floor), then
  /// renames it onto [target]. Returns null on success, otherwise
  /// the typed [PackFailure]; the partial file is always removed.
  Future<PackFailure?> _download(
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
      if (response.statusCode != 200) {
        return PackFailure.httpError;
      }
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
        return PackFailure.incomplete;
      }
      if (!await _fileOk(part, spec)) {
        await _deleteQuiet(part);
        return PackFailure.incomplete;
      }
      try {
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
      } catch (_) {
        await _deleteQuiet(part);
        return PackFailure.storage;
      }
      return null;
    } catch (_) {
      await _deleteQuiet(part);
      return PackFailure.network;
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
