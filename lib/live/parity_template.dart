/// Final Template parity (v1.3.0, brief §9) — the ONE source of
/// truth for the REAL Nigraan final template, as produced by the
/// channel's own pipeline (house style v8, user-approved
/// 14 Nov 2026; `make_reel.py` portrait + `make_news_video.py`
/// landscape in the 20 Nov backup pack).
///
/// The reference is TWO flush bottom ribbons of equal height —
/// Urdu #3D5AFE over English #EF0017 — both scrolling (Urdu
/// rightward, English leftward, gold-dot separators), black chips
/// with GOLD text (بریکنگ نیوز at the RIGHT of the Urdu ribbon,
/// HEADLINES at the LEFT of the English ribbon), the rotating logo
/// at bottom-right with its visible width 17.1% of the frame, and
/// directly under it a dark capsule that FLIPS between a ticking
/// PKT clock (drawtext `%{pts:localtime:%r}` over epoch-shifted
/// PTS) and the Urdu date, ~3 s each. No top ribbon in the parity
/// preset (it stays in the app as an optional extra), no end card.
///
/// This file holds: the pure [ParityGeometry], the dart:ui PNG
/// layer renderers (ribbon backgrounds, scrolling ticker strips,
/// chips, capsule bar + date face, the optional top-ribbon still),
/// and the FFmpeg command builder that animates them. The widget
/// preview (nigraan_final_preview.dart) and the PIL tasalli check
/// use the same constants.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../services/asset_download_service.dart';
import '../services/ffmpeg_service.dart';
import 'news_template.dart' show NigraanFinalLayout;
import '../news/channel_preset.dart';

/// Broadcast gold (#F5C542) — chips' text, ribbon top edges,
/// separators, capsule top line.
const int kParityGold = 0xFFF5C542;

/// Urdu ribbon colour (#3D5AFE) — the preset carries it; this is
/// the fallback when a preset colour is unset.
const int kParityUrduColor = 0xFF3D5AFE;

/// English ribbon colour (#EF0017).
const int kParityEnglishColor = 0xFFEF0017;

/// Pure reference geometry for a [width]x[height] frame.
///
/// Pixel constants come from the two reference renderers, which
/// work at 1080x1920 (portrait) and 1280x720 (landscape); [s] is
/// the scale against the orientation's reference width, so the
/// geometry reproduces both renderers exactly at their native
/// sizes and interpolates proportionally elsewhere.
class ParityGeometry {
  ParityGeometry(this.width, this.height);

  final double width;
  final double height;

  bool get portrait => height >= width;

  /// The reference renderer's frame width for this orientation.
  double get refW => portrait ? 1080 : 1280;

  /// Scale of reference pixels to this frame.
  double get s => width / refW;

  /// Equal ribbon height: 64/1920 of height (portrait), 40/720
  /// (landscape) — 3.33% / 5.56% of the frame height.
  double get ribbonH => portrait ? height * (64 / 1920) : height * (40 / 720);

  /// Gold line along each ribbon's top edge (3 px at reference).
  double get goldEdge => 3 * s;

  /// Fixed chip widths: Urdu 240 px (22.2% portrait / 18.75%
  /// landscape), English 220/260 px (≈20.4% both).
  double get urduChipW => portrait ? width * (240 / 1080) : width * (240 / 1280);
  double get englishChipW =>
      portrait ? width * (220 / 1080) : width * (260 / 1280);

  /// The logo's VISIBLE width: 185 px at 1080 wide, 219 at 1280
  /// (both ≈17.1% of the frame width).
  double get logoVisibleW => width * (185 / 1080);

  /// The alpha .mov's union crop (488:382:195:57) scaled so its
  /// visible content (422x347 inside the crop, offset 29,13,
  /// bottom edge at 360) is exactly [logoVisibleW] wide.
  double get logoCropW => 488 * logoVisibleW / 422;
  double get logoCropH => 382 * logoVisibleW / 422;
  double get logoVisibleL => 29 * logoVisibleW / 422;
  double get logoVisibleBot => 360 * logoVisibleW / 422;
  double get logoVisibleH => 347 * logoVisibleW / 422;

  /// Right margin of the logo/capsule stack (24 px at reference).
  double get logoMargin => 24 * s;

