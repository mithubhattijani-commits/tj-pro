import 'package:shared_preferences/shared_preferences.dart';

import 'asset_download_service.dart';
import 'caption_service.dart';
import 'caption_translator_service.dart';
import 'model_pack_service.dart';

/// v1.17.0 (G5, Point #37d): first-run tools preparation.
///
/// The user's rule: every feature model/asset the app needs
/// downloads ONCE, up front, with visible progress — so no
/// tool ever stalls on a download mid-use (the click-time
/// 114 MB BiRefNet download was one of the roots of the
/// Point #37a ANR). The item list is DERIVED from the real
/// registries (every [ModelPackService] pack + the Whisper
/// captions model + the Kasheeda font + the ML Kit Urdu/English
/// translation models), so a future pack joins the preparation
/// automatically.
///
/// Honesty rules: readiness is always verified against the
/// disk, never just a flag; a failed item is reported by name
/// and the preparation still completes (the owning tool keeps
/// its own at-use retry + honest error); nothing here can hang
/// a tool — worst case the tool downloads at use, as before.
class PrepItem {
  const PrepItem(this.id, this.label, this.weightBytes);

  /// 'pack:' + pack id for model packs; 'whisper' / 'kasheeda' /
  /// 'translate' for the non-pack assets.
  final String id;
  final String label;

  /// Expected download size — only used to weight the overall
  /// progress bar.
  final int weightBytes;
}

class PrepProgress {
  const PrepProgress({
    required this.label,
    required this.itemFraction,
    required this.overall,
  });

  /// The item currently downloading.
  final String label;

  /// 0..1 within the current item.
  final double itemFraction;

  /// 0..1 across the whole preparation (byte-weighted).
  final double overall;
}

class FirstRunPrepService {
  FirstRunPrepService._();

  /// Set when a full run finished with zero failures. The flag
  /// is only a fast path — [isComplete] re-verifies the disk,
  /// so a cleared cache re-triggers the preparation.
  static const String doneKey = 'tools_prep_v1_done';

  /// Process-level guard for the Home hook: the preparation
  /// screen is offered at most once per app launch.
  static bool offeredThisProcess = false;

  /// Process-level guard against two runs racing.
  static bool _running = false;

  static const Map<String, String> _packLabels = {
    'shruti_ur': 'Urdu speech model (Shruti)',
    'migan': 'Object remover model (MI-GAN)',
    'birefnet_fp16': 'Background remover model (BiRefNet)',
    'esrgan': 'AI enhance model (ESRGAN)',
    'depth_v2_small': 'Portrait depth model',
    'modnet': 'Video background model (MODNet)',
    'rife_v46': 'Smooth slow-motion model (RIFE)',
    'fns_udnie': 'Artistic style — Udnie',
    'fns_mosaic': 'Artistic style — Mosaic',
    'fns_rain': 'Artistic style — Rain',
    'dfn3': 'Video denoise model',
    'rnnoise_models': 'Noise reduction model (RNNoise)',
  };

  /// The full preparation list, derived from the registries.
  static List<PrepItem> items() {
    final list = <PrepItem>[];
    for (final pack in ModelPackService.packs) {
      var bytes = 0;
      for (final f in pack.files) {
        bytes += f.expectedBytes;
      }
      list.add(
        PrepItem(
          'pack:${pack.id}',
          _packLabels[pack.id] ?? 'AI model (${pack.id})',
          bytes > 0 ? bytes : 1024 * 1024,
        ),
      );
    }
    list.addAll(const [
      // ggml-tiny.bin ≈ 75 MB.
      PrepItem('whisper', 'Captions speech model (Whisper)', 75 * 1024 * 1024),
      PrepItem('kasheeda', 'Urdu Kasheeda font', 256 * 1024),
      // Two ML Kit on-device models ≈ 30 MB each.
      PrepItem(
        'translate',
        'Urdu ⇄ English translation models',
        60 * 1024 * 1024,
      ),
    ]);
    return list;
  }

  /// Byte-weighted overall progress from per-item fractions.
  /// Pure — unit-tested.
  static double overallFor(List<double> fractions, List<int> weights) {
    var totalWeight = 0;
    var acc = 0.0;
    for (var i = 0; i < fractions.length; i++) {
      final w = i < weights.length ? weights[i] : 0;
      if (w <= 0) continue;
      totalWeight += w;
      acc += fractions[i].clamp(0.0, 1.0) * w;
    }
    if (totalWeight == 0) {
      if (fractions.isEmpty) return 1;
      var sum = 0.0;
      for (final f in fractions) {
        sum += f.clamp(0.0, 1.0);
      }
      return sum / fractions.length;
    }
    return acc / totalWeight;
  }

  /// True only when EVERY item verifies on disk right now.
  static Future<bool> isComplete({required String kasheedaUrl}) async {
    for (final item in items()) {
      if (!await _itemReady(item, kasheedaUrl: kasheedaUrl)) return false;
    }
    return true;
  }

  static Future<bool> _itemReady(
    PrepItem item, {
    required String kasheedaUrl,
  }) async {
    try {
      if (item.id.startsWith('pack:')) {
        return await ModelPackService.instance.isReady(
          item.id.substring(5),
        );
      }
      switch (item.id) {
        case 'whisper':
          return await FileCaptionEngine.whisperModelReady();
        case 'kasheeda':
          return await AssetDownloadService().ensureKasheedaFontReady(
            url: kasheedaUrl,
          );
        case 'translate':
          return await CaptionTranslatorService.modelsReady();
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Runs the preparation once, sequentially, fail-soft per
  /// item. Returns the labels of the items that did NOT become
  /// ready (empty = fully prepared). Never throws.
  static Future<List<String>> run({
    required String kasheedaUrl,
    void Function(PrepProgress progress)? onProgress,
  }) async {
    if (_running) return const ['Preparation already running'];
    _running = true;
    final failed = <String>[];
    try {
      final list = items();
      final weights = [for (final i in list) i.weightBytes];
      final fractions = List<double>.filled(list.length, 0);
      void emit(int index) {
        onProgress?.call(
          PrepProgress(
            label: list[index].label,
            itemFraction: fractions[index],
            overall: overallFor(fractions, weights),
          ),
        );
      }

      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        emit(i);
        var ok = false;
        try {
          if (await _itemReady(item, kasheedaUrl: kasheedaUrl)) {
            fractions[i] = 1;
            ok = true;
          } else if (item.id.startsWith('pack:')) {
            ok = await ModelPackService.instance.ensurePack(
              item.id.substring(5),
              onProgress: (f) {
                fractions[i] = f;
                emit(i);
              },
            );
          } else if (item.id == 'whisper') {
            await FileCaptionEngine.ensureWhisperModel(
              onProgress: (f) {
                fractions[i] = f;
                emit(i);
              },
            );
            ok = await FileCaptionEngine.whisperModelReady();
          } else if (item.id == 'kasheeda') {
            ok = await AssetDownloadService().ensureKasheedaFontReady(
              url: kasheedaUrl,
            );
          } else if (item.id == 'translate') {
            try {
              await CaptionTranslatorService.ensureModels(
                fromLang: 'ur',
                toLang: 'en',
              );
              ok = true;
            } catch (_) {
              ok = false;
            }
          }
        } catch (_) {
          ok = false;
        }
        if (ok) {
          fractions[i] = 1;
        } else {
          failed.add(item.label);
        }
        emit(i);
      }
      if (failed.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(doneKey, true);
        } catch (_) {
          // The flag is only a fast path; the disk check rules.
        }
      }
      return failed;
    } finally {
      _running = false;
    }
  }
}
