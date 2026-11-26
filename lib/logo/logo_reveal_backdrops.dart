import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Shared Theme Constants
// ---------------------------------------------------------------------------

const Color _kBackgroundColor = Color(0xFF050914);
const Color _kCardFillColor = Color(0x0FFFFFFF); // White at 6% opacity
const Color _kCardBorderColor = Color(0x1FFFFFFF); // White at 12% opacity
const Color _kAccentBlue = Color(0xFF2E7CF6);
const Color _kAccentPurple = Color(0xFF8B5CF6);
const Color _kAccentCyan = Color(0xFF22D3EE);
const double _kCardRadius = 22.0;

const LinearGradient _kAccentGradient = LinearGradient(
  colors: <Color>[_kAccentBlue, _kAccentPurple, _kAccentCyan],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

Color _withAlphaFraction(Color color, double opacity) {
  return color.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

// ---------------------------------------------------------------------------
// PART A — REVEAL
// ---------------------------------------------------------------------------

/// Metadata defining an animated logo reveal style.
class LogoRevealStyle {
  const LogoRevealStyle({
    required this.id,
    required this.name,
    required this.durationMs,
  });

  final String id;
  final String name;
  final int durationMs;
}

/// Built-in reveal animation styles.
const List<LogoRevealStyle> kLogoRevealStyles = <LogoRevealStyle>[
  LogoRevealStyle(id: 'fade_zoom', name: 'Fade Zoom', durationMs: 1200),
  LogoRevealStyle(id: 'slide_wipe', name: 'Slide Wipe', durationMs: 1000),
  LogoRevealStyle(id: 'shine_sweep', name: 'Shine Sweep', durationMs: 1400),
  LogoRevealStyle(id: 'bounce_in', name: 'Bounce In', durationMs: 1100),
  LogoRevealStyle(id: 'spin_reveal', name: 'Spin Reveal', durationMs: 1300),
  LogoRevealStyle(id: 'rise_glow', name: 'Rise & Glow', durationMs: 1500),
];

/// Renders a logo [ui.Image] on a transparent background according to [styleId]
/// and normalized [progress] (`0.0` to `1.0`).
class LogoRevealPainter extends CustomPainter {
  LogoRevealPainter({
    required this.image,
    required this.styleId,
    required this.progress,
    this.glowColor = _kAccentCyan,
  });

  final ui.Image image;
  final String styleId;
  final double progress;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image.width == 0 || image.height == 0) {
      return;
    }

    final double t = progress.clamp(0.0, 1.0);
    if (t <= 0.0) {
      return;
    }

    final Rect srcRect = Rect.fromLTWH(
      0.0,
      0.0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final double maxSide = math.min(size.width, size.height) * 0.80;
    final double fitScale = math.min(
      maxSide / srcRect.width,
      maxSide / srcRect.height,
    );
    final Rect destRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.5),
      width: srcRect.width * fitScale,
      height: srcRect.height * fitScale,
    );

    // Identical plain settled end state at progress 1.0 for every style.
    if (t >= 1.0) {
      _drawLogo(canvas, srcRect, destRect, 1.0);
      return;
    }

    switch (styleId) {
      case 'slide_wipe':
        _paintSlideWipe(canvas, size, srcRect, destRect, t);
      case 'shine_sweep':
        _paintShineSweep(canvas, srcRect, destRect, t);
      case 'bounce_in':
        _paintBounceIn(canvas, srcRect, destRect, t);
      case 'spin_reveal':
        _paintSpinReveal(canvas, srcRect, destRect, t);
      case 'rise_glow':
        _paintRiseGlow(canvas, srcRect, destRect, t);
      case 'fade_zoom':
      default:
        _paintFadeZoom(canvas, srcRect, destRect, t);
    }
  }

  void _paintFadeZoom(Canvas canvas, Rect src, Rect dst, double t) {
    final double eased = Curves.easeOut.transform(t);
    final double scale = ui.lerpDouble(0.70, 1.00, eased)!;

    canvas.save();
    canvas.translate(dst.center.dx, dst.center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-dst.center.dx, -dst.center.dy);
    _drawLogo(canvas, src, dst, t);
    canvas.restore();
  }

  void _paintSlideWipe(
    Canvas canvas,
    Size size,
    Rect src,
    Rect dst,
    double t,
  ) {
    final double eased = Curves.easeOut.transform(t);
    final double dx = ui.lerpDouble(-dst.width * 0.60, 0.0, eased)!;
    final double opacity = ui.lerpDouble(0.40, 1.00, t)!;
    final Rect clipRect = Rect.fromLTWH(
      dst.left,
      0.0,
      dst.width * eased,
      size.height,
    );

    canvas.save();
    canvas.clipRect(clipRect);
    _drawLogo(canvas, src, dst.shift(Offset(dx, 0.0)), opacity);
    canvas.restore();
  }

  void _paintShineSweep(Canvas canvas, Rect src, Rect dst, double t) {
    final double logoOpacity = (t / 0.15).clamp(0.0, 1.0);
    if (logoOpacity <= 0.0) {
      return;
    }

    _drawLogo(canvas, src, dst, logoOpacity);

    // Diagonal bright light band sweeps across and exits before progress 1.0.
    final double sweepRaw = ((t - 0.10) / 0.85).clamp(0.0, 1.0);
    if (sweepRaw <= 0.0 || sweepRaw >= 1.0) {
      return;
    }

    final double easedSweep = Curves.easeInOut.transform(sweepRaw);
    const Offset dir = Offset(0.866, 0.5);
    final double halfSpan = dst.width * 0.28;
    final double maxProj =
        (dst.width * 0.5) * dir.dx + (dst.height * 0.5) * dir.dy;
    final double offsetAlongDir = ui.lerpDouble(
      -(maxProj + halfSpan),
      maxProj + halfSpan,
      easedSweep,
    )!;
    final Offset bandCenter = dst.center + dir * offsetAlongDir;
    final Offset from = bandCenter - dir * halfSpan;
    final Offset to = bandCenter + dir * halfSpan;

    // Mask the gradient strictly to the logo alpha, then screen-blend it.
    canvas.saveLayer(dst, Paint()..blendMode = BlendMode.screen);
    _drawLogo(canvas, src, dst, logoOpacity);
    final Paint shinePaint = Paint()
      ..blendMode = BlendMode.srcIn
      ..shader = ui.Gradient.linear(
        from,
        to,
        const <Color>[
          Color(0x00FFFFFF),
          Color(0x55FFFFFF),
          Color(0xE6FFFFFF),
          Color(0x55FFFFFF),
          Color(0x00FFFFFF),
        ],
        const <double>[0.0, 0.32, 0.50, 0.68, 1.0],
      );
    canvas.drawRect(dst, shinePaint);
    canvas.restore();
  }

  void _paintBounceIn(Canvas canvas, Rect src, Rect dst, double t) {
    final double opacity = math.min(1.0, t * 2.0);
    final double eased = Curves.easeOutBack.transform(t);
    final double scale = 0.20 + 0.80 * eased;

    canvas.save();
    canvas.translate(dst.center.dx, dst.center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-dst.center.dx, -dst.center.dy);
    _drawLogo(canvas, src, dst, opacity);
    canvas.restore();
  }

  void _paintSpinReveal(Canvas canvas, Rect src, Rect dst, double t) {
    final double eased = Curves.easeOut.transform(t);
    final double angle = (1.0 - eased) * 6.0 * math.pi;
    final double scaleX = math.cos(angle);
    if (scaleX.abs() < 0.001) {
      return;
    }

    final double baseScale = ui.lerpDouble(0.60, 1.00, eased)!;

    canvas.save();
    canvas.translate(dst.center.dx, dst.center.dy);
    canvas.scale(baseScale * scaleX, baseScale);
    canvas.translate(-dst.center.dx, -dst.center.dy);
    _drawLogo(canvas, src, dst, t);
    canvas.restore();
  }

  void _paintRiseGlow(Canvas canvas, Rect src, Rect dst, double t) {
    final double eased = Curves.easeOut.transform(t);
    final double dy = ui.lerpDouble(dst.height * 0.25, 0.0, eased)!;
    final Rect shiftedDst = dst.shift(Offset(0.0, dy));

    // Glow peaks at progress 0.7 and settles toward 40% approaching 1.0.
    final double glowStrength = t <= 0.7
        ? Curves.easeOut.transform(t / 0.7)
        : ui.lerpDouble(1.0, 0.4, (t - 0.7) / 0.3)!;

    final double blurSigma = ui.lerpDouble(6.0, 20.0, glowStrength)!;
    final Paint glowPaint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.mode(
        _withAlphaFraction(glowColor, glowStrength * 0.85),
        BlendMode.srcIn,
      )
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
      );

    canvas.drawImageRect(image, src, shiftedDst, glowPaint);
    _drawLogo(canvas, src, shiftedDst, t);
  }

  void _drawLogo(Canvas canvas, Rect src, Rect dst, double opacity) {
    final double clamped = opacity.clamp(0.0, 1.0);
    if (clamped <= 0.0) {
      return;
    }
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.high
      ..color = _withAlphaFraction(Colors.white, clamped);
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant LogoRevealPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.styleId != styleId ||
        oldDelegate.progress != progress ||
        oldDelegate.glowColor != glowColor;
  }
}

