/// Live Flutter previews for the breaking-news templates + the
/// Classic template (Phase 6) — the on-screen twins of the PNG
/// renderers in lib/live/news_template.dart ([BreakingLayout] /
/// [ClassicLayout] geometry, same house colours, same chip labels).
/// Used by the Templates Library, Template & Studio, News Studio
/// home, News Maker and AI News Maker.
///
/// Same contracts as [NigraanFinalPreview]: the top ticker scrolls
/// via [ScrollingTickerText] (paste-to-run — a text change
/// re-measures and restarts the loop immediately); middle/bottom
/// ribbons are pinned headline strips; the logo bug rotates via
/// [LogoBug]; empty ribbon texts show a grey placeholder (never an
/// invented headline); the PIP inset draws where the Phase 7 export
/// will put it (position + size from the template/preset).
library;

import 'package:flutter/material.dart';

import '../../live/news_template.dart';
import '../../services/asset_download_service.dart';
import '../breaking_templates.dart';
import '../channel_preset.dart';
import '../watermark.dart';
import 'nigraan_final_preview.dart';
import 'pip_inset.dart';
import 'rotating_logo.dart';

bool _hasArabic(String text) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(text);

/// Shared text-fit helpers live in nigraan_final_preview.dart
/// ([measurePreviewTextWidth], [fitPreviewChipFontSize]) — this file
/// imports them rather than duplicating them.

/// Readable text colour on a coloured strip: white, unless the strip
/// is light — then near-black (same rule as the PNG renderer).
Color _textOn(int bgColor) =>
    Color(bgColor).computeLuminance() > 0.6
        ? const Color(0xFF1A1A1A)
        : Colors.white;

/// Small rounded pill (category chip / intro / outro marker).
Widget _pill(String text, {bool bold = true, Color? bg}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg ?? Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
      maxLines: 1,
      softWrap: false,
    ),
  );
}

/// Interview name plate: red INTERVIEW tag + name + designation.
Widget _interviewPlate({
  required String name,
  required String designation,
  required double top,
  required double width,
  required double height,
}) {
  return Positioned(
    key: const Key('preview-interview-plate'),
    top: top,
    left: 0,
    width: width,
    height: height,
    child: Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            color: const Color(0xFFD50000),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (designation.isNotEmpty)
            Text(
              designation,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    ),
  );
}

