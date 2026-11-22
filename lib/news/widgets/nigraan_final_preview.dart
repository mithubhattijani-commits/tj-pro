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
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../live/news_template.dart';
import '../../live/parity_template.dart';
import '../../services/asset_download_service.dart';
import '../channel_preset.dart';
import '../watermark.dart';
import 'pip_inset.dart';

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

/// Full template preview (9:16 frame).
///
/// v1.3.0 (§9 Final-template parity): the preview now mirrors the
/// REAL reference template — the same geometry the export renders
/// ([ParityGeometry] in lib/live/parity_template.dart): two FLUSH,
/// equal-height bottom ribbons; the Urdu chip at the RIGHT with
/// GOLD text; the English chip at the left with GOLD text; BOTH
/// ribbons SCROLL (Urdu rightward, English leftward) with gold-dot
/// separators; the logo sits bottom-right with the flipping
/// TIME (with seconds) <-> Urdu DATE capsule directly under it.
/// The optional top ticker still scrolls at the top. Ribbon
/// heights carry a small legibility floor at preview sizes (the
/// export uses the exact fractions).
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
    // Parity fractions at preview scale (reference 1080x1920).
    final g = ParityGeometry(1080, 1920);
    final scaleW = w / 1080;
    final ribbonH = (g.ribbonH * (h / 1920)).clamp(22.0, 200.0);
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
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

    // Flush stack: English at the very bottom, Urdu directly on it.
    final englishTop = h - ribbonH;
    final urduTop = (showEnglish ? englishTop : h) - ribbonH;
    final ribbonsTop = showUrdu ? urduTop : (showEnglish ? englishTop : h);
    final lowerThirdTop = ribbonsTop - gap - ltH;
    final plateH = (h * 0.08).clamp(56.0, 120.0);
    final interviewTop =
        (hasLowerThird ? lowerThirdTop : ribbonsTop) - gap - plateH;

    final logoW = g.logoVisibleW * scaleW;
    final logoH = logoW * 347 / 422;
    final capsuleH = (g.capsuleH * (h / 1920)).clamp(15.0, 200.0);
    final logoRight = g.logoMargin * scaleW;

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
              left: 0,
              right: 0,
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
                          speed: preset.topRibbon.speed,
                          direction: preset.topRibbon.direction,
                          style: topStyle(preset.topRibbon, tickerH),
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
          // Logo + flipping capsule stack, bottom-right, sitting
          // directly on the ribbons (v1.3.0 parity).
          Positioned(
            key: const Key('preview-logo-bug'),
            right: logoRight,
            bottom: (showUrdu || showEnglish)
                ? (h - ribbonsTop) + capsuleH
                : capsuleH + 4,
            child: _ParityLogoBox(
              logoPath: preset.logoPath,
              initial: initial,
              width: logoW,
              height: logoH,
            ),
          ),
          Positioned(
            right: logoRight,
            bottom: showUrdu || showEnglish ? h - ribbonsTop : 4,
            child: _ParityCapsule(
              width: logoW,
              height: capsuleH,
              fontReady: fontReady,
            ),
          ),
          if (showUrdu)
            Positioned(
              key: const Key('preview-middle-ribbon'),
              top: urduTop,
              left: 0,
              right: 0,
              height: ribbonH,
              child: Container(
                color: Color(preset.urduRibbon.color),
                child: Column(
                  children: [
                    Container(height: 2, color: const Color(0xFFF5C542)),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _ParityScrollText(
                              text: preset.urduRibbon.text.isEmpty
                                  ? 'قومی خبریں'
                                  : preset.urduRibbon.text,
                              rtl: true,
                              speedPxPerSec: g.scrollSpeed * scaleW,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: ribbonH * 0.5625,
                                fontWeight: FontWeight.bold,
                                fontFamily:
                                    _kasheeda(preset.urduRibbon.text),
                              ),
                            ),
                          ),
                          if (preset.showBreakingBanner)
                            parityChip(
                              label: NigraanFinalLayout.urduChipText,
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
              left: 0,
              right: 0,
              bottom: 0,
              height: ribbonH,
              child: Container(
                color: Color(preset.englishRibbon.color),
                child: Column(
                  children: [
                    Container(height: 2, color: const Color(0xFFF5C542)),
                    Expanded(
                      child: Row(
                        children: [
                          parityChip(
                            label: NigraanFinalLayout.englishChipText,
                            widthPx: g.englishChipW * scaleW,
                            dividerOnLeft: false,
                            fontSize: ribbonH * 0.45,
                          ),
                          Expanded(
                            child: _ParityScrollText(
                              text: preset.englishRibbon.text.isEmpty
                                  ? 'International headlines'
                                  : preset.englishRibbon.text,
                              rtl: false,
                              speedPxPerSec: g.scrollSpeed * scaleW,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ).copyWith(fontSize: ribbonH * 0.53),
                            ),
                          ),
                        ],
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

/// The parity logo box: the picked logo image fitted into the
/// reference's VISIBLE box (185/1080 wide, 422:347), or the
/// channel initial tile when no logo is picked.
class _ParityLogoBox extends StatelessWidget {
  const _ParityLogoBox({
    required this.logoPath,
    required this.initial,
    required this.width,
    required this.height,
  });

  final String? logoPath;
  final String initial;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final path = logoPath;
    if (path != null && path.isNotEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _tile(),
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

/// The flipping TIME <-> Urdu DATE capsule (3s per face), black at
/// 67% alpha with a gold top line — the widget twin of the export's
/// drawtext clock + date PNG pair.
class _ParityCapsule extends StatefulWidget {
  const _ParityCapsule({
    required this.width,
    required this.height,
    required this.fontReady,
  });

  final double width;
  final double height;
  final bool fontReady;

  @override
  State<_ParityCapsule> createState() => _ParityCapsuleState();
}

class _ParityCapsuleState extends State<_ParityCapsule> {
  Timer? _timer;
  bool _showDate = false;

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
        color: Colors.black.withValues(alpha: 0.67),
        borderRadius: BorderRadius.circular(4),
        border: const Border(
          top: BorderSide(color: Color(0xFFF5C542), width: 2),
        ),
      ),
      alignment: Alignment.center,
      child: _showDate
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                parityUrduDate(now),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.height * 0.55,
                  fontFamily: dateFamily,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            )
          : Text(
              parityTimeString(now),
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.height * 0.55,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              softWrap: false,
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
  });

  final String text;
  final bool rtl;
  final double speedPxPerSec;
  final TextStyle style;

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
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
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
    _controller.repeat();
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