  /// Capsule: same width as the visible logo; height 47 px
  /// (portrait) / 39 px (landscape).
  double get capsuleW => logoVisibleW;
  double get capsuleH => portrait ? height * (47 / 1920) : height * (39 / 720);

  // ---- Rects (frame coordinates) ----

  ui.Rect get englishStrip =>
      ui.Rect.fromLTWH(0, height - ribbonH, width, ribbonH);
  ui.Rect get urduStrip =>
      ui.Rect.fromLTWH(0, height - 2 * ribbonH, width, ribbonH);
  ui.Rect get urduChip => ui.Rect.fromLTWH(
        width - urduChipW,
        urduStrip.top,
        urduChipW,
        ribbonH,
      );
  ui.Rect get englishChip =>
      ui.Rect.fromLTWH(0, englishStrip.top, englishChipW, ribbonH);

  /// Capsule bottom edge sits ON the Urdu ribbon's top edge.
  ui.Rect get capsule => ui.Rect.fromLTWH(
        width - logoMargin - capsuleW,
        urduStrip.top - capsuleH,
        capsuleW,
        capsuleH,
      );

  /// Where the logo's VISIBLE content lands.
  ui.Rect get logoVisible => ui.Rect.fromLTWH(
        capsule.left,
        capsule.top - logoVisibleH,
        logoVisibleW,
        logoVisibleH,
      );

  /// Overlay position for the scaled .mov crop: its visible part
  /// must land exactly on [logoVisible].
  double get logoCropX => logoVisible.left - logoVisibleL;
  double get logoCropY => capsule.top - logoVisibleBot;

  // ---- Motion / text metrics ----

  /// Ticker speed: 110 px/s scaled by frame width (brief §9.1).
  double get scrollSpeed => 110 * width / 1080;

  /// Gold-dot separator slot / radius (52 / 7 px at reference).
  double get sepSlot => 52 * s;
  double get dotR => 7 * s;

  /// Ribbon text sizes (fractions of the ribbon height — the
  /// reference's 36/29/34 px on a 64 px ribbon).
  double get urduFontAr => ribbonH * (36 / 64);
  double get urduFontLat => ribbonH * (29 / 64);
  double get englishFont => ribbonH * (34 / 64);

  /// Capsule clock size (the reference fits "12:59:59 PM" into the
  /// capsule; 0.55 of the capsule height reproduces its fitted
  /// 26 px on the 47 px portrait capsule).
  double get clockFont => capsuleH * 0.55;

  /// Scroll window of a ribbon = frame width minus its chip.
  double urduWindowW() => width - urduChipW;
  double englishWindowW() => width - englishChipW;
}

/// Splits a ribbon's text into headlines: the app stores one string
/// per ribbon; multiple headlines are separated by '•', '●', '|' or
/// newlines (the separators are re-drawn as gold dots).
List<String> paritySplitHeadlines(String text) {
  final parts = text
      .split(RegExp(r'[•●|\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return parts.isEmpty ? [text.trim()] : parts;
}

const _urduWeekdays = [
  'پیر',
  'منگل',
  'بدھ',
  'جمعرات',
  'جمعہ',
  'ہفتہ',
  'اتوار',
];
const _urduMonths = [
  'جنوری',
  'فروری',
  'مارچ',
  'اپریل',
  'مئی',
  'جون',
  'جولائی',
  'اگست',
  'ستمبر',
  'اکتوبر',
  'نومبر',
  'دسمبر',
];

/// The capsule's DATE face: Urdu weekday + day + month + year,
/// e.g. `ہفتہ 14 نومبر 2026` (the reference format).
String parityUrduDate(DateTime d) {
  final weekday = _urduWeekdays[(d.weekday - 1).clamp(0, 6)];
  return '$weekday ${d.day} ${_urduMonths[(d.month - 1).clamp(0, 11)]} ${d.year}';
}

/// The capsule's TIME face text (for previews): 12-hour with
/// seconds, e.g. `08:55:20 PM` — the `%r` format the export's
/// drawtext clock renders.
String parityTimeString(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h12)}:${two(d.minute)}:${two(d.second)} $ampm';
}

bool _hasArabic(String text) =>
    RegExp(r'[؀-ۿ]').hasMatch(text);

