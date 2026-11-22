/// Shared news-template model for TJ Pro v2 "Live Studio".
///
/// One template drives THREE surfaces so the news look stays identical:
///   1. The live view (Flutter widgets over the camera preview).
///   2. The live broadcast (a composited PNG refreshed while streaming
///      and pushed through the streamer's overlay-image slot).
///   3. Editor exports (FFmpeg drawtext/drawbox filters — see
///      FfmpegService.newsTemplateFilters; logo goes through a second
///      overlay pass because the export commands are single-input).
///
/// The template itself is NOT a secret (headline/ticker/logo path), so
/// it is persisted as plain JSON in the app documents directory. Stream
/// keys are NEVER stored here — they live in flutter_secure_storage
/// (see StreamKeyStore) and are never logged or printed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../news/breaking_templates.dart';
import '../news/channel_preset.dart';
import '../services/asset_download_service.dart';

/// Logo corner inside the frame.
enum LogoPosition {
  topLeft('Top left'),
  topRight('Top right'),
  bottomLeft('Bottom left'),
  bottomRight('Bottom right');

  const LogoPosition(this.label);
  final String label;
}

class NewsTemplate {
  NewsTemplate({
    this.breakingHeadline = '',
    this.lowerTitle = '',
    this.lowerSubtitle = '',
    this.tickerText = '',
    this.showClock = true,
    this.logoPath,
    this.logoPosition = LogoPosition.topRight,
    this.logoRotate = false,
  });

  String breakingHeadline;
  String lowerTitle;
  String lowerSubtitle;
  String tickerText;
  bool showClock;
  String? logoPath;
  LogoPosition logoPosition;
  bool logoRotate;

  bool get isEmpty =>
      breakingHeadline.trim().isEmpty &&
      lowerTitle.trim().isEmpty &&
      lowerSubtitle.trim().isEmpty &&
      tickerText.trim().isEmpty &&
      logoPath == null;

  Map<String, dynamic> toJson() => {
        'breakingHeadline': breakingHeadline,
        'lowerTitle': lowerTitle,
        'lowerSubtitle': lowerSubtitle,
        'tickerText': tickerText,
        'showClock': showClock,
        'logoPath': logoPath,
        'logoPosition': logoPosition.name,
        'logoRotate': logoRotate,
      };

  static NewsTemplate fromJson(Map<String, dynamic> json) {
    LogoPosition pos = LogoPosition.topRight;
    final raw = json['logoPosition'];
    if (raw is String) {
      for (final v in LogoPosition.values) {
        if (v.name == raw) pos = v;
      }
    }
    return NewsTemplate(
      breakingHeadline: (json['breakingHeadline'] as String?) ?? '',
      lowerTitle: (json['lowerTitle'] as String?) ?? '',
      lowerSubtitle: (json['lowerSubtitle'] as String?) ?? '',
      tickerText: (json['tickerText'] as String?) ?? '',
      showClock: (json['showClock'] as bool?) ?? true,
      logoPath: json['logoPath'] as String?,
      logoPosition: pos,
      logoRotate: (json['logoRotate'] as bool?) ?? false,
    );
  }

  static const _fileName = 'news_template.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Template persistence is a convenience; a failed save must never
      // block streaming or exporting with the in-memory template.
    }
  }

  static Future<NewsTemplate> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) return NewsTemplate.fromJson(data);
      }
    } catch (_) {}
    return NewsTemplate();
  }
}

/// Arabic-script range (Urdu, Arabic, Persian) — used to pick paragraph
/// direction so Urdu headlines shape correctly in the live image.
bool _hasArabic(String text) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(text);

/// Intrinsic width of one line of ticker text at [fontSize], bold.
/// Used to wrap the slide offset so the ticker loops seamlessly and to
/// lay the paragraph out at exactly its own width (otherwise an RTL
/// paragraph would right-align inside a wide box and slide wrong).
double _measureTickerWidth(String text, double fontSize) =>
    _measureTextWidth(text, fontSize);

