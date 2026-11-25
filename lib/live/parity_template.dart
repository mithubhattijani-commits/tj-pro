/// Final Template designs (v1.3.0, brief §9 + the 22 Nov 2026
/// rework) — the ONE source of truth for the Final template's two
/// selectable designs.
///
/// DEFAULT — 'final3' (user-declared FINAL 22 Nov 2026, demo v4):
/// the PUBLIC-News-style THREE-ribbon bottom stack measured from
/// the user's reference frame (720x119 crop): TOP ribbon slightly
/// thinner, YELLOW #FFC800 with BLACK headline text, carrying the
/// current/related URDU headline; MIDDLE ribbon the THICKEST, red
/// (sampled (136,12,3)), carrying the national URDU headline;
/// BOTTOM ribbon dark navy-black (sampled (8,30,70)) carrying the
/// international ENGLISH text as a continuously scrolling ticker.
/// Ribbon heights ratio 31:43:28 (fractions of frame WIDTH). The
/// DATE/TIME capsule sits ON the middle (red) ribbon at its right
/// end, bottom-aligned with the red ribbon's bottom edge, width =
/// the logo block width. The logo block sits directly ABOVE the
/// capsule (its bottom on the capsule top), width 232/1280 of the
/// frame, and the logo itself is the user's green-screen rotating
/// 3D-cube VIDEO (chromakeyed, solid alpha). No chips, no gold
/// edges — the ribbons are full-width headline bars and the logo
/// stack overlaps their right end. The Urdu ribbons carry their
/// headlines pinned (right-aligned) and scroll only when the text
/// overflows the text window left of the logo stack.
///
/// VARIANT — 'classic2': the v1.3.0 parity design, kept selectable:
/// TWO flush bottom ribbons of equal height — Urdu #3D5AFE over
/// English #EF0017 — both scrolling (Urdu rightward, English
/// leftward, gold-dot separators), black chips with GOLD text
/// (بریکنگ نیوز at the RIGHT of the Urdu ribbon, HEADLINES at the
/// LEFT of the English ribbon), the rotating logo at bottom-right
/// with its visible width 17.1% of the frame, and directly under
/// it a dark capsule that FLIPS between a ticking PKT clock
/// (drawtext `%{pts:localtime:%r}` over epoch-shifted PTS) and the
/// Urdu date, ~3 s each. Its reference is the channel's own
/// pipeline output (house style v8, user-approved 14 Nov 2026;
/// `make_reel.py` portrait + `make_news_video.py` landscape in the
/// 20 Nov backup pack).
///
/// This file holds: the pure [ParityGeometry], the dart:ui PNG
/// layer renderers (ribbon backgrounds, scrolling ticker strips,
/// static headline bars, chips, capsule bar + date face, the
/// classic optional top-ribbon still), and the FFmpeg command
/// builder that animates them. The widget preview
/// (nigraan_final_preview.dart) and the PIL tasalli check use the
/// same constants.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../services/asset_download_service.dart';
import '../services/ffmpeg_service.dart';
import 'news_template.dart' show NigraanFinalLayout;
import '../news/channel_preset.dart';
import '../news/element_override.dart';

/// Broadcast gold (#F5C542) — chips' text, ribbon top edges,
/// separators, capsule top line.
const int kParityGold = 0xFFF5C542;

/// Urdu ribbon colour (#3D5AFE) — the preset carries it; this is
/// the fallback when a preset colour is unset.
const int kParityUrduColor = 0xFF3D5AFE;

/// English ribbon colour (#EF0017) — classic2 design.
const int kParityEnglishColor = 0xFFEF0017;

/// Which Final-template design a [ParityGeometry] describes.
/// Mirrors [ChannelPreset.finalVariant] ('final3' / 'classic2').
enum ParityVariant {
  /// The default 3-ribbon PUBLIC-style stack (22 Nov 2026).
  final3,

  /// The v1.3.0 2-ribbon parity design.
  classic2;

  static ParityVariant fromId(String? id) =>
      id == kFinalVariantClassic2 ? ParityVariant.classic2 : ParityVariant.final3;
}

/// Pure reference geometry for a [width]x[height] frame.
///
/// Pixel constants come from the two reference renderers, which
/// work at 1080x1920 (portrait) and 1280x720 (landscape); [s] is
/// the scale against the orientation's reference width, so the
/// geometry reproduces both renderers exactly at their native
/// sizes and interpolates proportionally elsewhere.
///
/// The 'classic2' getters reproduce the v1.3.0 2-ribbon design;
/// the `f3*` getters + the variant-aware logo/capsule getters
/// describe the default 'final3' stack, whose proportions were
/// measured from the user's PUBLIC News frame (720x119 crop of a
/// 16:9 frame): ribbon heights 31:43:28 and the logo block 110
/// wide, all as fractions of the frame WIDTH (720 in the crop).
class ParityGeometry {
  ParityGeometry(this.width, this.height,
      {this.variant = ParityVariant.classic2,
      this.overrides = const {},
      this.tickerSpeedFactor = 1.0,
      this.tickerLoop = true});

  final double width;
  final double height;

  /// Build 13 (point #19): the project-level ticker speed
  /// factor (NewsProject.tickerSpeed, carried on the effective
  /// preset) — [scrollSpeed] is multiplied by it. Default 1.0 =
  /// the designed speed, so every pre-Build-13 caller renders
  /// identically.
  final double tickerSpeedFactor;

  /// Build 13 (point #19): false = the ticker strip plays ONE
  /// pass and stops (no wrap); true = the historic seamless
  /// loop.
  final bool tickerLoop;

  /// Which Final design this geometry describes.
  final ParityVariant variant;

  /// v1.5.0 (#33): per-element MANUAL overrides (News Maker),
  /// keyed by [NewsElement] id. DEFAULTS PRESERVED: an empty map
  /// (every pre-#33 caller) makes every getter below compute
  /// exactly the pre-#33 value — [_xform] returns its input
  /// untouched for an identity override and the size getters fall
  /// back to the unscaled formulas.
  final Map<String, ElementOverride> overrides;

  ElementOverride _ov(String id) =>
      overrides[id] ?? ElementOverride.identity;

  /// True when the user removed the element in the News Maker.
  bool isHidden(String id) => _ov(id).hidden;

