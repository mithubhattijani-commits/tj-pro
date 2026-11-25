/// Live Flutter preview of the Nigraan final template — the
/// on-screen twin of the parity renderer in
/// lib/live/parity_template.dart ([ParityGeometry], same house
/// colours, same chip labels). Used by the Template & Studio
/// screen (full preview + the paste-to-run ticker strip) and the
/// News Studio home preview.
///
/// TICKER PASTE-TO-RUN: the top ticker scrolls from the preset's
/// live text — [ScrollingTickerText] re-measures and restarts its
/// animation on every text change, so a paste scrolls in the
/// preview IMMEDIATELY, with no extra step. Since v1.3.0 the two
/// bottom ribbons scroll in the preview too, exactly like the
/// export (Urdu rightward, English leftward).
///
/// Two Final designs (the preset's `finalVariant`): the DEFAULT
/// 'final3' 3-ribbon stack (navy current-Urdu ribbon on a thick
/// red national-Urdu ribbon on a dark English ticker, logo + DATE
/// capsule at the stack's right) and 'classic2', the v1.3.0
/// 2-ribbon parity design. This widget branches on the variant;
/// the geometry comes from the same [ParityGeometry] either way.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../live/news_template.dart';
import '../../live/parity_template.dart';
import '../../services/asset_download_service.dart';
import '../channel_preset.dart';
import '../element_override.dart';
import '../logo_parts.dart';
import '../watermark.dart';
import 'keyed_logo_flipbook.dart';
import 'pip_inset.dart';
import 'reporter_overlay.dart';
import 'rotating_logo.dart';

/// Horizontally scrolling ticker line.
///
/// Measures its own text with a [TextPainter] after layout and
/// animates a seamless loop: RTL text enters from the right and exits
/// left, LTR text enters from the left and exits right. Any change to
/// [text], [speed] or [direction] re-measures and restarts the loop
/// on the next frame — that is the paste-to-run contract.
class ScrollingTickerText extends StatefulWidget {
  const ScrollingTickerText({
    super.key,
    required this.text,
    required this.speed,
    required this.direction,
    required this.style,
    this.loop = true,
  });

  final String text;
  final double speed;
  final RibbonDirection direction;
  final TextStyle style;

  /// Build 13 (point #19): false = scroll ONE pass, then hold
  /// (the project's ticker-loop setting). Default true = the
  /// historic seamless loop.
  final bool loop;

  @override
  State<ScrollingTickerText> createState() => _ScrollingTickerTextState();
}

class _ScrollingTickerTextState extends State<ScrollingTickerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  double _textWidth = 0;
  double _viewWidth = 0;
  String _measuredText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measureAndRestart(),
    );
  }

  @override
  void didUpdateWidget(ScrollingTickerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.speed != widget.speed ||
        oldWidget.direction != widget.direction ||
        oldWidget.style != widget.style ||
        oldWidget.loop != widget.loop) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _measureAndRestart(),
      );
    }
  }

  void _measureAndRestart() {
    if (!mounted) return;
    final viewWidth = context.size?.width ?? 0;
    if (viewWidth <= 0 || widget.text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: widget.direction == RibbonDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final changed = painter.width != _textWidth ||
        viewWidth != _viewWidth ||
        _measuredText != widget.text;
    _textWidth = painter.width;
    _viewWidth = viewWidth;
    _measuredText = widget.text;
    if (changed) _restart();
  }

  void _restart() {
    if (_textWidth <= 0 || _viewWidth <= 0) return;
    final distance = _textWidth + _viewWidth;
    final pxPerSec = 90.0 * widget.speed.clamp(0.25, 3.0);
    final seconds = (distance / pxPerSec).clamp(3.0, 180.0);
    _controller.duration =
        Duration(milliseconds: (seconds * 1000).round());
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) {
      return Text(
        'Ticker text yahan paste karein…',
        style: widget.style.copyWith(color: Colors.white70),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final double x;
          if (widget.direction == RibbonDirection.ltr) {
            // Enters from the left, exits right.
            x = -_textWidth + progress * (_textWidth + _viewWidth);
          } else {
            // Enters from the right, exits left.
            x = _viewWidth - progress * (_textWidth + _viewWidth);
          }
          return Transform.translate(offset: Offset(x, 0), child: child);
        },
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
          textDirection: widget.direction == RibbonDirection.rtl
              ? TextDirection.rtl
              : TextDirection.ltr,
        ),
      ),
    );
  }
}

/// Intrinsic width of one line of [text] at [fontSize], bold.
/// Shared with [BreakingTemplatePreview] (breaking_preview.dart).
double measurePreviewTextWidth(String text, double fontSize) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
    ),
    textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(text)
        ? TextDirection.rtl
        : TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// Shrinks [fontSize] (never below 60%) until [text] + its chip