/// One laid-out headline paragraph + its ink width, built with the
/// reference's mixed-script rule: Arabic runs in Kasheeda (when
/// [fontReady]), Latin/digit runs in the default bold face.
(ui.Paragraph, double) _headlineParagraph(
  String text, {
  required bool urdu,
  required bool fontReady,
  required ParityGeometry g,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: urdu ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  // Split into Arabic / Latin runs (spaces stay with the run before
  // them, like the reference's split_runs).
  final runs = <(bool, String)>[];
  var buf = StringBuffer();
  bool? bufArabic;
  void flush() {
    if (buf.isNotEmpty && bufArabic != null) {
      runs.add((bufArabic!, buf.toString()));
    }
    buf = StringBuffer();
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    final arabic = _hasArabic(ch);
    if (ch == ' ') {
      buf.write(ch);
      continue;
    }
    if (bufArabic != null && arabic != bufArabic) {
      flush();
    }
    bufArabic = arabic;
    buf.write(ch);
  }
  flush();
  if (runs.isEmpty) runs.add((urdu, text));
  for (final (arabic, run) in runs) {
    builder.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: arabic ? g.urduFontAr : (urdu ? g.urduFontLat : g.englishFont),
        fontWeight: ui.FontWeight.bold,
        fontFamily: arabic && fontReady
            ? AssetDownloadService.kasheedaFamily
            : null,
      ),
    );
    builder.addText(run);
  }
  final para = builder.build();
  para.layout(const ui.ParagraphConstraints(width: double.infinity));
  return (para, para.maxIntrinsicWidth);
}

Future<File> _writePng(
  ui.PictureRecorder recorder,
  int w,
  int h,
  Directory dir,
  String name,
) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Ribbon background layer (W x ribbonH): solid ribbon colour +
/// the gold top edge. [color] is the preset's ribbon colour.
Future<File> renderParityRibbonBg({
  required Directory dir,
  required ParityGeometry g,
  required bool urdu,
  required int color,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, g.width, g.ribbonH);
  canvas.drawRect(rect, ui.Paint()..color = ui.Color(color));
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, g.width, g.goldEdge),
    ui.Paint()..color = const ui.Color(kParityGold),
  );
  return _writePng(
    recorder,
    g.width.round(),
    g.ribbonH.ceil(),
    dir,
    urdu ? 'parity_t1bg.png' : 'parity_t2bg.png',
  );
}

/// Chip layer (W x ribbonH, transparent except the chip): black
/// chip with GOLD text and a gold divider on its inner edge, at the
/// reference's fixed width and side.
Future<File> renderParityChip({
  required Directory dir,
  required ParityGeometry g,
  required bool urdu,
  required bool fontReady,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final chipW = urdu ? g.urduChipW : g.englishChipW;
  final chipLeft = urdu ? g.width - chipW : 0.0;
  canvas.drawRect(
    ui.Rect.fromLTWH(chipLeft, 0, chipW, g.ribbonH),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  // Gold divider on the inner edge.
  final divX = urdu ? chipLeft : chipW - g.goldEdge;
  canvas.drawRect(
    ui.Rect.fromLTWH(divX, 0, g.goldEdge, g.ribbonH),
    ui.Paint()..color = const ui.Color(kParityGold),
  );
  final label = urdu
      ? NigraanFinalLayout.urduChipText
      : NigraanFinalLayout.englishChipText;
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      textDirection: urdu ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      maxLines: 1,
    ),
  );
  builder.pushStyle(
    ui.TextStyle(
      color: const ui.Color(kParityGold),
      fontSize: g.ribbonH * 0.5,
      fontWeight: ui.FontWeight.bold,
      fontFamily: urdu && fontReady
          ? AssetDownloadService.kasheedaFamily
          : null,
    ),
  );
  builder.addText(label);
  final para = builder.build();
  para.layout(ui.ParagraphConstraints(width: chipW));
  canvas.drawParagraph(
    para,
    ui.Offset(
      chipLeft,
      (g.ribbonH - para.height) / 2 + (urdu ? g.ribbonH * 0.06 : 0),
    ),
  );
  return _writePng(
    recorder,
    g.width.round(),
    g.ribbonH.ceil(),
    dir,
    urdu ? 'parity_t1top.png' : 'parity_t2top.png',
  );
}