/// Intrinsic width of one line of text at [fontSize], bold, in
/// [fontFamily] when given (Kasheeda for Urdu, null = system fallback).
double _measureTextWidth(
  String text,
  double fontSize, {
  String? fontFamily,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection:
          _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  builder.pushStyle(
    ui.TextStyle(
      fontSize: fontSize,
      fontWeight: ui.FontWeight.bold,
      fontFamily: fontFamily,
    ),
  );
  builder.addText(text);
  final para = builder.build();
  para.layout(const ui.ParagraphConstraints(width: 10000));
  return para.longestLine;
}

/// Renders the full news template into ONE transparent PNG sized
/// [width]x[height] (the stream's output size). The image is refreshed
/// while live: [tickerPx] slides the ticker leftwards and [now] drives
/// the clock; the logo rotates with the wall clock (one full turn in
/// 24s) when rotation is enabled. [tickerPx] may grow without bound —
/// the ticker wraps it into a seamless loop internally, so a long live
/// never ends up with an empty strip. [tickerAtStart] pins the ticker
/// text to the left margin instead of sliding it — the still frame
/// exports use it, so the ticker is visible in the exported video.
///
/// Returns the written file (overwritten on every call).
///
/// Phase 3 — Nigraan final 3-ribbon variant ([templateKind]
/// `'nigraanFinal'`): renders the final template from a [ChannelPreset]
/// instead of the live template — top ticker #01B0FF + red
/// "تازہ ترین" chip, middle Urdu #3D5AFE + black "بریکنگ نیوز" chip,
/// bottom English #EF0017 at half thickness + "HEADLINES" chip, logo
/// bug + time/date capsule, 10s intro marker. The existing live branch
/// below is UNTOUCHED (Live Studio depends on it); the variant is a
/// separate branch ([_renderNigraanFinalImage]) with its own output
/// file (`nigraan_final_template.png`).
///
/// [includeLogo] — DESIGN DECISION (Phase 3, recorded 20 Nov 2026):
/// the EXPORT path renders the template WITHOUT the logo
/// (`includeLogo: false`) because the logo is overlaid separately as a
/// rotating video loop in Phase 7 (see
/// ~/workspace/tj-pro-news-maker/rotation-decision.md — a static logo
/// baked into the PNG can never rotate, and the rotating loop is a
/// separate FFmpeg input). The PREVIEW path renders WITH the logo
/// (`includeLogo: true`, the default) via the rotating-logo widget.
/// The time/date capsule is NOT part of the logo: it stays in the PNG
/// in both paths (it is per-frame time/date, positioned in the logo
/// slot, so the Phase 7 overlay lands exactly on top of it).
///
/// [fontReady] — true once the Kasheeda font has been loaded in this
/// process via `AssetDownloadService.loadKasheedaFont()` (on-demand
/// download, see lib/services/asset_download_service.dart). When false
/// the renderer uses the system fallback font for Urdu and never
/// crashes — the Template & Studio screen exposes this state and
/// offers the download. The font family name comes from
/// [AssetDownloadService.kasheedaFamily] so renderer and loader agree.
///
/// [includeIntroMarker] — draws the small "INTRO • 10s" pill (only
/// when the preset's `showIntro` is on). Still/preview frames include
/// it; Phase 7 export frames pass false (the intro is a separate video
/// prepended at export, it must not be baked into every content frame).
///
/// Phase 6 — breaking + classic branches ([templateKind] `'breaking'`
/// / `'classic'`): the four breaking variants render through
/// [_renderBreakingImage] from a [BreakingTemplate] ([breakingTemplate]
/// — built by [BreakingTemplate.fromPreset] / `fromProject` when the
/// caller passes null) and the classic template through
/// [_renderClassicImage] from the [ChannelPreset]. Output files:
/// `breaking_template.png` / `classic_template.png` (never the live
/// or final overlay files). The live branch below is UNTOUCHED.
Future<File> renderLiveTemplateImage({
  required NewsTemplate template,
  required double tickerPx,
  required DateTime now,
  required Directory dir,
  int width = 720,
  int height = 1280,
  bool tickerAtStart = false,
  String templateKind = 'live',
  ChannelPreset? preset,
  BreakingTemplate? breakingTemplate,
  bool includeLogo = true,
  bool fontReady = false,
  bool includeIntroMarker = true,
}) async {
  if (templateKind == 'nigraanFinal') {
    return _renderNigraanFinalImage(
      preset: preset ?? ChannelPreset.nigraanTv(),
      tickerPx: tickerPx,
      now: now,
      dir: dir,
      width: width,
      height: height,
      tickerAtStart: tickerAtStart,
      includeLogo: includeLogo,
      fontReady: fontReady,
      includeIntroMarker: includeIntroMarker,
    );
  }
  if (templateKind == 'breaking') {
    final resolvedPreset = preset ?? ChannelPreset.nigraanTv();
    return _renderBreakingImage(
      template: breakingTemplate ??
          BreakingTemplate.fromPreset(resolvedPreset),
      preset: resolvedPreset,
      tickerPx: tickerPx,
      now: now,
      dir: dir,
      width: width,
      height: height,
      tickerAtStart: tickerAtStart,
      includeLogo: includeLogo,
      fontReady: fontReady,
      includeIntroMarker: includeIntroMarker,
    );
  }
  if (templateKind == 'classic') {
    return _renderClassicImage(
      preset: preset ?? ChannelPreset.nigraanTv(),
      tickerPx: tickerPx,
      now: now,
      dir: dir,
      width: width,
      height: height,
      tickerAtStart: tickerAtStart,
      includeLogo: includeLogo,
      fontReady: fontReady,
      includeIntroMarker: includeIntroMarker,
    );
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final w = width.toDouble();
  final h = height.toDouble();

  void drawText(
    String text,
    double x,
    double y,
    double fontSize, {
    ui.Color color = const ui.Color(0xFFFFFFFF),
    bool bold = true,
    ui.TextAlign align = ui.TextAlign.left,
    double maxWidth = 0,
    // Lay the paragraph out at exactly its own width. Needed for the
    // ticker: without it an RTL paragraph right-aligns inside a wide
    // box and slides with a large constant offset.
    double? exactWidth,
  }) {
    if (text.isEmpty) return;
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection:
            _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 2,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(
      ui.ParagraphConstraints(
        width: exactWidth ?? (maxWidth > 0 ? maxWidth : w),
      ),
    );
    canvas.drawParagraph(para, ui.Offset(x, y));
  }

  // Breaking banner (top red strip + headline).
  final headline = template.breakingHeadline.trim();
  if (headline.isNotEmpty) {
    final bh = h * 0.062;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, bh),
      ui.Paint()..color = const ui.Color(0xFFD50000),
    );
    drawText(
      'BREAKING: $headline',
      20,
      bh * 0.18,
      h * 0.028,
      maxWidth: w - 40,
    );
  }

  // Live clock (top-right, below the banner when the banner is on).
  if (template.showClock) {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final date =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    drawText(
      '$date  $hh:$mm:$ss  LIVE',
      w - 20,
      (headline.isNotEmpty ? h * 0.062 : 0) + 12,
      h * 0.020,
      color: const ui.Color(0xFFFFEB3B),
      align: ui.TextAlign.right,
      maxWidth: w - 40,
    );
  }

  // Lower-third (bottom-left box above the ticker strip).
  final title = template.lowerTitle.trim();
  final subtitle = template.lowerSubtitle.trim();
  if (title.isNotEmpty || subtitle.isNotEmpty) {
    final boxH = h * 0.115;
    final boxY = h - h * 0.20;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, boxY, w * 0.68, boxH),
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    if (title.isNotEmpty) {
      drawText(title, 20, boxY + boxH * 0.10, h * 0.024, maxWidth: w * 0.64);
    }
    if (subtitle.isNotEmpty) {
      drawText(
        subtitle,
        20,
        boxY + boxH * 0.55,
        h * 0.019,
        bold: false,
        maxWidth: w * 0.64,
      );
    }
  }

  // Ticker strip (bottom): the full text slides left, clipped to the
  // strip, so Urdu shaping stays intact (no substring windows).
  final ticker = template.tickerText.trim();
  if (ticker.isNotEmpty) {
    final stripH = h * 0.055;
    final stripY = h - stripH;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, stripY, w, stripH),
      ui.Paint()..color = const ui.Color(0xD9000000),
    );
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(0, stripY, w, stripH));
    // Seamless loop: wrap the slide offset at (text width + gap) and
    // draw a second copy, so the strip is never empty mid-cycle and
    // callers can advance tickerPx forever. tickerAtStart pins the
    // text to the left margin for still export frames.
    final textW = _measureTickerWidth(ticker, h * 0.022);
    final cycle = textW + 240;
    final wrapped = cycle > 0 ? tickerPx % cycle : tickerPx;
    final startX = tickerAtStart ? 20.0 : w - wrapped;
    final tickerY = stripY + stripH * 0.18;
    drawText(
      ticker,
      startX,
      tickerY,
      h * 0.022,
      maxWidth: w * 3,
      exactWidth: textW,
    );
    drawText(
      ticker,
      startX + cycle,
      tickerY,
      h * 0.022,
      maxWidth: w * 3,
      exactWidth: textW,
    );
    canvas.restore();
  }

  // Logo (corner, optional slow rotation).
  final logoPath = template.logoPath;
  if (logoPath != null) {
    try {
      final bytes = await File(logoPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final logo = frame.image;
      const size = 120.0;
      double x, y;
      switch (template.logoPosition) {
        case LogoPosition.topLeft:
          x = 20;
          y = headline.isNotEmpty ? h * 0.062 + 16 : 16;
          break;
        case LogoPosition.topRight:
          x = w - size - 20;
          y = headline.isNotEmpty ? h * 0.062 + 16 : 16;
          break;
        case LogoPosition.bottomLeft:
          x = 20;
          y = h - size - (ticker.isNotEmpty ? h * 0.055 : 0) - 20;
          break;
        case LogoPosition.bottomRight:
          x = w - size - 20;
          y = h - size - (ticker.isNotEmpty ? h * 0.055 : 0) - 20;
          break;
      }
      canvas.save();
      if (template.logoRotate) {
        // Angle is supplied by the caller through tickerPx-independent
        // state: reuse the clock so rotation advances once per second.
        final angle = (now.millisecondsSinceEpoch / 1000.0) * (3.14159265 / 12);
        canvas.translate(x + size / 2, y + size / 2);
        canvas.rotate(angle);
        canvas.translate(-size / 2, -size / 2);
        canvas.drawImageRect(
          logo,
          ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, size, size),
          ui.Paint(),
        );
      } else {
        canvas.drawImageRect(
          logo,
          ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          ui.Rect.fromLTWH(x, y, size, size),
          ui.Paint(),
        );
      }
      canvas.restore();
      logo.dispose();
    } catch (_) {
      // A bad logo file must never break the stream: skip it.
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'live_template.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

// ---------------------------------------------------------------------------
// Phase 3 — Nigraan final 3-ribbon template (templateKind 'nigraanFinal').
// ---------------------------------------------------------------------------

/// Pure layout geometry for the final 3-ribbon template.
///
/// Computed from the [ChannelPreset] (ribbon toggles, colours, sizes)
/// and the frame size, so the PNG renderer AND the unit tests share one
/// source of truth. Ribbons reflow bottom-up: the bottom English ribbon
/// always sits at the very bottom, the middle Urdu ribbon sits above
/// it, and the lower third sits above the lowest visible ribbon — a
/// disabled ribbon leaves no gap behind.
class NigraanFinalLayout {
  const NigraanFinalLayout({
    required this.width,
    required this.height,
    required this.tickerHeight,
    required this.englishHeight,
    required this.tickerStrip,
    required this.tickerChip,
    required this.urduStrip,
    required this.urduChip,
    required this.englishStrip,
    required this.englishChip,
    required this.lowerThird,
    required this.logoRect,
    required this.capsuleRect,
    required this.introMarker,
    required this.outroMarker,
    required this.categoryChip,
    required this.interviewPlate,
    required this.tickerTextSize,
    required this.urduTextSize,
    required this.englishTextSize,
  });

  /// Chip labels (broadcast package — never swapped between ribbons).
  static const String tickerChipText = 'تازہ ترین';
  static const String urduChipText = 'بریکنگ نیوز';
  static const String englishChipText = 'HEADLINES';
  static const String introMarkerText = 'INTRO • 10s';

  /// Outro marker label (Phase 6 — drawn next to the intro marker
  /// when the preset's outro is on).
  static const String outroMarkerText = 'OUTRO • 3s';

  /// Interview plate tag (Phase 6).
  static const String interviewTagText = 'INTERVIEW';

  final double width;
  final double height;

  /// Top ticker strip height; the bottom English ribbon is exactly
  /// half of it ("half-thickness").
  final double tickerHeight;
  final double englishHeight;

  /// Null when the ribbon is toggled off (renderer skips it).
  final ui.Rect? tickerStrip;
  final ui.Rect? tickerChip;
  final ui.Rect? urduStrip;

  /// Null when the ribbon is off OR the breaking banner is off — in
  /// the final template the breaking banner IS this chip.
  final ui.Rect? urduChip;
  final ui.Rect? englishStrip;
  final ui.Rect? englishChip;

  /// Null when the lower third is off or has no text.
  final ui.Rect? lowerThird;

  /// Logo-bug VISIBLE box (bottom-right, v1.3.0 parity geometry)
  /// and the time/date capsule directly under it, same width as
  /// the logo, zero gaps — the capsule's bottom edge sits on the
  /// Urdu ribbon's top edge.
  final ui.Rect logoRect;
  final ui.Rect capsuleRect;

  /// Null when the intro is off or [includeIntroMarker] is false.
  final ui.Rect? introMarker;

  /// Null when the outro is off or [includeIntroMarker] is false —
  /// sits right of the intro marker, same row.
  final ui.Rect? outroMarker;

  /// Null when the preset's category label is empty (Phase 6) —
  /// sits top-left below the ticker, above the intro marker.
  final ui.Rect? categoryChip;

  /// Null when the interview plate is off or has no name (Phase 6) —
  /// stacks above the lower third (or above the lowest ribbon when
  /// there is no lower third).
  final ui.Rect? interviewPlate;

  /// Clamped ribbon font sizes (see [ribbonFontSize]).
  final double tickerTextSize;
  final double urduTextSize;
  final double englishTextSize;

  /// Clamps a ribbon's configured font size so its ink can never poke
  /// out of its strip (Nastaleeq ink is ~1.33x the font size — §14
  /// rule 3: strip fonts stay ~0.52x the strip height).
  static double ribbonFontSize(RibbonConfig ribbon, double stripH) =>
      ribbon.fontSize.clamp(stripH * 0.30, stripH * 0.62).toDouble();

  static NigraanFinalLayout compute({
    required ChannelPreset preset,
    required double width,
    required double height,
    bool fontReady = false,
    bool includeIntroMarker = true,
  }) {
    String? kasheeda(String text) =>
        fontReady && _hasArabic(text)
            ? AssetDownloadService.kasheedaFamily
            : null;

    final tickerH = height * 0.055;
    // v1.3.0 (§9 Final-template parity): the bottom stack takes the
    // REAL reference geometry (see ParityGeometry in
    // parity_template.dart — the production house style v8): the
    // Urdu and English ribbons are EQUAL height (64/1920 of the
    // frame height portrait, 40/720 landscape) and FLUSH (zero
    // gap); the Urdu chip sits at the RIGHT at a fixed 240px
    // reference width, the English chip at the left (220/260px);
    // the logo's visible width is 185/1080 of the frame width and
    // the capsule (47/1920 / 39/720 high) sits directly under it,
    // its bottom edge ON the Urdu ribbon's top edge.
    final portraitFrame = height >= width;
    final ribbonH =
        portraitFrame ? height * (64 / 1920) : height * (40 / 720);
    final englishH = ribbonH;
    final urduH = ribbonH;
    final gap = height * 0.008;
    final refScale = width / (portraitFrame ? 1080 : 1280);

    ui.Rect? tickerStrip;
    ui.Rect? tickerChip;
    if (preset.topRibbon.enabled) {
      tickerStrip = ui.Rect.fromLTWH(0, 0, width, tickerH);
      final chipFont = tickerH * 0.45;
      final chipW = _measureTextWidth(
            tickerChipText,
            chipFont,
            fontFamily: kasheeda(tickerChipText),
          ) +
          28;
      tickerChip = ui.Rect.fromLTWH(0, 0, chipW, tickerH);
    }

    ui.Rect? englishStrip;
    ui.Rect? englishChip;
    if (preset.englishRibbon.enabled) {
      englishStrip = ui.Rect.fromLTWH(0, height - englishH, width, englishH);
      final chipW = width * (portraitFrame ? 220 / 1080 : 260 / 1280);
      englishChip = ui.Rect.fromLTWH(
        0,
        height - englishH,
        chipW,
        englishH,
      );
    }

    ui.Rect? urduStrip;
    ui.Rect? urduChip;
    if (preset.urduRibbon.enabled) {
      // Flush on the English ribbon (or the frame bottom) — the
      // reference stack has ZERO gap between the ribbons.
      final bottom =
          preset.englishRibbon.enabled ? height - englishH : height;
      urduStrip = ui.Rect.fromLTWH(0, bottom - urduH, width, urduH);
      // The breaking banner of the final template is this chip —
      // at the RIGHT end of the Urdu ribbon (reference), fixed
      // width, gold text (drawn by the renderer).
      if (preset.showBreakingBanner) {
        final chipW = width * (portraitFrame ? 240 / 1080 : 240 / 1280);
        urduChip = ui.Rect.fromLTWH(
          width - chipW,
          bottom - urduH,
          chipW,
          urduH,
        );
      }
    }

    ui.Rect? lowerThird;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    if (hasLowerThird) {
      final ltH = height * 0.10;
      var bottom = height;
      if (preset.urduRibbon.enabled) {
        bottom = urduStrip!.top - gap;
      } else if (preset.englishRibbon.enabled) {
        bottom = englishStrip!.top - gap;
      }
      lowerThird = ui.Rect.fromLTWH(0, bottom - ltH, width * 0.68, ltH);
    }

    // Logo + capsule stack, bottom-right (v1.3.0 parity): the
    // logo's VISIBLE box is 185/1080 of the frame width (aspect
    // 422:347, the alpha .mov's visible content); the capsule has
    // the same width and sits directly beneath it with zero gaps,
    // its bottom edge on the Urdu ribbon's top edge.
    final logoVisibleW = width * (185 / 1080);
    final logoVisibleH = 347 * logoVisibleW / 422;
    final capsuleH =
        portraitFrame ? height * (47 / 1920) : height * (39 / 720);
    final stackLeft = width - 24 * refScale - logoVisibleW;
    final ribbonsTop = urduStrip?.top ?? englishStrip?.top ?? height;
    final capsuleRect = ui.Rect.fromLTWH(
      stackLeft,
      ribbonsTop - capsuleH,
      logoVisibleW,
      capsuleH,
    );
    final logoRect = ui.Rect.fromLTWH(
      stackLeft,
      capsuleRect.top - logoVisibleH,
      logoVisibleW,
      logoVisibleH,
    );

    ui.Rect? introMarker;
    ui.Rect? outroMarker;
    ui.Rect? categoryChip;
    if (preset.categoryLabel.trim().isNotEmpty) {
      final chipH = height * 0.024;
      final chipW = _measureTextWidth(
            preset.categoryLabel.trim().toUpperCase(),
            height * 0.016,
          ) +
          24;
      categoryChip = ui.Rect.fromLTWH(
        16,
        (preset.topRibbon.enabled ? tickerH : 0) + 16,
        chipW,
        chipH,
      );
    }
    if (preset.showIntro && includeIntroMarker) {
      final markerFont = height * 0.016;
      final markerW =
          _measureTextWidth(introMarkerText, markerFont) + 28;
      final markerTop = (preset.topRibbon.enabled ? tickerH : 0.0) +
          16 +
          (categoryChip != null ? categoryChip.height + 8 : 0);
      introMarker = ui.Rect.fromLTWH(
        16,
        markerTop,
        markerW,
        height * 0.024,
      );
      if (preset.showOutro) {
        final outroW =
            _measureTextWidth(outroMarkerText, markerFont) + 28;
        outroMarker = ui.Rect.fromLTWH(
          introMarker.right + 8,
          markerTop,
          outroW,
          height * 0.024,
        );
      }
    }

    ui.Rect? interviewPlate;
    final hasInterviewPlate = preset.showInterviewPlate &&
        preset.interviewName.trim().isNotEmpty;
    if (hasInterviewPlate) {
      final plateH = height * 0.08;
      var bottom = height;
      if (lowerThird != null) {
        bottom = lowerThird.top - gap;
      } else if (preset.urduRibbon.enabled) {
        bottom = urduStrip!.top - gap;
      } else if (preset.englishRibbon.enabled) {
        bottom = englishStrip!.top - gap;
      }
      interviewPlate = ui.Rect.fromLTWH(
        0,
        bottom - plateH,
        width * 0.68,
        plateH,
      );
    }

    return NigraanFinalLayout(
      width: width,
      height: height,
      tickerHeight: tickerH,
      englishHeight: englishH,
      tickerStrip: tickerStrip,
      tickerChip: tickerChip,
      urduStrip: urduStrip,
      urduChip: urduChip,
      englishStrip: englishStrip,
      englishChip: englishChip,
      lowerThird: lowerThird,
      logoRect: logoRect,
      capsuleRect: capsuleRect,
      introMarker: introMarker,
      outroMarker: outroMarker,
      categoryChip: categoryChip,
      interviewPlate: interviewPlate,
      tickerTextSize: preset.topRibbon.enabled
          ? ribbonFontSize(preset.topRibbon, tickerH)
          : 0,
      // Reference text sizes (§9.7): Urdu 0.5625 x ribbon height,
      // English 0.53 x — fixed fractions, not the preset's clamped
      // font size, so the parity preset always matches the real
      // videos.
      urduTextSize: preset.urduRibbon.enabled ? urduH * (36 / 64) : 0,
      englishTextSize:
          preset.englishRibbon.enabled ? englishH * (34 / 64) : 0,
    );
  }
}

/// Renders the Nigraan final 3-ribbon template into ONE transparent PNG
/// sized [width]x[height] (see [renderLiveTemplateImage] for the
/// [includeLogo] / [fontReady] / [includeIntroMarker] contract).
/// Only the TOP ticker scrolls with [tickerPx]; the middle/bottom
/// ribbons are headline strips pinned at their start (per-ribbon scroll
/// phases are a Phase 7 export-animation item). Writes
/// `nigraan_final_template.png` (never the live overlay file).
Future<File> _renderNigraanFinalImage({
  required ChannelPreset preset,
  required double tickerPx,
  required DateTime now,
  required Directory dir,
  int width = 720,
  int height = 1280,
  bool tickerAtStart = false,
  bool includeLogo = true,
  bool fontReady = false,
  bool includeIntroMarker = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final w = width.toDouble();
  final h = height.toDouble();
  const white = ui.Color(0xFFFFFFFF);
  // v1.3.0 parity: reference scale (1080 portrait / 1280
  // landscape) for the gold edges and dividers.
  final refScaleR = w / (h >= w ? 1080 : 1280);

  final layout = NigraanFinalLayout.compute(
    preset: preset,
    width: w,
    height: h,
    fontReady: fontReady,
    includeIntroMarker: includeIntroMarker,
  );

  String? kasheeda(String text) =>
      fontReady && _hasArabic(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  /// One-line paragraph, built once and drawn at [x]/[y].
  ui.Paragraph buildLine(
    String text,
    double fontSize, {
    ui.Color color = white,
    bool bold = true,
    String? fontFamily,
    double? exactWidth,
    double maxWidth = 0,
    String? ellipsis,
    ui.TextAlign align = ui.TextAlign.left,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection:
            _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: ellipsis,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontFamily: fontFamily,
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(
      ui.ParagraphConstraints(
        width: exactWidth ?? (maxWidth > 0 ? maxWidth : w),
      ),
    );
    return para;
  }

  /// Draws [text] centred in [rect] (by real paragraph height, nudged
  /// down a touch for Urdu — §14 rule 3).
  void drawCentred(
    String text,
    ui.Rect rect,
    double fontSize, {
    ui.Color color = white,
    String? fontFamily,
    bool bold = true,
  }) {
    if (text.isEmpty) return;
    final para = buildLine(
      text,
      fontSize,
      color: color,
      fontFamily: fontFamily,
      maxWidth: rect.width,
      align: ui.TextAlign.center,
      bold: bold,
    );
    canvas.drawParagraph(
      para,
      ui.Offset(
        rect.left,
        rect.top +
            (rect.height - para.height) / 2 +
            (_hasArabic(text) ? rect.height * 0.06 : 0),
      ),
    );
  }

  // --- Top ticker (scrolling, #01B0FF default) + red chip. ---
  final tickerStrip = layout.tickerStrip;
  if (tickerStrip != null) {
    canvas.drawRect(
      tickerStrip,
      ui.Paint()..color = ui.Color(preset.topRibbon.color),
    );
    final chip = layout.tickerChip!;
    canvas.drawRect(
      chip,
      ui.Paint()..color = const ui.Color(0xFFD50000),
    );
    drawCentred(
      NigraanFinalLayout.tickerChipText,
      chip,
      layout.tickerHeight * 0.45,
      fontFamily: kasheeda(NigraanFinalLayout.tickerChipText),
    );
    final ticker = preset.topRibbon.text.trim();
    if (ticker.isNotEmpty) {
      final fontSize = layout.tickerTextSize;
      final family = kasheeda(ticker);
      final textW = _measureTextWidth(ticker, fontSize, fontFamily: family);
      final cycle = textW + 240;
      final wrapped = cycle > 0 ? tickerPx % cycle : tickerPx;
      final double startX;
      if (tickerAtStart) {
        startX = chip.right + 16;
      } else if (preset.topRibbon.direction == RibbonDirection.ltr) {
        startX = chip.right - cycle + wrapped;
      } else {
        startX = w - wrapped;
      }
      final para = buildLine(
        ticker,
        fontSize,
        fontFamily: family,
        exactWidth: textW,
      );
      final y = tickerStrip.top +
          (tickerStrip.height - para.height) / 2 +
          (_hasArabic(ticker) ? tickerStrip.height * 0.06 : 0);
      canvas.save();
      canvas.clipRect(
        ui.Rect.fromLTWH(
          chip.right,
          tickerStrip.top,
          w - chip.right,
          tickerStrip.height,
        ),
      );
      canvas.drawParagraph(para, ui.Offset(startX, y));
      canvas.drawParagraph(para, ui.Offset(startX + cycle, y));
      canvas.restore();
    }
  }

  // --- Middle Urdu ribbon (#3D5AFE default) + black chip.
  // v1.3.0 parity: 3px gold top edge; the chip sits at the RIGHT
  // with GOLD text + a gold inner divider; the pinned text
  // occupies the strip LEFT of the chip.
  final urduStrip = layout.urduStrip;
  if (urduStrip != null) {
    canvas.drawRect(
      urduStrip,
      ui.Paint()..color = ui.Color(preset.urduRibbon.color),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(urduStrip.left, urduStrip.top, w, 3 * refScaleR),
      ui.Paint()..color = const ui.Color(0xFFF5C542),
    );
    final chip = layout.urduChip;
    ui.Rect textStrip = urduStrip;
    if (chip != null) {
      canvas.drawRect(
        chip,
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      drawCentred(
        NigraanFinalLayout.urduChipText,
        chip,
        urduStrip.height * 0.45,
        color: const ui.Color(0xFFF5C542),
        fontFamily: kasheeda(NigraanFinalLayout.urduChipText),
      );
      canvas.drawRect(
        ui.Rect.fromLTWH(chip.left, chip.top, 2 * refScaleR, chip.height),
        ui.Paint()..color = const ui.Color(0xFFF5C542),
      );
      textStrip = ui.Rect.fromLTWH(
          urduStrip.left, urduStrip.top, chip.left, urduStrip.height);
    }
    final text = preset.urduRibbon.text.trim();
    if (text.isNotEmpty) {
      _drawStripText(
        canvas: canvas,
        text: text,
        strip: textStrip,
        textLeft: 12,
        fontSize: layout.urduTextSize,
        fontFamily: kasheeda(text),
        buildLine: buildLine,
      );
    }
  }

  // --- Bottom English ribbon (#EF0017) + chip. v1.3.0 parity:
  // equal height with the Urdu ribbon, 3px gold top edge, chip at
  // the left with GOLD text + a gold inner divider.
  final englishStrip = layout.englishStrip;
  if (englishStrip != null) {
    canvas.drawRect(
      englishStrip,
      ui.Paint()..color = ui.Color(preset.englishRibbon.color),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(
          englishStrip.left, englishStrip.top, w, 3 * refScaleR),
      ui.Paint()..color = const ui.Color(0xFFF5C542),
    );
    final chip = layout.englishChip!;
    canvas.drawRect(
      chip,
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    drawCentred(
      NigraanFinalLayout.englishChipText,
      chip,
      englishStrip.height * 0.55,
      color: const ui.Color(0xFFF5C542),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(
          chip.right - 2 * refScaleR, chip.top, 2 * refScaleR, chip.height),
      ui.Paint()..color = const ui.Color(0xFFF5C542),
    );
    final text = preset.englishRibbon.text.trim();
    if (text.isNotEmpty) {
      _drawStripText(
        canvas: canvas,
        text: text,
        strip: englishStrip,
        textLeft: chip.right + 12,
        fontSize: layout.englishTextSize,
        fontFamily: null,
        buildLine: buildLine,
      );
    }
  }

  // --- Lower third (reporter name + place), above the ribbons. ---
  final lowerThird = layout.lowerThird;
  if (lowerThird != null) {
    canvas.drawRect(
      lowerThird,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final title = preset.lowerThirdTitle.trim();
    final subtitle = preset.lowerThirdSubtitle.trim();
    if (title.isNotEmpty) {
      final para = buildLine(title, h * 0.024, maxWidth: w * 0.64);
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.10),
      );
    }
    if (subtitle.isNotEmpty) {
      final para = buildLine(
        subtitle,
        h * 0.019,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.55),
      );
    }
  }

  // --- Interview name plate (Phase 6) — above the lower third. ---
  final interviewPlate = layout.interviewPlate;
  if (interviewPlate != null) {
    canvas.drawRect(
      interviewPlate,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final tagFont = interviewPlate.height * 0.22;
    final tagW = _measureTextWidth(
          NigraanFinalLayout.interviewTagText,
          tagFont,
        ) +
        16;
    final tagRect = ui.Rect.fromLTWH(
      interviewPlate.left,
      interviewPlate.top,
      tagW,
      interviewPlate.height * 0.30,
    );
    canvas.drawRect(
      tagRect,
      ui.Paint()..color = const ui.Color(0xFFD50000),
    );
    drawCentred(
      NigraanFinalLayout.interviewTagText,
      tagRect,
      tagFont,
    );
    final name = preset.interviewName.trim();
    final designation = preset.interviewDesignation.trim();
    final namePara = buildLine(name, h * 0.022, maxWidth: w * 0.64);
    canvas.drawParagraph(
      namePara,
      ui.Offset(
        interviewPlate.left + 16,
        interviewPlate.top + tagRect.height + 4,
      ),
    );
    if (designation.isNotEmpty) {
      final desPara = buildLine(
        designation,
        h * 0.017,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        desPara,
        ui.Offset(
          interviewPlate.left + 16,
          interviewPlate.top + interviewPlate.height * 0.62,
        ),
      );
    }
  }

  // --- Logo bug (top-right) — skipped when includeLogo is false
  // (Phase 7 overlays the rotating loop separately). A missing logo
  // file falls back to the channel's initial-letter tile (§14 rule 7),
  // never a blank slot and never a static circular image.
  if (includeLogo) {
    final logoRect = layout.logoRect;
    var drewImage = false;
    final logoPath = preset.logoPath;
    if (logoPath != null) {
      try {
        final bytes = await File(logoPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final logo = frame.image;
        canvas.drawImageRect(
          logo,
          ui.Rect.fromLTWH(
            0,
            0,
            logo.width.toDouble(),
            logo.height.toDouble(),
          ),
          logoRect,
          ui.Paint(),
        );
        logo.dispose();
        drewImage = true;
      } catch (_) {
        // Bad logo file: fall through to the initial tile below.
      }
    }
    if (!drewImage) {
      final initial = preset.name.trim().isEmpty
          ? 'N'
          : preset.name.trim()[0].toUpperCase();
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(logoRect, const ui.Radius.circular(12)),
        ui.Paint()..color = const ui.Color(0xFF7C3AED),
      );
      drawCentred(initial, logoRect, logoRect.width * 0.45);
    }
  }

  // --- Time/date capsule under the logo, same width as the logo.
  // Always drawn (it is per-frame time/date in the logo slot, not
  // part of the logo — see the includeLogo note on
  // [renderLiveTemplateImage]). v1.3.0 parity: black at 67%
  // alpha, radius 8, 4px gold top line, and this still shows the
  // TIME face (hh:mm:ss AM/PM) — the export flips to the Urdu
  // date face every 3s (parity_template.dart).
  final capsule = layout.capsuleRect;
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final ampm = now.hour < 12 ? 'AM' : 'PM';
  final capsuleText =
      '${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $ampm';
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
        capsule, ui.Radius.circular(8 * refScaleR)),
    ui.Paint()..color = const ui.Color(0xAA000000),
  );
  canvas.save();
  canvas.clipRRect(ui.RRect.fromRectAndRadius(
      capsule, ui.Radius.circular(8 * refScaleR)));
  canvas.drawRect(
    ui.Rect.fromLTWH(capsule.left, capsule.top, capsule.width, 4 * refScaleR),
    ui.Paint()..color = const ui.Color(0xFFF5C542),
  );
  canvas.restore();
  drawCentred(capsuleText, capsule, capsule.height * 0.55, bold: false);

  // --- 10s intro marker (top-left pill; still/preview frames only). ---
  final introMarker = layout.introMarker;
  if (introMarker != null) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        introMarker,
        ui.Radius.circular(introMarker.height / 2),
      ),
      ui.Paint()..color = const ui.Color(0xCC000000),
    );
    drawCentred(
      NigraanFinalLayout.introMarkerText,
      introMarker,
      introMarker.height * 0.55,
      bold: false,
    );
  }

  // --- Outro marker (Phase 6) — right of the intro marker. ---
  final outroMarker = layout.outroMarker;
  if (outroMarker != null) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        outroMarker,
        ui.Radius.circular(outroMarker.height / 2),
      ),
      ui.Paint()..color = const ui.Color(0xCC000000),
    );
    drawCentred(
      NigraanFinalLayout.outroMarkerText,
      outroMarker,
      outroMarker.height * 0.55,
      bold: false,
    );
  }

  // --- Category label chip (Phase 6) — top-left below the ticker. ---
  final categoryChip = layout.categoryChip;
  if (categoryChip != null) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        categoryChip,
        ui.Radius.circular(categoryChip.height / 2),
      ),
      ui.Paint()..color = const ui.Color(0xCC000000),
    );
    drawCentred(
      preset.categoryLabel.trim().toUpperCase(),
      categoryChip,
      categoryChip.height * 0.55,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'nigraan_final_template.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Draws a pinned headline-strip line: right-aligned for RTL text,
/// left-aligned after the chip for LTR; over-long text gets a '…'
/// (the strip is clipped, so nothing can poke out of it).
void _drawStripText({
  required ui.Canvas canvas,
  required String text,
  required ui.Rect strip,
  required double textLeft,
  required double fontSize,
  required String? fontFamily,
  required ui.Paragraph Function(
    String text,
    double fontSize, {
    ui.Color color,
    bool bold,
    String? fontFamily,
    double? exactWidth,
    double maxWidth,
    String? ellipsis,
    ui.TextAlign align,
  }) buildLine,
}) {
  final availW = strip.right - textLeft - 12;
  if (availW <= 0) return;
  final isRtl = _hasArabic(text);
  final textW = _measureTextWidth(text, fontSize, fontFamily: fontFamily);
  ui.Paragraph para;
  double x;
  if (textW <= availW) {
    para = buildLine(text, fontSize, fontFamily: fontFamily, exactWidth: textW);
    x = isRtl ? strip.right - 12 - textW : textLeft;
  } else {
    para = buildLine(
      text,
      fontSize,
      fontFamily: fontFamily,
      maxWidth: availW,
      ellipsis: '…',
    );
    x = textLeft;
  }
  final y = strip.top +
      (strip.height - para.height) / 2 +
      (isRtl ? strip.height * 0.06 : 0);
  canvas.save();
  canvas.clipRect(strip);
  canvas.drawParagraph(para, ui.Offset(x, y));
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Phase 6 — breaking templates + classic template.
// ---------------------------------------------------------------------------

/// Text colour for a coloured strip: white, unless the strip is light
/// (white ticker strip on Latest News) — then near-black. Used by the
/// breaking + classic renderers so an edited swatch can never make
/// its own text unreadable (Broadcast Professional Standard §14
/// rule 1: bold, glanceable, highest contrast).
ui.Color _stripTextColor(int bgColor) =>
    ui.Color(bgColor).computeLuminance() > 0.6
        ? const ui.Color(0xFF1A1A1A)
        : const ui.Color(0xFFFFFFFF);

/// Draws a rounded dark pill with centred one-line [text] (category
/// chips, intro/outro markers). Latin text only — no font family.
void _drawPill(
  ui.Canvas canvas,
  ui.Rect rect,
  String text,
  double fontSize, {
  ui.Color bgColor = const ui.Color(0xCC000000),
  ui.Color textColor = const ui.Color(0xFFFFFFFF),
  bool bold = true,
}) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      rect,
      ui.Radius.circular(rect.height / 2),
    ),
    ui.Paint()..color = bgColor,
  );
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  builder.pushStyle(
    ui.TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
    ),
  );
  builder.addText(text);
  final para = builder.build();
  para.layout(ui.ParagraphConstraints(width: rect.width));
  canvas.drawParagraph(
    para,
    ui.Offset(rect.left, rect.top + (rect.height - para.height) / 2),
  );
}

