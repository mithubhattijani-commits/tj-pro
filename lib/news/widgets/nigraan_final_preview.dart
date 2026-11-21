/// Live Flutter preview of the Nigraan final 3-ribbon template
/// (Phase 3) — the on-screen twin of the PNG renderer in
/// lib/live/news_template.dart ([NigraanFinalLayout] geometry, same
/// house colours, same chip labels). Used by the Template & Studio
/// screen (full preview + the paste-to-run ticker strip) and the News
/// Studio home preview.
///
/// TICKER PASTE-TO-RUN: the top ticker scrolls from the preset's live
/// text — [ScrollingTickerText] re-measures and restarts its animation
/// on every text change, so a paste scrolls in the preview
/// IMMEDIATELY, with no extra step. Only the top ticker scrolls in
/// the preview (middle/bottom are headline strips, pinned at their
/// start — same as the PNG renderer; per-ribbon scroll phases are a
/// Phase 7 export-animation item).
library;

import 'package:flutter/material.dart';

import '../../live/news_template.dart';
import '../../services/asset_download_service.dart';
import '../channel_preset.dart';
import '../watermark.dart';
import 'pip_inset.dart';
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
  });

  final String text;
  final double speed;
  final RibbonDirection direction;
  final TextStyle style;

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
        oldWidget.style != widget.style) {
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
    _controller.repeat();
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

/// Full 3-ribbon template preview (9:16 frame): top ticker with the
/// scrolling text + red "تازہ ترین" chip, rotating logo bug + capsule
/// top-right, middle Urdu ribbon + black "بریکنگ نیوز" chip, bottom
/// English ribbon at half thickness + "HEADLINES" chip, lower third
/// above the ribbons. Disabled ribbons are skipped and the layout
/// reflows (same bottom-up rule as [NigraanFinalLayout]).
class NigraanFinalPreview extends StatelessWidget {
  const NigraanFinalPreview({
    super.key,
    required this.preset,
    this.fontReady = false,
    this.height = 320,
  });

  final ChannelPreset preset;
  final bool fontReady;
  final double height;

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
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
    final englishH = tickerH / 2;
    final urduH = tickerH;
    const gap = 6.0;
    final ltH = (h * 0.10).clamp(36.0, 200.0);

    final showTicker = preset.topRibbon.enabled;
    final showUrdu = preset.urduRibbon.enabled;
    final showEnglish = preset.englishRibbon.enabled;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    final hasInterviewPlate = preset.showInterviewPlate &&
        preset.interviewName.trim().isNotEmpty;

    final urduTop =
        (showEnglish ? h - englishH - gap : h) - urduH;
    final lowerThirdTop = (showUrdu
            ? urduTop - gap
            : (showEnglish ? h - englishH - gap : h)) -
        ltH;
    // Interview plate stacks above the lower third (or above the
    // lowest ribbon when there is no lower third) — Phase 6.
    // Minimum 56px so tag + name + designation always fit (§14
    // rule 4: no overflow).
    final plateH = (h * 0.08).clamp(56.0, 120.0);
    final interviewTop = hasLowerThird
        ? lowerThirdTop - gap - plateH
        : (showUrdu
                ? urduTop - gap
                : (showEnglish ? h - englishH - gap : h)) -
            gap -
            plateH;

    TextStyle ribbonStyle(RibbonConfig ribbon, double stripH) {
      final size = NigraanFinalLayout.ribbonFontSize(ribbon, stripH);
      return TextStyle(
        color: Colors.white,
        fontSize: size,
        fontWeight: FontWeight.bold,
        fontFamily: _kasheeda(ribbon.text),
      );
    }

    Widget chip(
      String label,
      Color bg,
      double stripH, {
      String? fontFamily,
      double fontFactor = 0.45,
    }) {
      // Fixed ribbon labels shrink to fit (never truncate, never
      // overflow the row — the scrolling text takes the rest).
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
          // Video area hint (the template overlays the video).
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
              left: 0,
              right: 0,
              height: tickerH,
              child: Container(
                color: Color(preset.topRibbon.color),
                child: Row(
                  children: [
                    chip(
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
                          speed: preset.topRibbon.speed,
                          direction: preset.topRibbon.direction,
                          style: ribbonStyle(preset.topRibbon, tickerH),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            key: const Key('preview-logo-bug'),
            top: (showTicker ? tickerH : 0) + 8,
            right: 8,
            child: LogoBug(
              logoPath: preset.logoPath,
              initial: initial,
              size: 52,
            ),
          ),
          // Category chip + intro/outro markers (Phase 6, top-left).
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
              top: urduTop,
              left: 0,
              right: 0,
              height: urduH,
              child: Container(
                color: Color(preset.urduRibbon.color),
                child: Row(
                  children: [
                    if (preset.showBreakingBanner)
                      chip(
                        NigraanFinalLayout.urduChipText,
                        Colors.black,
                        urduH,
                        fontFamily: _kasheeda(
                          NigraanFinalLayout.urduChipText,
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          preset.urduRibbon.text.isEmpty
                              ? 'قومی خبریں'
                              : preset.urduRibbon.text,
                          style: ribbonStyle(preset.urduRibbon, urduH)
                              .copyWith(
                            color: preset.urduRibbon.text.isEmpty
                                ? Colors.white70
                                : Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (showEnglish)
            Positioned(
              key: const Key('preview-english-ribbon'),
              left: 0,
              right: 0,
              bottom: 0,
              height: englishH,
              child: Container(
                color: Color(preset.englishRibbon.color),
                child: Row(
                  children: [
                    chip(
                      NigraanFinalLayout.englishChipText,
                      Colors.black,
                      englishH,
                      fontFactor: 0.55,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          preset.englishRibbon.text.isEmpty
                              ? 'International headlines'
                              : preset.englishRibbon.text,
                          style: ribbonStyle(
                            preset.englishRibbon,
                            englishH,
                          ).copyWith(
                            color: preset.englishRibbon.text.isEmpty
                                ? Colors.white70
                                : Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (preset.pipEnabled)
            PipInset(
              position: preset.pipPosition,
              scale: preset.pipScale,
              frameWidth: w,
            ),
          if (preset.watermarkEnabled)
            WatermarkMark(
              preset: preset,
              frameWidth: w,
              frameHeight: h,
            ),
        ],
      ),
    );
  }
}