/// padding fits [maxWidth]. A fixed broadcast label (BREAKING NEWS,
/// تازہ ترین) must never be cut — it gets smaller instead (§14
/// rule 4: no truncation). Shared with breaking_preview.dart.
double fitPreviewChipFontSize(String text, double fontSize, double maxWidth) {
  final w = measurePreviewTextWidth(text, fontSize) + 20;
  if (w <= maxWidth) return fontSize;
  return (fontSize * (maxWidth - 20) / measurePreviewTextWidth(text, fontSize))
      .clamp(fontSize * 0.6, fontSize);
}

/// Full template preview (9:16 frame).
///
/// The preview mirrors the template the export renders — the
/// same geometry ([ParityGeometry] in lib/live/parity_template.dart)
/// for BOTH Final designs. classic2 (v1.3.0 §9 parity): two
/// FLUSH, equal-height bottom ribbons; the Urdu chip at the RIGHT
/// with GOLD text; the English chip at the left with GOLD text;
/// BOTH ribbons SCROLL (Urdu rightward, English leftward) with
/// gold-dot separators; the logo sits bottom-right with the
/// flipping TIME (with seconds) <-> Urdu DATE capsule directly
/// under it; the optional top ticker scrolls at the frame top.
/// final3 (the DEFAULT, user-declared FINAL 22 Nov 2026, demo
/// v4): the 3-ribbon bottom stack — YELLOW current-Urdu ribbon
/// (thinner) with BLACK headline text, thick red national-Urdu
/// ribbon, dark English ticker scrolling continuously; the Urdu
/// headlines sit pinned right-aligned when they fit the window
/// left of the logo stack and scroll on overflow; NO chips; the
/// DATE/TIME capsule sits ON the middle (red) ribbon at its right
/// end, bottom-aligned with the red ribbon's bottom edge, and the
/// logo block (the user's green-screen rotating-cube video, shown
/// here as its keyed first frame) sits directly above the capsule.
/// Ribbon heights carry a small legibility floor at preview sizes
/// (the export uses the exact fractions).
/// v1.5.0 (#33): applies a TEXT element's manual offset + size
/// to its preview content (identity → the child untouched).
Widget _overrideTransform(
  ElementOverride o,
  double frameW,
  double frameH,
  Widget child,
) {
  if (o.isIdentity) return child;
  return Transform.translate(
    offset: Offset(o.dx * frameW, o.dy * frameH),
    child: Transform.scale(scale: o.scale, child: child),
  );
}

class NigraanFinalPreview extends StatelessWidget {
  const NigraanFinalPreview({
    super.key,
    required this.preset,
    this.fontReady = false,
    this.height = 320,
    this.elementOverrides = const {},
    this.tickerLabel,
    this.headlineFontFamily,
    this.tickerFontFamily,
    this.headlineTextColor,
    this.tickerTextColor,
    this.tickerLabelColor,
    this.headlineShadows,
    this.tickerShadows,
    this.reporterPhotoPath,
    this.reporterName,
    this.reporterFontFamily,
    this.logoRotate = true,
  });

  final ChannelPreset preset;
  final bool fontReady;
  final double height;

  /// v1.5.0 (#33): per-project MANUAL element overrides (News
  /// Maker). DEFAULTS PRESERVED: the default empty map makes
  /// every position/size below compute exactly the pre-#33
  /// value (the geometry is constructed without overrides and
  /// every adjustment term is 0 / 1).
  final Map<String, ElementOverride> elementOverrides;

  /// v1.5.1 (fix #49): the project's EDITABLE ticker side label.
  /// Null/empty = no label chip (the pre-#49 render). final3: a
  /// red chip at the LEFT of the bottom band, the ticker scrolling
  /// right of it; classic2: it replaces the fixed 'HEADLINES'
  /// chip text.
  final String? tickerLabel;

  /// v1.5.1 (fixes #51/#52): the project's chosen font families
  /// for the headline ribbons / the ticker (null = the historic
  /// Kasheeda-when-ready behaviour — the caller resolves the
  /// house-default font id to null so the default render is
  /// byte-identical).
  final String? headlineFontFamily;
  final String? tickerFontFamily;

  /// v1.5.1 (fix #52): Text Style colours (ARGB) for the headline
  /// band's text / the ticker text / the label chip's background.
  /// Null = the design colours.
  final int? headlineTextColor;
  final int? tickerTextColor;
  final int? tickerLabelColor;

  /// v1.5.1 (fix #52): Text Style shadow/glow for the headline /
  /// ticker text (null = none).
  final List<Shadow>? headlineShadows;
  final List<Shadow>? tickerShadows;

  /// v1.5.1 (fix #50): the Reporter block — photo path + name
  /// plate text + the plate's font family. Null photo = no block.
  final String? reporterPhotoPath;
  final String? reporterName;
  final String? reporterFontFamily;

  /// v1.5.1 (fix #47): a PICKED logo swings (3D) in the preview
  /// when true — the preset's rotation choice. The final3 default
  /// logo stays its keyed still (documented preview limit; the
  /// export plays the real rotating video).
  final bool logoRotate;