/// Draws the logo bug into [rect]: the picked logo file when it
/// reads, otherwise the channel's initial-letter tile (§14 rule 7 —
/// never a blank slot, never a static circular image). Shared by the
/// breaking + classic renderers (the final renderer has its own copy
/// — Phase 3, left untouched).
Future<void> _drawLogoBug({
  required ui.Canvas canvas,
  required String? logoPath,
  required String initial,
  required ui.Rect rect,
}) async {
  var drewImage = false;
  if (logoPath != null) {
    try {
      final bytes = await File(logoPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final logo = frame.image;
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(
          0,
          0,
          logo.width.toDouble(),
          logo.height.toDouble(),
        ),
        rect,
        ui.Paint(),
      );
      logo.dispose();
      drewImage = true;
    } catch (_) {
      // Bad logo file: fall through to the initial tile below.
    }
  }
  if (!drewImage) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(12)),
      ui.Paint()..color = const ui.Color(0xFF7C3AED),
    );
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: rect.width * 0.45,
        fontWeight: ui.FontWeight.bold,
      ),
    );
    builder.addText(initial);
    final para = builder.build();
    para.layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(
      para,
      ui.Offset(rect.left, rect.top + (rect.height - para.height) / 2),
    );
  }
}

/// Draws the flipping time/date capsule (same text as the LogoBug
/// widget's capsule): `HH:MM AM  DD-MM-YYYY`, same width as the logo.
/// Shared by the breaking + classic renderers.
void _drawTimeDateCapsule({
  required ui.Canvas canvas,
  required ui.Rect rect,
  required DateTime now,
}) {
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final ampm = now.hour < 12 ? 'AM' : 'PM';
  final text =
      '${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm  '
      '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(6)),
    ui.Paint()..color = const ui.Color(0xCC000000),
  );
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  builder.pushStyle(
    ui.TextStyle(
      color: const ui.Color(0xFFFFFFFF),
      fontSize: rect.height * 0.52,
    ),
  );
  builder.addText(text);
  final para = builder.build();
  para.layout(ui.ParagraphConstraints(width: rect.width));
  canvas.drawParagraph(
    para,
    ui.Offset(rect.left, rect.top + (rect.height - para.height) / 2),
  );
}