/// One scrolling ticker strip. Returns the PNG and the scroll
/// period (one full repeated sequence, `sw` in the reference
/// formulas): the strip image is TWO copies of the sequence, and
/// the sequence itself repeats the headlines until it covers at
/// least twice the ribbon's window — the overlay expression then
/// loops seamlessly forever.
Future<(File, double)> renderParityStrip({
  required Directory dir,
  required ParityGeometry g,
  required bool urdu,
  required List<String> headlines,
  required bool fontReady,
}) async {
  (ui.Paragraph, double, bool) buildOne(String h) {
    final r = _headlineParagraph(h, urdu: urdu, fontReady: fontReady, g: g);
    return (r.$1, r.$2, _hasArabic(h));
  }

  final paras = <(ui.Paragraph, double, bool)>[
    for (final h in headlines) buildOne(h),
  ];
  final seqOnce = paras.fold<double>(0, (a, e) => a + e.$2 + 4) +
      g.sepSlot * paras.length;
  final window = urdu ? g.urduWindowW() : g.englishWindowW();
  var reps = 1;
  while (seqOnce * reps < window * 2) {
    reps++;
  }
  final sw = seqOnce * reps;
  final stripW = (sw * 2).ceil();
  final stripH = g.ribbonH.ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final gold = ui.Paint()..color = const ui.Color(kParityGold);
  void drawDot(double cx) {
    canvas.drawCircle(ui.Offset(cx, g.ribbonH / 2), g.dotR, gold);
  }

  void drawHeadline((ui.Paragraph, double, bool) e, double x) {
    final (para, _, arabic) = e;
    // Ink-centred like the reference; Nastaleeq ink sits high in
    // its line box, so Arabic headlines nudge down a touch (the
    // same convention as the still renderer).
    final y = (g.ribbonH - para.height) / 2 +
        (arabic ? g.ribbonH * 0.06 : 0);
    canvas.drawParagraph(para, ui.Offset(x, y));
  }

  for (var copy = 0; copy < 2; copy++) {
    if (urdu) {
      // Reference RTL build: cursor starts at the block's right
      // edge; headlines are placed right-to-left, dot after each.
      var x = copy * sw + sw;
      for (var r = 0; r < reps; r++) {
        for (final e in paras) {
          x -= e.$2 + 4;
          drawHeadline(e, x);
          x -= g.sepSlot;
          drawDot(x + g.sepSlot / 2);
        }
      }
    } else {
      var x = copy * sw;
      for (var r = 0; r < reps; r++) {
        for (final e in paras) {
          drawHeadline(e, x);
          x += e.$2 + 4;
          drawDot(x + g.sepSlot / 2);
          x += g.sepSlot;
        }
      }
    }
  }
  final file = await _writePng(
    recorder,
    stripW,
    stripH,
    dir,
    urdu ? 'parity_t1strip.png' : 'parity_t2strip.png',
  );
  return (file, sw);
}

/// Capsule bar layer (full frame): dark translucent rounded bar
/// with a gold top line, at the capsule rect. Both clock faces are
/// drawn over it (drawtext time / PNG date).
Future<File> renderParityCapsuleBar({
  required Directory dir,
  required ParityGeometry g,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final cap = g.capsule;
  final rrect = ui.RRect.fromRectAndRadius(
    cap,
    ui.Radius.circular(8 * g.s),
  );
  canvas.drawRRect(rrect, ui.Paint()..color = const ui.Color(0xAA000000));
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(
    ui.Rect.fromLTWH(cap.left, cap.top, cap.width, 4 * g.s),
    ui.Paint()..color = const ui.Color(kParityGold),
  );
  canvas.restore();
  return _writePng(
    recorder,
    g.width.round(),
    g.height.round(),
    dir,
    'parity_capbar.png',
  );
}

/// Capsule DATE face layer (full frame): the Urdu date, white
/// Kasheeda, centred in the capsule; the font shrinks until it
/// fits the capsule width (the reference's fit loop).
Future<File> renderParityCapsuleDate({
  required Directory dir,
  required ParityGeometry g,
  required DateTime now,
  required bool fontReady,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final cap = g.capsule;
  final text = parityUrduDate(now);
  var size = 30 * g.s;
  ui.Paragraph para;
  while (true) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.rtl,
        maxLines: 1,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: size,
        fontWeight: ui.FontWeight.bold,
        fontFamily:
            fontReady ? AssetDownloadService.kasheedaFamily : null,
      ),
    );
    builder.addText(text);
    para = builder.build();
    para.layout(const ui.ParagraphConstraints(width: double.infinity));
    if (para.maxIntrinsicWidth <= cap.width - 20 * g.s || size <= 18 * g.s) {
      break;
    }
    size -= 2 * g.s;
  }
  canvas.drawParagraph(
    para,
    ui.Offset(
      cap.left + (cap.width - para.maxIntrinsicWidth) / 2,
      cap.top + (cap.height - para.height) / 2 + cap.height * 0.06,
    ),
  );
  return _writePng(
    recorder,
    g.width.round(),
    g.height.round(),
    dir,
    'parity_capdate.png',
  );
}