  /// Applies [id]'s override to its DESIGNED rect: scale about
  /// the rect's centre, then translate by (dx · frame width,
  /// dy · frame height). Identity → [base] itself, untouched.
  ui.Rect _xform(ui.Rect base, String id) {
    final o = _ov(id);
    if (o.isIdentity) return base;
    final w = base.width * o.scale;
    final h = base.height * o.scale;
    final cx = base.center.dx + o.dx * width;
    final cy = base.center.dy + o.dy * height;
    return ui.Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h);
  }

  bool get isFinal3 => variant == ParityVariant.final3;

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

  /// The logo's VISIBLE width: classic2 — 185 px at 1080 wide,
  /// 219 at 1280 (both ≈17.1% of the frame width); final3 — the
  /// demo-v4 logo block, 232 px at 1280 wide (≈18.1%).
  /// The logo's DESIGNED visible width (pre-override).
  double get _logoBaseW =>
      isFinal3 ? width * (232 / 1280) : width * (185 / 1080);

  double get logoVisibleW =>
      _logoBaseW * _ov(NewsElement.logo).scale;

  /// The alpha .mov's union crop (488:382:195:57) scaled so its
  /// visible content (422x347 inside the crop, offset 29,13,
  /// bottom edge at 360) is exactly [logoVisibleW] wide.
  double get logoCropW => 488 * logoVisibleW / 422;
  double get logoCropH => 382 * logoVisibleW / 422;
  double get logoVisibleL => 29 * logoVisibleW / 422;
  double get logoVisibleBot => 360 * logoVisibleW / 422;
  double get logoVisibleH => 347 * logoVisibleW / 422;
  double get _logoVisibleBaseH => 347 * _logoBaseW / 422;
  double get _f3LogoBlockBaseH => _logoBaseW * (344 / 408);

  /// Right margin of the logo/capsule stack: classic2 — 24 px at
  /// reference; final3 — the reference block is FLUSH with the
  /// frame's right edge (margin 0).
  double get logoMargin => isFinal3 ? 0 : 24 * s;

  /// Capsule: same width as the visible logo; height — classic2:
  /// 47 px (portrait) / 39 px (landscape); final3: the reference
  /// date box's 14 px at 720 wide.
  double get _capsuleBaseW => _logoBaseW;
  double get _capsuleBaseH => isFinal3
      ? width * (14 / 720)
      : (portrait ? height * (47 / 1920) : height * (39 / 720));

  double get capsuleW => _capsuleBaseW * _ov(NewsElement.capsule).scale;
  double get capsuleH => _capsuleBaseH * _ov(NewsElement.capsule).scale;

  // ---- Rects (frame coordinates) ----

  ui.Rect get _englishBaseStrip =>
      ui.Rect.fromLTWH(0, height - ribbonH, width, ribbonH);
  ui.Rect get _urduBaseStrip =>
      ui.Rect.fromLTWH(0, height - 2 * ribbonH, width, ribbonH);

  ui.Rect get englishStrip =>
      _xform(_englishBaseStrip, NewsElement.bottomRibbon);
  ui.Rect get urduStrip =>
      _xform(_urduBaseStrip, NewsElement.middleRibbon);
  ui.Rect get urduChip => ui.Rect.fromLTWH(
        width - urduChipW,
        urduStrip.top,
        urduChipW,
        ribbonH,
      );
  ui.Rect get englishChip =>
      ui.Rect.fromLTWH(0, englishStrip.top, englishChipW, ribbonH);

  /// Capsule position. classic2: its bottom edge sits ON the Urdu
  /// ribbon's top edge, logo above it. final3 (demo v4 + user
  /// lift, 22 Nov 2026): the capsule sits ON the middle (red)
  /// ribbon at its right end, bottom-aligned with the red
  /// ribbon's bottom edge and then raised by [f3BlockLift]; the
  /// logo block sits directly above it.
  /// The capsule's DESIGNED rect (pre-override; the logo's base
  /// anchors to this, never to the adjusted capsule — the two
  /// elements move independently).
  ui.Rect get _capsuleBase => isFinal3
      ? ui.Rect.fromLTWH(
          width - _capsuleBaseW,
          _f3MidBaseStrip.bottom - _capsuleBaseH - f3BlockLift,
          _capsuleBaseW,
          _capsuleBaseH,
        )
      : ui.Rect.fromLTWH(
          width - logoMargin - _capsuleBaseW,
          _urduBaseStrip.top - _capsuleBaseH,
          _capsuleBaseW,
          _capsuleBaseH,
        );

  /// A hidden capsule parks a full frame below the picture: its
  /// PNG layers render blank and the clock drawtext lands
  /// off-frame — the element is gone from the export.
  ui.Rect get capsule => isHidden(NewsElement.capsule)
      ? _capsuleBase.translate(0, height + 100)
      : _xform(_capsuleBase, NewsElement.capsule);

  /// Where the logo's VISIBLE content lands. final3 (demo v4):
  /// directly above the capsule, its bottom edge ON the capsule
  /// top; classic2: above its capsule (bottom on the capsule top).
  ui.Rect get _logoBase => isFinal3
      ? ui.Rect.fromLTWH(
          width - _logoBaseW,
          _capsuleBase.top - _f3LogoBlockBaseH,
          _logoBaseW,
          _f3LogoBlockBaseH,
        )
      : ui.Rect.fromLTWH(
          _capsuleBase.left,
          _capsuleBase.top - _logoVisibleBaseH,
          _logoBaseW,
          _logoVisibleBaseH,
        );

  ui.Rect get logoVisible => _xform(_logoBase, NewsElement.logo);

  /// Overlay position for the scaled .mov crop: its visible part
  /// must land exactly on [logoVisible].
  double get logoCropX => logoVisible.left - logoVisibleL;
  double get logoCropY => logoVisible.bottom - logoVisibleBot;

  // ---- Motion / text metrics ----

  /// Ticker speed: 110 px/s scaled by frame width (brief §9.1),
  /// times the project's ticker speed factor (Build 13).
  double get scrollSpeed =>
      110 * width / 1080 * tickerSpeedFactor.clamp(0.25, 3.0);

  /// Gold-dot separator slot / radius (52 / 7 px at reference).
  double get sepSlot => 52 * s;
  double get dotR => 7 * s;

  /// Ribbon text sizes (fractions of the ribbon height — the
  /// reference's 36/29/34 px on a 64 px ribbon).
  double get urduFontAr =>
      ribbonH * (36 / 64) * _ov(NewsElement.headlineText).scale;
  double get urduFontLat =>
      ribbonH * (29 / 64) * _ov(NewsElement.headlineText).scale;
  double get englishFont =>
      ribbonH * (34 / 64) * _ov(NewsElement.tickerText).scale;

  /// Capsule clock size (the reference fits "12:59:59 PM" into the
  /// capsule; 0.55 of the capsule height reproduces its fitted
  /// 26 px on the 47 px portrait capsule).
  double get clockFont => capsuleH * 0.55;

  /// Scroll window of a ribbon = frame width minus its chip.
  double urduWindowW() => width - urduChipW;
  double englishWindowW() => width - englishChipW;

  // ---- Final 3-Ribbon geometry (variant final3) ----
  // Measured from the user's PUBLIC News frame (720x119 crop):
  // ribbon heights 31 (top) : 43 (middle) : 28 (bottom), all in
  // crop px, i.e. fractions of the frame WIDTH. The demo-v4
  // (user-declared FINAL, 22 Nov 2026) logo block is 232 wide at
  // 1280 (18.1% of W) and sits directly above the capsule, which
  // sits ON the red ribbon.

  /// The user's green-screen rotating-cube logo video: union crop
  /// of the chromakeyed content over the full 10 s (key 0x10C81C,
  /// similarity 0.22, blend 0.08) — 408x344 at (228,72) of the
  /// 848x478 source (the FINAL stabilized tagline logo, 22 Nov
  /// 2026: zoom removed, "عوام کی آواز" ribbon tagline, original
  /// colours). The export crops to this box, then scales it
  /// to the logo block.
  int get f3GsCropW => 408;
  int get f3GsCropH => 344;
  int get f3GsCropX => 228;
  int get f3GsCropY => 72;

  /// Height of the logo block on the template: the GS crop's
  /// aspect (344/408 ≈ 0.843) at the block width.
  double get f3LogoBlockH => logoVisibleW * (344 / 408);

  /// Extra lift of the final3 capsule+logo block (user order,
  /// 22 Nov 2026: "logo aur time capsule thora sa aur oper"):
  /// the whole block sits W × 10/1280 higher than the demo-v4
  /// position (≈10 px at 1280 wide, ≈8.4 px at 1080 wide). The
  /// capsule is raised by this much off the red ribbon's bottom
  /// edge — it still overlaps the red ribbon — and the logo
  /// block rides on the raised capsule top.
  double get f3BlockLift => width * (10 / 1280);

  double get _f3BaseTopH => width * (31 / 720);
  double get _f3BaseMidH => width * (43 / 720);
  double get _f3BaseBotH => width * (28 / 720);

  double get f3TopH => _f3BaseTopH * _ov(NewsElement.topRibbon).scale;
  double get f3MidH => _f3BaseMidH * _ov(NewsElement.middleRibbon).scale;
  double get f3BotH => _f3BaseBotH * _ov(NewsElement.bottomRibbon).scale;

  /// Top edge of the whole 3-ribbon stack (DESIGNED stack —
  /// overrides never re-stack the other bands).
  double get f3StackTop =>
      height - _f3BaseTopH - _f3BaseMidH - _f3BaseBotH;

  ui.Rect get _f3TopBaseStrip =>
      ui.Rect.fromLTWH(0, f3StackTop, width, _f3BaseTopH);
  ui.Rect get _f3MidBaseStrip => ui.Rect.fromLTWH(
      0, f3StackTop + _f3BaseTopH, width, _f3BaseMidH);
  ui.Rect get _f3BotBaseStrip =>
      ui.Rect.fromLTWH(0, height - _f3BaseBotH, width, _f3BaseBotH);

  ui.Rect get f3TopStrip => _xform(_f3TopBaseStrip, NewsElement.topRibbon);
  ui.Rect get f3MidStrip =>
      _xform(_f3MidBaseStrip, NewsElement.middleRibbon);
  ui.Rect get f3BotStrip =>
      _xform(_f3BotBaseStrip, NewsElement.bottomRibbon);

  /// Text window of the two Urdu ribbons: from the left edge to
  /// the logo stack (their headlines end at the logo block, like
  /// the reference). The bottom ticker runs the full width.
  double get f3TextWindowW => width - logoVisibleW;

  /// Ribbon text sizes (fractions of each ribbon's own height —
  /// the reference's headline ink fills roughly half its ribbon).
  double get f3TopFontAr => f3TopH * 0.52;
  double get f3TopFontLat => f3TopH * 0.42;
  double get f3MidFontAr =>
      f3MidH * 0.56 * _ov(NewsElement.headlineText).scale;
  double get f3MidFontLat =>
      f3MidH * 0.45 * _ov(NewsElement.headlineText).scale;
  double get f3BotFont =>
      f3BotH * 0.53 * _ov(NewsElement.tickerText).scale;

  // ---- Reporter (numainda) block (v1.5.1, fix #50) ----
  // Photo + name plate on the side OPPOSITE the logo, anchored to
  // the ribbon stack's top-left over the media (the NS6
  // composition: photo top-left, plate under it, the stack
  // untouched below). Pure
  // additions: nothing pre-#50 reads these getters, so every
  // existing render is unchanged; the block is drawn (preview +
  // export post-pass) only when a project carries a reporter
  // photo. The photo and the plate share the ONE reporter
  // override — they move / resize / hide as a single block.

  /// Photo width: the logo block's DESIGNED width — the two
  /// blocks balance each other across the frame.
  double get reporterPhotoW => _logoBaseW;

  /// Photo height: a near-square portrait box; the photo itself
  /// is cover-fitted into it.
  double get reporterPhotoH => reporterPhotoW * 1.08;

  /// Name plate height: a readable fraction of the bottom band.
  double get reporterPlateH =>
      (isFinal3 ? _f3BaseBotH : ribbonH) * 0.85;

  /// Name plate width: a third wider than the photo, centred on
  /// it (NS6), clamped to the frame.
  double get reporterPlateW {
    final w = reporterPhotoW * 1.3;
    return w > width ? width : w;
  }

  /// Left inset of the reporter block: final3's logo side is
  /// flush, so the reporter keeps a small inset; classic2 mirrors
  /// its logo margin.
  double get _reporterLeft => isFinal3 ? width * (10 / 720) : 24 * s;

  /// Top edge of the ribbon stack at its DESIGNED position —
  /// the reporter block anchors here (NS6 composition: the block
  /// floats over the media at the stack's top-left, its plate
  /// ENDING where the stack begins, so it never covers the
  /// ribbons, the ticker or its label chip).
  double get _stackTopBase =>
      isFinal3 ? _f3TopBaseStrip.top : _urduBaseStrip.top;

  ui.Rect get _reporterPhotoBase {
    final plateTop = _stackTopBase - reporterPlateH;
    // The plate straddles the photo's bottom edge: the photo's
    // bottom sits 35% of the plate height below the plate's top.
    final photoBottom = plateTop + reporterPlateH * 0.35;
    return ui.Rect.fromLTWH(
      _reporterLeft,
      photoBottom - reporterPhotoH,
      reporterPhotoW,
      reporterPhotoH,
    );
  }

  ui.Rect get _reporterPlateBase {
    final cx = _reporterPhotoBase.center.dx;
    var left = cx - reporterPlateW / 2;
    if (left < 0) left = 0;
    if (left > width - reporterPlateW) left = width - reporterPlateW;
    return ui.Rect.fromLTWH(
      left,
      _stackTopBase - reporterPlateH,
      reporterPlateW,
      reporterPlateH,
    );
  }

  /// The reporter photo's rect WITH its manual override applied
  /// (a hidden reporter parks a full frame below the picture,
  /// like the capsule).
  ui.Rect get reporterPhotoRect => isHidden(NewsElement.reporter)
      ? _reporterPhotoBase.translate(0, height + 100)
      : _xform(_reporterPhotoBase, NewsElement.reporter);

  /// The reporter name plate's rect (same override as the photo).
  ui.Rect get reporterPlateRect => isHidden(NewsElement.reporter)
      ? _reporterPlateBase.translate(0, height + 100)
      : _xform(_reporterPlateBase, NewsElement.reporter);

  /// Photo ∪ plate — the block's hit/selection rect.
  ui.Rect get reporterBlockRect =>
      reporterPhotoRect.expandToInclude(reporterPlateRect);
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