/// Pure layout geometry for one breaking-news template variant.
///
/// Same contract as [NigraanFinalLayout]: the PNG renderer AND the
/// unit tests share this one source of truth. 24px side margins
/// (§14 rule 6); the bottom ticker / ribbons reflow bottom-up so a
/// disabled ribbon leaves no gap behind.
///
/// Colour roles per variant (see [BreakingTemplate.topColor]):
///   breakingRedBanner — banner = topColor (red), ticker strip =
///     bottomColor (black by default).
///   latestNews — top bar = topColor (blue), ticker strip =
///     bottomColor (white by default, dark text).
///   topHeadlineBar — headline bar = topColor (white, dark text),
///     ticker strip = bottomColor (blue).
///   breakingTickerCombo — banner = topColor (red), top ticker strip
///     = tickerColor (house blue), middle = middleColor, bottom =
///     bottomColor (half-thickness). The combo is the only variant
///     with the full 3-ribbon set, so the RIBBON-CONTENT RULE applies
///     to it exactly as to the final template.
class BreakingLayout {
  const BreakingLayout({
    required this.width,
    required this.height,
    required this.bannerHeight,
    required this.tickerHeight,
    required this.englishHeight,
    required this.bannerRect,
    required this.bannerChipRect,
    required this.headlineRect,
    required this.tickerStrip,
    required this.topTickerStrip,
    required this.topTickerChip,
    required this.middleStrip,
    required this.middleChip,
    required this.bottomStrip,
    required this.bottomChip,
    required this.lowerThird,
    required this.logoRect,
    required this.capsuleRect,
    required this.introMarker,
    required this.outroMarker,
    required this.categoryChip,
    required this.interviewPlate,
    required this.headlineSize,
    required this.chipSize,
    required this.tickerTextSize,
    required this.middleTextSize,
    required this.englishTextSize,
  });