/// Lower-third box: reporter name + place.
Widget _lowerThirdBox({
  required String title,
  required String subtitle,
  required double top,
  required double width,
  required double height,
}) {
  return Positioned(
    key: const Key('preview-lower-third'),
    top: top,
    left: 0,
    width: width,
    height: height,
    child: Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (title.trim().isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (subtitle.trim().isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    ),
  );
}

/// Full breaking-template preview (9:16 frame): banner + chip +
/// headline, scrolling ticker, logo bug + capsule, lower third,
/// interview plate, category chip, intro/outro markers, PIP inset.
class BreakingTemplatePreview extends StatelessWidget {
  const BreakingTemplatePreview({
    super.key,
    required this.template,
    required this.preset,
    this.fontReady = false,
    this.height = 320,
  });

  final BreakingTemplate template;
  final ChannelPreset preset;
  final bool fontReady;
  final double height;

  String? _kasheeda(String text) =>
      fontReady && _hasArabic(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  @override
  Widget build(BuildContext context) {
    final h = height;
    final w = h * 9 / 16;
    final isCombo =
        template.variant == BreakingVariant.breakingTickerCombo;
    final bannerH = switch (template.variant) {
      BreakingVariant.breakingRedBanner => h * 0.10,
      BreakingVariant.latestNews => h * 0.08,
      BreakingVariant.topHeadlineBar => h * 0.08,
      BreakingVariant.breakingTickerCombo => h * 0.062,
    };
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
    final englishH = tickerH / 2;
    const gap = 6.0;
    final ltH = (h * 0.10).clamp(36.0, 200.0);
    final plateH = (h * 0.08).clamp(56.0, 120.0);

    final showBottomTicker = !isCombo && template.showRibbons;
    final showTopTicker = isCombo && template.showRibbons && template.showTop;
    final showMiddle =
        isCombo && template.showRibbons && template.showMiddle;
    final showBottom =
        isCombo && template.showRibbons && template.showBottom;
    final hasLowerThird = template.showLowerThird &&
        (template.lowerThirdTitle.trim().isNotEmpty ||
            template.lowerThirdSubtitle.trim().isNotEmpty);
    final hasInterviewPlate = template.showInterviewPlate &&
        template.interviewName.trim().isNotEmpty;

    final topBelow = bannerH + (showTopTicker ? tickerH : 0);
    final bottomTop = showBottom ? h - englishH : h;
    final middleTop = showMiddle ? bottomTop - gap - tickerH : h;
    var lowerBottom = h;
    if (isCombo) {
      if (showBottom) {
        lowerBottom = bottomTop - gap;
      } else if (showMiddle) {
        lowerBottom = middleTop - gap;
      }
    } else if (showBottomTicker) {
      lowerBottom = h - tickerH - gap;
    }
    final lowerThirdTop = lowerBottom - ltH;
    final interviewTop = hasLowerThird
        ? lowerThirdTop - gap - plateH
        : lowerBottom - gap - plateH;

    final chipText = template.variant == BreakingVariant.latestNews
        ? BreakingLayout.latestChipText
        : BreakingLayout.breakingChipText;
    final hasBannerChip =
        template.variant != BreakingVariant.topHeadlineBar;
    final bannerTextColor = _textOn(template.topColor);
    // The banner chip is a fixed broadcast label — it shrinks to fit
    // (never truncates). The headline shows only when the chip +
    // a 40px headline still fit the row; in a tiny thumbnail the
    // chip alone carries the banner.
    final chipFontSize = hasBannerChip
        ? fitPreviewChipFontSize(
            chipText,
            bannerH * 0.28,
            (w - 24) * 0.55,
          )
        : bannerH * 0.28;
    final chipW = hasBannerChip
        ? measurePreviewTextWidth(chipText, chipFontSize) + 16
        : 0.0;
    final showHeadline = !hasBannerChip || chipW + 8 + 40 <= w - 24;

    TextStyle tickerStyle(double stripH, int bgColor) {
      final size =
          BreakingLayout.clampFontSize(template.fontSize, stripH);
      return TextStyle(
        color: _textOn(bgColor),
        fontSize: size,
        fontWeight: FontWeight.bold,
      );
    }

    Widget ribbonChip(
      String label,
      Color bg,
      double stripH, {
      String? fontFamily,
      double fontFactor = 0.45,
      Color textColor = Colors.white,
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
              color: textColor,
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
      key: const Key('breaking-preview'),
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
          // Banner / top bar + chip + headline.
          Positioned(
            key: const Key('breaking-banner'),
            top: 0,
            left: 0,
            right: 0,
            height: bannerH,
            child: Container(
              color: Color(template.topColor),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (hasBannerChip)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        chipText,
                        style: TextStyle(
                          color: Color(template.topColor),
                          fontSize: chipFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  if (hasBannerChip && showHeadline)
                    const SizedBox(width: 8),
                  if (showHeadline)
                    Expanded(
                      child: Text(
                        template.headline.isEmpty
                            ? 'Headline yahan likhein…'
                            : template.headline,
                        style: TextStyle(
                          color: template.headline.isEmpty
                              ? bannerTextColor.withValues(alpha: 0.7)
                              : bannerTextColor,
                          fontSize: (bannerH * 0.30).clamp(10.0, 20.0),
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Combo: top ticker strip below the banner.
          if (showTopTicker)
            Positioned(
              key: const Key('breaking-top-ticker'),
              top: bannerH,
              left: 0,
              right: 0,
              height: tickerH,
              child: Container(
                color: Color(template.tickerColor),
                child: Row(
                  children: [
                    ribbonChip(
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
                          text: template.tickerText,
                          speed: template.speed,
                          direction: template.direction,
                          style: tickerStyle(
                            tickerH,
                            template.tickerColor,
                          ).copyWith(
                            fontFamily: _kasheeda(template.tickerText),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Logo bug + capsule (below the top elements).
          Positioned(
            key: const Key('preview-logo-bug'),
            top: topBelow + 8,
            right: 8,
            child: LogoBug(
              logoPath: template.logoPath ?? preset.logoPath,
              initial: initial,
              size: 52,
            ),
          ),
          // Category chip + intro/outro markers (top-left).
          Positioned(
            top: topBelow + 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (template.categoryLabel.trim().isNotEmpty)
                  _pill(template.categoryLabel.trim().toUpperCase()),
                if (template.categoryLabel.trim().isNotEmpty)
                  const SizedBox(height: 4),
                if (template.showIntro)
                  Row(
                    children: [
                      _pill(
                        NigraanFinalLayout.introMarkerText,
                        bold: false,
                      ),
                      if (template.showOutro) ...[
                        const SizedBox(width: 4),
                        _pill(
                          NigraanFinalLayout.outroMarkerText,
                          bold: false,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (hasInterviewPlate)
            _interviewPlate(
              name: template.interviewName,
              designation: template.interviewDesignation,
              top: interviewTop,
              width: w * 0.68,
              height: plateH,
            ),
          if (hasLowerThird)
            _lowerThirdBox(
              title: template.lowerThirdTitle,
              subtitle: template.lowerThirdSubtitle,
              top: lowerThirdTop,
              width: w * 0.68,
              height: ltH,
            ),
          // Combo: middle Urdu ribbon.
          if (showMiddle)
            Positioned(
              key: const Key('breaking-middle-ribbon'),
              top: middleTop,
              left: 0,
              right: 0,
              height: tickerH,
              child: Container(
                color: Color(template.middleColor),
                child: Row(
                  children: [
                    ribbonChip(
                      NigraanFinalLayout.urduChipText,
                      Colors.black,
                      tickerH,
                      fontFamily: _kasheeda(
                        NigraanFinalLayout.urduChipText,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          template.middleText.isEmpty
                              ? 'قومی خبریں'
                              : template.middleText,
                          style: TextStyle(
                            color: template.middleText.isEmpty
                                ? Colors.white70
                                : Colors.white,
                            fontSize: BreakingLayout.clampFontSize(
                              template.fontSize,
                              tickerH,
                            ),
                            fontWeight: FontWeight.bold,
                            fontFamily: _kasheeda(template.middleText),
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
          // Combo: bottom English ribbon (half-thickness).
          if (showBottom)
            Positioned(
              key: const Key('breaking-bottom-ribbon'),
              left: 0,
              right: 0,
              bottom: 0,
              height: englishH,
              child: Container(
                color: Color(template.bottomColor),
                child: Row(
                  children: [
                    ribbonChip(
                      NigraanFinalLayout.englishChipText,
                      Colors.black,
                      englishH,
                      fontFactor: 0.55,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          template.bottomText.isEmpty
                              ? 'International headlines'
                              : template.bottomText,
                          style: TextStyle(
                            color: template.bottomText.isEmpty
                                ? Colors.white70
                                : Colors.white,
                            fontSize: BreakingLayout.clampFontSize(
                              template.fontSize,
                              englishH,
                            ),
                            fontWeight: FontWeight.bold,
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
          // Single variants: bottom scrolling ticker strip.
          if (showBottomTicker)
            Positioned(
              key: const Key('breaking-ticker'),
              left: 0,
              right: 0,
              bottom: 0,
              height: tickerH,
              child: Container(
                color: Color(template.bottomColor),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ScrollingTickerText(
                    text: template.tickerText,
                    speed: template.speed,
                    direction: template.direction,
                    style: tickerStyle(
                      tickerH,
                      template.bottomColor,
                    ).copyWith(
                      fontFamily: _kasheeda(template.tickerText),
                    ),
                  ),
                ),
              ),
            ),
          if (template.pipEnabled)
            PipInset(
              position: template.pipPosition,
              scale: template.pipScale,
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

/// Classic template preview (9:16 frame): dark top bar with the
/// channel name + red LIVE chip, scrolling ticker strip at the
/// bottom, logo bug + capsule, lower third, interview plate,
/// category chip, intro/outro markers, PIP inset.
class ClassicPreview extends StatelessWidget {
  const ClassicPreview({
    super.key,
    required this.preset,
    this.fontReady = false,
    this.height = 320,
  });

  final ChannelPreset preset;
  final bool fontReady;
  final double height;

  String? _kasheeda(String text) =>
      fontReady && _hasArabic(text)
          ? AssetDownloadService.kasheedaFamily
          : null;

  @override
  Widget build(BuildContext context) {
    final h = height;
    final w = h * 9 / 16;
    final topBarH = h * 0.07;
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
    const gap = 6.0;
    final ltH = (h * 0.10).clamp(36.0, 200.0);
    final plateH = (h * 0.08).clamp(56.0, 120.0);

    final showTicker = preset.topRibbon.enabled;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    final hasInterviewPlate = preset.showInterviewPlate &&
        preset.interviewName.trim().isNotEmpty;
    final lowerBottom = showTicker ? h - tickerH - gap : h;
    final lowerThirdTop = lowerBottom - ltH;
    final interviewTop = hasLowerThird
        ? lowerThirdTop - gap - plateH
        : lowerBottom - gap - plateH;

    final initial = preset.name.trim().isEmpty
        ? 'N'
        : preset.name.trim()[0].toUpperCase();

    return Container(
      key: const Key('classic-preview'),
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
          Positioned(
            key: const Key('classic-top-bar'),
            top: 0,
            left: 0,
            right: 0,
            height: topBarH,
            child: Container(
              color: const Color(0xFF1B1B2F),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.name.isEmpty ? 'Channel' : preset.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (topBarH * 0.42).clamp(10.0, 18.0),
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    color: const Color(0xFFD50000),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      ClassicLayout.liveChipText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (topBarH * 0.38).clamp(9.0, 16.0),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            key: const Key('preview-logo-bug'),
            top: topBarH + 8,
            right: 8,
            child: LogoBug(
              logoPath: preset.logoPath,
              initial: initial,
              size: 52,
            ),
          ),
          Positioned(
            top: topBarH + 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preset.categoryLabel.trim().isNotEmpty)
                  _pill(preset.categoryLabel.trim().toUpperCase()),
                if (preset.categoryLabel.trim().isNotEmpty)
                  const SizedBox(height: 4),
                if (preset.showIntro)
                  Row(
                    children: [
                      _pill(
                        NigraanFinalLayout.introMarkerText,
                        bold: false,
                      ),
                      if (preset.showOutro) ...[
                        const SizedBox(width: 4),
                        _pill(
                          NigraanFinalLayout.outroMarkerText,
                          bold: false,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (hasInterviewPlate)
            _interviewPlate(
              name: preset.interviewName,
              designation: preset.interviewDesignation,
              top: interviewTop,
              width: w * 0.68,
              height: plateH,
            ),
          if (hasLowerThird)
            _lowerThirdBox(
              title: preset.lowerThirdTitle,
              subtitle: preset.lowerThirdSubtitle,
              top: lowerThirdTop,
              width: w * 0.68,
              height: ltH,
            ),
          if (showTicker)
            Positioned(
              key: const Key('classic-ticker'),
              left: 0,
              right: 0,
              bottom: 0,
              height: tickerH,
              child: Container(
                color: Color(preset.topRibbon.color),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ScrollingTickerText(
                    text: preset.topRibbon.text,
                    speed: preset.topRibbon.speed,
                    direction: preset.topRibbon.direction,
                    style: TextStyle(
                      color: _textOn(preset.topRibbon.color),
                      fontSize: BreakingLayout.clampFontSize(
                        preset.topRibbon.fontSize,
                        tickerH,
                      ),
                      fontWeight: FontWeight.bold,
                      fontFamily: _kasheeda(preset.topRibbon.text),
                    ),
                  ),
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