// ---------------------------------------------------------------------------
// PART B — BACKDROP SCENES
// ---------------------------------------------------------------------------

/// Metadata defining a procedural backdrop scene.
class LogoBackdropDef {
  const LogoBackdropDef({required this.id, required this.name});

  final String id;
  final String name;
}

/// Built-in procedural backdrop scenes.
const List<LogoBackdropDef> kLogoBackdrops = <LogoBackdropDef>[
  LogoBackdropDef(id: 'midnight_studio', name: 'Midnight Studio'),
  LogoBackdropDef(id: 'royal_stage', name: 'Royal Stage'),
  LogoBackdropDef(id: 'neon_grid', name: 'Neon Grid'),
  LogoBackdropDef(id: 'soft_spotlight', name: 'Soft Spotlight'),
  LogoBackdropDef(id: 'deep_ocean', name: 'Deep Ocean'),
  LogoBackdropDef(id: 'plain_dark', name: 'Plain Dark'),
];

/// Procedurally paints a dark studio backdrop filling the entire canvas.
class LogoBackdropPainter extends CustomPainter {
  LogoBackdropPainter({
    required this.backdropId,
    this.glowIntensity = 0.6,
  });

  final String backdropId;
  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final Rect rect = Offset.zero & size;
    final double intensity = glowIntensity.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRect(rect);