  static const String breakingChipText = 'BREAKING NEWS';
  static const String latestChipText = 'LATEST NEWS';

  final double width;
  final double height;

  final double bannerHeight;
  final double tickerHeight;
  final double englishHeight;

  /// Full-width banner / top bar at the very top (all variants).
  final ui.Rect bannerRect;

  /// Chip inside the banner ("BREAKING NEWS" / "LATEST NEWS") —
  /// null for Top Headline Bar (no chip, headline only).
  final ui.Rect? bannerChipRect;

  /// Headline text area inside the banner / bar.
  final ui.Rect headlineRect;

  /// Single-variant bottom scrolling ticker strip — null for the
  /// combo (it has [topTickerStrip] instead) and null when the
  /// ticker is toggled off.
  final ui.Rect? tickerStrip;

  /// Combo only: the top ticker strip below the banner + its red
  /// "تازہ ترین" chip. Null for the other variants / when off.
  final ui.Rect? topTickerStrip;
  final ui.Rect? topTickerChip;

  /// Combo only: middle Urdu ribbon + black "بریکنگ نیوز" chip.
  final ui.Rect? middleStrip;
  final ui.Rect? middleChip;

  /// Combo only: bottom English ribbon (half-thickness) + "HEADLINES"
  /// chip.
  final ui.Rect? bottomStrip;
  final ui.Rect? bottomChip;

  /// Null when the lower third is off or has no text.
  final ui.Rect? lowerThird;

  /// Logo-bug slot (top-right, below the top elements) and the
  /// time/date capsule directly under it, same width as the logo.
  final ui.Rect logoRect;
  final ui.Rect capsuleRect;

  /// Null when intro/outro is off or [includeIntroMarker] is false.
  final ui.Rect? introMarker;
  final ui.Rect? outroMarker;

  /// Null when the template's category label is empty.
  final ui.Rect? categoryChip;

  /// Null when the interview plate is off or has no name.
  final ui.Rect? interviewPlate;

  final double headlineSize;
  final double chipSize;
  final double tickerTextSize;
  final double middleTextSize;
  final double englishTextSize;

  /// Same clamp as [NigraanFinalLayout.ribbonFontSize] (§14 rule 3:
  /// strip fonts stay ~0.52× the strip height so Nastaleeq ink can
  /// never poke out of its strip).
  static double clampFontSize(double size, double stripH) =>
      size.clamp(stripH * 0.30, stripH * 0.62).toDouble();

