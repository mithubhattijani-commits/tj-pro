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
double _measureTickerWidth(String text, double fontSize) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection:
          _hasArabic(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  builder.pushStyle(
    ui.TextStyle(fontSize: fontSize, fontWeight: ui.FontWeight.bold),
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
Future<File> renderLiveTemplateImage({
  required NewsTemplate template,
  required double tickerPx,
  required DateTime now,
  required Directory dir,
  int width = 720,
  int height = 1280,
  bool tickerAtStart = false,
}) async {
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
