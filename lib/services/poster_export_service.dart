/// Thumbnail / poster export (Phase 9, master prompt §5 + §7 item 12).
///
/// Renders the CURRENT template frame (final 3-ribbon / breaking /
/// classic, with the channel preset's ribbons, logo and colours) as a
/// real PNG poster — the same dart:ui renderer the live preview and
/// the reel export use (`renderLiveTemplateImage`), so the poster
/// looks exactly like the video's template. Two sizes:
///
///   - portrait 720×1280 (reel / Shorts thumbnail)
///   - landscape 1280×720 (YouTube / Facebook thumbnail)
///
/// The render is BOUNDED: the portrait poster never exceeds
/// 720×1280 even for a 4K project (preview renders are capped —
/// since Build 10 the cap is the engine's per-tier bound, see
/// [PerformanceConfig]; the file written IS the poster at that
/// size, no upscaling).
///
/// The returned file is a real PNG on disk (decoded + dimension
/// checked in tests). Saving to the gallery (`Gal.putImage`) and
/// sharing (`SharePlus`) are separate steps so tests can verify the
/// render without a gallery.
library;

import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../live/news_template.dart';
import '../news/breaking_templates.dart';
import '../news/channel_preset.dart';
import '../news/news_project.dart';
import 'performance_engine.dart';

/// Poster size. The file written is exactly this many pixels —
/// verified in tests by decoding the PNG.
enum PosterSize {
  portrait(720, 1280, '720×1280'),
  landscape(1280, 720, '1280×720');

  const PosterSize(this.width, this.height, this.label);

  final int width;
  final int height;
  final String label;
}

/// Result of one poster render.
class PosterResult {
  const PosterResult({
    required this.success,
    this.file,
    this.error,
  });

  final bool success;

  /// The rendered PNG file (in [dirOverride] when given, else the
  /// app documents dir).
  final File? file;
  final String? error;
}

class PosterExportService {
  /// Renders the project's template as a poster PNG of [size].
  /// The ticker is pinned at the start (`tickerAtStart: true`) so
  /// the text is visible in the still frame, and the logo IS
  /// included (a poster is a still — unlike the reel export, where
  /// the logo is a separate rotating loop). [dirOverride] is a test
  /// seam; production passes none (documents dir).
  static Future<PosterResult> renderPoster({
    required NewsProject project,
    required ChannelPreset preset,
    PosterSize size = PosterSize.portrait,
    Directory? dirOverride,
    bool fontReady = false,
  }) async {
    try {
      // Portrait posters are capped at the preview bound; landscape
      // is the same pixel count rotated (1280×720).
      // Build 10 (7B): the bound is the engine's per-tier
      // preview cap; on MID/HIGH it equals the historical
      // ExportLimits bound exactly.
      final engineCap = PerformanceEngine.instance.config.value;
      assert(
        size.width <= engineCap.previewMaxWidth ||
            size.height <= engineCap.previewMaxHeight,
        'Poster size exceeds the preview render bound',
      );
      final dir = dirOverride ?? await getApplicationDocumentsDirectory();
      final file = await renderLiveTemplateImage(
        template: NewsTemplate(),
        tickerPx: 0,
        now: DateTime.now(),
        dir: dir,
        width: size.width,
        height: size.height,
        templateKind: project.templateKind,
        preset: preset,
        breakingTemplate: project.templateKind == 'breaking'
            ? BreakingTemplate.fromProject(project, preset)
            : null,
        tickerAtStart: true,
        includeLogo: true,
        fontReady: fontReady,
        includeIntroMarker: false,
      );
      return PosterResult(success: true, file: file);
    } catch (e) {
      return PosterResult(
        success: false,
        error: 'Poster did not render: $e',
      );
    }
  }

  /// Saves [poster] to the gallery. Returns false (with the reason
  /// in [error]) when gallery access is denied — never a silent
  /// "saved".
  static Future<({bool ok, String? error})> saveToGallery(
    File poster,
  ) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          return (ok: false, error: 'Gallery access denied.');
        }
      }
      await Gal.putImage(poster.path);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Shares [poster] via the system share sheet. Returns false with
  /// the reason when sharing fails.
  static Future<({bool ok, String? error})> sharePoster(
    File poster,
  ) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(poster.path)]),
      );
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }
}