  String? _kasheeda(String text) =>
      fontReady && _hasArabicForPreview(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  static bool _hasArabicForPreview(String text) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  @override
  Widget build(BuildContext context) {
    final h = height;
    final w = h * 9 / 16;
    // Parity fractions at preview scale (reference 1080x1920).
    final isFinal3 = preset.finalIs3Ribbon;
    final g = ParityGeometry(
      1080,
      1920,
      variant: isFinal3 ? ParityVariant.final3 : ParityVariant.classic2,
      overrides: elementOverrides,
      tickerSpeedFactor: preset.tickerSpeedFactor,
      tickerLoop: preset.tickerLoop,
    );
    // #33 helpers: per-element override + the manual offsets in
    // preview pixels (all zero when no override is set).
    ElementOverride ov(String id) => overrideFor(elementOverrides, id);
    final topOv = ov(NewsElement.topRibbon);
    final midOv = ov(NewsElement.middleRibbon);
    final botOv = ov(NewsElement.bottomRibbon);
    final headOv = ov(NewsElement.headlineText);
    final tickOv = ov(NewsElement.tickerText);
    final logoOv = ov(NewsElement.logo);
    final capOv = ov(NewsElement.capsule);
    final overlayOv = ov(NewsElement.overlay);
    final repOv = ov(NewsElement.reporter);
    // The watermark's SIZE override applies through a cloned
    // preset (its mark sizes from preset.watermarkSize).
    final wmPreset = overlayOv.isIdentity
        ? preset
        : (ChannelPreset.fromJson(preset.toJson())
          ..watermarkSize =
              (preset.watermarkSize * overlayOv.scale).clamp(0.05, 0.30));
    final scaleW = w / 1080;
    final scaleH = h / 1920;
    final ribbonH = (g.ribbonH * scaleH).clamp(22.0, 200.0);
    // Final3 stack heights at preview scale (same fractions).
    final f3TopH = (g.f3TopH * scaleH).clamp(12.0, 200.0);
    final f3MidH = (g.f3MidH * scaleH).clamp(18.0, 200.0);
    final f3BotH = (g.f3BotH * scaleH).clamp(12.0, 200.0);
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
    const gap = 6.0;
    final ltH = (h * 0.10).clamp(36.0, 200.0);

    // classic2: the top ribbon is the FRAME-TOP ticker. final3:
    // it is the stack's TOP ribbon instead (showTop).
    final showTicker =
        !isFinal3 && preset.topRibbon.enabled && !topOv.hidden;
    final showTop = isFinal3 && preset.topRibbon.enabled && !topOv.hidden;
    final showUrdu = preset.urduRibbon.enabled && !midOv.hidden;
    final showEnglish = preset.englishRibbon.enabled && !botOv.hidden;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    final hasInterviewPlate = preset.showInterviewPlate &&
        preset.interviewName.trim().isNotEmpty;

    // Flush stack: English at the very bottom, Urdu directly on
    // it, and (final3) the top ribbon directly on the Urdu one.
    // classic2: the shared ribbonH is the DESIGNED height — the
    // per-band size override multiplies it here (final3's heights
    // already carry their band scale via the geometry).
    final midH = isFinal3 ? f3MidH : ribbonH * midOv.scale;
    final botH = isFinal3 ? f3BotH : ribbonH * botOv.scale;
    final englishTop = h - botH;
    final urduTop = (showEnglish ? englishTop : h) - midH;
    final stackBelowTop = showUrdu ? urduTop : (showEnglish ? englishTop : h);
    final topStackTop = stackBelowTop - f3TopH;
    final ribbonsTop = showTop ? topStackTop : stackBelowTop;
    final lowerThirdTop = ribbonsTop - gap - ltH;
    final plateH = (h * 0.08).clamp(56.0, 120.0);
    final interviewTop =
        (hasLowerThird ? lowerThirdTop : ribbonsTop) - gap - plateH;

    final logoW = g.logoVisibleW * scaleW;
    // final3: the logo block is the green-screen video's keyed
    // aspect (408:344); classic2 keeps the .mov aspect (422:347).
    final logoH = isFinal3 ? logoW * 344 / 408 : logoW * 347 / 422;
    final capsuleH =
        (g.capsuleH * scaleH).clamp(isFinal3 ? 9.0 : 15.0, 200.0);
    // final3 (demo v4 + user lift): the capsule sits ON the
    // middle (red) ribbon at its right end, bottom-aligned with
    // the red ribbon's bottom edge and raised by g.f3BlockLift;
    // the logo block sits directly above it. Anchored to the
    // middle ribbon's geometric bottom, like the export (which
    // always renders the full stack).
    final capTop = urduTop + midH - capsuleH - g.f3BlockLift * scaleH;
    final logoTop = capTop - logoH;
    final logoRight = g.logoMargin * scaleW;
    // #33 manual positions: ribbons shift by their own override;
    // the logo / capsule shift by theirs (right-anchored, so a
    // +dx move right shrinks the right inset).
    final urduTopAdj = urduTop + midOv.dy * h;
    final topStackTopAdj = topStackTop + topOv.dy * h;
    final englishTopAdj = englishTop + botOv.dy * h;
    final logoTopAdj = logoTop + logoOv.dy * h;
    final logoRightAdj = logoRight - logoOv.dx * w;
    final capTopAdj = capTop + capOv.dy * h;
    final capRightAdj = logoRight - capOv.dx * w;
    final capW = g.capsuleW * scaleW;

    TextStyle topStyle(RibbonConfig ribbon, double stripH) {
      final size = NigraanFinalLayout.ribbonFontSize(ribbon, stripH);
      return TextStyle(
        color: Colors.white,
        fontSize: size,
        fontWeight: FontWeight.bold,
        fontFamily: _kasheeda(ribbon.text),
      );
    }

    Widget topChip(
      String label,
      Color bg,
      double stripH, {
      String? fontFamily,
      double fontFactor = 0.45,
    }) {
      final maxChipW = w * 0.45;
      final chipFontSize = fitPreviewChipFontSize(
        label,
        stripH * fontFactor,
        maxChipW,
      );
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxChipW),
        child: Container(
          color: bg,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: chipFontSize,
              fontWeight: FontWeight.bold,
              fontFamily: fontFamily,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Parity chip: black, GOLD text, fixed reference width, gold
    // divider on the window side.
    Widget parityChip({
      required String label,
      required double widthPx,
      required bool dividerOnLeft,
      String? fontFamily,
      required double fontSize,
    }) {
      return Container(
        width: widthPx,
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Text(
                label,
                style: TextStyle(
                  color: const Color(0xFFF5C542),
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: dividerOnLeft ? 0 : null,
              right: dividerOnLeft ? null : 0,
              child: Container(width: 1.5, color: const Color(0xFFF5C542)),
            ),
          ],
        ),
      );
    }

    // Final3 Urdu ribbon content: the headline sits PINNED,
    // right-aligned, when its sequence fits the text window left
    // of the logo stack; longer text scrolls (RTL, rightward) —
    // the same still-vs-scroll decision the export makes
    // (paritySequenceWidth vs the text window).
    Widget f3UrduContent({
      required String text,
      required String fallback,
      required double fontSize,
      Color textColor = Colors.white,
      List<Shadow>? shadows,
    }) {
      final shown = text.isEmpty ? fallback : text;
      final style = TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        fontFamily: headlineFontFamily ?? _kasheeda(text),
        shadows: shadows,
      );
      final parts = paritySplitHeadlines(shown);
      final seq = parts.isEmpty ? shown : '${parts.join('  ●  ')}  ●  ';
      final windowW = w - logoW;
      // v1.5.1 (fix #41): measure with the REAL style (font family
      // included) — the old measure used a bare bold style, so a
      // wide font (Kasheeda) could be judged "fits" and then be
      // ellipsized by the pinned Text ('HEADL…'). Now the
      // fits/scroll decision matches what is actually drawn: a
      // headline that does not fit SCROLLS, it is never cut.
      final seqPainter = TextPainter(
        text: TextSpan(text: seq, style: style),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      final fits = seqPainter.width <= windowW - 16;
      if (fits) {
        return Container(
          alignment: Alignment.centerRight,
          padding: EdgeInsets.only(right: logoW + 8, left: 8),
          child: Text(
            shown,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.only(right: logoW),
        child: _ParityScrollText(
          text: shown,
          rtl: true,
          speedPxPerSec: g.scrollSpeed * scaleW,
          style: style,
          loop: g.tickerLoop,
        ),
      );
    }

    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF101018),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white24,
                size: 48,
              ),
            ),
          ),
          if (showTicker)
            Positioned(
              key: const Key('preview-top-ribbon'),
              top: 0,
              left: topOv.dx * w,
              right: -topOv.dx * w,
              height: tickerH,
              child: Container(
                color: Color(preset.topRibbon.color),
                child: Row(
                  children: [
                    topChip(
                      NigraanFinalLayout.tickerChipText,
                      const Color(0xFFD50000),
                      tickerH,
                      fontFamily: _kasheeda(
                        NigraanFinalLayout.tickerChipText,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ScrollingTickerText(
                          text: preset.topRibbon.text,
                          speed: preset.topRibbon.speed *
                              preset.tickerSpeedFactor,
                          direction: preset.topRibbon.direction,
                          style: topStyle(preset.topRibbon, tickerH),
                          loop: preset.tickerLoop,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Category chip + intro/outro markers (top-left).
          Positioned(
            top: (showTicker ? tickerH : 0) + 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preset.categoryLabel.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      preset.categoryLabel.trim().toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                if (preset.categoryLabel.trim().isNotEmpty)
                  const SizedBox(height: 4),
                if (preset.showIntro)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          NigraanFinalLayout.introMarkerText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                      if (preset.showOutro) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            NigraanFinalLayout.outroMarkerText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (hasInterviewPlate)
            Positioned(
              key: const Key('preview-interview-plate'),
              top: interviewTop,
              left: 0,
              width: w * 0.68,
              height: plateH,
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      color: const Color(0xFFD50000),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      child: const Text(
                        'INTERVIEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.interviewName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (preset.interviewDesignation.trim().isNotEmpty)
                      Text(
                        preset.interviewDesignation,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          if (hasLowerThird)
            Positioned(
              key: const Key('preview-lower-third'),
              top: lowerThirdTop,
              left: 0,
              width: w * 0.68,
              height: ltH,
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (preset.lowerThirdTitle.trim().isNotEmpty)
                      Text(
                        preset.lowerThirdTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (preset.lowerThirdSubtitle.trim().isNotEmpty)
                      Text(
                        preset.lowerThirdSubtitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          if (showUrdu)
            Positioned(
              key: const Key('preview-middle-ribbon'),
              top: urduTopAdj,
              left: midOv.dx * w,
              right: -midOv.dx * w,
              height: midH,
              child: isFinal3
                  ? Container(
                      color: Color(preset.designUrduColor),
                      child: headOv.hidden
                          ? const SizedBox.shrink()
                          : _overrideTransform(
                              headOv,
                              w,
                              h,
                              f3UrduContent(
                                text: preset.urduRibbon.text,
                                fallback: 'قومی خبریں',
                                fontSize: f3MidH * 0.56,
                                textColor: headlineTextColor != null
                                    ? Color(headlineTextColor!)
                                    : Colors.white,
                                shadows: headlineShadows,
                              ),
                            ),
                    )
                  : Container(
                      // v1.5.1 (fix #40): the preview is the export's
                      // twin — classic2 renders its RESOLVED design
                      // colours here too, never the raw stored ones.
                      color: Color(preset.designUrduColor),
                      child: Column(
                        children: [
                          Container(
                              height: 2,
                              color: const Color(0xFFF5C542)),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: headOv.hidden
                                      ? const SizedBox.shrink()
                                      : _overrideTransform(
                                          headOv,
                                          w,
                                          h,
                                          _ParityScrollText(
                                            text: preset.urduRibbon.text
                                                    .isEmpty
                                                ? 'قومی خبریں'
                                                : preset.urduRibbon.text,
                                            rtl: true,
                                            speedPxPerSec:
                                                g.scrollSpeed * scaleW,
                                            loop: g.tickerLoop,
                                            style: TextStyle(
                                              color: headlineTextColor != null
                                                  ? Color(headlineTextColor!)
                                                  : Colors.white,
                                              fontSize: ribbonH * 0.5625,
                                              fontWeight: FontWeight.bold,
                                              fontFamily:
                                                  headlineFontFamily ??
                                                      _kasheeda(preset
                                                          .urduRibbon.text),
                                              shadows: headlineShadows,
                                            ),
                                          ),
                                        ),
                                ),
                                if (preset.showBreakingBanner)
                                  parityChip(
                                    label:
                                        NigraanFinalLayout.urduChipText,
                                    widthPx: g.urduChipW * scaleW,
                                    dividerOnLeft: true,
                                    fontFamily: _kasheeda(
                                      NigraanFinalLayout.urduChipText,
                                    ),
                                    fontSize: ribbonH * 0.45,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          if (showEnglish)
            Positioned(
              key: const Key('preview-english-ribbon'),
              left: botOv.dx * w,
              right: -botOv.dx * w,
              top: englishTopAdj,
              height: botH,
              child: isFinal3
                  ? Container(
                      color: Color(preset.designEnglishColor),
                      child: tickOv.hidden
                          ? const SizedBox.shrink()
                          : _overrideTransform(
                              tickOv,
                              w,
                              h,
                              // v1.5.1 (fix #49): with an editable
                              // label the band is [red chip | ticker
                              // window]; without one the ticker
                              // keeps the full width, as before.
                              (tickerLabel != null &&
                                      tickerLabel!.trim().isNotEmpty)
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          width:
                                              g.englishChipW * scaleW,
                                          color: Color(
                                              tickerLabelColor ??
                                                  0xFFD50000),
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets
                                              .symmetric(horizontal: 4),
                                          child: Text(
                                            tickerLabel!.trim(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize:
                                                  fitPreviewChipFontSize(
                                                tickerLabel!.trim(),
                                                f3BotH * 0.53,
                                                g.englishChipW * scaleW,
                                              ),
                                              fontWeight:
                                                  FontWeight.bold,
                                              fontFamily:
                                                  tickerFontFamily ??
                                                      _kasheeda(
                                                          tickerLabel!),
                                            ),
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                        Expanded(
                                          child: _ParityScrollText(
                                            text: preset.englishRibbon
                                                    .text.isEmpty
                                                ? 'International headlines'
                                                : preset
                                                    .englishRibbon.text,
                                            rtl: false,
                                            speedPxPerSec:
                                                g.scrollSpeed * scaleW,
                                            loop: g.tickerLoop,
                                            style: TextStyle(
                                              color: tickerTextColor !=
                                                      null
                                                  ? Color(
                                                      tickerTextColor!)
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: f3BotH * 0.53,
                                              fontFamily:
                                                  tickerFontFamily ??
                                                      _kasheeda(preset
                                                          .englishRibbon
                                                          .text),
                                              shadows: tickerShadows,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : _ParityScrollText(
                                      text: preset.englishRibbon.text
                                              .isEmpty
                                          ? 'International headlines'
                                          : preset.englishRibbon.text,
                                      rtl: false,
                                      speedPxPerSec:
                                          g.scrollSpeed * scaleW,
                                            loop: g.tickerLoop,
                                      style: TextStyle(
                                        color: tickerTextColor != null
                                            ? Color(tickerTextColor!)
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: f3BotH * 0.53,
                                        fontFamily: tickerFontFamily ??
                                            _kasheeda(
                                                preset.englishRibbon.text),
                                        shadows: tickerShadows,
                                      ),
                                    ),
                            ),
                    )
                  : Container(
                      // v1.5.1 (fix #40): resolved design colour,
                      // like the export (see the Urdu ribbon note).
                      color: Color(preset.designEnglishColor),
                      child: Column(
                        children: [
                          Container(
                              height: 2,
                              color: const Color(0xFFF5C542)),
                          Expanded(
                            child: Row(
                              children: [
                                parityChip(
                                  // v1.5.1 (fix #49): the editable
                                  // label replaces the fixed chip
                                  // text when the project carries one.
                                  label: (tickerLabel != null &&
                                          tickerLabel!.trim().isNotEmpty)
                                      ? tickerLabel!.trim()
                                      : NigraanFinalLayout.englishChipText,
                                  widthPx: g.englishChipW * scaleW,
                                  dividerOnLeft: false,
                                  fontFamily: tickerFontFamily ??
                                      _kasheeda(
                                          NigraanFinalLayout
                                              .englishChipText),
                                  fontSize: ribbonH * 0.45,
                                ),
                                Expanded(
                                  child: tickOv.hidden
                                      ? const SizedBox.shrink()
                                      : _overrideTransform(
                                          tickOv,
                                          w,
                                          h,
                                          _ParityScrollText(
                                            text: preset.englishRibbon.text
                                                    .isEmpty
                                                ? 'International headlines'
                                                : preset.englishRibbon.text,
                                            rtl: false,
                                            speedPxPerSec:
                                                g.scrollSpeed * scaleW,
                                            loop: g.tickerLoop,
                                            style: TextStyle(
                                              color: tickerTextColor !=
                                                      null
                                                  ? Color(
                                                      tickerTextColor!)
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: ribbonH * 0.53,
                                              fontFamily:
                                                  tickerFontFamily ??
                                                      _kasheeda(preset
                                                          .englishRibbon
                                                          .text),
                                              shadows: tickerShadows,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          if (showTop)
            Positioned(
              key: const Key('preview-top-stack-ribbon'),
              top: topStackTopAdj,
              left: topOv.dx * w,
              right: -topOv.dx * w,
              height: f3TopH,
              child: Container(
                color: Color(preset.designTopColor),
                child: f3UrduContent(
                  text: preset.topRibbon.text,
                  fallback: 'موجودہ خبر',
                  fontSize: f3TopH * 0.52,
                  // Yellow design top ribbon → BLACK headline text.
                  textColor: Color(preset.designTopTextColor),
                  shadows: headlineShadows,
                ),
              ),
            ),
          // Logo + flipping capsule stack — painted AFTER the
          // ribbons so it lands ON TOP of them. classic2:
          // bottom-right, the capsule sitting directly on the
          // ribbons (v1.3.0 parity). final3 (demo v4): the DATE
          // capsule sits ON the middle (red) ribbon at its right
          // end and the logo block sits directly above it.
          if (!logoOv.hidden)
          Positioned(
            key: const Key('preview-logo-bug'),
            right: logoRightAdj,
            top: isFinal3 ? logoTopAdj : null,
            bottom: isFinal3
                ? null
                : ((showUrdu || showEnglish)
                        ? (h - ribbonsTop) + capsuleH
                        : capsuleH + 4) -
                    logoOv.dy * h,
            child: _ParityLogoBox(
              logoPath: preset.logoPath,
              initial: initial,
              width: logoW,
              height: logoH,
              isFinal3: isFinal3,
              rotate: logoRotate,
              logoGsFrameAssetPath: preset.logoGsFrameAssetPath,
              logoMediaKind: preset.logoMediaKind,
              keyedFramesDir: preset.logoKeyedFramesDir,
              videoStillPath: preset.logoVideoStillPath,
              cubeFacePaths: preset.logoCubeFacePaths,
              cubeTiltX: preset.logoCubeTilt,
              cubeSpeedSec: preset.logoCubeSpeedSec,
              cubeClockwise: preset.logoCubeDirection != 'ccw',
              cubePedestal: preset.logoCubePedestal,
              parts: preset.logoParts,
              partsScene: preset.logoPartsScene,
            ),
          ),
          if (!capOv.hidden)
          Positioned(
            right: capRightAdj,
            top: isFinal3 ? capTopAdj : null,
            bottom: isFinal3
                ? null
                : (showUrdu || showEnglish ? h - ribbonsTop : 4) -
                    capOv.dy * h,
            child: _ParityCapsule(
              width: capW,
              height: capsuleH,
              fontReady: fontReady,
              dateFirst: isFinal3,
              goldLine: !isFinal3,
              shortDate: isFinal3,
            ),
          ),
          // v1.5.1 (fix #50): the Reporter block — photo + name
          // plate on the side OPPOSITE the logo, from the shared
          // ParityGeometry reporter rects (the export post-pass
          // draws the same composition). Only when a caller
          // passes a reporter photo.
          if (reporterPhotoPath != null &&
              reporterPhotoPath!.isNotEmpty &&
              !repOv.hidden)
            Positioned.fromRect(
              rect: Rect.fromLTWH(
                g.reporterBlockRect.left * scaleW,
                g.reporterBlockRect.top * scaleH,
                g.reporterBlockRect.width * scaleW,
                g.reporterBlockRect.height * scaleH,
              ),
              child: ReporterOverlay(
                photoRect: Rect.fromLTWH(
                  (g.reporterPhotoRect.left -
                          g.reporterBlockRect.left) *
                      scaleW,
                  (g.reporterPhotoRect.top - g.reporterBlockRect.top) *
                      scaleH,
                  g.reporterPhotoRect.width * scaleW,
                  g.reporterPhotoRect.height * scaleH,
                ),
                plateRect: Rect.fromLTWH(
                  (g.reporterPlateRect.left -
                          g.reporterBlockRect.left) *
                      scaleW,
                  (g.reporterPlateRect.top - g.reporterBlockRect.top) *
                      scaleH,
                  g.reporterPlateRect.width * scaleW,
                  g.reporterPlateRect.height * scaleH,
                ),
                photoPath: reporterPhotoPath!,
                name: reporterName ?? '',
                fontFamily: reporterFontFamily,
              ),
            ),
          if (preset.pipEnabled && !overlayOv.hidden)
            PipInset(
              position: preset.pipPosition,
              scale: preset.pipScale,
              frameWidth: w,
            ),
          if (preset.watermarkEnabled && !overlayOv.hidden)
            WatermarkMark(
              preset: wmPreset,
              frameWidth: w,
              frameHeight: h,
            ),
        ],
      ),
    );
  }
}

/// The parity logo box: the picked logo image fitted into the
/// design's VISIBLE box (classic2: 185/1080 wide, 422:347;
/// final3: 232/1280 wide, 408:344), or — final3 with no logo
/// picked — the keyed first frame of the user's green-screen
/// rotating-cube logo video (a still: the preview has no
/// chroma-key shader plumbing, the EXPORT plays the real video),
/// or the channel initial tile otherwise.
class _ParityLogoBox extends StatelessWidget {
  const _ParityLogoBox({
    required this.logoPath,
    required this.initial,
    required this.width,
    required this.height,
    this.isFinal3 = false,
    this.rotate = true,
    this.logoGsFrameAssetPath =
        AssetDownloadService.logoGsFrameAssetPath,
    this.logoMediaKind = 'image',
    this.keyedFramesDir,
    this.videoStillPath,
    this.cubeFacePaths = const {},
    this.cubeTiltX = 0.0,
    this.cubeSpeedSec = 6,
    this.cubeClockwise = true,
    this.cubePedestal = false,
    this.parts = const [],
    this.partsScene,
  });

  final String? logoPath;
  final String initial;
  final double width;
  final double height;
  final bool isFinal3;

  /// Build 7 (v1.5.9, Phase 8 generic branding): the channel's
  /// keyed logo still — passed from the active preset (defaults
  /// to the Nigraan TV frame, the old hardcoded literal).
  final String logoGsFrameAssetPath;

  /// v1.5.1 (fix #47): a picked logo rotates (3D) in the preview
  /// when true — any uploaded logo rotates, not only the built-in
  /// one (the export overlays generated rotating frames for a
  /// picked logo). Build 12: the rotation is the continuous
  /// full-turn 3D CUBE.
  final bool rotate;

  /// Build 12 (point #13): 'video' when the preset's logo
  /// source is a logo video — the box then plays the honestly
  /// keyed frames instead of the cube / GS still.
  final String logoMediaKind;
  final String? keyedFramesDir;
  final String? videoStillPath;

  /// Build 13 (point #19): the preset's Logo Cube settings,
  /// passed through to the cube (image source only).
  final Map<String, String> cubeFacePaths;
  final double cubeTiltX;
  final double cubeSpeedSec;
  final bool cubeClockwise;
  final bool cubePedestal;

  /// Build 13 (point 6): the preset's working logo parts.
  final List<LogoPart> parts;

  /// Redesign Build 2: the parts SCENE (glow + base) riding
  /// with [parts].
  final LogoPartsScene? partsScene;

  @override
  Widget build(BuildContext context) {
    if (logoMediaKind == 'video') {
      final still = videoStillPath;
      return SizedBox(
        width: width,
        height: height,
        child: KeyedLogoFlipbook(
          framesDir: keyedFramesDir,
          width: width,
          height: height,
          fallback: still != null && File(still).existsSync()
              ? Image.file(
                  File(still),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _tile(),
                )
              : _tile(),
        ),
      );
    }
    final path = logoPath;
    if (path != null && path.isNotEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.fill,
          child: RotatingLogo(
            logoPath: path,
            initial: initial,
            size: width,
            animate: rotate,
            facePaths: cubeFacePaths,
            tiltX: cubeTiltX,
            speedSec: cubeSpeedSec,
            clockwise: cubeClockwise,
            pedestal: cubePedestal,
            parts: parts,
            partsScene: partsScene,
          ),
        ),
      );
    }
    if (isFinal3) {
      return SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          logoGsFrameAssetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _tile(),
        ),
      );
    }
    return _tile();
  }

  Widget _tile() => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: width * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

/// The flipping TIME <-> Urdu DATE capsule (3s per face) — the
/// widget twin of the export's drawtext clock + date PNG pair.
/// classic2: black at 67% alpha with a gold top line, TIME face
/// first, full date (with year). final3: the reference's solid
/// black date box (no gold line), DATE face first, short date
/// (no year — the box is thin).
class _ParityCapsule extends StatefulWidget {
  const _ParityCapsule({
    required this.width,
    required this.height,
    required this.fontReady,
    this.dateFirst = false,
    this.goldLine = true,
    this.shortDate = false,
  });

  final double width;
  final double height;
  final bool fontReady;
  final bool dateFirst;
  final bool goldLine;
  final bool shortDate;

  @override
  State<_ParityCapsule> createState() => _ParityCapsuleState();
}

class _ParityCapsuleState extends State<_ParityCapsule> {
  Timer? _timer;
  late bool _showDate = widget.dateFirst;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _showDate = !_showDate);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateFamily = widget.fontReady
        ? AssetDownloadService.kasheedaFamily
        : null;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.goldLine
            ? Colors.black.withValues(alpha: 0.67)
            : Colors.black,
        borderRadius: BorderRadius.circular(widget.goldLine ? 4 : 2),
        border: widget.goldLine
            ? const Border(
                top: BorderSide(color: Color(0xFFF5C542), width: 2),
              )
            : null,
      ),
      alignment: Alignment.center,
      child: _showDate
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.shortDate
                    ? parityShortUrduDate(now)
                    : parityUrduDate(now),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.height * 0.55,
                  fontFamily: dateFamily,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            )
          // v1.5.1 (fix #41): the TIME face gets the same
          // FittedBox the DATE face always had — the plain Text
          // truncated the seconds ('08:08:5') whenever the
          // capsule ran narrow.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                parityTimeString(now),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.height * 0.55,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
    );
  }
}

/// One parity ribbon's scrolling headline sequence: the headlines
/// of [text] joined by gold dots, looping seamlessly — RTL moves
/// RIGHTWARD, LTR moves leftward (the reference directions).
class _ParityScrollText extends StatefulWidget {
  const _ParityScrollText({
    required this.text,
    required this.rtl,
    required this.speedPxPerSec,
    required this.style,
    this.loop = true,
  });

  final String text;
  final bool rtl;
  final double speedPxPerSec;
  final TextStyle style;

  /// Build 13 (point #19): false = one pass, then hold.
  final bool loop;

  @override
  State<_ParityScrollText> createState() => _ParityScrollTextState();
}

class _ParityScrollTextState extends State<_ParityScrollText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  double _seqW = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _measureAndRestart());
  }

  @override
  void didUpdateWidget(_ParityScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.loop != widget.loop ||
        oldWidget.speedPxPerSec != widget.speedPxPerSec) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _measureAndRestart());
    }
  }

  String get _sequence {
    final parts = paritySplitHeadlines(widget.text);
    if (parts.isEmpty) return widget.text;
    return '${parts.join('  ●  ')}  ●  ';
  }

  void _measureAndRestart() {
    if (!mounted) return;
    final painter = TextPainter(
      text: TextSpan(text: _sequence, style: widget.style),
      textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _seqW = painter.width;
    if (_seqW <= 0) return;
    final speed = widget.speedPxPerSec <= 0 ? 20.0 : widget.speedPxPerSec;
    _controller.duration =
        Duration(milliseconds: (_seqW / speed * 1000).round());
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          if (_seqW <= 0) return const SizedBox.shrink();
          final travelled = _controller.value * _seqW;
          final x = widget.rtl ? -_seqW + travelled : -travelled;
          return Stack(
            children: [
              Transform.translate(
                offset: Offset(x, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
              ),
              Transform.translate(
                offset: Offset(x + _seqW, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
              ),
            ],
          );
        },
        child: Text(
          _sequence,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
          textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
        ),
      ),
    );
  }
}