    switch (backdropId) {
      case 'midnight_studio':
        _paintMidnightStudio(canvas, rect, size, intensity);
      case 'royal_stage':
        _paintRoyalStage(canvas, rect, size, intensity);
      case 'neon_grid':
        _paintNeonGrid(canvas, rect, size, intensity);
      case 'soft_spotlight':
        _paintSoftSpotlight(canvas, rect, size, intensity);
      case 'deep_ocean':
        _paintDeepOcean(canvas, rect, size, intensity);
      case 'plain_dark':
      default:
        _paintPlainDark(canvas, rect, size);
    }

    canvas.restore();
  }

  void _paintMidnightStudio(
    Canvas canvas,
    Rect rect,
    Size size,
    double intensity,
  ) {
    _fillVerticalGradient(
      canvas,
      rect,
      const <Color>[Color(0xFF050914), Color(0xFF0A1230)],
    );
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.5, size.height * 0.40),
      radius: math.max(size.width, size.height) * 0.62,
      color: _kAccentBlue,
      alpha: 0.42 * intensity,
    );
  }

  void _paintRoyalStage(
    Canvas canvas,
    Rect rect,
    Size size,
    double intensity,
  ) {
    _fillVerticalGradient(
      canvas,
      rect,
      const <Color>[Color(0xFF090514), Color(0xFF150B2B), Color(0xFF080410)],
      stops: const <double>[0.0, 0.55, 1.0],
    );

    final double maxDim = math.max(size.width, size.height);
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.22, size.height * 0.24),
      radius: maxDim * 0.56,
      color: _kAccentPurple,
      alpha: 0.34 * intensity,
    );
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.80, size.height * 0.78),
      radius: maxDim * 0.52,
      color: const Color(0xFFF59E0B),
      alpha: 0.24 * intensity,
    );

    // Soft elliptical stage floor glow near the bottom.
    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.88);
    canvas.scale(1.0, 0.28);
    _drawSoftGlow(
      canvas,
      center: Offset.zero,
      radius: size.width * 0.56,
      color: const Color(0xFFE9D5FF),
      alpha: 0.16 * intensity + 0.04,
    );
    canvas.restore();
  }

  void _paintNeonGrid(
    Canvas canvas,
    Rect rect,
    Size size,
    double intensity,
  ) {
    const double horizonRatio = 0.55;
    final double horizonY = size.height * horizonRatio;
    final Offset vanishingPoint = Offset(size.width * 0.5, horizonY);

    _fillVerticalGradient(
      canvas,
      rect,
      const <Color>[Color(0xFF030712), Color(0xFF06162B), Color(0xFF040A18)],
      stops: const <double>[0.0, horizonRatio, 1.0],
    );

    // Soft elongated cyan glow along the horizon.
    canvas.save();
    canvas.translate(vanishingPoint.dx, vanishingPoint.dy);
    canvas.scale(1.45, 0.42);
    _drawSoftGlow(
      canvas,
      center: Offset.zero,
      radius: size.width * 0.48,
      color: _kAccentCyan,
      alpha: 0.38 * intensity + 0.06,
    );
    canvas.restore();

    // Perspective grid lines below the 55% horizon.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0.0, horizonY, size.width, size.height));

    final Paint convergingPaint = Paint()
      ..strokeWidth = 1.0
      ..shader = ui.Gradient.linear(
        Offset(0.0, horizonY),
        Offset(0.0, size.height),
        <Color>[
          _withAlphaFraction(_kAccentCyan, 0.04 * intensity),
          _withAlphaFraction(_kAccentCyan, 0.42 * intensity + 0.10),
        ],
      );

    for (int i = -7; i <= 7; i++) {
      final double bottomX = size.width * 0.5 + i * (size.width * 0.18);
      canvas.drawLine(
        vanishingPoint,
        Offset(bottomX, size.height),
        convergingPaint,
      );
    }

    const int horizontalRows = 10;
    for (int i = 1; i <= horizontalRows; i++) {
      final double frac = i / horizontalRows;
      final double y = horizonY + (size.height - horizonY) * (frac * frac);
      final Paint rowPaint = Paint()
        ..strokeWidth = 1.0
        ..color = _withAlphaFraction(
          _kAccentCyan,
          (0.08 + 0.34 * frac) * intensity + 0.05,
        );
      canvas.drawLine(Offset(0.0, y), Offset(size.width, y), rowPaint);
    }

    canvas.restore();

    // Subtle glowing horizon seam fading to transparent at edges.
    final Paint horizonLinePaint = Paint()
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(
        Offset(0.0, horizonY),
        Offset(size.width, horizonY),
        <Color>[
          const Color(0x0022D3EE),
          _withAlphaFraction(_kAccentCyan, 0.45 * intensity + 0.10),
          const Color(0x0022D3EE),
        ],
        const <double>[0.0, 0.5, 1.0],
      );
    canvas.drawLine(
      Offset(0.0, horizonY),
      Offset(size.width, horizonY),
      horizonLinePaint,
    );
  }

  void _paintSoftSpotlight(
    Canvas canvas,
    Rect rect,
    Size size,
    double intensity,
  ) {
    _fillVerticalGradient(
      canvas,
      rect,
      const <Color>[Color(0xFF14161D), Color(0xFF06070B)],
    );
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.5, size.height * 0.06),
      radius: math.max(size.width, size.height) * 0.85,
      color: Colors.white,
      alpha: 0.28 * intensity + 0.05,
    );
  }

  void _paintDeepOcean(
    Canvas canvas,
    Rect rect,
    Size size,
    double intensity,
  ) {
    _fillVerticalGradient(
      canvas,
      rect,
      const <Color>[Color(0xFF062A4A), Color(0xFF020B18)],
    );

    final double maxDim = math.max(size.width, size.height);
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.32, size.height * 0.28),
      radius: maxDim * 0.56,
      color: const Color(0xFF14B8A6),
      alpha: 0.30 * intensity,
    );
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.72, size.height * 0.72),
      radius: maxDim * 0.50,
      color: const Color(0xFF06B6D4),
      alpha: 0.22 * intensity,
    );

    // Deterministic soft translucent bubbles (fixed seed for identical repaints).
    final math.Random rng = math.Random(42);
    final double minDim = math.min(size.width, size.height);
    for (int i = 0; i < 14; i++) {
      final Offset center = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final double radius = (0.014 + rng.nextDouble() * 0.032) * minDim;
      final double alpha =
          (0.06 + rng.nextDouble() * 0.10) * (0.45 + 0.55 * intensity);
      final Paint bubblePaint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            _withAlphaFraction(const Color(0xFFBAE6FD), alpha),
            _withAlphaFraction(const Color(0xFF38BDF8), alpha * 0.45),
            const Color(0x0038BDF8),
          ],
          const <double>[0.0, 0.65, 1.0],
        );
      canvas.drawCircle(center, radius, bubblePaint);
    }
  }

  void _paintPlainDark(Canvas canvas, Rect rect, Size size) {
    canvas.drawRect(rect, Paint()..color = _kBackgroundColor);
    _drawSoftGlow(
      canvas,
      center: Offset(size.width * 0.5, size.height * 0.5),
      radius: math.max(size.width, size.height) * 0.65,
      color: Colors.white,
      alpha: 0.04,
    );
  }

  void _fillVerticalGradient(
    Canvas canvas,
    Rect rect,
    List<Color> colors, {
    List<double>? stops,
  }) {
    final Paint paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        colors,
        stops,
      );
    canvas.drawRect(rect, paint);
  }

  void _drawSoftGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double alpha,
  }) {
    if (radius <= 0.0 || alpha <= 0.0) {
      return;
    }
    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[
          _withAlphaFraction(color, alpha),
          _withAlphaFraction(color, alpha * 0.35),
          _withAlphaFraction(color, 0.0),
        ],
        const <double>[0.0, 0.48, 1.0],
      );
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant LogoBackdropPainter oldDelegate) {
    return oldDelegate.backdropId != backdropId ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}