  static BreakingLayout compute({
    required BreakingTemplate template,
    required double width,
    required double height,
    bool fontReady = false,
    bool includeIntroMarker = true,
  }) {
    String? kasheeda(String text) =>
        fontReady && _hasArabic(text)
            ? AssetDownloadService.kasheedaFamily
            : null;

    const margin = 24.0;
    final gap = height * 0.008;
    final tickerH = height * 0.055;
    final englishH = tickerH / 2;
    final urduH = tickerH;
    final logoSize = width * 0.153;
    final capsuleH = height * 0.022;

    final double bannerH;
    switch (template.variant) {
      case BreakingVariant.breakingRedBanner:
        bannerH = height * 0.10;
      case BreakingVariant.latestNews:
      case BreakingVariant.topHeadlineBar:
        bannerH = height * 0.08;
      case BreakingVariant.breakingTickerCombo:
        bannerH = height * 0.062;
    }
    final isCombo = template.variant == BreakingVariant.breakingTickerCombo;
    final bannerRect = ui.Rect.fromLTWH(0, 0, width, bannerH);

    ui.Rect? bannerChipRect;
    ui.Rect headlineRect;
    final String? chipText;
    switch (template.variant) {
      case BreakingVariant.breakingRedBanner:
      case BreakingVariant.breakingTickerCombo:
        chipText = breakingChipText;
      case BreakingVariant.latestNews:
        chipText = latestChipText;
      case BreakingVariant.topHeadlineBar:
        chipText = null;
    }
    if (chipText != null) {
      final chipFont = bannerH * 0.30;
      final chipW = _measureTextWidth(chipText, chipFont) + 28;
      bannerChipRect = ui.Rect.fromLTWH(
        margin,
        bannerH * 0.20,
        chipW,
        bannerH * 0.60,
      );
      headlineRect = ui.Rect.fromLTWH(
        bannerChipRect.right + 16,
        0,
        width - margin - (bannerChipRect.right + 16),
        bannerH,
      );
    } else {
      headlineRect = ui.Rect.fromLTWH(margin, 0, width - margin * 2, bannerH);
    }

    ui.Rect? tickerStrip;
    ui.Rect? topTickerStrip;
    ui.Rect? topTickerChip;
    ui.Rect? middleStrip;
    ui.Rect? middleChip;
    ui.Rect? bottomStrip;
    ui.Rect? bottomChip;
    if (template.showRibbons) {
      if (isCombo) {
        if (template.showTop) {
          topTickerStrip =
              ui.Rect.fromLTWH(0, bannerH, width, tickerH);
          final chipFont = tickerH * 0.45;
          final chipW = _measureTextWidth(
                NigraanFinalLayout.tickerChipText,
                chipFont,
                fontFamily: kasheeda(NigraanFinalLayout.tickerChipText),
              ) +
              28;
          topTickerChip = ui.Rect.fromLTWH(0, bannerH, chipW, tickerH);
        }
        if (template.showBottom) {
          bottomStrip =
              ui.Rect.fromLTWH(0, height - englishH, width, englishH);
          final chipFont = englishH * 0.55;
          final chipW =
              _measureTextWidth(NigraanFinalLayout.englishChipText, chipFont) +
              28;
          bottomChip = ui.Rect.fromLTWH(0, height - englishH, chipW, englishH);
        }
        if (template.showMiddle) {
          final bottom = template.showBottom
              ? height - englishH - gap
              : height;
          middleStrip = ui.Rect.fromLTWH(0, bottom - urduH, width, urduH);
          final chipFont = urduH * 0.45;
          final chipW = _measureTextWidth(
                NigraanFinalLayout.urduChipText,
                chipFont,
                fontFamily: kasheeda(NigraanFinalLayout.urduChipText),
              ) +
              28;
          middleChip = ui.Rect.fromLTWH(0, bottom - urduH, chipW, urduH);
        }
      } else {
        tickerStrip = ui.Rect.fromLTWH(0, height - tickerH, width, tickerH);
      }
    }

    // Top edge below the banner (combo: below the top ticker strip).
    final topBelow = isCombo ? bannerH + tickerH : bannerH;

    ui.Rect? categoryChip;
    if (template.categoryLabel.trim().isNotEmpty) {
      final chipH = height * 0.024;
      final chipW = _measureTextWidth(
            template.categoryLabel.trim().toUpperCase(),
            height * 0.016,
          ) +
          24;
      categoryChip = ui.Rect.fromLTWH(margin, topBelow + 16, chipW, chipH);
    }

    ui.Rect? introMarker;
    ui.Rect? outroMarker;
    if (template.showIntro && includeIntroMarker) {
      final markerFont = height * 0.016;
      final markerW =
          _measureTextWidth(NigraanFinalLayout.introMarkerText, markerFont) +
          28;
      final markerTop = topBelow +
          16 +
          (categoryChip != null ? categoryChip.height + 8 : 0);
      introMarker = ui.Rect.fromLTWH(
        margin,
        markerTop,
        markerW,
        height * 0.024,
      );
      if (template.showOutro) {
        final outroW =
            _measureTextWidth(NigraanFinalLayout.outroMarkerText, markerFont) +
            28;
        outroMarker = ui.Rect.fromLTWH(
          introMarker.right + 8,
          markerTop,
          outroW,
          height * 0.024,
        );
      }
    }

    final logoRect = ui.Rect.fromLTWH(
      width - margin - logoSize,
      topBelow + 16,
      logoSize,
      logoSize,
    );
    final capsuleRect = ui.Rect.fromLTWH(
      logoRect.left,
      logoRect.bottom + 6,
      logoSize,
      capsuleH,
    );

    ui.Rect? lowerThird;
    final hasLowerThird = template.showLowerThird &&
        (template.lowerThirdTitle.trim().isNotEmpty ||
            template.lowerThirdSubtitle.trim().isNotEmpty);
    if (hasLowerThird) {
      final ltH = height * 0.10;
      var bottom = height;
      if (isCombo) {
        if (bottomStrip != null) {
          bottom = bottomStrip.top - gap;
        } else if (middleStrip != null) {
          bottom = middleStrip.top - gap;
        }
      } else if (tickerStrip != null) {
        bottom = tickerStrip.top - gap;
      }
      lowerThird = ui.Rect.fromLTWH(0, bottom - ltH, width * 0.68, ltH);
    }

    ui.Rect? interviewPlate;
    final hasInterviewPlate = template.showInterviewPlate &&
        template.interviewName.trim().isNotEmpty;
    if (hasInterviewPlate) {
      final plateH = height * 0.08;
      var bottom = height;
      if (lowerThird != null) {
        bottom = lowerThird.top - gap;
      } else if (isCombo) {
        if (bottomStrip != null) {
          bottom = bottomStrip.top - gap;
        } else if (middleStrip != null) {
          bottom = middleStrip.top - gap;
        }
      } else if (tickerStrip != null) {
        bottom = tickerStrip.top - gap;
      }
      interviewPlate = ui.Rect.fromLTWH(
        0,
        bottom - plateH,
        width * 0.68,
        plateH,
      );
    }

    return BreakingLayout(
      width: width,
      height: height,
      bannerHeight: bannerH,
      tickerHeight: tickerH,
      englishHeight: englishH,
      bannerRect: bannerRect,
      bannerChipRect: bannerChipRect,
      headlineRect: headlineRect,
      tickerStrip: tickerStrip,
      topTickerStrip: topTickerStrip,
      topTickerChip: topTickerChip,
      middleStrip: middleStrip,
      middleChip: middleChip,
      bottomStrip: bottomStrip,
      bottomChip: bottomChip,
      lowerThird: lowerThird,
      logoRect: logoRect,
      capsuleRect: capsuleRect,
      introMarker: introMarker,
      outroMarker: outroMarker,
      categoryChip: categoryChip,
      interviewPlate: interviewPlate,
      headlineSize: (bannerH * 0.30).clamp(10.0, 44.0).toDouble(),
      chipSize: bannerH * 0.28,
      tickerTextSize: clampFontSize(template.fontSize, tickerH),
      middleTextSize: clampFontSize(template.fontSize, urduH),
      englishTextSize: clampFontSize(template.fontSize, englishH),
    );
  }
}

