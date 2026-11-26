import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/tool_guide.dart';
import 'logo_reveal_backdrops.dart';
import 'logo_text_shapes.dart';

const Color _kBackgroundColor = Color(0xFF050914);
const Color _kCardFillColor = Color.fromRGBO(255, 255, 255, 0.06);
const Color _kCardBorderColor = Color.fromRGBO(255, 255, 255, 0.12);
const Color _kAccentBlue = Color(0xFF2E7CF6);
const Color _kAccentPurple = Color(0xFF8B5CF6);
const Color _kAccentCyan = Color(0xFF22D3EE);
const double _kCardRadius = 22.0;

const LinearGradient _kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[_kAccentBlue, _kAccentPurple, _kAccentCyan],
);

/// Immutable configuration for all 3D logo styling and animation parameters.
class LogoMakerSettings {
  const LogoMakerSettings({
    this.presetId = 'gold_spin',
    this.materialId = 'gold',
    this.depth = 18.0,
    this.bevel = 6.0,
    this.shadowOn = true,
    this.shadowBlur = 14.0,
    this.shadowOpacity = 0.45,
    this.spinSpeed = 1.0,
    this.spinOn = true,
    this.glowOn = false,
    this.glowIntensity = 0.5,
    this.revealStyleId = 'fade_zoom',
    this.backdropId = 'midnight_studio',
    this.backdropGlow = 0.6,
  });

  final String presetId;
  final String materialId;
  final double depth;
  final double bevel;
  final bool shadowOn;
  final double shadowBlur;
  final double shadowOpacity;
  final double spinSpeed;
  final bool spinOn;
  final bool glowOn;
  final double glowIntensity;

  /// Reveal animation for the Reveal tab (v1.21.0): one of
  /// the `kLogoRevealStyles` ids, or '' for no reveal. The
  /// reveal is a preview presentation of the styled logo —
  /// it does not enter the export (see the Guide entry).
  final String revealStyleId;

  /// Procedural backdrop scene behind the reveal preview:
  /// one of the `kLogoBackdrops` ids.
  final String backdropId;

  /// Glow strength of the backdrop scene, 0..1.
  final double backdropGlow;

  LogoMakerSettings copyWith({
    String? presetId,
    String? materialId,
    double? depth,
    double? bevel,
    bool? shadowOn,
    double? shadowBlur,
    double? shadowOpacity,
    double? spinSpeed,
    bool? spinOn,
    bool? glowOn,
    double? glowIntensity,
    String? revealStyleId,
    String? backdropId,
    double? backdropGlow,
  }) {
    return LogoMakerSettings(
      presetId: presetId ?? this.presetId,
      materialId: materialId ?? this.materialId,
      depth: depth ?? this.depth,
      bevel: bevel ?? this.bevel,
      shadowOn: shadowOn ?? this.shadowOn,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      spinSpeed: spinSpeed ?? this.spinSpeed,
      spinOn: spinOn ?? this.spinOn,
      glowOn: glowOn ?? this.glowOn,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      revealStyleId: revealStyleId ?? this.revealStyleId,
      backdropId: backdropId ?? this.backdropId,
      backdropGlow: backdropGlow ?? this.backdropGlow,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'presetId': presetId,
      'materialId': materialId,
      'depth': depth,
      'bevel': bevel,
      'shadowOn': shadowOn,
      'shadowBlur': shadowBlur,
      'shadowOpacity': shadowOpacity,
      'spinSpeed': spinSpeed,
      'spinOn': spinOn,
      'glowOn': glowOn,
      'glowIntensity': glowIntensity,
      'revealStyleId': revealStyleId,
      'backdropId': backdropId,
      'backdropGlow': backdropGlow,
    };
  }