/// The OPTIONAL top ribbon as a still layer (full frame): strip +
/// red chip + its text pinned at the start. It is off in the parity
/// preset; when a user enables it, the export carries it as a still
/// (its live scrolling stays a preview behaviour) — never dropped
/// silently.
Future<File> renderParityTopRibbon({
  required Directory dir,
  required ParityGeometry g,
  required ChannelPreset preset,
  required bool fontReady,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final h = g.height * 0.055;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, g.width, h),
    ui.Paint()..color = ui.Color(preset.topRibbon.color),
  );
  final label = NigraanFinalLayout.tickerChipText;
  final chipPara = _headlineParagraph(
    label,
    urdu: true,
    fontReady: fontReady,
    g: g,
  );
  final chipW = chipPara.$2 + 28 * g.s;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, chipW, h),
    ui.Paint()..color = const ui.Color(0xFFD50000),
  );
  canvas.drawParagraph(
    chipPara.$1,
    ui.Offset(14 * g.s, (h - chipPara.$1.height) / 2 + h * 0.06),
  );
  final text = preset.topRibbon.text.trim();
  if (text.isNotEmpty) {
    final para = _headlineParagraph(
      text,
      urdu: _hasArabic(text),
      fontReady: fontReady,
      g: g,
    );
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(chipW, 0, g.width - chipW, h));
    canvas.drawParagraph(
      para.$1,
      ui.Offset(chipW + 16 * g.s, (h - para.$1.height) / 2),
    );
    canvas.restore();
  }
  return _writePng(
    recorder,
    g.width.round(),
    g.height.round(),
    dir,
    'parity_top.png',
  );
}

/// All rendered layers for one parity export.
class ParityAssets {
  const ParityAssets({
    required this.geometry,
    required this.t1bg,
    required this.t1strip,
    required this.t1Period,
    required this.t1top,
    required this.t2bg,
    required this.t2strip,
    required this.t2Period,
    required this.t2top,
    required this.capBar,
    required this.capDate,
    required this.topRibbon,
  });

  final ParityGeometry geometry;
  final File t1bg;
  final File t1strip;
  final double t1Period;
  final File t1top;
  final File t2bg;
  final File t2strip;
  final double t2Period;
  final File t2top;
  final File capBar;
  final File capDate;

  /// Null unless the preset's optional top ribbon is enabled.
  final File? topRibbon;
}

/// Renders every parity layer for [preset] at [width]x[height].
/// Urdu/English ribbon texts come from the preset's ribbons
/// (falling back to the breaking headline / a placeholder line so
/// the ribbons never render empty in a stock export).
Future<ParityAssets> renderParityAssets({
  required Directory dir,
  required ChannelPreset preset,
  required int width,
  required int height,
  required DateTime now,
  required bool fontReady,
  String urduText = '',
  String englishText = '',
}) async {
  final g = ParityGeometry(width.toDouble(), height.toDouble());
  final urdu = urduText.trim().isNotEmpty
      ? urduText.trim()
      : preset.urduRibbon.text.trim();
  final english = englishText.trim().isNotEmpty
      ? englishText.trim()
      : preset.englishRibbon.text.trim();
  final t1bg = await renderParityRibbonBg(
    dir: dir,
    g: g,
    urdu: true,
    color: preset.urduRibbon.color,
  );
  final (t1strip, t1Period) = await renderParityStrip(
    dir: dir,
    g: g,
    urdu: true,
    headlines: paritySplitHeadlines(urdu.isEmpty ? 'قومی خبریں' : urdu),
    fontReady: fontReady,
  );
  final t1top = await renderParityChip(dir: dir, g: g, urdu: true, fontReady: fontReady);
  final t2bg = await renderParityRibbonBg(
    dir: dir,
    g: g,
    urdu: false,
    color: preset.englishRibbon.color,
  );
  final (t2strip, t2Period) = await renderParityStrip(
    dir: dir,
    g: g,
    urdu: false,
    headlines:
        paritySplitHeadlines(english.isEmpty ? 'International headlines' : english),
    fontReady: fontReady,
  );
  final t2top = await renderParityChip(dir: dir, g: g, urdu: false, fontReady: fontReady);
  final capBar = await renderParityCapsuleBar(dir: dir, g: g);
  final capDate = await renderParityCapsuleDate(
    dir: dir,
    g: g,
    now: now,
    fontReady: fontReady,
  );
  final top = preset.topRibbon.enabled
      ? await renderParityTopRibbon(
          dir: dir,
          g: g,
          preset: preset,
          fontReady: fontReady,
        )
      : null;
  return ParityAssets(
    geometry: g,
    t1bg: t1bg,
    t1strip: t1strip,
    t1Period: t1Period,
    t1top: t1top,
    t2bg: t2bg,
    t2strip: t2strip,
    t2Period: t2Period,
    t2top: t2top,
    capBar: capBar,
    capDate: capDate,
    topRibbon: top,
  );
}

