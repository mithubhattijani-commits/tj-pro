import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Shared Theme Constants
// ---------------------------------------------------------------------------

const Color _kBgColor = Color(0xFF050914);
const Color _kCardFill = Color.fromRGBO(255, 255, 255, 0.06);
const Color _kCardBorder = Color.fromRGBO(255, 255, 255, 0.12);
const Color _kCyan = Color(0xFF22D3EE);
const double _kCardRadius = 22.0;

const LinearGradient _kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF2E7CF6),
    Color(0xFF8B5CF6),
    Color(0xFF22D3EE),
  ],
);

const List<BoxShadow> _kButtonGlow = [
  BoxShadow(
    color: Color.fromRGBO(46, 124, 246, 0.40),
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
  BoxShadow(
    color: Color.fromRGBO(34, 211, 238, 0.28),
    blurRadius: 12,
    offset: Offset(0, 2),
  ),
];

// ---------------------------------------------------------------------------
// PART A — TEXT TO LOGO
// ---------------------------------------------------------------------------

class LogoTextStyle {
  final String id;
  final String name;
  final String fontFamily;
  final FontWeight fontWeight;
  final double letterSpacing;
  final List<Color> gradientColors;
  final Color strokeColor;
  final double strokeWidth;
  final bool italic;

  const LogoTextStyle({
    required this.id,
    required this.name,
    required this.fontFamily,
    required this.fontWeight,
    required this.letterSpacing,
    required this.gradientColors,
    required this.strokeColor,
    required this.strokeWidth,
    required this.italic,
  });
}

const List<LogoTextStyle> kLogoTextStyles = [
  LogoTextStyle(
    id: 'bold_gold',
    name: 'Bold Gold',
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w900,
    letterSpacing: 2.0,
    gradientColors: [
      Color(0xFFFFF3B0),
      Color(0xFFF59E0B),
      Color(0xFFB45309),
    ],
    strokeColor: Color(0xFF451A03),
    strokeWidth: 4.0,
    italic: false,
  ),
  LogoTextStyle(
    id: 'neon_glow',
    name: 'Neon Glow',
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w800,
    letterSpacing: 3.0,
    gradientColors: [
      Color(0xFF22D3EE),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
    ],
    strokeColor: Color(0xFFE0F2FE),
    strokeWidth: 3.0,
    italic: false,
  ),
  LogoTextStyle(
    id: 'chrome_block',
    name: 'Chrome Block',
    fontFamily: 'Courier New',
    fontWeight: FontWeight.w900,
    letterSpacing: 2.5,
    gradientColors: [
      Color(0xFFFFFFFF),
      Color(0xFFCBD5E1),
      Color(0xFF475569),
    ],
    strokeColor: Color(0xFF0F172A),
    strokeWidth: 4.5,
    italic: false,
  ),
  LogoTextStyle(
    id: 'royal_serif',
    name: 'Royal Serif',
    fontFamily: 'Georgia',
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    gradientColors: [
      Color(0xFFFDE68A),
      Color(0xFFD97706),
      Color(0xFF9333EA),
    ],
    strokeColor: Color(0xFF2E1065),
    strokeWidth: 2.5,
    italic: false,
  ),
  LogoTextStyle(
    id: 'modern_sans',
    name: 'Modern Sans',
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    gradientColors: [
      Color(0xFFFFFFFF),
      Color(0xFF93C5FD),
      Color(0xFF2E7CF6),
    ],
    strokeColor: Color(0xFF0B132B),
    strokeWidth: 0.0,
    italic: false,
  ),
  LogoTextStyle(
    id: 'retro_script',
    name: 'Retro Script',
    fontFamily: 'Pacifico',
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    gradientColors: [
      Color(0xFFFDA4AF),
      Color(0xFFF43F5E),
      Color(0xFF8B5CF6),
    ],
    strokeColor: Color(0xFFFFFFFF),
    strokeWidth: 3.0,
    italic: true,
  ),
  LogoTextStyle(
    id: 'fire_text',
    name: 'Fire Text',
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w900,
    letterSpacing: 2.2,
    gradientColors: [
      Color(0xFFFEF08A),
      Color(0xFFF97316),
      Color(0xFFDC2626),
    ],
    strokeColor: Color(0xFF450A0A),
    strokeWidth: 4.0,
    italic: true,
  ),
  LogoTextStyle(
    id: 'ocean_clean',
    name: 'Ocean Clean',
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w800,
    letterSpacing: 1.6,
    gradientColors: [
      Color(0xFFA5F3FC),
      Color(0xFF22D3EE),
      Color(0xFF2563EB),
    ],
    strokeColor: Color(0xFF082F49),
    strokeWidth: 2.0,
    italic: false,
  ),
];

Future<ui.Image> _createEmptyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder, const Rect.fromLTWH(0, 0, 1, 1));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return image;
}