/// Renders one breaking-news template variant into ONE transparent
/// PNG sized [width]x[height]. Only the scrolling ticker strip moves
/// with [tickerPx]; the combo's middle/bottom ribbons are headline
/// strips pinned at their start (same as the final template).
/// Writes `breaking_template.png` (never the live/final overlay).
Future<File> _renderBreakingImage({
  required BreakingTemplate template,
  required ChannelPreset preset,
  required double tickerPx,
  required DateTime now,
  required Directory dir,
  int width = 720,
  int height = 1280,
  bool tickerAtStart = false,
  bool includeLogo = true,
  bool fontReady = false,
  bool includeIntroMarker = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final w = width.toDouble();
  final h = height.toDouble();
  const white = ui.Color(0xFFFFFFFF);

  final layout = BreakingLayout.compute(
    template: template,
    width: w,
    height: h,
    fontReady: fontReady,
    includeIntroMarker: includeIntroMarker,
  );

  String? kasheeda(String text) =>
      fontReady && _hasArabic(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  ui.Paragraph buildLine(
    String text,
    double fontSize, {
    ui.Color color = white,
    bool bold = true,
    String? fontFamily,
    double? exactWidth,
    double maxWidth = 0,
    String? ellipsis,
    ui.TextAlign align = ui.TextAlign.left,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection:
            _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: ellipsis,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontFamily: fontFamily,
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(
      ui.ParagraphConstraints(
        width: exactWidth ?? (maxWidth > 0 ? maxWidth : w),
      ),
    );
    return para;
  }

  /// Draws [text] centred in [rect] (by real paragraph height, nudged
  /// down a touch for Urdu — §14 rule 3).
  void drawCentred(
    String text,
    ui.Rect rect,
    double fontSize, {
    ui.Color color = white,
    String? fontFamily,
    bool bold = true,
  }) {
    if (text.isEmpty) return;
    final para = buildLine(
      text,
      fontSize,
      color: color,
      fontFamily: fontFamily,
      maxWidth: rect.width,
      align: ui.TextAlign.center,
      bold: bold,
    );
    canvas.drawParagraph(
      para,
      ui.Offset(
        rect.left,
        rect.top +
            (rect.height - para.height) / 2 +
            (_hasArabic(text) ? rect.height * 0.06 : 0),
      ),
    );
  }

  /// Draws the scrolling ticker inside [strip], clipped to the strip
  /// past the [chipRight] edge. Only the ticker scrolls with
  /// [tickerPx]; [direction] is the template's own direction.
  void drawScrollingTicker({
    required ui.Rect strip,
    required double chipRight,
    required String text,
    required double fontSize,
    required ui.Color textColor,
    required RibbonDirection direction,
  }) {
    if (text.isEmpty) return;
    final family = kasheeda(text);
    final textW = _measureTextWidth(text, fontSize, fontFamily: family);
    final cycle = textW + 240;
    final wrapped = cycle > 0 ? tickerPx % cycle : tickerPx;
    final double startX;
    if (tickerAtStart) {
      startX = chipRight + 16;
    } else if (direction == RibbonDirection.ltr) {
      startX = chipRight - cycle + wrapped;
    } else {
      startX = w - wrapped;
    }
    final para = buildLine(
      text,
      fontSize,
      color: textColor,
      fontFamily: family,
      exactWidth: textW,
    );
    final y = strip.top +
        (strip.height - para.height) / 2 +
        (_hasArabic(text) ? strip.height * 0.06 : 0);
    canvas.save();
    canvas.clipRect(
      ui.Rect.fromLTWH(
        chipRight,
        strip.top,
        w - chipRight,
        strip.height,
      ),
    );
    canvas.drawParagraph(para, ui.Offset(startX, y));
    canvas.drawParagraph(para, ui.Offset(startX + cycle, y));
    canvas.restore();
  }

  final isCombo = template.variant == BreakingVariant.breakingTickerCombo;

  // --- Banner / top bar + chip + headline. ---
  canvas.drawRect(
    layout.bannerRect,
    ui.Paint()..color = ui.Color(template.topColor),
  );
  final bannerTextColor = _stripTextColor(template.topColor);
  final chipRect = layout.bannerChipRect;
  if (chipRect != null) {
    final chipText = template.variant == BreakingVariant.latestNews
        ? BreakingLayout.latestChipText
        : BreakingLayout.breakingChipText;
    canvas.drawRect(
      chipRect,
      ui.Paint()..color = white,
    );
    drawCentred(
      chipText,
      chipRect,
      layout.chipSize,
      color: ui.Color(template.topColor),
    );
  }
  final headline = template.headline.trim();
  if (headline.isNotEmpty) {
    final para = buildLine(
      headline,
      layout.headlineSize,
      color: bannerTextColor,
      maxWidth: layout.headlineRect.width,
      ellipsis: '…',
    );
    canvas.drawParagraph(
      para,
      ui.Offset(
        layout.headlineRect.left,
        layout.headlineRect.top +
            (layout.headlineRect.height - para.height) / 2,
      ),
    );
  }

  // --- Single-variant bottom ticker strip (scrolling). ---
  final tickerStrip = layout.tickerStrip;
  if (tickerStrip != null) {
    canvas.drawRect(
      tickerStrip,
      ui.Paint()..color = ui.Color(template.bottomColor),
    );
    drawScrollingTicker(
      strip: tickerStrip,
      chipRight: 0,
      text: template.tickerText.trim(),
      fontSize: layout.tickerTextSize,
      textColor: _stripTextColor(template.bottomColor),
      direction: template.direction,
    );
  }

  // --- Combo: top ticker strip (scrolling) + middle + bottom ribbons. ---
  if (isCombo) {
    final topStrip = layout.topTickerStrip;
    if (topStrip != null) {
      canvas.drawRect(
        topStrip,
        ui.Paint()..color = ui.Color(template.tickerColor),
      );
      final chip = layout.topTickerChip!;
      canvas.drawRect(
        chip,
        ui.Paint()..color = const ui.Color(0xFFD50000),
      );
      drawCentred(
        NigraanFinalLayout.tickerChipText,
        chip,
        layout.tickerHeight * 0.45,
        fontFamily: kasheeda(NigraanFinalLayout.tickerChipText),
      );
      drawScrollingTicker(
        strip: topStrip,
        chipRight: chip.right,
        text: template.tickerText.trim(),
        fontSize: layout.tickerTextSize,
        textColor: _stripTextColor(template.tickerColor),
        direction: template.direction,
      );
    }
    final middleStrip = layout.middleStrip;
    if (middleStrip != null) {
      canvas.drawRect(
        middleStrip,
        ui.Paint()..color = ui.Color(template.middleColor),
      );
      final chip = layout.middleChip;
      final textLeft = chip?.right ?? 0;
      if (chip != null) {
        canvas.drawRect(
          chip,
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
        drawCentred(
          NigraanFinalLayout.urduChipText,
          chip,
          middleStrip.height * 0.45,
          fontFamily: kasheeda(NigraanFinalLayout.urduChipText),
        );
      }
      final text = template.middleText.trim();
      if (text.isNotEmpty) {
        _drawStripText(
          canvas: canvas,
          text: text,
          strip: middleStrip,
          textLeft: textLeft + 12,
          fontSize: layout.middleTextSize,
          fontFamily: kasheeda(text),
          buildLine: buildLine,
        );
      }
    }
    final bottomStrip = layout.bottomStrip;
    if (bottomStrip != null) {
      canvas.drawRect(
        bottomStrip,
        ui.Paint()..color = ui.Color(template.bottomColor),
      );
      final chip = layout.bottomChip!;
      canvas.drawRect(
        chip,
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      drawCentred(
        NigraanFinalLayout.englishChipText,
        chip,
        bottomStrip.height * 0.55,
      );
      final text = template.bottomText.trim();
      if (text.isNotEmpty) {
        _drawStripText(
          canvas: canvas,
          text: text,
          strip: bottomStrip,
          textLeft: chip.right + 12,
          fontSize: layout.englishTextSize,
          fontFamily: null,
          buildLine: buildLine,
        );
      }
    }
  }

  // --- Lower third (reporter name + place), above the ribbons. ---
  final lowerThird = layout.lowerThird;
  if (lowerThird != null) {
    canvas.drawRect(
      lowerThird,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final title = template.lowerThirdTitle.trim();
    final subtitle = template.lowerThirdSubtitle.trim();
    if (title.isNotEmpty) {
      final para = buildLine(title, h * 0.024, maxWidth: w * 0.64);
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.10),
      );
    }
    if (subtitle.isNotEmpty) {
      final para = buildLine(
        subtitle,
        h * 0.019,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.55),
      );
    }
  }

  // --- Interview name plate — above the lower third. ---
  final interviewPlate = layout.interviewPlate;
  if (interviewPlate != null) {
    canvas.drawRect(
      interviewPlate,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final tagFont = interviewPlate.height * 0.22;
    final tagW = _measureTextWidth(
          NigraanFinalLayout.interviewTagText,
          tagFont,
        ) +
        16;
    final tagRect = ui.Rect.fromLTWH(
      interviewPlate.left,
      interviewPlate.top,
      tagW,
      interviewPlate.height * 0.30,
    );
    canvas.drawRect(
      tagRect,
      ui.Paint()..color = const ui.Color(0xFFD50000),
    );
    drawCentred(
      NigraanFinalLayout.interviewTagText,
      tagRect,
      tagFont,
    );
    final name = template.interviewName.trim();
    final designation = template.interviewDesignation.trim();
    final namePara = buildLine(name, h * 0.022, maxWidth: w * 0.64);
    canvas.drawParagraph(
      namePara,
      ui.Offset(
        interviewPlate.left + 16,
        interviewPlate.top + tagRect.height + 4,
      ),
    );
    if (designation.isNotEmpty) {
      final desPara = buildLine(
        designation,
        h * 0.017,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        desPara,
        ui.Offset(
          interviewPlate.left + 16,
          interviewPlate.top + interviewPlate.height * 0.62,
        ),
      );
    }
  }

  // --- Logo bug + time/date capsule. ---
  if (includeLogo) {
    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();
    await _drawLogoBug(
      canvas: canvas,
      logoPath: template.logoPath ?? preset.logoPath,
      initial: initial,
      rect: layout.logoRect,
    );
  }
  _drawTimeDateCapsule(canvas: canvas, rect: layout.capsuleRect, now: now);

  // --- Category chip + intro/outro markers. ---
  final categoryChip = layout.categoryChip;
  if (categoryChip != null) {
    _drawPill(
      canvas,
      categoryChip,
      template.categoryLabel.trim().toUpperCase(),
      categoryChip.height * 0.55,
    );
  }
  final introMarker = layout.introMarker;
  if (introMarker != null) {
    _drawPill(
      canvas,
      introMarker,
      NigraanFinalLayout.introMarkerText,
      introMarker.height * 0.55,
      bold: false,
    );
  }
  final outroMarker = layout.outroMarker;
  if (outroMarker != null) {
    _drawPill(
      canvas,
      outroMarker,
      NigraanFinalLayout.outroMarkerText,
      outroMarker.height * 0.55,
      bold: false,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'breaking_template.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Pure layout geometry for the Classic template (Phase 6).
///
/// The pre-3-ribbon classic look: a dark top bar with the channel
/// name + red LIVE chip, a scrolling ticker strip at the bottom
/// (the preset's top ribbon colour + text), logo bug + time/date
/// capsule, lower third, interview plate, category chip and
/// intro/outro markers. Same 24px side margins as the breaking
/// layouts (§14 rule 6).
class ClassicLayout {
  const ClassicLayout({
    required this.width,
    required this.height,
    required this.topBarHeight,
    required this.tickerHeight,
    required this.topBarRect,
    required this.liveChipRect,
    required this.channelNameRect,
    required this.tickerStrip,
    required this.lowerThird,
    required this.logoRect,
    required this.capsuleRect,
    required this.introMarker,
    required this.outroMarker,
    required this.categoryChip,
    required this.interviewPlate,
    required this.channelNameSize,
    required this.tickerTextSize,
  });

  static const String liveChipText = 'LIVE';

  final double width;
  final double height;

  final double topBarHeight;
  final double tickerHeight;

  /// Dark top bar (channel name + LIVE chip).
  final ui.Rect topBarRect;
  final ui.Rect liveChipRect;

  /// Channel-name text area inside the top bar.
  final ui.Rect channelNameRect;

  /// Bottom scrolling ticker strip — null when the top ribbon is off.
  final ui.Rect? tickerStrip;

  /// Null when the lower third is off or has no text.
  final ui.Rect? lowerThird;

  /// Logo-bug slot (top-right, below the top bar) and the time/date
  /// capsule directly under it, same width as the logo.
  final ui.Rect logoRect;
  final ui.Rect capsuleRect;

  /// Null when intro/outro is off or [includeIntroMarker] is false.
  final ui.Rect? introMarker;
  final ui.Rect? outroMarker;

  /// Null when the preset's category label is empty.
  final ui.Rect? categoryChip;

  /// Null when the interview plate is off or has no name.
  final ui.Rect? interviewPlate;

  final double channelNameSize;
  final double tickerTextSize;

  static ClassicLayout compute({
    required ChannelPreset preset,
    required double width,
    required double height,
    bool includeIntroMarker = true,
  }) {
    const margin = 24.0;
    final gap = height * 0.008;
    final topBarH = height * 0.07;
    final tickerH = height * 0.055;
    final logoSize = width * 0.153;
    final capsuleH = height * 0.022;

    final topBarRect = ui.Rect.fromLTWH(0, 0, width, topBarH);
    final liveFont = topBarH * 0.38;
    final liveW = _measureTextWidth(liveChipText, liveFont) + 20;
    final liveChipRect = ui.Rect.fromLTWH(
      width - margin - liveW,
      topBarH * 0.225,
      liveW,
      topBarH * 0.55,
    );
    final channelNameRect = ui.Rect.fromLTWH(
      margin,
      0,
      liveChipRect.left - 16 - margin,
      topBarH,
    );

    ui.Rect? tickerStrip;
    if (preset.topRibbon.enabled) {
      tickerStrip = ui.Rect.fromLTWH(0, height - tickerH, width, tickerH);
    }

    ui.Rect? categoryChip;
    if (preset.categoryLabel.trim().isNotEmpty) {
      final chipH = height * 0.024;
      final chipW = _measureTextWidth(
            preset.categoryLabel.trim().toUpperCase(),
            height * 0.016,
          ) +
          24;
      categoryChip = ui.Rect.fromLTWH(margin, topBarH + 16, chipW, chipH);
    }

    ui.Rect? introMarker;
    ui.Rect? outroMarker;
    if (preset.showIntro && includeIntroMarker) {
      final markerFont = height * 0.016;
      final markerW =
          _measureTextWidth(NigraanFinalLayout.introMarkerText, markerFont) +
          28;
      final markerTop = topBarH +
          16 +
          (categoryChip != null ? categoryChip.height + 8 : 0);
      introMarker = ui.Rect.fromLTWH(
        margin,
        markerTop,
        markerW,
        height * 0.024,
      );
      if (preset.showOutro) {
        final outroW =
            _measureTextWidth(NigraanFinalLayout.outroMarkerText, markerFont) +
            28;
        outroMarker = ui.Rect.fromLTWH(
          introMarker.right + 8,
          markerTop,
          outroW,
          height * 0.024,
        );
      }
    }

    final logoRect = ui.Rect.fromLTWH(
      width - margin - logoSize,
      topBarH + 16,
      logoSize,
      logoSize,
    );
    final capsuleRect = ui.Rect.fromLTWH(
      logoRect.left,
      logoRect.bottom + 6,
      logoSize,
      capsuleH,
    );

    ui.Rect? lowerThird;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    if (hasLowerThird) {
      final ltH = height * 0.10;
      final bottom =
          tickerStrip != null ? tickerStrip.top - gap : height;
      lowerThird = ui.Rect.fromLTWH(0, bottom - ltH, width * 0.68, ltH);
    }

    ui.Rect? interviewPlate;
    final hasInterviewPlate = preset.showInterviewPlate &&
        preset.interviewName.trim().isNotEmpty;
    if (hasInterviewPlate) {
      final plateH = height * 0.08;
      var bottom = height;
      if (lowerThird != null) {
        bottom = lowerThird.top - gap;
      } else if (tickerStrip != null) {
        bottom = tickerStrip.top - gap;
      }
      interviewPlate = ui.Rect.fromLTWH(
        0,
        bottom - plateH,
        width * 0.68,
        plateH,
      );
    }

    return ClassicLayout(
      width: width,
      height: height,
      topBarHeight: topBarH,
      tickerHeight: tickerH,
      topBarRect: topBarRect,
      liveChipRect: liveChipRect,
      channelNameRect: channelNameRect,
      tickerStrip: tickerStrip,
      lowerThird: lowerThird,
      logoRect: logoRect,
      capsuleRect: capsuleRect,
      introMarker: introMarker,
      outroMarker: outroMarker,
      categoryChip: categoryChip,
      interviewPlate: interviewPlate,
      channelNameSize: topBarH * 0.42,
      tickerTextSize: BreakingLayout.clampFontSize(
        preset.topRibbon.fontSize,
        tickerH,
      ),
    );
  }
}

/// Renders the Classic template into ONE transparent PNG sized
/// [width]x[height]. Writes `classic_template.png` (never the live /
/// final / breaking overlay files).
Future<File> _renderClassicImage({
  required ChannelPreset preset,
  required double tickerPx,
  required DateTime now,
  required Directory dir,
  int width = 720,
  int height = 1280,
  bool tickerAtStart = false,
  bool includeLogo = true,
  bool fontReady = false,
  bool includeIntroMarker = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final w = width.toDouble();
  final h = height.toDouble();
  const white = ui.Color(0xFFFFFFFF);

  final layout = ClassicLayout.compute(
    preset: preset,
    width: w,
    height: h,
    includeIntroMarker: includeIntroMarker,
  );

  String? kasheeda(String text) =>
      fontReady && _hasArabic(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  ui.Paragraph buildLine(
    String text,
    double fontSize, {
    ui.Color color = white,
    bool bold = true,
    String? fontFamily,
    double? exactWidth,
    double maxWidth = 0,
    String? ellipsis,
    ui.TextAlign align = ui.TextAlign.left,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection:
            _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: ellipsis,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontFamily: fontFamily,
      ),
    );
    builder.addText(text);
    final para = builder.build();
    para.layout(
      ui.ParagraphConstraints(
        width: exactWidth ?? (maxWidth > 0 ? maxWidth : w),
      ),
    );
    return para;
  }

  // --- Top bar: channel name + LIVE chip. ---
  canvas.drawRect(
    layout.topBarRect,
    ui.Paint()..color = const ui.Color(0xFF1B1B2F),
  );
  final name = preset.name.trim().isEmpty ? 'Channel' : preset.name.trim();
  final namePara = buildLine(
    name,
    layout.channelNameSize,
    maxWidth: layout.channelNameRect.width,
    ellipsis: '…',
  );
  canvas.drawParagraph(
    namePara,
    ui.Offset(
      layout.channelNameRect.left,
      layout.channelNameRect.top +
          (layout.channelNameRect.height - namePara.height) / 2,
    ),
  );
  canvas.drawRect(
    layout.liveChipRect,
    ui.Paint()..color = const ui.Color(0xFFD50000),
  );
  final livePara = buildLine(
    ClassicLayout.liveChipText,
    layout.topBarHeight * 0.38,
    maxWidth: layout.liveChipRect.width,
    align: ui.TextAlign.center,
  );
  canvas.drawParagraph(
    livePara,
    ui.Offset(
      layout.liveChipRect.left,
      layout.liveChipRect.top +
          (layout.liveChipRect.height - livePara.height) / 2,
    ),
  );

  // --- Bottom ticker strip (scrolling). ---
  final tickerStrip = layout.tickerStrip;
  if (tickerStrip != null) {
    canvas.drawRect(
      tickerStrip,
      ui.Paint()..color = ui.Color(preset.topRibbon.color),
    );
    final ticker = preset.topRibbon.text.trim();
    if (ticker.isNotEmpty) {
      final fontSize = layout.tickerTextSize;
      final family = kasheeda(ticker);
      final textW = _measureTextWidth(ticker, fontSize, fontFamily: family);
      final cycle = textW + 240;
      final wrapped = cycle > 0 ? tickerPx % cycle : tickerPx;
      final double startX;
      if (tickerAtStart) {
        startX = 24.0;
      } else if (preset.topRibbon.direction == RibbonDirection.ltr) {
        startX = -cycle + wrapped;
      } else {
        startX = w - wrapped;
      }
      final para = buildLine(
        ticker,
        fontSize,
        color: _stripTextColor(preset.topRibbon.color),
        fontFamily: family,
        exactWidth: textW,
      );
      final y = tickerStrip.top +
          (tickerStrip.height - para.height) / 2 +
          (_hasArabic(ticker) ? tickerStrip.height * 0.06 : 0);
      canvas.save();
      canvas.clipRect(tickerStrip);
      canvas.drawParagraph(para, ui.Offset(startX, y));
      canvas.drawParagraph(para, ui.Offset(startX + cycle, y));
      canvas.restore();
    }
  }

  // --- Lower third (reporter name + place), above the ticker. ---
  final lowerThird = layout.lowerThird;
  if (lowerThird != null) {
    canvas.drawRect(
      lowerThird,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final title = preset.lowerThirdTitle.trim();
    final subtitle = preset.lowerThirdSubtitle.trim();
    if (title.isNotEmpty) {
      final para = buildLine(title, h * 0.024, maxWidth: w * 0.64);
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.10),
      );
    }
    if (subtitle.isNotEmpty) {
      final para = buildLine(
        subtitle,
        h * 0.019,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        para,
        ui.Offset(20, lowerThird.top + lowerThird.height * 0.55),
      );
    }
  }

  // --- Interview name plate — above the lower third. ---
  final interviewPlate = layout.interviewPlate;
  if (interviewPlate != null) {
    canvas.drawRect(
      interviewPlate,
      ui.Paint()..color = const ui.Color(0xA6000000),
    );
    final tagFont = interviewPlate.height * 0.22;
    final tagW = _measureTextWidth(
          NigraanFinalLayout.interviewTagText,
          tagFont,
        ) +
        16;
    final tagRect = ui.Rect.fromLTWH(
      interviewPlate.left,
      interviewPlate.top,
      tagW,
      interviewPlate.height * 0.30,
    );
    canvas.drawRect(
      tagRect,
      ui.Paint()..color = const ui.Color(0xFFD50000),
    );
    final tagPara = buildLine(
      NigraanFinalLayout.interviewTagText,
      tagFont,
      maxWidth: tagRect.width,
      align: ui.TextAlign.center,
    );
    canvas.drawParagraph(
      tagPara,
      ui.Offset(
        tagRect.left,
        tagRect.top + (tagRect.height - tagPara.height) / 2,
      ),
    );
    final iname = preset.interviewName.trim();
    final designation = preset.interviewDesignation.trim();
    final namePara2 = buildLine(iname, h * 0.022, maxWidth: w * 0.64);
    canvas.drawParagraph(
      namePara2,
      ui.Offset(
        interviewPlate.left + 16,
        interviewPlate.top + tagRect.height + 4,
      ),
    );
    if (designation.isNotEmpty) {
      final desPara = buildLine(
        designation,
        h * 0.017,
        bold: false,
        maxWidth: w * 0.64,
      );
      canvas.drawParagraph(
        desPara,
        ui.Offset(
          interviewPlate.left + 16,
          interviewPlate.top + interviewPlate.height * 0.62,
        ),
      );
    }
  }

  // --- Logo bug + time/date capsule. ---
  if (includeLogo) {
    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();
    await _drawLogoBug(
      canvas: canvas,
      logoPath: preset.logoPath,
      initial: initial,
      rect: layout.logoRect,
    );
  }
  _drawTimeDateCapsule(canvas: canvas, rect: layout.capsuleRect, now: now);

  // --- Category chip + intro/outro markers. ---
  final categoryChip = layout.categoryChip;
  if (categoryChip != null) {
    _drawPill(
      canvas,
      categoryChip,
      preset.categoryLabel.trim().toUpperCase(),
      categoryChip.height * 0.55,
    );
  }
  final introMarker = layout.introMarker;
  if (introMarker != null) {
    _drawPill(
      canvas,
      introMarker,
      NigraanFinalLayout.introMarkerText,
      introMarker.height * 0.55,
      bold: false,
    );
  }
  final outroMarker = layout.outroMarker;
  if (outroMarker != null) {
    _drawPill(
      canvas,
      outroMarker,
      NigraanFinalLayout.outroMarkerText,
      outroMarker.height * 0.55,
      bold: false,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, 'classic_template.png'));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}