/// The final3 capsule's DATE face: the SHORT Urdu date (weekday +
/// day + month, no year) — the reference's date box is a thin
/// strip ("Thu 19-Nov"), so the long date would shrink to
/// illegibility inside it.
String parityShortUrduDate(DateTime d) {
  final weekday = _urduWeekdays[(d.weekday - 1).clamp(0, 6)];
  return '$weekday ${d.day} ${_urduMonths[(d.month - 1).clamp(0, 11)]}';
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
  double? fontAr,
  double? fontLat,
  int textColor = 0xFFFFFFFF,
  // v1.5.1 (fix #51): opt-in font-family overrides for a
  // project's chosen headline / ticker font (built-in registry
  // family or a user-uploaded font's FontLoader family). Null
  // (every pre-#51 caller) = the exact historic behaviour:
  // Arabic runs take the Kasheeda family when [fontReady],
  // Latin runs the default font.
  String? fontFamilyAr,
  String? fontFamilyLat,
  // v1.5.1 (fix #52): opt-in text shadows from a Text Style
  // recipe (shadow + glow). Null = historic rendering.
  List<ui.Shadow>? shadows,
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
      runs.add((bufArabic, buf.toString()));
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
        color: ui.Color(textColor),
        fontSize: arabic
            ? (fontAr ?? g.urduFontAr)
            : (fontLat ?? (urdu ? g.urduFontLat : g.englishFont)),
        fontWeight: ui.FontWeight.bold,
        fontFamily: arabic
            ? (fontFamilyAr ??
                (fontReady ? AssetDownloadService.kasheedaFamily : null))
            : fontFamilyLat,
        shadows: shadows,
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
/// the gold top edge (classic2 only — the final3 ribbons have no
/// gold edge; pass [goldEdge] false). [color] is the resolved
/// ribbon colour (see [ChannelPreset.designTopColor] etc.).
Future<File> renderParityRibbonBg({
  required Directory dir,
  required ParityGeometry g,
  required bool urdu,
  required int color,
  bool goldEdge = true,
  double? height,
  String? name,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final h = height ?? g.ribbonH;
  final rect = ui.Rect.fromLTWH(0, 0, g.width, h);
  canvas.drawRect(rect, ui.Paint()..color = ui.Color(color));
  if (goldEdge) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, g.width, g.goldEdge),
      ui.Paint()..color = const ui.Color(kParityGold),
    );
  }
  return _writePng(
    recorder,
    g.width.round(),
    h.ceil(),
    dir,
    name ?? (urdu ? 'parity_t1bg.png' : 'parity_t2bg.png'),
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
  double? height,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rH = height ?? g.ribbonH;
  final chipW = urdu ? g.urduChipW : g.englishChipW;
  final chipLeft = urdu ? g.width - chipW : 0.0;
  canvas.drawRect(
    ui.Rect.fromLTWH(chipLeft, 0, chipW, rH),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  // Gold divider on the inner edge.
  final divX = urdu ? chipLeft : chipW - g.goldEdge;
  canvas.drawRect(
    ui.Rect.fromLTWH(divX, 0, g.goldEdge, rH),
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
      fontSize: rH * 0.5,
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
      (rH - para.height) / 2 + (urdu ? rH * 0.06 : 0),
    ),
  );
  return _writePng(
    recorder,
    g.width.round(),
    rH.ceil(),
    dir,
    urdu ? 'parity_t1top.png' : 'parity_t2top.png',
  );
}