  factory LogoMakerSettings.fromJson(Map<String, dynamic> json) {
    final String rawMaterial = (json['materialId'] as String?) ?? 'gold';
    final String safeMaterial =
        kLogoMaterials.containsKey(rawMaterial) ? rawMaterial : 'gold';

    // v1.21.0 fields — payloads saved before they existed
    // carry none of these keys and must load as the defaults
    // (fail-soft, exactly like every older field above).
    final String rawReveal = (json['revealStyleId'] as String?) ?? 'fade_zoom';
    final String safeReveal = (rawReveal.isEmpty ||
            kLogoRevealStyles.any((s) => s.id == rawReveal))
        ? rawReveal
        : 'fade_zoom';
    final String rawBackdrop =
        (json['backdropId'] as String?) ?? 'midnight_studio';
    final String safeBackdrop =
        kLogoBackdrops.any((b) => b.id == rawBackdrop)
            ? rawBackdrop
            : 'midnight_studio';

    return LogoMakerSettings(
      presetId: (json['presetId'] as String?) ?? 'gold_spin',
      materialId: safeMaterial,
      depth: ((json['depth'] as num?)?.toDouble() ?? 18.0).clamp(0.0, 40.0),
      bevel: ((json['bevel'] as num?)?.toDouble() ?? 6.0).clamp(0.0, 20.0),
      shadowOn: (json['shadowOn'] as bool?) ?? true,
      shadowBlur:
          ((json['shadowBlur'] as num?)?.toDouble() ?? 14.0).clamp(2.0, 40.0),
      shadowOpacity: ((json['shadowOpacity'] as num?)?.toDouble() ?? 0.45)
          .clamp(0.0, 0.8),
      spinSpeed:
          ((json['spinSpeed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 3.0),
      spinOn: (json['spinOn'] as bool?) ?? true,
      glowOn: (json['glowOn'] as bool?) ?? false,
      glowIntensity: ((json['glowIntensity'] as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0),
      revealStyleId: safeReveal,
      backdropId: safeBackdrop,
      backdropGlow: ((json['backdropGlow'] as num?)?.toDouble() ?? 0.6)
          .clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogoMakerSettings &&
        other.presetId == presetId &&
        other.materialId == materialId &&
        other.depth == depth &&
        other.bevel == bevel &&
        other.shadowOn == shadowOn &&
        other.shadowBlur == shadowBlur &&
        other.shadowOpacity == shadowOpacity &&
        other.spinSpeed == spinSpeed &&
        other.spinOn == spinOn &&
        other.glowOn == glowOn &&
        other.glowIntensity == glowIntensity &&
        other.revealStyleId == revealStyleId &&
        other.backdropId == backdropId &&
        other.backdropGlow == backdropGlow;
  }

  @override
  int get hashCode => Object.hash(
        presetId,
        materialId,
        depth,
        bevel,
        shadowOn,
        shadowBlur,
        shadowOpacity,
        spinSpeed,
        spinOn,
        glowOn,
        glowIntensity,
        revealStyleId,
        backdropId,
        backdropGlow,
      );
}

/// Curated 3D style preset definition.
class LogoStylePreset {
  const LogoStylePreset({
    required this.id,
    required this.name,
    required this.materialId,
    required this.depth,
    required this.bevel,
    required this.shadowOn,
    required this.glowOn,
    required this.gradientColors,
  });

  final String id;
  final String name;
  final String materialId;
  final double depth;
  final double bevel;
  final bool shadowOn;
  final bool glowOn;
  final List<Color> gradientColors;
}

/// Material gradient definitions mapped by material ID.
const Map<String, List<Color>> kLogoMaterials = <String, List<Color>>{
  'gold': <Color>[
    Color(0xFFFFF3B0),
    Color(0xFFF5B700),
    Color(0xFFB87300),
    Color(0xFFFFE066),
  ],
  'chrome': <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFB8C6DB),
    Color(0xFF4B5563),
    Color(0xFFE5E7EB),
  ],
  'silver': <Color>[
    Color(0xFFF3F4F6),
    Color(0xFFC0C7D1),
    Color(0xFF7B8494),
    Color(0xFFDDE2E8),
  ],
  'neon': <Color>[
    Color(0xFF22D3EE),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ],
  'glass': <Color>[
    Color(0xFFE0F7FA),
    Color(0xFF80DEEA),
    Color(0xFF38BDF8),
    Color(0xFFFFFFFF),
  ],
  'fire': <Color>[
    Color(0xFFFFF176),
    Color(0xFFFF9100),
    Color(0xFFFF3D00),
    Color(0xFFB71C1C),
  ],
  'ocean': <Color>[
    Color(0xFF67E8F9),
    Color(0xFF0EA5E9),
    Color(0xFF1D4ED8),
  ],
  'sunset': <Color>[
    Color(0xFFFDE047),
    Color(0xFFFB7185),
    Color(0xFF9333EA),
  ],
  'mono': <Color>[
    Color(0xFFF9FAFB),
    Color(0xFF9CA3AF),
    Color(0xFF1F2937),
  ],
  'none': <Color>[],
};

/// Built-in 3D logo style presets.
const List<LogoStylePreset> kLogoStylePresets = <LogoStylePreset>[
  LogoStylePreset(
    id: 'gold_spin',
    name: 'Gold Spin',
    materialId: 'gold',
    depth: 18.0,
    bevel: 6.0,
    shadowOn: true,
    glowOn: false,
    gradientColors: <Color>[Color(0xFFFFE066), Color(0xFFF59E0B)],
  ),
  LogoStylePreset(
    id: 'chrome_flip',
    name: 'Chrome Flip',
    materialId: 'chrome',
    depth: 22.0,
    bevel: 10.0,
    shadowOn: true,
    glowOn: false,
    gradientColors: <Color>[Color(0xFFF3F4F6), Color(0xFF64748B)],
  ),
  LogoStylePreset(
    id: 'neon_pulse',
    name: 'Neon Pulse',
    materialId: 'neon',
    depth: 16.0,
    bevel: 8.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFF22D3EE), Color(0xFFEC4899)],
  ),
  LogoStylePreset(
    id: 'glass_shine',
    name: 'Glass Shine',
    materialId: 'glass',
    depth: 12.0,
    bevel: 14.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFFE0F7FA), Color(0xFF38BDF8)],
  ),
  LogoStylePreset(
    id: 'royal_gold',
    name: 'Royal Gold',
    materialId: 'gold',
    depth: 28.0,
    bevel: 12.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFFFFF3B0), Color(0xFFB45309)],
  ),
  LogoStylePreset(
    id: 'silver_swing',
    name: 'Silver Swing',
    materialId: 'silver',
    depth: 15.0,
    bevel: 7.0,
    shadowOn: true,
    glowOn: false,
    gradientColors: <Color>[Color(0xFFE5E7EB), Color(0xFF94A3B8)],
  ),
  LogoStylePreset(
    id: 'fire_glow',
    name: 'Fire Glow',
    materialId: 'fire',
    depth: 20.0,
    bevel: 8.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFFFFB300), Color(0xFFDC2626)],
  ),
  LogoStylePreset(
    id: 'ocean_wave',
    name: 'Ocean Wave',
    materialId: 'ocean',
    depth: 17.0,
    bevel: 9.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFF67E8F9), Color(0xFF1D4ED8)],
  ),
  LogoStylePreset(
    id: 'sunset_gradient',
    name: 'Sunset Gradient',
    materialId: 'sunset',
    depth: 19.0,
    bevel: 7.0,
    shadowOn: true,
    glowOn: true,
    gradientColors: <Color>[Color(0xFFFDE047), Color(0xFF9333EA)],
  ),
  LogoStylePreset(
    id: 'mono_classic',
    name: 'Mono Classic',
    materialId: 'mono',
    depth: 14.0,
    bevel: 5.0,
    shadowOn: true,
    glowOn: false,
    gradientColors: <Color>[Color(0xFFE5E7EB), Color(0xFF374151)],
  ),
];

/// The rect the logo occupies when [LogoDepthPainter] paints it
/// into [size]: fitted into the middle 66% of the canvas,
/// aspect preserved, centred. ONE source of geometry for the
/// painter and for [renderLogoDepthStatic], so the cached and
/// direct renders can never drift apart.
Rect logoDepthDestRect(ui.Image image, Size size) {
  final double imgWidth = image.width.toDouble();
  final double imgHeight = image.height.toDouble();
  final double availWidth = math.max(1.0, size.width * 0.66);
  final double availHeight = math.max(1.0, size.height * 0.66);
  final double fitScale =
      math.min(availWidth / imgWidth, availHeight / imgHeight);
  return Rect.fromCenter(
    center: Offset(size.width * 0.5, size.height * 0.5),
    width: imgWidth * fitScale,
    height: imgHeight * fitScale,
  );
}

