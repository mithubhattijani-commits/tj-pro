/// Caption translation Urdu↔English (Phase 5, ported from Magic
/// Box's `translation_service.dart`, v1.0.13 — adapted: Magic Box's
/// coin charge (`translateCharged`, 25 coins/min) is NOT ported —
/// TJ Pro has no coin economy for translation (5/day cap covers
/// Gemini TTS only; translation is on-device and free). The
/// on-device ML Kit part is unchanged.
///
/// Fully on-device with ML Kit. No server, no paid API, no keys.
/// The models download once on first use (about 30 MB per language,
/// over any connection — mobile data included); after that
/// translation works offline.
library;

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'caption_service.dart';

class CaptionTranslatorService {
  static TranslateLanguage _mlKitLang(String lang) {
    if (lang == 'ur') return TranslateLanguage.urdu;
    if (lang == 'en') return TranslateLanguage.english;
    throw Exception('Translation supports Urdu and English only.');
  }

  /// Download the two language models if missing. Returns normally
  /// once both are ready; throws when the download fails (offline,
  /// Play services missing, …). Mobile data is allowed.
  static Future<void> ensureModels({
    required String fromLang,
    required String toLang,
  }) async {
    final manager = OnDeviceTranslatorModelManager();
    for (final lang in {_mlKitLang(fromLang), _mlKitLang(toLang)}) {
      final code = lang.bcpCode;
      final downloaded = await manager.isModelDownloaded(code);
      if (!downloaded) {
        final ok = await manager.downloadModel(
          code,
          isWifiRequired: false,
        );
        if (!ok) {
          throw Exception(
            'Could not download the translation model ($code). '
            'Check the internet and try again.',
          );
        }
      }
    }
  }

  /// Translate caption lines one by one (line-by-line keeps the 1:1
  /// timing — every translated line keeps its original start/end).
  /// Empty lines stay empty. [onProgress] reports (done, total).
  static Future<List<String>> translateLines({
    required List<String> lines,
    required String fromLang,
    required String toLang,
    void Function(int done, int total)? onProgress,
  }) async {
    final translator = OnDeviceTranslator(
      sourceLanguage: _mlKitLang(fromLang),
      targetLanguage: _mlKitLang(toLang),
    );
    try {
      final out = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) {
          out.add('');
        } else {
          out.add(await translator.translateText(line));
        }
        onProgress?.call(i + 1, lines.length);
      }
      return out;
    } finally {
      await translator.close();
    }
  }

  /// Translate timed caption segments, keeping every segment's
  /// start/end. Returns the translated segments in the same order.
  static Future<List<CaptionSegment>> translateSegments({
    required List<CaptionSegment> segments,
    required String fromLang,
    required String toLang,
    void Function(int done, int total)? onProgress,
  }) async {
    final texts = await translateLines(
      lines: segments.map((s) => s.text).toList(),
      fromLang: fromLang,
      toLang: toLang,
      onProgress: onProgress,
    );
    return [
      for (var i = 0; i < segments.length; i++)
        CaptionSegment(
          texts[i],
          segments[i].start,
          segments[i].end,
          words: segments[i].words,
        ),
    ];
  }
}