/// v1.5.1 (fix #49): the Final 3-Ribbon ticker's EDITABLE side
/// label as a chip layer (frame width x ribbon height, transparent
/// except the chip): a solid red chip at the LEFT of the bottom
/// band carrying the project's label in white bold — the NS6
/// composition. The chip's width is the classic English chip
/// width; the caller passes the same value as the ribbon's chipW
/// so the ticker strip scrolls in the window right of the chip.
/// The label's font shrinks until it fits (never truncated).
Future<File> renderParityLabelChip({
  required Directory dir,
  required ParityGeometry g,
  required String label,
  required double height,
  String? fontFamily,
  // v1.5.1 (fix #52): a Ticker Text Style's label background can
  // recolour the chip; the NS6 red is the default.
  int chipColor = 0xFFD50000,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final chipW = g.englishChipW;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, chipW, height),
    ui.Paint()..color = ui.Color(chipColor),
  );
  final maxW = chipW - 12 * g.s;
  var size = height * 0.53;
  ui.Paragraph para;
  while (true) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        textDirection:
            _hasArabic(label) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        maxLines: 1,
      ),
    );
    builder.pushStyle(
      ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: size,
        fontWeight: ui.FontWeight.bold,
        fontFamily: fontFamily,
      ),
    );
    builder.addText(label);
    para = builder.build();
    para.layout(ui.ParagraphConstraints(width: maxW));
    if (para.maxIntrinsicWidth <= maxW || size <= 8 * g.s) break;
    size -= 2 * g.s;
  }
  canvas.drawParagraph(
    para,
    ui.Offset(6 * g.s, (height - para.height) / 2),
  );
  return _writePng(
    recorder,
    g.width.round(),
    height.ceil(),
    dir,
    'parity_f3label.png',
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
  double? ribbonH,
  double? windowW,
  int dotColor = kParityGold,
  int textColor = 0xFFFFFFFF,
  double? fontAr,
  double? fontLat,
  String? name,
  // v1.5.1 (fix #51): opt-in font families (see _headlineParagraph).
  String? fontFamilyAr,
  String? fontFamilyLat,
  // v1.5.1 (fix #52): opt-in shadows (see _headlineParagraph).
  List<ui.Shadow>? shadows,
}) async {
  final rH = ribbonH ?? g.ribbonH;
  (ui.Paragraph, double, bool) buildOne(String h) {
    final r = _headlineParagraph(
      h,
      urdu: urdu,
      fontReady: fontReady,
      g: g,
      fontAr: fontAr,
      fontLat: fontLat,
      textColor: textColor,
      fontFamilyAr: fontFamilyAr,
      fontFamilyLat: fontFamilyLat,
      shadows: shadows,
    );
    return (r.$1, r.$2, _hasArabic(h));
  }

  final paras = <(ui.Paragraph, double, bool)>[
    for (final h in headlines) buildOne(h),
  ];
  final seqOnce = paras.fold<double>(0, (a, e) => a + e.$2 + 4) +
      g.sepSlot * paras.length;
  final window = windowW ?? (urdu ? g.urduWindowW() : g.englishWindowW());
  var reps = 1;
  while (seqOnce * reps < window * 2) {
    reps++;
  }
  final sw = seqOnce * reps;
  final stripW = (sw * 2).ceil();
  final stripH = rH.ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final gold = ui.Paint()..color = ui.Color(dotColor);
  void drawDot(double cx) {
    canvas.drawCircle(ui.Offset(cx, rH / 2), g.dotR, gold);
  }

  void drawHeadline((ui.Paragraph, double, bool) e, double x) {
    final (para, _, arabic) = e;
    // Ink-centred like the reference; Nastaleeq ink sits high in
    // its line box, so Arabic headlines nudge down a touch (the
    // same convention as the still renderer).
    final y = (rH - para.height) / 2 +
        (arabic ? rH * 0.06 : 0);
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
    name ?? (urdu ? 'parity_t1strip.png' : 'parity_t2strip.png'),
  );
  return (file, sw);
}

/// The ink width of ONE pass of [headlines] (no repetition) at a
/// ribbon's font sizes — the final3 Urdu ribbons compare this
/// against their text window to decide pinned vs scrolling.
double paritySequenceWidth({
  required ParityGeometry g,
  required bool urdu,
  required List<String> headlines,
  required bool fontReady,
  double? fontAr,
  double? fontLat,
  // v1.5.1 (fix #51): opt-in font families (see _headlineParagraph).
  String? fontFamilyAr,
  String? fontFamilyLat,
  // v1.5.1 (fix #52): opt-in shadows (see _headlineParagraph).
  List<ui.Shadow>? shadows,
}) {
  var w = 0.0;
  for (final h in headlines) {
    final r = _headlineParagraph(
      h,
      urdu: urdu,
      fontReady: fontReady,
      g: g,
      fontAr: fontAr,
      fontLat: fontLat,
      fontFamilyAr: fontFamilyAr,
      fontFamilyLat: fontFamilyLat,
      shadows: shadows,
    );
    w += r.$2 + 4;
  }
  return w + g.sepSlot * headlines.length;
}