Future<ui.Image> renderLogoText({
  required String text,
  required LogoTextStyle style,
  double fontSize = 120,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return _createEmptyImage();
  }

  final double safeSize = fontSize.clamp(12.0, 400.0);
  final FontStyle fontStyle =
      style.italic ? FontStyle.italic : FontStyle.normal;

  // Measure text bounds first.
  final measurePainter = TextPainter(
    text: TextSpan(
      text: trimmed,
      style: TextStyle(
        fontFamily: style.fontFamily,
        fontSize: safeSize,
        fontWeight: style.fontWeight,
        fontStyle: fontStyle,
        letterSpacing: style.letterSpacing,
        height: 1.15,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  final double textW = math.max(1.0, measurePainter.width);
  final double textH = math.max(1.0, measurePainter.height);
  measurePainter.dispose();

  // Extra horizontal slack protects italic overhang and outer stroke width.
  final double padX =
      math.max(20.0, style.strokeWidth * 2.0 + safeSize * (style.italic ? 0.25 : 0.14));
  final double padY = math.max(16.0, style.strokeWidth * 2.0 + safeSize * 0.12);

  final double rawW = textW + padX * 2.0;
  final double rawH = textH + padY * 2.0;

  // Enforce max 2048 px width while preserving aspect ratio.
  const double maxDim = 2048.0;
  final double scale = math.min(
    1.0,
    math.min(maxDim / rawW, maxDim / rawH),
  );

  final int imgW = math.max(1, (rawW * scale).ceil());
  final int imgH = math.max(1, (rawH * scale).ceil());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
  );

  canvas.save();
  if (scale < 1.0) {
    canvas.scale(scale, scale);
  }
  canvas.translate(padX, padY);

  // Pass 1: Stroke pass (only when strokeWidth > 0).
  if (style.strokeWidth > 0) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = style.strokeColor;

    final strokePainter = TextPainter(
      text: TextSpan(
        text: trimmed,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: safeSize,
          fontWeight: style.fontWeight,
          fontStyle: fontStyle,
          letterSpacing: style.letterSpacing,
          height: 1.15,
          foreground: strokePaint,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    strokePainter.paint(canvas, Offset.zero);
    strokePainter.dispose();
  }

  // Pass 2: Linear gradient fill pass (top-left to bottom-right).
  final List<Color> fillColors = _normalizeGradientColors(style.gradientColors);
  final fillPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: fillColors,
    ).createShader(Rect.fromLTWH(0, 0, textW, textH));

  final fillPainter = TextPainter(
    text: TextSpan(
      text: trimmed,
      style: TextStyle(
        fontFamily: style.fontFamily,
        fontSize: safeSize,
        fontWeight: style.fontWeight,
        fontStyle: fontStyle,
        letterSpacing: style.letterSpacing,
        height: 1.15,
        foreground: fillPaint,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  fillPainter.paint(canvas, Offset.zero);
  fillPainter.dispose();

  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(imgW, imgH);
  picture.dispose();
  return image;
}

class LogoTextCreator extends StatefulWidget {
  final void Function(ui.Image) onCreated;

  const LogoTextCreator({
    super.key,
    required this.onCreated,
  });

  @override
  State<LogoTextCreator> createState() => _LogoTextCreatorState();
}

class _LogoTextCreatorState extends State<LogoTextCreator> {
  final TextEditingController _textController = TextEditingController();
  final Set<ui.Image> _deliveredImages = <ui.Image>{};

  LogoTextStyle _selectedStyle = kLogoTextStyles.first;
  double _fontSize = 120.0;
  int _renderVersion = 0;

  Future<ui.Image>? _renderFuture;
  ui.Image? _latestImage;
  bool _hasValidRender = false;

  @override
  void initState() {
    super.initState();
    _triggerRender();
  }

  @override
  void dispose() {
    _textController.dispose();
    if (_latestImage != null && !_deliveredImages.contains(_latestImage)) {
      _latestImage!.dispose();
    }
    super.dispose();
  }

  void _scheduleDisposeIfUnused(ui.Image? image) {
    if (image == null || _deliveredImages.contains(image)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deliveredImages.contains(image)) {
        image.dispose();
      }
    });
  }

  void _triggerRender() {
    final int version = ++_renderVersion;
    final String currentText = _textController.text;
    final bool validText = currentText.trim().isNotEmpty;

    final Future<ui.Image> future = renderLogoText(
      text: currentText,
      style: _selectedStyle,
      fontSize: _fontSize,
    ).then((ui.Image rendered) {
      if (!mounted || version != _renderVersion) {
        rendered.dispose();
        return rendered;
      }
      final ui.Image? previous = _latestImage;
      setState(() {
        _latestImage = rendered;
        _hasValidRender = validText;
      });
      if (!identical(previous, rendered)) {
        _scheduleDisposeIfUnused(previous);
      }
      return rendered;
    });

    setState(() {
      _renderFuture = future;
      if (!validText) {
        _hasValidRender = false;
      }
    });
  }

  void _handleUseLogo() {
    final ui.Image? img = _latestImage;
    if (!_hasValidRender || img == null) return;
    _deliveredImages.add(img);
    widget.onCreated(img);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = _textController.text.trim().isNotEmpty;

    return Container(
      color: _kBgColor,
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Text to Logo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Live preview box
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: _kCardFill,
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(color: _kCardBorder, width: 1),
              ),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: FutureBuilder<ui.Image>(
                future: _renderFuture,
                builder: (context, snapshot) {
                  if (!hasText) {
                    return const Text(
                      'Type text below to preview your logo',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    );
                  }
                  final ui.Image? displayImage =
                      snapshot.hasData ? snapshot.data : _latestImage;
                  if (displayImage == null) {
                    return const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _kCyan,
                      ),
                    );
                  }
                  return RawImage(
                    image: displayImage,
                    fit: BoxFit.contain,
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // Text input
            const Text(
              'Logo Text',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _kCardFill,
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(color: _kCardBorder, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: _kCyan,
                decoration: const InputDecoration(
                  hintText: 'Type name or text',
                  hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                  border: InputBorder.none,
                ),
                onChanged: (_) => _triggerRender(),
              ),
            ),
            const SizedBox(height: 18),

            // Style chips
            const Text(
              'Text Style',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kLogoTextStyles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final style = kLogoTextStyles[index];
                  final bool isSelected = style.id == _selectedStyle.id;
                  return _SelectableChip(
                    label: style.name,
                    selected: isSelected,
                    onTap: () {
                      if (_selectedStyle.id == style.id) return;
                      _selectedStyle = style;
                      _triggerRender();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // Font size slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Font Size',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_fontSize.round()} px',
                  style: const TextStyle(
                    color: _kCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _kCyan,
                inactiveTrackColor: _kCardBorder,
                thumbColor: _kCyan,
                overlayColor: const Color.fromRGBO(34, 211, 238, 0.20),
              ),
              child: Slider(
                value: _fontSize,
                min: 48,
                max: 220,
                onChanged: (value) {
                  _fontSize = value;
                  _triggerRender();
                },
              ),
            ),
            const SizedBox(height: 16),

            // Submit CTA
            _GlowingGradientButton(
              label: 'Use This Logo',
              enabled: _hasValidRender && _latestImage != null,
              onPressed: _handleUseLogo,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PART B — SHAPES / BADGES
// ---------------------------------------------------------------------------

class LogoShapeDef {
  final String id;
  final String name;

  const LogoShapeDef({
    required this.id,
    required this.name,
  });
}

const List<LogoShapeDef> kLogoShapes = [
  LogoShapeDef(id: 'circle_badge', name: 'Circle Badge'),
  LogoShapeDef(id: 'star', name: 'Star'),
  LogoShapeDef(id: 'shield', name: 'Shield'),
  LogoShapeDef(id: 'hexagon', name: 'Hexagon'),
  LogoShapeDef(id: 'ribbon_banner', name: 'Ribbon Banner'),
  LogoShapeDef(id: 'diamond', name: 'Diamond'),
  LogoShapeDef(id: 'oval_seal', name: 'Oval Seal'),
  LogoShapeDef(id: 'play_triangle', name: 'Play Triangle'),
  LogoShapeDef(id: 'heart', name: 'Heart'),
  LogoShapeDef(id: 'crown', name: 'Crown'),
  LogoShapeDef(id: 'lightning_bolt', name: 'Lightning Bolt'),
  LogoShapeDef(id: 'sun_burst', name: 'Sun Burst'),
];

class LogoShapePainter extends CustomPainter {
  final String shapeId;
  final List<Color> colors;
  final bool strokeOn;

  const LogoShapePainter({
    required this.shapeId,
    required this.colors,
    this.strokeOn = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double minDim = math.min(size.width, size.height);
    final double padding = minDim * 0.08;
    final double side = math.max(1.0, minDim - padding * 2.0);
    final Rect bounds = Rect.fromCenter(
      center: Offset(size.width / 2.0, size.height / 2.0),
      width: side,
      height: side,
    );

    final Path path = _buildShapePath(shapeId, bounds);
    final List<Color> fillColors = _normalizeGradientColors(colors);

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: fillColors,
      ).createShader(bounds);

    canvas.drawPath(path, fillPaint);

    if (strokeOn) {
      // Clip to path and stroke at 2x width to produce a crisp 2px inner stroke.
      canvas.save();
      canvas.clipPath(path);
      final Paint innerStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color.fromRGBO(255, 255, 255, 0.35);
      canvas.drawPath(path, innerStroke);
      canvas.restore();
    }
  }

  Path _buildShapePath(String id, Rect r) {
    switch (id) {
      case 'circle_badge':
        return Path()..addOval(r);
      case 'star':
        return _polygonStarPath(r, points: 5, innerRatio: 0.42);
      case 'shield':
        return _shieldPath(r);
      case 'hexagon':
        return _regularPolygonPath(r, sides: 6);
      case 'ribbon_banner':
        return _ribbonBannerPath(r);
      case 'diamond':
        return _diamondPath(r);
      case 'oval_seal':
        return _ovalSealPath(r);
      case 'play_triangle':
        return _playTrianglePath(r);
      case 'heart':
        return _heartPath(r);
      case 'crown':
        return _crownPath(r);
      case 'lightning_bolt':
        return _lightningBoltPath(r);
      case 'sun_burst':
        return _polygonStarPath(r, points: 12, innerRatio: 0.64);
      default:
        // v1.19.0 (G4): an unknown id draws NOTHING. The old
        // code silently fell back to a hexagon, so a typo'd id
        // showed the user a shape they never chose. Callers
        // that need a hard failure use renderLogoShape, which
        // throws ArgumentError for unknown ids.
        return Path();
    }
  }

  Offset _pt(Rect r, double nx, double ny) =>
      Offset(r.left + r.width * nx, r.top + r.height * ny);

  Path _regularPolygonPath(Rect r, {required int sides}) {
    final path = Path();
    final double radius = r.width / 2.0;
    final Offset c = r.center;
    for (int i = 0; i < sides; i++) {
      final double angle = -math.pi / 2.0 + (2.0 * math.pi * i / sides);
      final double x = c.dx + radius * math.cos(angle);
      final double y = c.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _polygonStarPath(
    Rect r, {
    required int points,
    required double innerRatio,
  }) {
    final path = Path();
    final double outerR = r.width / 2.0;
    final double innerR = outerR * innerRatio;
    final Offset c = r.center;
    final int total = points * 2;
    for (int i = 0; i < total; i++) {
      final double radius = i.isEven ? outerR : innerR;
      final double angle = -math.pi / 2.0 + (math.pi * i / points);
      final double x = c.dx + radius * math.cos(angle);
      final double y = c.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _shieldPath(Rect r) {
    final p = Path();
    final topCenter = _pt(r, 0.50, 0.03);
    final topRight = _pt(r, 0.90, 0.16);
    final rightCurveCtrl1 = _pt(r, 0.90, 0.58);
    final rightCurveCtrl2 = _pt(r, 0.72, 0.84);
    final bottomTip = _pt(r, 0.50, 0.98);
    final leftCurveCtrl1 = _pt(r, 0.28, 0.84);
    final leftCurveCtrl2 = _pt(r, 0.10, 0.58);
    final topLeft = _pt(r, 0.10, 0.16);

    p.moveTo(topCenter.dx, topCenter.dy);
    p.quadraticBezierTo(
      _pt(r, 0.72, 0.12).dx,
      _pt(r, 0.72, 0.12).dy,
      topRight.dx,
      topRight.dy,
    );
    p.cubicTo(
      rightCurveCtrl1.dx,
      rightCurveCtrl1.dy,
      rightCurveCtrl2.dx,
      rightCurveCtrl2.dy,
      bottomTip.dx,
      bottomTip.dy,
    );
    p.cubicTo(
      leftCurveCtrl1.dx,
      leftCurveCtrl1.dy,
      leftCurveCtrl2.dx,
      leftCurveCtrl2.dy,
      topLeft.dx,
      topLeft.dy,
    );
    p.quadraticBezierTo(
      _pt(r, 0.28, 0.12).dx,
      _pt(r, 0.28, 0.12).dy,
      topCenter.dx,
      topCenter.dy,
    );
    p.close();
    return p;
  }

  Path _ribbonBannerPath(Rect r) {
    final p = Path();
    final tl = _pt(r, 0.16, 0.25);
    final topArch = _pt(r, 0.50, 0.19);
    final tr = _pt(r, 0.84, 0.25);
    final trStep = _pt(r, 0.84, 0.37);
    final rtTop = _pt(r, 1.00, 0.37);
    final rtNotch = _pt(r, 0.90, 0.55);
    final rtBottom = _pt(r, 1.00, 0.73);
    final rbFold = _pt(r, 0.74, 0.73);
    final rbInner = _pt(r, 0.74, 0.61);
    final bottomArch = _pt(r, 0.50, 0.56);
    final lbInner = _pt(r, 0.26, 0.61);
    final lbFold = _pt(r, 0.26, 0.73);
    final ltBottom = _pt(r, 0.00, 0.73);
    final ltNotch = _pt(r, 0.10, 0.55);
    final ltTop = _pt(r, 0.00, 0.37);
    final tlStep = _pt(r, 0.16, 0.37);

    p.moveTo(tl.dx, tl.dy);
    p.quadraticBezierTo(topArch.dx, topArch.dy, tr.dx, tr.dy);
    p.lineTo(trStep.dx, trStep.dy);
    p.lineTo(rtTop.dx, rtTop.dy);
    p.lineTo(rtNotch.dx, rtNotch.dy);
    p.lineTo(rtBottom.dx, rtBottom.dy);
    p.lineTo(rbFold.dx, rbFold.dy);
    p.lineTo(rbInner.dx, rbInner.dy);
    p.quadraticBezierTo(bottomArch.dx, bottomArch.dy, lbInner.dx, lbInner.dy);
    p.lineTo(lbFold.dx, lbFold.dy);
    p.lineTo(ltBottom.dx, ltBottom.dy);
    p.lineTo(ltNotch.dx, ltNotch.dy);
    p.lineTo(ltTop.dx, ltTop.dy);
    p.lineTo(tlStep.dx, tlStep.dy);
    p.close();
    return p;
  }

  Path _diamondPath(Rect r) {
    final p = Path();
    final crownL = _pt(r, 0.22, 0.14);
    final crownR = _pt(r, 0.78, 0.14);
    final girdleR = _pt(r, 0.98, 0.40);
    final tip = _pt(r, 0.50, 0.92);
    final girdleL = _pt(r, 0.02, 0.40);

    p.moveTo(crownL.dx, crownL.dy);
    p.lineTo(crownR.dx, crownR.dy);
    p.lineTo(girdleR.dx, girdleR.dy);
    p.lineTo(tip.dx, tip.dy);
    p.lineTo(girdleL.dx, girdleL.dy);
    p.close();
    return p;
  }

  Path _ovalSealPath(Rect r) {
    final Rect oval = Rect.fromCenter(
      center: r.center,
      width: r.width,
      height: r.height * 0.68,
    );
    return Path()..addOval(oval);
  }

  Path _playTrianglePath(Rect r) {
    final a = _pt(r, 0.18, 0.08);
    final b = _pt(r, 0.92, 0.50);
    final c = _pt(r, 0.18, 0.92);
    const double t = 0.14;

    Offset lerp(Offset p1, Offset p2, double f) =>
        Offset(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);

    final p = Path();
    final start = lerp(a, b, t);
    p.moveTo(start.dx, start.dy);

    final bIn = lerp(b, a, t);
    final bOut = lerp(b, c, t);
    p.lineTo(bIn.dx, bIn.dy);
    p.quadraticBezierTo(b.dx, b.dy, bOut.dx, bOut.dy);

    final cIn = lerp(c, b, t);
    final cOut = lerp(c, a, t);
    p.lineTo(cIn.dx, cIn.dy);
    p.quadraticBezierTo(c.dx, c.dy, cOut.dx, cOut.dy);

    final aIn = lerp(a, c, t);
    p.lineTo(aIn.dx, aIn.dy);
    p.quadraticBezierTo(a.dx, a.dy, start.dx, start.dy);
    p.close();
    return p;
  }

  Path _heartPath(Rect r) {
    final p = Path();
    final bottom = _pt(r, 0.50, 0.92);
    final leftPeak = _pt(r, 0.16, 0.17);
    final cleft = _pt(r, 0.50, 0.27);
    final rightPeak = _pt(r, 0.84, 0.17);

    p.moveTo(bottom.dx, bottom.dy);
    p.cubicTo(
      _pt(r, 0.08, 0.66).dx,
      _pt(r, 0.08, 0.66).dy,
      _pt(r, 0.00, 0.34).dx,
      _pt(r, 0.00, 0.34).dy,
      leftPeak.dx,
      leftPeak.dy,
    );
    p.cubicTo(
      _pt(r, 0.28, 0.04).dx,
      _pt(r, 0.28, 0.04).dy,
      _pt(r, 0.45, 0.10).dx,
      _pt(r, 0.45, 0.10).dy,
      cleft.dx,
      cleft.dy,
    );
    p.cubicTo(
      _pt(r, 0.55, 0.10).dx,
      _pt(r, 0.55, 0.10).dy,
      _pt(r, 0.72, 0.04).dx,
      _pt(r, 0.72, 0.04).dy,
      rightPeak.dx,
      rightPeak.dy,
    );
    p.cubicTo(
      _pt(r, 1.00, 0.34).dx,
      _pt(r, 1.00, 0.34).dy,
      _pt(r, 0.92, 0.66).dx,
      _pt(r, 0.92, 0.66).dy,
      bottom.dx,
      bottom.dy,
    );
    p.close();
    return p;
  }

  Path _crownPath(Rect r) {
    final p = Path();
    final bl = _pt(r, 0.12, 0.82);
    final leftTip = _pt(r, 0.04, 0.28);
    final leftValley = _pt(r, 0.30, 0.50);
    final centerTip = _pt(r, 0.50, 0.14);
    final rightValley = _pt(r, 0.70, 0.50);
    final rightTip = _pt(r, 0.96, 0.28);
    final br = _pt(r, 0.88, 0.82);
    final baseCurve = _pt(r, 0.50, 0.88);

    p.moveTo(bl.dx, bl.dy);
    p.lineTo(leftTip.dx, leftTip.dy);
    p.lineTo(leftValley.dx, leftValley.dy);
    p.lineTo(centerTip.dx, centerTip.dy);
    p.lineTo(rightValley.dx, rightValley.dy);
    p.lineTo(rightTip.dx, rightTip.dy);
    p.lineTo(br.dx, br.dy);
    p.quadraticBezierTo(baseCurve.dx, baseCurve.dy, bl.dx, bl.dy);
    p.close();
    return p;
  }

  Path _lightningBoltPath(Rect r) {
    final p = Path();
    final p0 = _pt(r, 0.58, 0.02);
    final p1 = _pt(r, 0.16, 0.54);
    final p2 = _pt(r, 0.48, 0.54);
    final p3 = _pt(r, 0.36, 0.98);
    final p4 = _pt(r, 0.84, 0.42);
    final p5 = _pt(r, 0.52, 0.42);

    p.moveTo(p0.dx, p0.dy);
    p.lineTo(p1.dx, p1.dy);
    p.lineTo(p2.dx, p2.dy);
    p.lineTo(p3.dx, p3.dy);
    p.lineTo(p4.dx, p4.dy);
    p.lineTo(p5.dx, p5.dy);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant LogoShapePainter oldDelegate) {
    if (oldDelegate.shapeId != shapeId || oldDelegate.strokeOn != strokeOn) {
      return true;
    }
    if (oldDelegate.colors.length != colors.length) return true;
    for (int i = 0; i < colors.length; i++) {
      if (oldDelegate.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// Whether [id] is one of the built-in [kLogoShapes] ids.
bool isKnownLogoShapeId(String id) =>
    kLogoShapes.any((shape) => shape.id == id);

Future<ui.Image> renderLogoShape({
  required String shapeId,
  required List<Color> colors,
  int size = 512,
}) async {
  // v1.19.0 (G4): unknown ids fail loudly here instead of
  // silently rendering some other shape.
  if (!isKnownLogoShapeId(shapeId)) {
    throw ArgumentError.value(
      shapeId,
      'shapeId',
      'Unknown logo shape id',
    );
  }
  final int dim = math.max(1, size);
  final double d = dim.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, d, d));

  LogoShapePainter(
    shapeId: shapeId,
    colors: colors,
    strokeOn: true,
  ).paint(canvas, Size(d, d));

  final picture = recorder.endRecording();
  final image = await picture.toImage(dim, dim);
  picture.dispose();
  return image;
}

class _ShapeColorScheme {
  final String name;
  final List<Color> colors;

  const _ShapeColorScheme({
    required this.name,
    required this.colors,
  });
}

const List<_ShapeColorScheme> _kShapeColorSchemes = [
  _ShapeColorScheme(
    name: 'Gold',
    colors: [Color(0xFFFFF3B0), Color(0xFFF59E0B), Color(0xFFB45309)],
  ),
  _ShapeColorScheme(
    name: 'Chrome',
    colors: [Color(0xFFFFFFFF), Color(0xFFCBD5E1), Color(0xFF475569)],
  ),
  _ShapeColorScheme(
    name: 'Neon',
    colors: [Color(0xFF2E7CF6), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
  ),
  _ShapeColorScheme(
    name: 'Fire',
    colors: [Color(0xFFFEF08A), Color(0xFFF97316), Color(0xFFDC2626)],
  ),
  _ShapeColorScheme(
    name: 'Ocean',
    colors: [Color(0xFFA5F3FC), Color(0xFF22D3EE), Color(0xFF1D4ED8)],
  ),
  _ShapeColorScheme(
    name: 'Sunset',
    colors: [Color(0xFFFDE68A), Color(0xFFEC4899), Color(0xFF7C3AED)],
  ),
];

class LogoShapePicker extends StatefulWidget {
  final void Function(ui.Image) onPicked;

  const LogoShapePicker({
    super.key,
    required this.onPicked,
  });

  @override
  State<LogoShapePicker> createState() => _LogoShapePickerState();
}

class _LogoShapePickerState extends State<LogoShapePicker> {
  String _selectedShapeId = kLogoShapes.first.id;
  _ShapeColorScheme _selectedScheme = _kShapeColorSchemes.first;
  bool _isRendering = false;

  Future<void> _handleUseShape() async {
    if (_isRendering) return;
    setState(() => _isRendering = true);
    try {
      final ui.Image image = await renderLogoShape(
        shapeId: _selectedShapeId,
        colors: _selectedScheme.colors,
        size: 512,
      );
      if (mounted) {
        widget.onPicked(image);
      } else {
        image.dispose();
      }
    } finally {
      if (mounted) {
        setState(() => _isRendering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBgColor,
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Shapes & Badges',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),

            // 3-column shape grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: kLogoShapes.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, index) {
                final shape = kLogoShapes[index];
                final bool selected = shape.id == _selectedShapeId;
                return _ShapeGridCell(
                  shape: shape,
                  colors: _selectedScheme.colors,
                  selected: selected,
                  onTap: () {
                    if (_selectedShapeId == shape.id) return;
                    setState(() => _selectedShapeId = shape.id);
                  },
                );
              },
            ),
            const SizedBox(height: 18),

            // Color scheme chips
            const Text(
              'Color Scheme',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kShapeColorSchemes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final scheme = _kShapeColorSchemes[index];
                  final bool isSelected = scheme.name == _selectedScheme.name;
                  return _SelectableChip(
                    label: scheme.name,
                    selected: isSelected,
                    swatchColors: scheme.colors,
                    onTap: () {
                      if (_selectedScheme.name == scheme.name) return;
                      setState(() => _selectedScheme = scheme);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Submit CTA
            _GlowingGradientButton(
              label: _isRendering ? 'Rendering...' : 'Use This Shape',
              enabled: !_isRendering,
              onPressed: _handleUseShape,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal Shared Helpers & UI Components
// ---------------------------------------------------------------------------

List<Color> _normalizeGradientColors(List<Color> colors) {
  if (colors.isEmpty) {
    return const [Color(0xFF2E7CF6), Color(0xFF22D3EE)];
  }
  if (colors.length == 1) {
    return [colors.first, colors.first];
  }
  return colors;
}

class _ShapeGridCell extends StatelessWidget {
  final LogoShapeDef shape;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeGridCell({
    required this.shape,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget innerContent = Container(
      decoration: BoxDecoration(
        color: _kCardFill,
        borderRadius: BorderRadius.circular(selected ? _kCardRadius - 1.5 : _kCardRadius),
        border: selected ? null : Border.all(color: _kCardBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: LogoShapePainter(
                  shapeId: shape.id,
                  colors: colors,
                  strokeOn: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            shape.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: selected
          ? Container(
              decoration: BoxDecoration(
                gradient: _kAccentGradient,
                borderRadius: BorderRadius.circular(_kCardRadius),
              ),
              padding: const EdgeInsets.all(1.5),
              child: Container(
                decoration: BoxDecoration(
                  color: _kBgColor,
                  borderRadius: BorderRadius.circular(_kCardRadius - 1.5),
                ),
                child: innerContent,
              ),
            )
          : innerContent,
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final List<Color>? swatchColors;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatchColors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? _kAccentGradient : null,
          color: selected ? null : _kCardFill,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: selected ? null : Border.all(color: _kCardBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatchColors != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _normalizeGradientColors(swatchColors!),
                  ),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.55),
                    width: 1,
                  ),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowingGradientButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _GlowingGradientButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled ? _kAccentGradient : null,
            color: enabled ? null : _kCardFill,
            borderRadius: BorderRadius.circular(_kCardRadius),
            border: enabled ? null : Border.all(color: _kCardBorder, width: 1),
            boxShadow: enabled ? _kButtonGlow : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