// ---------------------------------------------------------------------------
// PART C — PREVIEW WIDGET
// ---------------------------------------------------------------------------

/// Interactive preview studio combining procedural backdrops and logo reveals.
class LogoRevealStudio extends StatefulWidget {
  const LogoRevealStudio({super.key, required this.logoImage});

  final ui.Image logoImage;

  @override
  State<LogoRevealStudio> createState() => _LogoRevealStudioState();
}

class _LogoRevealStudioState extends State<LogoRevealStudio>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String _selectedStyleId = kLogoRevealStyles.first.id;
  String _selectedBackdropId = kLogoBackdrops.first.id;

  LogoRevealStyle get _selectedStyle {
    return kLogoRevealStyles.firstWhere(
      (LogoRevealStyle style) => style.id == _selectedStyleId,
      orElse: () => kLogoRevealStyles.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _selectedStyle.durationMs),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playFromStart() {
    _controller.duration = Duration(milliseconds: _selectedStyle.durationMs);
    _controller.forward(from: 0.0);
  }

  void _selectStyle(LogoRevealStyle style) {
    setState(() {
      _selectedStyleId = style.id;
    });
    _controller.duration = Duration(milliseconds: style.durationMs);
    _controller.forward(from: 0.0);
  }

  void _selectBackdrop(LogoBackdropDef backdrop) {
    setState(() {
      _selectedBackdropId = backdrop.id;
    });
  }

  void _onScrub(double value) {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    _controller.value = value.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final double previewHeight = MediaQuery.sizeOf(context).height * 0.46;

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Logo Reveal Studio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14.0),
              _buildPreviewCard(previewHeight),
              const SizedBox(height: 14.0),
              _buildPlaybackCard(),
              const SizedBox(height: 16.0),
              const Text(
                'Reveal Style',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10.0),
              _buildRevealStyleRow(),
              const SizedBox(height: 16.0),
              const Text(
                'Backdrop Scene',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10.0),
              _buildBackdropRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius - 1.0),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              painter: LogoBackdropPainter(backdropId: _selectedBackdropId),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: LogoRevealPainter(
                    image: widget.logoImage,
                    styleId: _selectedStyleId,
                    progress: _controller.value,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final int percent = (_controller.value * 100).round();
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _buildPlayButton(),
                  const SizedBox(width: 14.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const Text(
                              'Progress',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$percent%  •  ${_selectedStyle.durationMs}ms',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _kAccentCyan,
                            inactiveTrackColor: _kCardBorderColor,
                            thumbColor: _kAccentCyan,
                            overlayColor: _withAlphaFraction(_kAccentCyan, 0.2),
                            trackHeight: 4.0,
                          ),
                          child: Slider(
                            value: _controller.value,
                            min: 0.0,
                            max: 1.0,
                            onChanged: _onScrub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      onTap: _playFromStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
        decoration: BoxDecoration(
          gradient: _kAccentGradient,
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20.0),
            SizedBox(width: 4.0),
            Text(
              'Play',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevealStyleRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < kLogoRevealStyles.length; i++) ...<Widget>[
            _buildChip(
              label: kLogoRevealStyles[i].name,
              selected: kLogoRevealStyles[i].id == _selectedStyleId,
              onTap: () => _selectStyle(kLogoRevealStyles[i]),
            ),
            if (i < kLogoRevealStyles.length - 1) const SizedBox(width: 10.0),
          ],
        ],
      ),
    );
  }

  Widget _buildBackdropRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < kLogoBackdrops.length; i++) ...<Widget>[
            _buildChip(
              label: kLogoBackdrops[i].name,
              selected: kLogoBackdrops[i].id == _selectedBackdropId,
              onTap: () => _selectBackdrop(kLogoBackdrops[i]),
            ),
            if (i < kLogoBackdrops.length - 1) const SizedBox(width: 10.0),
          ],
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          gradient: selected ? _kAccentGradient : null,
          color: selected ? null : _kCardFillColor,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: selected
              ? null
              : Border.all(color: _kCardBorderColor, width: 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12.0,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