/// A final3 Urdu ribbon's STATIC headline layer (full frame
/// width x ribbonH, transparent): the headlines drawn ONCE,
/// right-aligned so the last headline's ink ends at the text
/// window's right edge (the logo stack boundary), like the
/// reference. Used when the sequence fits the window; longer
/// sequences scroll via [renderParityStrip] instead.
Future<File> renderParityHeadlineStill({
  required Directory dir,
  required ParityGeometry g,
  required List<String> headlines,
  required bool fontReady,
  required double ribbonH,
  required double windowW,
  required double fontAr,
  required double fontLat,
  required String name,
  int textColor = 0xFFFFFFFF,
  // v1.5.1 (fix #51): opt-in font families (see _headlineParagraph).
  String? fontFamilyAr,
  String? fontFamilyLat,
  // v1.5.1 (fix #52): opt-in shadows (see _headlineParagraph).
  List<ui.Shadow>? shadows,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // Build right-to-left: cursor at the window's right edge (with
  // a small inset), each headline placed left of the previous,
  // dot separator between them — the separator follows the text
  // colour (black on the final3 yellow top ribbon, white on the
  // red middle ribbon).
  var x = windowW - 4 * g.s;
  final dotPaint = ui.Paint()..color = ui.Color(textColor);
  for (var i = headlines.length - 1; i >= 0; i--) {
    final (para, inkW, arabic) = () {
      final r = _headlineParagraph(
        headlines[i],
        urdu: true,
        fontReady: fontReady,
        g: g,
        fontAr: fontAr,
        fontLat: fontLat,
        textColor: textColor,
        fontFamilyAr: fontFamilyAr,
        fontFamilyLat: fontFamilyLat,
        shadows: shadows,
      );
      return (r.$1, r.$2, _hasArabic(headlines[i]));
    }();
    x -= inkW + 4;
    final y = (ribbonH - para.height) / 2 + (arabic ? ribbonH * 0.06 : 0);
    canvas.drawParagraph(para, ui.Offset(x, y));
    if (i > 0) {
      x -= g.sepSlot;
      canvas.drawCircle(ui.Offset(x + g.sepSlot / 2, ribbonH / 2), g.dotR, dotPaint);
    }
  }
  return _writePng(
    recorder,
    g.width.round(),
    ribbonH.ceil(),
    dir,
    name,
  );
}

/// Capsule bar layer (full frame): classic2 — dark translucent
/// rounded bar with a gold top line; final3 — the reference's
/// solid black date box with a small radius and NO gold line.
/// Both clock faces are drawn over it (drawtext time / PNG date).
Future<File> renderParityCapsuleBar({
  required Directory dir,
  required ParityGeometry g,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final cap = g.capsule;
  if (g.isFinal3) {
    final rrect = ui.RRect.fromRectAndRadius(
      cap,
      ui.Radius.circular(2 * g.s),
    );
    canvas.drawRRect(rrect, ui.Paint()..color = const ui.Color(0xFF000000));
    return _writePng(
      recorder,
      g.width.round(),
      g.height.round(),
      dir,
      'parity_capbar.png',
    );
  }
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
  // final3's thin date box takes the SHORT date (the reference's
  // "Thu 19-Nov" strip); classic2 keeps the long Urdu date.
  final text = g.isFinal3 ? parityShortUrduDate(now) : parityUrduDate(now);
  var size = g.isFinal3 ? cap.height * 0.76 : 30 * g.s;
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
    final floor = g.isFinal3 ? 8 * g.s : 18 * g.s;
    if (para.maxIntrinsicWidth <= cap.width - 20 * g.s || size <= floor) {
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

/// One ribbon's rendered layers for a parity export.
class ParityRibbonAssets {
  const ParityRibbonAssets({
    required this.bg,
    required this.y,
    this.strip,
    this.period = 0,
    this.still,
    this.chip,
    this.scrollRight = false,
    this.windowW = 0,
    this.chipW = 0,
    this.textDx = 0,
    this.textDy = 0,
  });

  /// Background layer (frame width x ribbon height).
  final File bg;

  /// Overlay y of the bg / strip / still / chip.
  final double y;

  /// Scrolling strip PNG (null when the ribbon is static).
  final File? strip;

  /// Scroll period of [strip] (its sequence width).
  final double period;

  /// Static headline layer (final3 Urdu ribbons whose text fits
  /// their window — they are pinned, not scrolling).
  final File? still;

  /// Chip layer (classic2's fixed chips; final3 — only the
  /// editable ticker label chip, fix #49).
  final File? chip;

  /// Strip motion: true = the Urdu formula (content moves
  /// RIGHT, starting from [windowW] − 2·period), false = the
  /// English formula (content moves LEFT, starting after
  /// [chipW]).
  final bool scrollRight;

  /// Scroll window width (the Urdu formula's base).
  final double windowW;

  /// Chip width the English formula starts after (classic2
  /// English ribbon; final3 — the label chip's width when a
  /// ticker label is set, else 0).
  final double chipW;

  /// v1.5.0 (#33): the TEXT layer's manual offset from the band
  /// (headline / ticker element overrides), in frame pixels.
  /// 0/0 = the designed position.
  final double textDx;
  final double textDy;
}

/// All rendered layers for one parity export.
class ParityAssets {
  const ParityAssets({
    required this.geometry,
    required this.ribbons,
    required this.capBar,
    required this.capDate,
    required this.topRibbon,
  });

  final ParityGeometry geometry;

  /// Ribbons in top-to-bottom stack order: classic2 =
  /// [urdu, english]; final3 = [top, mid, bot].
  final List<ParityRibbonAssets> ribbons;

  final File capBar;
  final File capDate;

  /// The classic2 OPTIONAL frame-top ribbon as a still layer.
  /// Null when disabled, and always null in final3 (its top
  /// ribbon lives in the stack, never at the frame top).
  final File? topRibbon;
}

/// Renders every parity layer for [preset] at [width]x[height],
/// in the preset's Final design ([ChannelPreset.finalVariant]).
/// Ribbon texts come from the preset's ribbons (falling back to
/// a placeholder line so the ribbons never render empty in a
/// stock export); [urduText]/[englishText] override the middle /
/// bottom ribbon texts (the reel export's per-story fills).
Future<ParityAssets> renderParityAssets({
  required Directory dir,
  required ChannelPreset preset,
  required int width,
  required int height,
  required DateTime now,
  required bool fontReady,
  String urduText = '',
  String englishText = '',
  Map<String, ElementOverride> overrides = const {},
  // v1.5.1 opt-ins (fixes #49 + #51), all defaulting to the
  // pre-#51 behaviour: [tickerLabel] — the project's EDITABLE
  // ticker side label; when non-empty (final3 only) the bottom
  // band gains its red label chip and the ticker scrolls in the
  // window right of it. [headlineFontFamily] / [tickerFontFamily]
  // — the project's chosen font families for the headline ribbons
  // / the ticker (null = the historic Kasheeda/default split).
  String? tickerLabel,
  String? headlineFontFamily,
  String? tickerFontFamily,
  // v1.5.1 (fix #52): opt-in Text Style colours from the Library
  // engine. [headlineTextColor] recolours the middle (headline)
  // band's text — the final3 TOP band keeps its design text
  // colour (black on yellow) so the style can never make it
  // unreadable; the style's font still applies there.
  // [tickerTextColor] recolours the ticker text + its separator
  // dots; [tickerLabelColor] is the label chip's background.
  int? headlineTextColor,
  int? tickerTextColor,
  int? tickerLabelColor,
  // v1.5.1 (fix #52): opt-in Text Style shadows (shadow + glow)
  // for the headline ribbons / the ticker. Null = no shadows.
  List<ui.Shadow>? headlineShadows,
  List<ui.Shadow>? tickerShadows,
}) async {
  final variant = ParityVariant.fromId(preset.finalVariant);
  final g = ParityGeometry(
    width.toDouble(),
    height.toDouble(),
    variant: variant,
    overrides: overrides,
    tickerSpeedFactor: preset.tickerSpeedFactor,
    tickerLoop: preset.tickerLoop,
  );
  final urdu = urduText.trim().isNotEmpty
      ? urduText.trim()
      : preset.urduRibbon.text.trim();
  final english = englishText.trim().isNotEmpty
      ? englishText.trim()
      : preset.englishRibbon.text.trim();
  final capBar = await renderParityCapsuleBar(dir: dir, g: g);
  final capDate = await renderParityCapsuleDate(
    dir: dir,
    g: g,
    now: now,
    fontReady: fontReady,
  );

  if (variant == ParityVariant.classic2) {
    final showUrduBand = !g.isHidden(NewsElement.middleRibbon);
    final showEnglishBand = !g.isHidden(NewsElement.bottomRibbon);
    final showUrduText = !g.isHidden(NewsElement.headlineText);
    final showEnglishText = !g.isHidden(NewsElement.tickerText);
    final headOv = g._ov(NewsElement.headlineText);
    final tickOv = g._ov(NewsElement.tickerText);
    final ribbons = <ParityRibbonAssets>[];
    if (showUrduBand) {
      final t1bg = await renderParityRibbonBg(
        dir: dir,
        g: g,
        urdu: true,
        color: preset.designUrduColor,
        height: g.urduStrip.height,
      );
      final t1chip = await renderParityChip(
        dir: dir,
        g: g,
        urdu: true,
        fontReady: fontReady,
        height: g.urduStrip.height,
      );
      if (showUrduText) {
        final (t1strip, t1Period) = await renderParityStrip(
          dir: dir,
          g: g,
          urdu: true,
          headlines:
              paritySplitHeadlines(urdu.isEmpty ? 'قومی خبریں' : urdu),
          fontReady: fontReady,
          ribbonH: g.urduStrip.height,
          textColor: headlineTextColor ?? 0xFFFFFFFF,
          fontAr: g.urduFontAr,
          fontLat: g.urduFontLat,
          fontFamilyAr: headlineFontFamily,
          fontFamilyLat: headlineFontFamily,
          shadows: headlineShadows,
        );
        ribbons.add(ParityRibbonAssets(
          bg: t1bg,
          y: g.urduStrip.top,
          strip: t1strip,
          period: t1Period,
          chip: t1chip,
          scrollRight: true,
          windowW: g.urduWindowW(),
          textDx: headOv.dx * g.width,
          textDy: headOv.dy * g.height,
        ));
      } else {
        ribbons.add(ParityRibbonAssets(
          bg: t1bg,
          y: g.urduStrip.top,
          chip: t1chip,
        ));
      }
    }
    if (showEnglishBand) {
      final t2bg = await renderParityRibbonBg(
        dir: dir,
        g: g,
        urdu: false,
        color: preset.designEnglishColor,
        height: g.englishStrip.height,
      );
      final t2chip = await renderParityChip(
        dir: dir,
        g: g,
        urdu: false,
        fontReady: fontReady,
        height: g.englishStrip.height,
      );
      if (showEnglishText) {
        final (t2strip, t2Period) = await renderParityStrip(
          dir: dir,
          g: g,
          urdu: false,
          headlines: paritySplitHeadlines(
              english.isEmpty ? 'International headlines' : english),
          fontReady: fontReady,
          ribbonH: g.englishStrip.height,
          // The renderer's own defaults for an English strip:
          // Arabic runs take urduFontAr, Latin runs englishFont —
          // passed explicitly so the values are the geometry's
          // (override-scaled) ones, identical when no override.
          fontAr: g.urduFontAr,
          fontLat: g.englishFont,
          fontFamilyAr: tickerFontFamily,
          fontFamilyLat: tickerFontFamily,
          textColor: tickerTextColor ?? 0xFFFFFFFF,
          shadows: tickerShadows,
        );
        ribbons.add(ParityRibbonAssets(
          bg: t2bg,
          y: g.englishStrip.top,
          strip: t2strip,
          period: t2Period,
          chip: t2chip,
          chipW: g.englishChipW,
          textDx: tickOv.dx * g.width,
          textDy: tickOv.dy * g.height,
        ));
      } else {
        ribbons.add(ParityRibbonAssets(
          bg: t2bg,
          y: g.englishStrip.top,
          chip: t2chip,
        ));
      }
    }
    final top = preset.topRibbon.enabled &&
            !g.isHidden(NewsElement.topRibbon)
        ? await renderParityTopRibbon(
            dir: dir,
            g: g,
            preset: preset,
            fontReady: fontReady,
          )
        : null;
    return ParityAssets(
      geometry: g,
      ribbons: ribbons,
      capBar: capBar,
      capDate: capDate,
      topRibbon: top,
    );
  }

  // ---- final3 (default): the 3-ribbon PUBLIC-style stack. ----
  // v1.5.0 (#33): a band the user removed is skipped entirely; a
  // TEXT element the user removed leaves its band bare; text
  // offsets ride on the assets. No overrides → the exact
  // pre-#33 asset list.
  final headOv = g._ov(NewsElement.headlineText);
  final tickOv = g._ov(NewsElement.tickerText);
  final ribbons = <ParityRibbonAssets>[];

  // One Urdu stack ribbon: pinned still when its headlines fit
  // the text window, a looping strip when they overflow.
  Future<ParityRibbonAssets> urduStackRibbon({
    required File bg,
    required double y,
    required double ribbonH,
    required String text,
    required String fallback,
    required double fontAr,
    required double fontLat,
    required String tag,
    int textColor = 0xFFFFFFFF,
    bool showText = true,
    double textDx = 0,
    double textDy = 0,
    // v1.5.1 (fix #51): the project's headline font family.
    String? fontFamily,
    // v1.5.1 (fix #52): the headline Text Style's shadows.
    List<ui.Shadow>? shadows,
  }) async {
    if (!showText) {
      return ParityRibbonAssets(bg: bg, y: y);
    }
    final headlines =
        paritySplitHeadlines(text.isEmpty ? fallback : text);
    final seqW = paritySequenceWidth(
      g: g,
      urdu: true,
      headlines: headlines,
      fontReady: fontReady,
      fontAr: fontAr,
      fontLat: fontLat,
      fontFamilyAr: fontFamily,
      fontFamilyLat: fontFamily,
      shadows: shadows,
    );
    if (seqW <= g.f3TextWindowW) {
      final still = await renderParityHeadlineStill(
        dir: dir,
        g: g,
        headlines: headlines,
        fontReady: fontReady,
        ribbonH: ribbonH,
        windowW: g.f3TextWindowW,
        fontAr: fontAr,
        fontLat: fontLat,
        name: 'parity_f3${tag}still.png',
        textColor: textColor,
        fontFamilyAr: fontFamily,
        fontFamilyLat: fontFamily,
        shadows: shadows,
      );
      return ParityRibbonAssets(
        bg: bg,
        y: y,
        still: still,
        textDx: textDx,
        textDy: textDy,
      );
    }
    final (strip, period) = await renderParityStrip(
      dir: dir,
      g: g,
      urdu: true,
      headlines: headlines,
      fontReady: fontReady,
      ribbonH: ribbonH,
      windowW: g.f3TextWindowW,
      dotColor: textColor,
      textColor: textColor,
      fontAr: fontAr,
      fontLat: fontLat,
      fontFamilyAr: fontFamily,
      fontFamilyLat: fontFamily,
      shadows: shadows,
      name: 'parity_f3${tag}strip.png',
    );
    return ParityRibbonAssets(
      bg: bg,
      y: y,
      strip: strip,
      period: period,
      scrollRight: true,
      windowW: g.f3TextWindowW,
      textDx: textDx,
      textDy: textDy,
    );
  }

  if (!g.isHidden(NewsElement.topRibbon)) {
    final topBg = await renderParityRibbonBg(
      dir: dir,
      g: g,
      urdu: true,
      color: preset.designTopColor,
      goldEdge: false,
      height: g.f3TopH,
      name: 'parity_f3topbg.png',
    );
    ribbons.add(await urduStackRibbon(
      bg: topBg,
      y: g.f3TopStrip.top,
      ribbonH: g.f3TopH,
      text: preset.topRibbon.text.trim(),
      fallback: 'موجودہ خبر',
      fontAr: g.f3TopFontAr,
      fontLat: g.f3TopFontLat,
      tag: 'top',
      // Yellow design top ribbon → BLACK headline text (and dots);
      // a user-customised top colour keeps white text.
      textColor: preset.designTopTextColor,
      fontFamily: headlineFontFamily,
      shadows: headlineShadows,
    ));
  }
  if (!g.isHidden(NewsElement.middleRibbon)) {
    final midBg = await renderParityRibbonBg(
      dir: dir,
      g: g,
      urdu: true,
      color: preset.designUrduColor,
      goldEdge: false,
      height: g.f3MidH,
      name: 'parity_f3midbg.png',
    );
    ribbons.add(await urduStackRibbon(
      bg: midBg,
      y: g.f3MidStrip.top,
      ribbonH: g.f3MidH,
      text: urdu,
      fallback: 'قومی خبریں',
      fontAr: g.f3MidFontAr,
      fontLat: g.f3MidFontLat,
      tag: 'mid',
      showText: !g.isHidden(NewsElement.headlineText),
      textDx: headOv.dx * g.width,
      textDy: headOv.dy * g.height,
      fontFamily: headlineFontFamily,
      // Fix #52: a headline Text Style's colour lands here (the
      // default stays white).
      textColor: headlineTextColor ?? 0xFFFFFFFF,
      shadows: headlineShadows,
    ));
  }
  if (!g.isHidden(NewsElement.bottomRibbon)) {
    final botBg = await renderParityRibbonBg(
      dir: dir,
      g: g,
      urdu: false,
      color: preset.designEnglishColor,
      goldEdge: false,
      height: g.f3BotH,
      name: 'parity_f3botbg.png',
    );
    if (g.isHidden(NewsElement.tickerText)) {
      ribbons.add(ParityRibbonAssets(bg: botBg, y: g.f3BotStrip.top));
    } else {
      // Bottom: the international ENGLISH ticker — always
      // scrolling, white dot separators. v1.5.1 (fix #49): with
      // an editable side label the band gains its red label chip
      // and the ticker scrolls in the window RIGHT of the chip
      // (the command's LTR formula starts the strip after
      // chipW); without a label the ticker keeps the full width,
      // exactly as before.
      final label = (tickerLabel ?? '').trim();
      final hasLabel = label.isNotEmpty;
      final botWindowW = hasLabel ? g.width - g.englishChipW : g.width;
      final (botStrip, botPeriod) = await renderParityStrip(
        dir: dir,
        g: g,
        urdu: false,
        headlines: paritySplitHeadlines(
            english.isEmpty ? 'International headlines' : english),
        fontReady: fontReady,
        ribbonH: g.f3BotH,
        windowW: botWindowW,
        dotColor: tickerTextColor ?? 0xFFFFFFFF,
        textColor: tickerTextColor ?? 0xFFFFFFFF,
        fontAr: g.f3BotFont,
        fontLat: g.f3BotFont,
        fontFamilyAr: tickerFontFamily,
        fontFamilyLat: tickerFontFamily,
        shadows: tickerShadows,
        name: 'parity_f3botstrip.png',
      );
      final botChip = hasLabel
          ? await renderParityLabelChip(
              dir: dir,
              g: g,
              label: label,
              height: g.f3BotH,
              fontFamily: tickerFontFamily,
              chipColor: tickerLabelColor ?? 0xFFD50000,
            )
          : null;
      ribbons.add(ParityRibbonAssets(
        bg: botBg,
        y: g.f3BotStrip.top,
        strip: botStrip,
        period: botPeriod,
        chip: botChip,
        chipW: hasLabel ? g.englishChipW : 0,
        windowW: botWindowW,
        textDx: tickOv.dx * g.width,
        textDy: tickOv.dy * g.height,
      ));
    }
  }
  return ParityAssets(
    geometry: g,
    ribbons: ribbons,
    capBar: capBar,
    capDate: capDate,
    topRibbon: null,
  );
}

String _n(double v) =>
    v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

/// The alpha .mov's opaque bbox for the PARITY graph
/// (crop=488:382:195:57 — the reference crop). Callers
/// rendering a parity ping-pong cycle pass these to
/// [FfmpegService.logoPingPongCycleCommand].
const int kParityLogoCropW = 488;
const int kParityLogoCropH = 382;
const int kParityLogoCropX = 195;
const int kParityLogoCropY = 57;

/// The animated parity overlay command: the ribbons scroll
/// seamlessly in the reference directions (classic2: both;
/// final3: the bottom ticker always, the Urdu ribbons only when
/// their text overflows), the logo stack sits at the right (the
/// .mov's pre-rendered ping-pong cycle is overlaid TWICE, as
/// the reference), and
/// the capsule flips DATE ↔ TIME (drawtext over epoch-shifted
/// PTS, ticking 1 s per video second) every ~3 s — classic2 shows
/// TIME first, final3 shows DATE first (its reference box is a
/// date box).
///
/// Logo source — exactly one of:
/// * [logoGsPath]: the user's green-screen rotating-cube logo
///   VIDEO (final3 default, demo v4): chromakeyed (0x10C81C,
///   0.22/0.08), despilled, cropped to the keyed union, scaled to
///   the logo block and alpha-hardened so it reads SOLID, looped
///   for the export duration. Takes precedence over the cycle.
/// * [logoPingPongPath]: a FINITE pre-rendered ping-pong cycle
///   of the alpha .mov (see
///   [FfmpegService.logoPingPongCycleCommand]; hotfix audit C3 —
///   the in-graph `reverse` over a `-stream_loop -1` input
///   buffered without bound and killed exports mid-run).
/// * [logoFramesDir]: generated rotating frames (user/default logo).
/// * [logoStillPng]: a static logo image (last-resort fallback).
/// When all four are null the logo stack is skipped (the capsule
/// still renders) and the caller notes it.
///
/// [clockFontFile] null skips the TIME face (the DATE face still
/// flips in) — the caller notes it.
String buildParityTemplateCommand({
  required String input,
  required String output,
  required ParityAssets assets,
  String? logoGsPath,
  String? logoPingPongPath,
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

  // Assign an input index per layer, in stack order.
  final ribbonInputs = <(ParityRibbonAssets, int, int?, int?, int?)>[];
  for (final r in assets.ribbons) {
    final iBg = next(r.bg);
    final iStrip = r.strip == null ? null : next(r.strip!);
    final iStill = r.still == null ? null : next(r.still!);
    final iChip = r.chip == null ? null : next(r.chip!);
    ribbonInputs.add((r, iBg, iStrip, iStill, iChip));
  }
  final iCapBar = next(assets.capBar);
  final iCapDate = next(assets.capDate);
  final iTop = assets.topRibbon == null ? null : next(assets.topRibbon!);
  int? iLogo;
  if (logoGsPath != null) {
    // The green-screen logo video is 10 s — loop it for the whole
    // export, like the .mov below.
    buf.write('-stream_loop -1 -i ${q(logoGsPath)} ');
    iLogo = idx++;
  } else if (logoPingPongPath != null) {
    buf.write('-stream_loop -1 -i ${q(logoPingPongPath)} ');
    iLogo = idx++;
  } else if (logoFramesDir != null) {
    buf.write('-framerate 12 -stream_loop -1 -i ${q('$logoFramesDir/frame_%02d.png')} ');
    iLogo = idx++;
  } else if (logoStillPng != null) {
    buf.write('-i ${q(logoStillPng)} ');
    iLogo = idx++;
  }

  final speed = _n(g.scrollSpeed);

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

  // Reference overlay-x formulas (make_reel.py): an RTL strip
  // starts at (window − 2·period) and advances mod(t·speed,
  // period) — content moves RIGHT; an LTR strip starts after its
  // chip and retreats — content moves LEFT.
  for (final (r, iBg, iStrip, iStill, iChip) in ribbonInputs) {
    final y = _n(r.y);
    step('[$iBg:v]overlay=0:$y');
    if (iStill != null) {
      // v1.5.0 (#33): the still TEXT layer carries its own manual
      // offset (0/0 = designed — the pre-#33 command string).
      step('[$iStill:v]overlay=${_n(r.textDx)}:${_n(r.y + r.textDy)}');
    } else if (iStrip != null) {
      // Build 13 (point #19): loop OFF replaces the mod() wrap
      // with a min() clamp — the strip travels exactly one
      // period and then stays past the window (single pass).
      final x = g.tickerLoop
          ? (r.scrollRight
              ? '${_n(r.textDx + r.windowW - 2 * r.period)}+mod(t*$speed\\,${_n(r.period)})'
              : '${_n(r.textDx + r.chipW)}-mod(t*$speed\\,${_n(r.period)})')
          : (r.scrollRight
              ? '${_n(r.textDx + r.windowW - 2 * r.period)}+min(t*$speed\\,${_n(r.period)})'
              : '${_n(r.textDx + r.chipW)}-min(t*$speed\\,${_n(r.period)})');
      step("[$iStrip:v]overlay=x='$x':y=${_n(r.y + r.textDy)}");
    }
    if (iChip != null) {
      step('[$iChip:v]overlay=0:$y');
    }
  }
  step('[$iCapBar:v]overlay=0:0');
  // Capsule faces: classic2 = TIME 0–3 s, DATE 3–6 s; final3 =
  // DATE first (its box is a date box), TIME second.
  step("[$iCapDate:v]overlay=0:0:enable='${g.isFinal3 ? 'lt' : 'gte'}(mod(t\\,6)\\,3)'");
  if (iTop != null) {
    step('[$iTop:v]overlay=0:0');
  }
  if (iLogo != null) {
    if (logoGsPath != null) {
      // Green-screen rotating-cube logo video (final3 default):
      // chromakey the green out, despill, crop to the keyed
      // content's union box, scale to the logo block, then HARDEN
      // the alpha — a soft key read as "transparent" in the demo,
      // so the alpha is thresholded to solid (values >70 → 255)
      // with only a ~1 px soft edge (0.6 sigma blur) kept.
      fc.write(
        '[$iLogo:v]chromakey=0x10C81C:0.22:0.08,despill=type=green,'
        'crop=${g.f3GsCropW}:${g.f3GsCropH}:${g.f3GsCropX}:${g.f3GsCropY},'
        'format=yuva420p,scale=${g.logoVisibleW.round()}:${g.f3LogoBlockH.round()},'
        'split[gsrgb][gsa];'
        '[gsa]alphaextract,lut=a=\'if(gt(val\\,70)\\,255\\,0)\','
        'gblur=sigma=0.6[gsah];'
        '[gsrgb][gsah]alphamerge[gsout];',
      );
      step('[gsout]overlay=${_n(g.logoVisible.left)}:${_n(g.logoVisible.top)}');
    } else if (logoPingPongPath != null) {
      // Hotfix (audit C3): the cycle file already carries the
      // reference crop (488:382:195:57) AND the forward+reverse
      // ping-pong — the graph only scales it and splits it for
      // the reference's double overlay. The old in-graph
      // `reverse` over the `-stream_loop -1` mov input buffered
      // the endless stream until the process died.
      fc.write(
        '[$iLogo:v]format=yuva420p,'
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
        '$graph${cur}settb=AVTB,setpts=\'PTS-STARTPTS+$epochUs\'[sh];'
        '[sh]drawtext=fontfile=${clockFontFile.replaceAll(':', '\\:')}'
        ":text='%{pts\\\\:localtime\\\\:0\\\\:%r}'"
        ':fontsize=${g.clockFont.round()}:fontcolor=white'
        ":x='$capCx-text_w/2'"
        ":y='$capY+(${_n(g.capsuleH)}-text_h)/2'"
        ":enable='${g.isFinal3 ? 'gte' : 'lt'}(mod(t-$epochMod\\,6)\\,3)'[sh2];"
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

/// True when [preset] uses a Final parity design (either the
/// default 'final3' stack or the 'classic2' 2-ribbon variant).
/// The animated pass runs for every 'nigraanFinal' export; this
/// helper is for callers that need the design check.
bool isParityPreset(ChannelPreset preset) =>
    preset.templateKind == 'nigraanFinal';
