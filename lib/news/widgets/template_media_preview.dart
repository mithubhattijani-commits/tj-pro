/// Template + user-media composite preview (v1.5.0, fix #32).
///
/// The Final template's main area exists for the USER's own news
/// video/photo, but v1.4.0 gave News Studio no way to put media
/// there. This widget composites the project's first clip UNDER the
/// template furniture exactly where the export puts it: the export
/// renders the clip full-frame and draws the ribbons / logo /
/// lower-third OVER it, so here the media layer is sized to the full
/// frame and clipped to the main-area shape — full width from the
/// top (below the classic top ticker) down to the ribbon stack,
/// with a notch cut out for the logo block, which hangs into the
/// main area above the middle ribbon. The furniture itself is the
/// REAL [NigraanFinalPreview] (unguessable parity geometry — this
/// file only replicates its published layout fractions from
/// [ParityGeometry] to compute the clip shape; it never re-draws a
/// ribbon).
///
/// Honest limits: only the FIRST clip is previewed (the export uses
/// all of them, in order); a video clip autoplays muted + looped.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../live/parity_template.dart';
import '../channel_preset.dart';
import '../element_override.dart';
import 'nigraan_final_preview.dart';

/// True for file extensions the reel export treats as a still photo
/// (photoClipCommand path) rather than a video (normalize path).
bool isPhotoMediaPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.gif');
}

class TemplateMediaPreview extends StatefulWidget {
  const TemplateMediaPreview({
    super.key,
    required this.preset,
    required this.mediaPaths,
    this.fontReady = false,
    this.height = 300,
    this.elementOverrides = const {},
  });

  final ChannelPreset preset;

  /// v1.5.0 (#33): the project's manual element overrides — the
  /// furniture preview receives them, the media layer is moved /
  /// scaled / hidden by the media override, and the logo notch
  /// follows the logo + capsule overrides.
  final Map<String, ElementOverride> elementOverrides;

  /// The project's clip paths, in order; the first existing file is
  /// previewed in the main area.
  final List<String> mediaPaths;
  final bool fontReady;
  final double height;

  @override
  State<TemplateMediaPreview> createState() => _TemplateMediaPreviewState();
}

class _TemplateMediaPreviewState extends State<TemplateMediaPreview> {
  VideoPlayerController? _controller;
  String? _videoPath;