/// How much transparent margin a static render needs around the
/// logo rect so nothing is clipped: the glow/shadow blurs spread
/// about 3× their sigma, the shadow also drops by its offset,
/// and the extrusion walks up to `depth` px away from the face.
double logoDepthStaticMargin(LogoMakerSettings settings) {
  double margin = 8.0;
  if (settings.glowOn) {
    final double glowSigma = 16.0 + settings.glowIntensity * 22.0;
    margin = math.max(margin, glowSigma * 3.0);
  }
  if (settings.shadowOn) {
    margin = math.max(
      margin,
      settings.shadowBlur * 3.0 + settings.depth * 0.35 + 6.0,
    );
  }
  margin = math.max(margin, settings.depth + 4.0);
  return margin.ceilToDouble();
}

List<double> _logoDepthEvenStops(int count) {
  if (count <= 1) return const <double>[0.0];
  return List<double>.generate(
    count,
    (int i) => i / (count - 1),
    growable: false,
  );
}

/// Draws ALL the static layers (glow, shadow, extrusion, face,
/// material, bevel) for one facing into [canvas], with the
/// logo's top face at [dstRect] in canvas coordinates. This is
/// the single layer implementation: [LogoDepthPainter] calls it
/// directly (per frame, under the spin transform) and
/// [renderLogoDepthStatic] calls it once into a cached image —
/// parity between the two paths holds by construction.
void _drawLogoDepthLayers(
  Canvas canvas,
  ui.Image image,
  LogoMakerSettings settings,
  bool isBackFacing,
  Rect dstRect,
) {
  final Rect srcRect =
      Rect.fromLTWH(0.0, 0.0, image.width.toDouble(), image.height.toDouble());
  final List<Color> materialColors =
      kLogoMaterials[settings.materialId] ?? const <Color>[];

  {
    // f. Glow rendered behind all other layers when enabled.
    if (settings.glowOn) {
      final Color glowBase = materialColors.isNotEmpty
          ? materialColors.first
          : _kAccentCyan;
      final double glowAlpha = (settings.glowIntensity * 0.8).clamp(0.0, 0.8);
      final double glowSigma = 16.0 + (settings.glowIntensity * 22.0);
      final Paint glowPaint = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.mode(
          glowBase.withAlpha((glowAlpha * 255).round()),
          BlendMode.srcIn,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma);
      canvas.drawImageRect(image, srcRect, dstRect, glowPaint);
    }

    // a. Drop shadow.
    if (settings.shadowOn) {
      final double shadowAlpha = settings.shadowOpacity.clamp(0.0, 0.8);
      final Offset shadowOffset = Offset(0.0, settings.depth * 0.35 + 6.0);
      final Paint shadowPaint = Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(0, 0, 0, shadowAlpha),
          BlendMode.srcIn,
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          settings.shadowBlur.clamp(2.0, 40.0),
        );
      canvas.drawImageRect(
        image,
        srcRect,
        dstRect.shift(shadowOffset),
        shadowPaint,
      );
    }

    // b. Fake 3D extrusion along normalized direction (0.6, 0.8).
    final int depthSteps = settings.depth.round().clamp(0, 40);
    if (depthSteps > 0) {
      const double dirX = 0.6;
      const double dirY = 0.8;
      final double dirLen = math.sqrt(dirX * dirX + dirY * dirY);
      final double stepX = dirX / dirLen;
      final double stepY = dirY / dirLen;

      for (int step = depthSteps; step >= 1; step--) {
        final double ratio = step / depthSteps;
        final double tintAlpha =
            (isBackFacing ? 0.68 : 0.50) + (0.28 * ratio);
        final Paint extrudePaint = Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(32, 37, 48, tintAlpha.clamp(0.0, 0.92)),
            BlendMode.srcATop,
          );
        canvas.drawImageRect(
          image,
          srcRect,
          dstRect.shift(Offset(stepX * step, stepY * step)),
          extrudePaint,
        );
      }
    }

    // c. Top face (slightly darkened when rotated to the back side).
    final Paint facePaint = Paint()..filterQuality = FilterQuality.high;
    if (isBackFacing) {
      facePaint.colorFilter = const ColorFilter.mode(
        Color.fromRGBO(0, 0, 0, 0.24),
        BlendMode.srcATop,
      );
    }
    canvas.drawImageRect(image, srcRect, dstRect, facePaint);

    // d. Material overlay clipped to logo alpha and blended over the top face.
    if (settings.materialId != 'none' && materialColors.isNotEmpty) {
      final List<Color> gradientPalette = materialColors.length == 1
          ? <Color>[materialColors.first, materialColors.first]
          : materialColors;
      final double overlayOpacity = isBackFacing ? 0.38 : 0.52;

      canvas.saveLayer(
        dstRect.inflate(2.0),
        Paint()..color = Color.fromRGBO(255, 255, 255, overlayOpacity),
      );
      canvas.drawImageRect(
        image,
        srcRect,
        dstRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      final Paint materialPaint = Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = ui.Gradient.linear(
          dstRect.topLeft,
          dstRect.bottomRight,
          gradientPalette,
          _logoDepthEvenStops(gradientPalette.length),
        );
      canvas.drawRect(dstRect, materialPaint);
      canvas.restore();
    }

    // e. Bevel highlight masked to a 1-2px top-left light rim.
    if (settings.bevel > 0.0) {
      final double bevelRatio = (settings.bevel / 20.0).clamp(0.0, 1.0);
      final double edgeShift = 1.0 + bevelRatio;
      final double edgeOpacity =
          (0.14 + 0.36 * bevelRatio) * (isBackFacing ? 0.65 : 1.0);

      canvas.saveLayer(
        dstRect.inflate(4.0),
        Paint()..blendMode = BlendMode.screen,
      );
      final Paint highlightPaint = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(255, 255, 255, edgeOpacity),
          BlendMode.srcIn,
        );
      canvas.drawImageRect(
        image,
        srcRect,
        dstRect.shift(Offset(-edgeShift, -edgeShift)),
        highlightPaint,
      );
      // Punch out the interior so only the top-left edge remains illuminated.
      final Paint maskCutPaint = Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.dstOut;
      canvas.drawImageRect(image, srcRect, dstRect, maskCutPaint);
      canvas.restore();
    }

  }
}