String _n(double v) =>
    v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

/// The animated parity overlay command (brief §9 criteria 1–6):
/// both ribbons scroll seamlessly in the reference directions, the
/// logo stack sits bottom-right flush on the ribbons (the .mov is
/// ping-ponged and overlaid TWICE, as the reference), the capsule
/// flips TIME (drawtext over epoch-shifted PTS, ticking 1 s per
/// video second) ↔ DATE every ~3 s.
///
/// Logo source — exactly one of:
/// * [logoMovPath]: the pre-rendered alpha .mov (reference crop).
/// * [logoFramesDir]: generated rotating frames (user/default logo).
/// * [logoStillPng]: a static logo image (last-resort fallback).
/// When all three are null the logo stack is skipped (the capsule
/// still renders) and the caller notes it.
///
/// [clockFontFile] null skips the TIME face (the DATE face still
/// flips in) — the caller notes it.
String buildParityTemplateCommand({
  required String input,
  required String output,
  required ParityAssets assets,
  String? logoMovPath,
  String? logoFramesDir,
  String? logoStillPng,
  required String? clockFontFile,
  required DateTime exportStart,
  int? videoBitrateKbps,
}) {
  final g = assets.geometry;
  final q = FfmpegService.q;
  final buf = StringBuffer();
  buf.write('-y -i ${q(input)} ');
  var idx = 1;
  int next(File f) {
    buf.write('-i ${q(f.path)} ');
    return idx++;
  }

  final iT1bg = next(assets.t1bg);
  final iT1strip = next(assets.t1strip);
  final iT1top = next(assets.t1top);
  final iT2bg = next(assets.t2bg);
  final iT2strip = next(assets.t2strip);
  final iT2top = next(assets.t2top);
  final iCapBar = next(assets.capBar);
  final iCapDate = next(assets.capDate);
  final iTop = assets.topRibbon == null ? null : next(assets.topRibbon!);
  int? iLogo;
  if (logoMovPath != null) {
    buf.write('-stream_loop -1 -i ${q(logoMovPath)} ');
    iLogo = idx++;
  } else if (logoFramesDir != null) {
    buf.write('-framerate 12 -stream_loop -1 -i ${q('$logoFramesDir/frame_%02d.png')} ');
    iLogo = idx++;
  } else if (logoStillPng != null) {
    buf.write('-i ${q(logoStillPng)} ');
    iLogo = idx++;
  }

  final speed = _n(g.scrollSpeed);
  final y1 = _n(g.urduStrip.top);
  final y2 = _n(g.englishStrip.top);
  // Reference overlay-x formulas (make_reel.py): Urdu strip starts
  // at (window − 2·sw) and advances mod(t·speed, sw) — content
  // moves RIGHT; English starts at its chip width and retreats —
  // content moves LEFT.
  final urduX =
      '${_n(g.urduWindowW() - 2 * assets.t1Period)}+mod(t*$speed\\,${_n(assets.t1Period)})';
  final englishX =
      '${_n(g.englishChipW)}-mod(t*$speed\\,${_n(assets.t2Period)})';

  final fc = StringBuffer();
  var cur = '[0:v]';
  var n = 0;
  String step(String filter) {
    n++;
    final out = '[p$n]';
    fc.write('$cur$filter$out;');
    cur = out;
    return cur;
  }

  step('[$iT1bg:v]overlay=0:$y1');
  step('[$iT1strip:v]overlay=x=\'$urduX\':y=$y1');
  step('[$iT1top:v]overlay=0:$y1');
  step('[$iT2bg:v]overlay=0:$y2');
  step('[$iT2strip:v]overlay=x=\'$englishX\':y=$y2');
  step('[$iT2top:v]overlay=0:$y2');
  step('[$iCapBar:v]overlay=0:0');
  step("[$iCapDate:v]overlay=0:0:enable='gte(mod(t\\,6)\\,3)'");
  if (iTop != null) {
    step('[$iTop:v]overlay=0:0');
  }
  if (iLogo != null) {
    if (logoMovPath != null) {
      fc.write(
        '[$iLogo:v]crop=488:382:195:57,format=yuva420p,split[lgf][lgr];'
        '[lgr]reverse[lgrr];[lgf][lgrr]concat=n=2:v=1:a=0,format=yuva420p,'
        'scale=${g.logoCropW.round()}:-1,split[logoa][logob];',
      );
      final lx = _n(g.logoCropX);
      final ly = _n(g.logoCropY);
      step('[logoa]overlay=$lx:$ly');
      step('[logob]overlay=$lx:$ly');
    } else if (logoFramesDir != null) {
      fc.write(
        '[$iLogo:v]format=yuva420p,scale=${g.logoVisibleW.round()}:-1[logof];',
      );
      step(
        '[logof]overlay=${_n(g.logoVisible.left)}:${_n(g.capsule.top - g.logoVisibleW)}',
      );
    } else {
      fc.write('[$iLogo:v]scale=${g.logoVisibleW.round()}:-1[logof];');
      step(
        '[logof]overlay=${_n(g.logoVisible.left)}:${_n(g.capsule.top)}-h',
      );
    }
  }

  String videoLabel;
  var graph = fc.toString();
  if (clockFontFile != null) {
    final epoch = exportStart.millisecondsSinceEpoch ~/ 1000;
    final epochUs = epoch * 1000000;
    final epochMod = epoch % 6;
    final capCx = _n(g.capsule.left + g.capsuleW / 2);
    final capY = _n(g.capsule.top);
    graph =
        '${graph}${cur}settb=AVTB,setpts=\'PTS-STARTPTS+$epochUs\'[sh];'
        '[sh]drawtext=fontfile=${clockFontFile.replaceAll(':', '\\:')}'
        ":text='%{pts\\\\:localtime\\\\:0\\\\:%r}'"
        ':fontsize=${g.clockFont.round()}:fontcolor=white'
        ":x='$capCx-text_w/2'"
        ":y='$capY+(${_n(g.capsuleH)}-text_h)/2'"
        ":enable='lt(mod(t-$epochMod\\,6)\\,3)'[sh2];"
        '[sh2]setpts=PTS-STARTPTS[vout]';
    videoLabel = '[vout]';
  } else {
    // Drop the trailing ';' of the last overlay step.
    graph = graph.endsWith(';') ? graph.substring(0, graph.length - 1) : graph;
    videoLabel = cur;
  }

  buf.write('-filter_complex "$graph" ');
  buf.write('-map "$videoLabel" -map 0:a? ');
  final videoArgs = videoBitrateKbps == null
      ? '-c:v libx264 -preset veryfast -crf 23'
      : '-c:v libx264 -preset veryfast '
          '-b:v ${videoBitrateKbps}k '
          '-maxrate ${(videoBitrateKbps * 3 / 2).round()}k '
          '-bufsize ${videoBitrateKbps * 2}k';
  buf.write(
    '$videoArgs -c:a copy -movflags +faststart ${q(output)}',
  );
  return buf.toString();
}

/// True when [preset] is the stock Nigraan TV parity preset (the
/// Final template with the top ribbon off — criterion 2). The
/// animated pass itself runs for every 'nigraanFinal' export; this
/// helper is for callers that need the strict-parity check.
bool isParityPreset(ChannelPreset preset) =>
    preset.templateKind == 'nigraanFinal' && !preset.topRibbon.enabled;