  String? get _firstExisting {
    for (final path in widget.mediaPaths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(TemplateMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final first = _firstExisting;
    final videoPath =
        (first != null && !isPhotoMediaPath(first)) ? first : null;
    if (videoPath == _videoPath) return;
    _videoPath = videoPath;
    final old = _controller;
    _controller = null;
    if (old != null) {
      unawaited(old.dispose());
    }
    if (videoPath != null) {
      final controller = VideoPlayerController.file(File(videoPath));
      _controller = controller;
      unawaited(() async {
        try {
          await controller.initialize();
          await controller.setLooping(true);
          await controller.setVolume(0);
          await controller.play();
          if (mounted) setState(() {});
        } catch (_) {
          // A broken clip file must never break the preview — the
          // plain template preview underneath stays visible.
        }
      }());
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final h = widget.height;
    final w = h * 9 / 16;
    final first = _firstExisting;

    // --- Main-area geometry: the SAME fractions/clamps the real
    // preview uses (see NigraanFinalPreview.build), computed from
    // the shared ParityGeometry — replicated, never re-drawn.
    final isFinal3 = preset.finalIs3Ribbon;
    final g = ParityGeometry(
      1080,
      1920,
      variant: isFinal3 ? ParityVariant.final3 : ParityVariant.classic2,
      overrides: widget.elementOverrides,
    );
    final mediaOv = overrideFor(widget.elementOverrides, NewsElement.media);
    final logoOv = overrideFor(widget.elementOverrides, NewsElement.logo);
    final capOv = overrideFor(widget.elementOverrides, NewsElement.capsule);
    final scaleW = w / 1080;
    final scaleH = h / 1920;
    final ribbonH = (g.ribbonH * scaleH).clamp(22.0, 200.0);
    final f3TopH = (g.f3TopH * scaleH).clamp(12.0, 200.0);
    final f3MidH = (g.f3MidH * scaleH).clamp(18.0, 200.0);
    final f3BotH = (g.f3BotH * scaleH).clamp(12.0, 200.0);
    final tickerH = (h * 0.055).clamp(26.0, 44.0);
    const gap = 6.0;
    final ltH = (h * 0.10).clamp(36.0, 200.0);
    final plateH = (h * 0.08).clamp(56.0, 120.0);

    final showTicker = !isFinal3 && preset.topRibbon.enabled;
    final showTop = isFinal3 && preset.topRibbon.enabled;
    final showUrdu = preset.urduRibbon.enabled;
    final showEnglish = preset.englishRibbon.enabled;
    final hasLowerThird = preset.showLowerThird &&
        (preset.lowerThirdTitle.trim().isNotEmpty ||
            preset.lowerThirdSubtitle.trim().isNotEmpty);
    final hasInterviewPlate =
        preset.showInterviewPlate && preset.interviewName.trim().isNotEmpty;

    final midH = isFinal3 ? f3MidH : ribbonH;
    final botH = isFinal3 ? f3BotH : ribbonH;
    final englishTop = h - botH;
    final urduTop = (showEnglish ? englishTop : h) - midH;
    final stackBelowTop = showUrdu ? urduTop : (showEnglish ? englishTop : h);
    final topStackTop = stackBelowTop - f3TopH;
    final ribbonsTop = showTop ? topStackTop : stackBelowTop;
    final lowerThirdTop = ribbonsTop - gap - ltH;
    final interviewTop =
        (hasLowerThird ? lowerThirdTop : ribbonsTop) - gap - plateH;

    // The media's bottom edge: the topmost furniture element that
    // floats over the main area (interview plate > lower third >
    // ribbon stack).
    final mediaBottom = hasInterviewPlate
        ? interviewTop
        : hasLowerThird
            ? lowerThirdTop
            : ribbonsTop;
    final mediaTop = showTicker ? tickerH : 0.0;

    // Logo notch: the block hangs into the main area above the
    // capsule, which sits on the middle ribbon.
    final logoW = g.logoVisibleW * scaleW;
    final logoH = isFinal3 ? logoW * 344 / 408 : logoW * 347 / 422;
    final capsuleH =
        (g.capsuleH * scaleH).clamp(isFinal3 ? 9.0 : 15.0, 200.0);
    final capTop = urduTop + midH - capsuleH - g.f3BlockLift * scaleH +
        capOv.dy * h;
    final logoTop = capTop - logoH;
    final logoLeft = w - g.logoMargin * scaleW - logoW + logoOv.dx * w;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          NigraanFinalPreview(
            preset: preset,
            fontReady: widget.fontReady,
            height: h,
            elementOverrides: widget.elementOverrides,
          ),
          if (first != null && !mediaOv.hidden)
            Positioned.fill(
              child: ClipPath(
                clipper: _MainAreaClipper(
                  top: mediaTop,
                  bottom: mediaBottom,
                  notchTop: logoTop,
                  notchLeft: logoLeft,
                ),
                child: Transform.translate(
                  offset: Offset(mediaOv.dx * w, mediaOv.dy * h),
                  child: Transform.scale(
                    scale: mediaOv.scale,
                    child: _mediaLayer(first),
                  ),
                ),
              ),
            ),
          if (first != null && widget.mediaPaths.length > 1)
            Positioned(
              left: 8,
              top: mediaTop + 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.mediaPaths.length} clips — pehli clip ka preview',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mediaLayer(String path) {
    if (isPhotoMediaPath(path)) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF101018));
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// The main-area L-shape: the full-width band [top]..[bottom], with
/// the logo block's rectangle (from [notchTop] down, at the right)
/// cut out so the template's logo stays visible over the media —
/// the same stacking the export renders.
class _MainAreaClipper extends CustomClipper<Path> {
  const _MainAreaClipper({
    required this.top,
    required this.bottom,
    required this.notchTop,
    required this.notchLeft,
  });

  final double top;
  final double bottom;
  final double notchTop;
  final double notchLeft;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final notchFrom = notchTop.clamp(top, bottom);
    return Path()
      ..moveTo(0, top)
      ..lineTo(w, top)
      ..lineTo(w, notchFrom)
      ..lineTo(notchLeft, notchFrom)
      ..lineTo(notchLeft, bottom)
      ..lineTo(0, bottom)
      ..close();
  }

  @override
  bool shouldReclip(_MainAreaClipper oldClipper) =>
      top != oldClipper.top ||
      bottom != oldClipper.bottom ||
      notchTop != oldClipper.notchTop ||
      notchLeft != oldClipper.notchLeft;
}

/// v1.5.0 (#33): the Final template's element rectangles in a
/// [w]x[h] preview frame, WITH the project's overrides applied —
/// the News Maker's selection / drag layer hit-tests against
/// these, so what the user grabs is exactly what the preview
/// shows. Media = the main area (frame top down to the ribbon
/// stack); headline/ticker text share their band's rect.
Map<String, Rect> finalElementRects({
  required ChannelPreset preset,
  required Map<String, ElementOverride> overrides,
  required double w,
  required double h,
}) {
  final isFinal3 = preset.finalIs3Ribbon;
  final g = ParityGeometry(
    1080,
    1920,
    variant: isFinal3 ? ParityVariant.final3 : ParityVariant.classic2,
    overrides: overrides,
  );
  final sx = w / 1080;
  final sy = h / 1920;
  Rect scale(Rect r) =>
      Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy);
  final top = isFinal3 ? g.f3TopStrip : Rect.fromLTWH(0, 0, 1080, 1920 * 0.055);
  final mid = isFinal3 ? g.f3MidStrip : g.urduStrip;
  final bot = isFinal3 ? g.f3BotStrip : g.englishStrip;
  return {
    NewsElement.media: Rect.fromLTWH(0, 0, w, mid.top * sy),
    NewsElement.topRibbon: scale(top),
    NewsElement.middleRibbon: scale(mid),
    NewsElement.headlineText: scale(mid),
    NewsElement.bottomRibbon: scale(bot),
    NewsElement.tickerText: scale(bot),
    NewsElement.logo: scale(g.logoVisible),
    NewsElement.capsule: scale(g.capsule),
    NewsElement.overlay: Rect.fromLTWH(
      w - w * 0.2 - 8,
      8,
      w * 0.2,
      w * 0.2,
    ),
  };
}