/// Renders the static layers ONCE into an image of the logo
/// rect plus [logoDepthStaticMargin] on every side. The spin
/// animation then only transforms this image per frame instead
/// of re-running the whole layer stack (up to 40 extrusion
/// draws + 2 saveLayer passes) at 60fps — the permanent fix
/// for the depth painter's per-frame cost noted in the
/// v1.19.0 plan (G3).
Future<ui.Image> renderLogoDepthStatic({
  required ui.Image image,
  required LogoMakerSettings settings,
  required bool backFacing,
  required Size size,
}) async {
  final Rect dest = logoDepthDestRect(image, size);
  final double margin = logoDepthStaticMargin(settings);
  final int width = (dest.width + margin * 2).ceil();
  final int height = (dest.height + margin * 2).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _drawLogoDepthLayers(
    canvas,
    image,
    settings,
    backFacing,
    Rect.fromLTWH(margin, margin, dest.width, dest.height),
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(width, height);
  picture.dispose();
  return rendered;
}

/// Holds the front/back static renders for ONE
/// (image, settings, size) combination. A new combination
/// re-renders both facings; the same combination is served
/// from memory. Owned images are disposed on replacement.
class LogoDepthImageCache {
  ui.Image? frontImage;
  ui.Image? backImage;

  /// Total static renders performed (test hook: proves the
  /// spin loop does NOT re-render, and that a settings/image
  /// change DOES invalidate).
  int renderCount = 0;

  String _key = '';
  bool _building = false;

  static String keyFor(ui.Image image, LogoMakerSettings settings, Size size) {
    return '${identityHashCode(image)}|${settings.hashCode}'
        '|${size.width.round()}x${size.height.round()}';
  }

  bool isReadyFor(ui.Image image, LogoMakerSettings settings, Size size) {
    return _key == keyFor(image, settings, size) && frontImage != null;
  }

  /// Ensures the statics for this combination exist. Returns
  /// true when they are ready afterwards. A call while another
  /// build is in flight returns false (the caller retries on
  /// its next build).
  Future<bool> ensure(
    ui.Image image,
    LogoMakerSettings settings,
    Size size,
  ) async {
    final String key = keyFor(image, settings, size);
    if (_key == key && frontImage != null) return true;
    if (_building) return false;
    _building = true;
    try {
      final ui.Image front = await renderLogoDepthStatic(
        image: image,
        settings: settings,
        backFacing: false,
        size: size,
      );
      final ui.Image back = await renderLogoDepthStatic(
        image: image,
        settings: settings,
        backFacing: true,
        size: size,
      );
      final ui.Image? oldFront = frontImage;
      final ui.Image? oldBack = backImage;
      frontImage = front;
      backImage = back;
      _key = key;
      renderCount += 2;
      oldFront?.dispose();
      oldBack?.dispose();
      return true;
    } finally {
      _building = false;
    }
  }

  void clear() {
    frontImage?.dispose();
    backImage?.dispose();
    frontImage = null;
    backImage = null;
    _key = '';
  }
}

/// Renders a logo image with simulated 3D extrusion, material shading, bevel,
/// drop shadow, glow, and horizontal flat-spin projection.
///
/// When [staticFront]/[staticBack] are provided (the
/// [LogoDepthImageCache] path), paint() only transforms the
/// pre-rendered static image for the current facing — the
/// expensive layer stack runs once per settings change, not
/// per animation frame.
class LogoDepthPainter extends CustomPainter {
  const LogoDepthPainter({
    required this.image,
    required this.settings,
    required this.spinAngle,
    this.staticFront,
    this.staticBack,
  });

  final ui.Image image;
  final LogoMakerSettings settings;
  final double spinAngle;
  final ui.Image? staticFront;
  final ui.Image? staticBack;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image.width == 0 || image.height == 0) {
      return;
    }

    final Rect dest = logoDepthDestRect(image, size);
    final double cosVal = math.cos(spinAngle);
    final bool isBackFacing = cosVal < 0.0;
    final double scaleX =
        cosVal.abs() < 0.015 ? (isBackFacing ? -0.015 : 0.015) : cosVal;

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.scale(scaleX, 1.0);

    final ui.Image? stat = isBackFacing ? staticBack : staticFront;
    if (stat != null) {
      // The static image holds the logo rect at (margin,
      // margin) inside it, at 1:1 scale. It is positioned so
      // that rect lands EXACTLY on the direct path's centred
      // rect — merely centring the static would drift by the
      // fractional part of (rect + 2x margin), because the
      // static's pixel size is that value's ceiling.
      final double margin = logoDepthStaticMargin(settings);
      canvas.drawImageRect(
        stat,
        Rect.fromLTWH(
          0,
          0,
          stat.width.toDouble(),
          stat.height.toDouble(),
        ),
        Rect.fromLTWH(
          -dest.width / 2 - margin,
          -dest.height / 2 - margin,
          stat.width.toDouble(),
          stat.height.toDouble(),
        ),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      _drawLogoDepthLayers(
        canvas,
        image,
        settings,
        isBackFacing,
        Rect.fromCenter(
          center: Offset.zero,
          width: dest.width,
          height: dest.height,
        ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoDepthPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.settings != settings ||
        oldDelegate.spinAngle != spinAngle ||
        oldDelegate.staticFront != staticFront ||
        oldDelegate.staticBack != staticBack;
  }
}

/// The dock carries ONLY tools whose panels are real: Logo
/// (source: current / text / shapes), Style (presets +
/// material + depth/bevel/shadow/glow), Spin (on/off + speed)
/// and Reveal (v1.21.0: reveal styles + backdrop scenes over
/// the section's big preview), plus the Save action. The Cube
/// and Parts engines keep their full controls in the News
/// Studio Logo tool (nothing was removed there); their
/// placeholder buttons were dropped here rather than shipping
/// dead buttons — the app's hard rule. They return to this
/// dock when their real panels land in this section.
enum _DockTool {
  logo('Logo', Icons.image_outlined),
  style('Style', Icons.auto_awesome_rounded),
  spin('Spin', Icons.threesixty_rounded),
  reveal('Reveal', Icons.play_circle_outline_rounded),
  save('Save', Icons.check_circle_outline_rounded);

  const _DockTool(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Which view the Logo panel shows: the source menu, the
/// text creator, or the shapes picker.
enum _LogoSourceView { menu, text, shapes }

class _MaterialOption {
  const _MaterialOption(this.id, this.label);

  final String id;
  final String label;
}

const List<_MaterialOption> _kMaterialOptions = <_MaterialOption>[
  _MaterialOption('gold', 'Gold'),
  _MaterialOption('chrome', 'Chrome'),
  _MaterialOption('silver', 'Silver'),
  _MaterialOption('neon', 'Neon'),
  _MaterialOption('glass', 'Glass'),
  _MaterialOption('fire', 'Fire'),
  _MaterialOption('ocean', 'Ocean'),
  _MaterialOption('sunset', 'Sunset'),
  _MaterialOption('mono', 'Mono'),
  _MaterialOption('none', 'None'),
];

/// Opens the full-screen Logo Maker as a pushed route (the
/// News Studio Logo tool's entry, v1.19.0 G1). [onClose] is
/// wired to pop the route; [onLogoImageChanged] fires when the
/// user creates a new logo from text or a shape inside the
/// section, so the host can persist it as the channel logo.
Future<void> pushLogoMakerSection(
  BuildContext context, {
  required ui.Image logoImage,
  LogoMakerSettings? initialSettings,
  required void Function(LogoMakerSettings) onSettingsChanged,
  required void Function(LogoMakerSettings) onSave,
  void Function(ui.Image)? onLogoImageChanged,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (routeContext) => LogoMakerSection(
        logoImage: logoImage,
        initialSettings: initialSettings,
        onSettingsChanged: onSettingsChanged,
        onSave: onSave,
        onClose: () => Navigator.of(routeContext).pop(),
        onLogoImageChanged: onLogoImageChanged,
      ),
    ),
  );
}

/// Full-screen 3D Logo Maker editor with live animated preview and tool dock.
class LogoMakerSection extends StatefulWidget {
  const LogoMakerSection({
    super.key,
    required this.logoImage,
    this.initialSettings,
    required this.onSettingsChanged,
    required this.onSave,
    required this.onClose,
    this.onLogoImageChanged,
  });

  final ui.Image logoImage;
  final LogoMakerSettings? initialSettings;
  final void Function(LogoMakerSettings) onSettingsChanged;
  final void Function(LogoMakerSettings) onSave;
  final VoidCallback onClose;

  /// Fires when a NEW logo image is created inside the section
  /// (from text or from a shape). The host owns persistence;
  /// the section keeps showing the new image as its current
  /// logo either way.
  final void Function(ui.Image)? onLogoImageChanged;

  @override
  State<LogoMakerSection> createState() => _LogoMakerSectionState();
}

class _LogoMakerSectionState extends State<LogoMakerSection>
    with TickerProviderStateMixin {
  late LogoMakerSettings _settings;
  late AnimationController _spinController;

  /// v1.21.0: drives the Reveal tab's one-shot animation.
  /// Separate from the spin loop — the two transforms never
  /// run on the same frame (the Reveal preview paints the
  /// reveal, the other tabs paint the spin).
  late AnimationController _revealController;
  _DockTool _selectedTool = _DockTool.logo;

  /// The logo the preview styles. Starts as the host's image;
  /// replaced when the user creates one from text or a shape.
  late ui.Image _currentImage;

  /// True when [_currentImage] was created inside this section
  /// (text/shape) — those are ours to dispose; the host's
  /// initial image is never disposed here.
  bool _ownsCurrentImage = false;

  String _sourceLabel = 'Current logo';
  _LogoSourceView _sourceView = _LogoSourceView.menu;

  /// G3: the depth painter's static renders, rebuilt only when
  /// the image, settings or preview size change.
  final LogoDepthImageCache _depthCache = LogoDepthImageCache();
  bool _staticScheduled = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings ?? const LogoMakerSettings();
    _currentImage = widget.logoImage;
    _spinController = AnimationController(
      vsync: this,
      duration: _durationForSpeed(_settings.spinSpeed),
    );
    if (_settings.spinOn) {
      _spinController.repeat();
    }
    _revealController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _revealStyle.durationMs),
    );
  }

  @override
  void dispose() {
    _depthCache.clear();
    if (_ownsCurrentImage) {
      _currentImage.dispose();
    }
    _revealController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  /// The reveal style the settings name (the first style
  /// when none is selected — its duration still sizes the
  /// controller, and the preview then holds the settled
  /// state instead of animating).
  LogoRevealStyle get _revealStyle {
    for (final style in kLogoRevealStyles) {
      if (style.id == _settings.revealStyleId) return style;
    }
    return kLogoRevealStyles.first;
  }

  /// Plays the selected reveal from the start, at the
  /// style's own duration. No style selected → nothing to
  /// play (the panel offers the style chips instead).
  void _playReveal() {
    if (_settings.revealStyleId.isEmpty) return;
    _revealController.duration =
        Duration(milliseconds: _revealStyle.durationMs);
    _revealController.forward(from: 0.0);
  }

  /// A style chip tap: persist the choice, then play it at
  /// its own duration. '' (the None chip) stops the reveal —
  /// the preview holds the settled logo over the backdrop.
  void _selectRevealStyle(String styleId) {
    _updateSettings(_settings.copyWith(revealStyleId: styleId));
    if (styleId.isEmpty) {
      _revealController.stop();
    } else {
      _playReveal();
    }
  }

  /// Scrubbing parks the reveal exactly where the user puts
  /// it — the Studio's proven pattern: stop first, then set
  /// the value directly (assigning value halts the running
  /// simulation, which is precisely what a scrub must do).
  void _onRevealScrub(double value) {
    if (_revealController.isAnimating) {
      _revealController.stop();
    }
    _revealController.value = value.clamp(0.0, 1.0);
  }

  /// A logo created from text or a shape becomes the section's
  /// current logo AND is reported to the host, which persists
  /// it as the channel logo (News Studio's logo file).
  void _adoptNewLogo(ui.Image image, String label) {
    final ui.Image old = _currentImage;
    final bool ownedOld = _ownsCurrentImage;
    setState(() {
      _currentImage = image;
      _ownsCurrentImage = true;
      _sourceLabel = label;
      _sourceView = _LogoSourceView.menu;
    });
    if (ownedOld && !identical(old, image)) {
      old.dispose();
    }
    widget.onLogoImageChanged?.call(image);
  }

  /// Schedules the static renders for the current combination
  /// (no-op while they are ready or already building).
  void _scheduleStatics(Size size) {
    if (_depthCache.isReadyFor(_currentImage, _settings, size)) return;
    if (_staticScheduled) return;
    _staticScheduled = true;
    final ui.Image image = _currentImage;
    final LogoMakerSettings settings = _settings;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool ready = await _depthCache.ensure(image, settings, size);
      _staticScheduled = false;
      if (ready && mounted) {
        setState(() {});
      }
    });
  }

  Duration _durationForSpeed(double spinSpeed) {
    final double safeSpeed = spinSpeed.clamp(0.5, 3.0);
    return Duration(milliseconds: (12000.0 / safeSpeed).round());
  }

  void _updateSettings(LogoMakerSettings next) {
    final bool spinChanged = next.spinOn != _settings.spinOn;
    final bool speedChanged = next.spinSpeed != _settings.spinSpeed;

    setState(() {
      _settings = next;
    });

    if (speedChanged) {
      _spinController.duration = _durationForSpeed(next.spinSpeed);
      if (next.spinOn) {
        // repeat() continues from the current value on its own. Assigning
        // _spinController.value here would stop the animation (the value
        // setter halts any running simulation), so it must not be touched.
        _spinController.repeat();
      }
    }

    if (spinChanged) {
      if (next.spinOn) {
        _spinController.repeat();
      } else {
        _spinController.stop();
        _spinController.value = 0.0;
      }
    }

    widget.onSettingsChanged(next);
  }

  void _applyPreset(LogoStylePreset preset) {
    _updateSettings(
      _settings.copyWith(
        presetId: preset.id,
        materialId: preset.materialId,
        depth: preset.depth,
        bevel: preset.bevel,
        shadowOn: preset.shadowOn,
        glowOn: preset.glowOn,
      ),
    );
  }

  void _handleDockTap(_DockTool tool) {
    if (tool == _DockTool.save) {
      widget.onSave(_settings);
      return;
    }
    setState(() {
      _selectedTool = tool;
    });
    if (tool == _DockTool.reveal) {
      // Opening the Reveal tab plays the reveal once, so the
      // user sees it immediately instead of a frozen frame.
      _playReveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // Keep preview around 52% of screen height without starving panels.
            final double targetPreviewHeight = math.min(
              screenHeight * 0.52,
              math.max(180.0, constraints.maxHeight - 260.0),
            );

            return Column(
              children: <Widget>[
                _buildTopBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                  child: SizedBox(
                    height: targetPreviewHeight,
                    width: double.infinity,
                    child: _buildLivePreview(),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildActivePanel(),
                  ),
                ),
                const SizedBox(height: 10.0),
                _buildBottomDock(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 16.0, 8.0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20.0,
            ),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4.0),
          const Expanded(
            child: Text(
              'Logo Maker',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const ToolGuideButton(guideId: 'ns.logo_maker', compact: true),
          const SizedBox(width: 6.0),
          GestureDetector(
            onTap: () => widget.onSave(_settings),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                gradient: _kAccentGradient,
                borderRadius: BorderRadius.circular(_kCardRadius),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color.fromRGBO(46, 124, 246, 0.55),
                    blurRadius: 16.0,
                    spreadRadius: 1.0,
                    offset: Offset(0.0, 2.0),
                  ),
                  BoxShadow(
                    color: Color.fromRGBO(34, 211, 238, 0.35),
                    blurRadius: 20.0,
                    offset: Offset(0.0, 0.0),
                  ),
                ],
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreview() {
    return Container(
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: <Color>[
            Color.fromRGBO(46, 124, 246, 0.14),
            Color.fromRGBO(255, 255, 255, 0.04),
            Color.fromRGBO(5, 9, 20, 0.92),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size paintSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            // G3: once the statics for this combination exist,
            // the per-frame paint is a single transformed draw
            // of the cached image; until then the painter runs
            // its direct layer path (identical output).
            _scheduleStatics(paintSize);
            final bool staticsReady =
                _depthCache.isReadyFor(_currentImage, _settings, paintSize);
            if (_selectedTool == _DockTool.reveal) {
              // v1.21.0: the SAME preview box (its size never
              // changes — Point #27) shows the backdrop scene
              // with the reveal playing over it. The reveal
              // animates the maker's STYLED logo — the depth
              // cache's front static once it exists, the raw
              // logo only until that first render lands. The
              // spin transform is NOT applied here: one
              // transform per frame.
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(
                    size: Size.infinite,
                    painter: LogoBackdropPainter(
                      backdropId: _settings.backdropId,
                      glowIntensity: _settings.backdropGlow,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _revealController,
                    builder: (BuildContext context, Widget? child) {
                      final bool hasStyle =
                          _settings.revealStyleId.isNotEmpty;
                      return CustomPaint(
                        size: Size.infinite,
                        painter: LogoRevealPainter(
                          image: staticsReady &&
                                  _depthCache.frontImage != null
                              ? _depthCache.frontImage!
                              : _currentImage,
                          styleId: hasStyle
                              ? _settings.revealStyleId
                              : 'fade_zoom',
                          progress:
                              hasStyle ? _revealController.value : 1.0,
                        ),
                      );
                    },
                  ),
                ],
              );
            }
            return AnimatedBuilder(
              animation: _spinController,
              builder: (BuildContext context, Widget? child) {
                final double angle = _settings.spinOn
                    ? _spinController.value * 2.0 * math.pi
                    : 0.0;
                return CustomPaint(
                  size: Size.infinite,
                  painter: LogoDepthPainter(
                    image: _currentImage,
                    settings: _settings,
                    spinAngle: angle,
                    staticFront:
                        staticsReady ? _depthCache.frontImage : null,
                    staticBack: staticsReady ? _depthCache.backImage : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildActivePanel() {
    switch (_selectedTool) {
      case _DockTool.logo:
        return _buildLogoPanel();
      case _DockTool.style:
        return _buildStylePanel();
      case _DockTool.spin:
        return _buildSpinPanel();
      case _DockTool.reveal:
        return _buildRevealPanel();
      case _DockTool.save:
        // Save is an action, never a panel.
        return _buildLogoPanel();
    }
  }

  /// v1.21.0 — the Reveal panel: the checked Studio's parts
  /// (style chips, backdrop chips, Play + scrub) rebuilt on
  /// the section's own chrome, plus the backdrop glow slider
  /// the backdrop painter takes. The preview above shows the
  /// result; this panel never resizes it.
  Widget _buildRevealPanel() {
    final bool hasStyle = _settings.revealStyleId.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Reveal Style',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10.0),
            SizedBox(
              height: 38.0,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kLogoRevealStyles.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return _buildSelectableChip(
                      label: 'None',
                      selected: !hasStyle,
                      swatchColors: const <Color>[],
                      onTap: () => _selectRevealStyle(''),
                    );
                  }
                  final LogoRevealStyle style =
                      kLogoRevealStyles[index - 1];
                  return _buildSelectableChip(
                    label: style.name,
                    selected: _settings.revealStyleId == style.id,
                    swatchColors: const <Color>[],
                    onTap: () => _selectRevealStyle(style.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 14.0),
            const Text(
              'Backdrop Scene',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10.0),
            SizedBox(
              height: 38.0,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kLogoBackdrops.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                itemBuilder: (BuildContext context, int index) {
                  final LogoBackdropDef backdrop = kLogoBackdrops[index];
                  return _buildSelectableChip(
                    label: backdrop.name,
                    selected: _settings.backdropId == backdrop.id,
                    swatchColors: const <Color>[],
                    onTap: () => _updateSettings(
                      _settings.copyWith(backdropId: backdrop.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10.0),
            _buildSliderRow(
              label: 'Backdrop Glow',
              value: _settings.backdropGlow,
              min: 0.0,
              max: 1.0,
              valueLabel: '${(_settings.backdropGlow * 100).round()}%',
              onChanged: (double value) =>
                  _updateSettings(_settings.copyWith(backdropGlow: value)),
            ),
            const SizedBox(height: 8.0),
            if (hasStyle)
              _buildRevealPlaybackRow()
            else
              const Text(
                'Pick a reveal style above to play it here.',
                style: TextStyle(color: Colors.white54, fontSize: 12.0),
              ),
            const SizedBox(height: 8.0),
            const Text(
              'The reveal plays over the backdrop in the preview '
              'above, animating the same styled logo (depth and '
              'material included). In the video export the logo '
              'keeps its styled look and spin — the reveal and '
              'the backdrop are preview-only for now.',
              style: TextStyle(color: Colors.white54, fontSize: 12.0),
            ),
          ],
        ),
      ),
    );
  }

  /// Play + scrub for the reveal, rebuilt on every tick so
  /// the slider and the progress readout track the playing
  /// animation (the Studio's playback card pattern).
  Widget _buildRevealPlaybackRow() {
    return AnimatedBuilder(
      animation: _revealController,
      builder: (BuildContext context, Widget? child) {
        final int percent = (_revealController.value * 100).round();
        return Row(
          children: <Widget>[
            GestureDetector(
              key: const Key('logoMakerRevealPlay'),
              onTap: _playReveal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                decoration: BoxDecoration(
                  gradient: _kAccentGradient,
                  borderRadius: BorderRadius.circular(_kCardRadius),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18.0,
                    ),
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
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _kAccentCyan,
                  inactiveTrackColor: _kCardBorderColor,
                  thumbColor: _kAccentCyan,
                  overlayColor:
                      const Color.fromRGBO(34, 211, 238, 0.2),
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                ),
                child: Slider(
                  key: const Key('logoMakerRevealScrub'),
                  value: _revealController.value.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: _onRevealScrub,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Text(
              '$percent% · ${_revealStyle.durationMs}ms',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogoPanel() {
    switch (_sourceView) {
      case _LogoSourceView.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildSourceBackRow(),
            Expanded(
              child: LogoTextCreator(
                onCreated: (ui.Image image) =>
                    _adoptNewLogo(image, 'Text logo'),
              ),
            ),
          ],
        );
      case _LogoSourceView.shapes:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildSourceBackRow(),
            Expanded(
              child: LogoShapePicker(
                onPicked: (ui.Image image) =>
                    _adoptNewLogo(image, 'Shape logo'),
              ),
            ),
          ],
        );
      case _LogoSourceView.menu:
        return Container(
          decoration: BoxDecoration(
            color: _kCardFillColor,
            borderRadius: BorderRadius.circular(_kCardRadius),
            border: Border.all(color: _kCardBorderColor, width: 1.0),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Logo Source',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10.0),
                Row(
                  children: <Widget>[
                    Container(
                      width: 56.0,
                      height: 56.0,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.35),
                        borderRadius: BorderRadius.circular(12.0),
                        border:
                            Border.all(color: _kCardBorderColor, width: 1.0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: RawImage(
                          image: _currentImage,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Current Image',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            _sourceLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14.0),
                _buildSourceButton(
                  key: const Key('logoMakerTextButton'),
                  icon: Icons.text_fields_rounded,
                  label: 'Create from Text',
                  onTap: () => setState(
                    () => _sourceView = _LogoSourceView.text,
                  ),
                ),
                const SizedBox(height: 8.0),
                _buildSourceButton(
                  key: const Key('logoMakerShapesButton'),
                  icon: Icons.star_outline_rounded,
                  label: 'Pick a Shape / Badge',
                  onTap: () => setState(
                    () => _sourceView = _LogoSourceView.shapes,
                  ),
                ),
                const SizedBox(height: 12.0),
                const Text(
                  'A logo made from text or a shape becomes the '
                  'channel logo right away. The 3D Cube and Parts '
                  'controls stay in the News Studio Logo tool — '
                  'nothing was removed.',
                  style: TextStyle(color: Colors.white54, fontSize: 12.0),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildSourceBackRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: GestureDetector(
        key: const Key('logoMakerSourceBack'),
        onTap: () => setState(() => _sourceView = _LogoSourceView.menu),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _kAccentCyan,
              size: 14.0,
            ),
            SizedBox(width: 6.0),
            Text(
              'Logo source',
              style: TextStyle(
                color: _kAccentCyan,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: _kCardFillColor,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: _kCardBorderColor, width: 1.0),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: _kAccentCyan, size: 18.0),
            const SizedBox(width: 10.0),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white54,
              size: 18.0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpinPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Spin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10.0),
            _buildToggleTile(
              label: 'Spin',
              value: _settings.spinOn,
              onChanged: (bool value) =>
                  _updateSettings(_settings.copyWith(spinOn: value)),
            ),
            const SizedBox(height: 8.0),
            _buildSliderRow(
              label: 'Spin Speed',
              value: _settings.spinSpeed,
              min: 0.5,
              max: 3.0,
              valueLabel: '${_settings.spinSpeed.toStringAsFixed(1)}x',
              onChanged: (double value) =>
                  _updateSettings(_settings.copyWith(spinSpeed: value)),
            ),
            const SizedBox(height: 6.0),
            const Text(
              'Spin on/off and speed are saved with the channel '
              'and restored when you come back.',
              style: TextStyle(color: Colors.white54, fontSize: 12.0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStylePanel() {
    return Container(
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14.0, 14.0, 14.0, 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Presets',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10.0),
              SizedBox(
                height: 38.0,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kLogoStylePresets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                  itemBuilder: (BuildContext context, int index) {
                    final LogoStylePreset preset = kLogoStylePresets[index];
                    final bool isSelected = _settings.presetId == preset.id;
                    return _buildSelectableChip(
                      label: preset.name,
                      selected: isSelected,
                      swatchColors: preset.gradientColors,
                      onTap: () => _applyPreset(preset),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14.0),
              _buildSliderRow(
                label: 'Depth',
                value: _settings.depth,
                min: 0.0,
                max: 40.0,
                valueLabel: _settings.depth.round().toString(),
                onChanged: (double value) =>
                    _updateSettings(_settings.copyWith(depth: value)),
              ),
              _buildSliderRow(
                label: 'Bevel',
                value: _settings.bevel,
                min: 0.0,
                max: 20.0,
                valueLabel: _settings.bevel.round().toString(),
                onChanged: (double value) =>
                    _updateSettings(_settings.copyWith(bevel: value)),
              ),
              _buildSliderRow(
                label: 'Shadow Blur',
                value: _settings.shadowBlur,
                min: 2.0,
                max: 40.0,
                valueLabel: _settings.shadowBlur.round().toString(),
                onChanged: (double value) =>
                    _updateSettings(_settings.copyWith(shadowBlur: value)),
              ),
              const SizedBox(height: 4.0),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildToggleTile(
                      label: 'Shadow',
                      value: _settings.shadowOn,
                      onChanged: (bool value) =>
                          _updateSettings(_settings.copyWith(shadowOn: value)),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: _buildToggleTile(
                      label: 'Glow',
                      value: _settings.glowOn,
                      onChanged: (bool value) =>
                          _updateSettings(_settings.copyWith(glowOn: value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              _buildSliderRow(
                label: 'Glow Intensity',
                value: _settings.glowIntensity,
                min: 0.0,
                max: 1.0,
                valueLabel: '${(_settings.glowIntensity * 100).round()}%',
                onChanged: (double value) =>
                    _updateSettings(_settings.copyWith(glowIntensity: value)),
              ),
              const SizedBox(height: 10.0),
              const Text(
                'Material',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10.0),
              SizedBox(
                height: 38.0,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kMaterialOptions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8.0),
                  itemBuilder: (BuildContext context, int index) {
                    final _MaterialOption option = _kMaterialOptions[index];
                    final bool isSelected = _settings.materialId == option.id;
                    final List<Color> swatch =
                        kLogoMaterials[option.id] ?? const <Color>[];
                    return _buildSelectableChip(
                      label: option.label,
                      selected: isSelected,
                      swatchColors: swatch,
                      onTap: () => _updateSettings(
                        _settings.copyWith(materialId: option.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectableChip({
    required String label,
    required bool selected,
    required List<Color> swatchColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          gradient: selected ? _kAccentGradient : null,
          color: selected ? null : _kCardFillColor,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(
            color: selected ? Colors.transparent : _kCardBorderColor,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (swatchColors.isNotEmpty) ...<Widget>[
              Container(
                width: 10.0,
                height: 10.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: swatchColors.length == 1
                        ? <Color>[swatchColors.first, swatchColors.first]
                        : swatchColors,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12.0,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96.0,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.0,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _kAccentCyan,
                inactiveTrackColor: _kCardBorderColor,
                thumbColor: _kAccentCyan,
                overlayColor: const Color.fromRGBO(34, 211, 238, 0.2),
                trackHeight: 3.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7.0),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38.0,
            child: Text(
              valueLabel,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: _kCardFillColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorderColor, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _kAccentCyan,
            activeThumbColor: Colors.white,
            inactiveTrackColor: _kCardBorderColor,
            inactiveThumbColor: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 10.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: _kCardFillColor,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: _kCardBorderColor, width: 1.0),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _DockTool.values.map((_DockTool tool) {
              final bool isSelected =
                  tool != _DockTool.save && _selectedTool == tool;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: GestureDetector(
                  onTap: () => _handleDockTap(tool),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 58.0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      gradient: isSelected ? _kAccentGradient : null,
                      color: isSelected ? null : _kCardFillColor,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(
                        color:
                            isSelected ? Colors.transparent : _kCardBorderColor,
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          tool.icon,
                          size: 18.0,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          tool.label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 12.0,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
