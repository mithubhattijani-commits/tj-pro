import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

class LogoLightingCameraSettings {
  final bool lightingOn;
  final double lightAngleDeg;
  final double lightIntensity;
  final double shadowDepth;
  final double rimGlow;
  final double cameraTiltX;
  final double cameraTiltY;
  final double cameraZoom;
  final double cameraRotationDeg;

  const LogoLightingCameraSettings({
    this.lightingOn = false,
    this.lightAngleDeg = -35,
    this.lightIntensity = 0.6,
    this.shadowDepth = 0.45,
    this.rimGlow = 0.0,
    this.cameraTiltX = 0.0,
    this.cameraTiltY = 0.0,
    this.cameraZoom = 1.0,
    this.cameraRotationDeg = 0.0,
  });

  static const LogoLightingCameraSettings defaults =
      LogoLightingCameraSettings();

  static double _clamp(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  LogoLightingCameraSettings copyWith({
    bool? lightingOn,
    double? lightAngleDeg,
    double? lightIntensity,
    double? shadowDepth,
    double? rimGlow,
    double? cameraTiltX,
    double? cameraTiltY,
    double? cameraZoom,
    double? cameraRotationDeg,
  }) {
    return LogoLightingCameraSettings(
      lightingOn: lightingOn ?? this.lightingOn,
      lightAngleDeg: _clamp(lightAngleDeg ?? this.lightAngleDeg, -180, 180),
      lightIntensity:
          _clamp(lightIntensity ?? this.lightIntensity, 0, 1),
      shadowDepth: _clamp(shadowDepth ?? this.shadowDepth, 0, 1),
      rimGlow: _clamp(rimGlow ?? this.rimGlow, 0, 1),
      cameraTiltX: _clamp(cameraTiltX ?? this.cameraTiltX, -1, 1),
      cameraTiltY: _clamp(cameraTiltY ?? this.cameraTiltY, -1, 1),
      cameraZoom: _clamp(cameraZoom ?? this.cameraZoom, 0.6, 1.8),
      cameraRotationDeg:
          _clamp(cameraRotationDeg ?? this.cameraRotationDeg, -30, 30),
    );
  }

  Map<String, dynamic> toJson() => {
        'lightingOn': lightingOn,
        'lightAngleDeg': lightAngleDeg,
        'lightIntensity': lightIntensity,
        'shadowDepth': shadowDepth,
        'rimGlow': rimGlow,
        'cameraTiltX': cameraTiltX,
        'cameraTiltY': cameraTiltY,
        'cameraZoom': cameraZoom,
        'cameraRotationDeg': cameraRotationDeg,
      };

  static LogoLightingCameraSettings fromJson(Object? json) {
    if (json is! Map) return defaults;

    bool readBool(String key, bool fallback) {
      try {
        final value = json[key];
        return value is bool ? value : fallback;
      } catch (_) {
        return fallback;
      }
    }

    double readDouble(
      String key,
      double fallback,
      double min,
      double max,
    ) {
      try {
        final value = json[key];
        if (value is! num) return fallback;

        final result = value.toDouble();
        if (!result.isFinite) return fallback;

        return _clamp(result, min, max);
      } catch (_) {
        return fallback;
      }
    }

    return LogoLightingCameraSettings(
      lightingOn: readBool('lightingOn', false),
      lightAngleDeg: readDouble('lightAngleDeg', -35, -180, 180),
      lightIntensity: readDouble('lightIntensity', 0.6, 0, 1),
      shadowDepth: readDouble('shadowDepth', 0.45, 0, 1),
      rimGlow: readDouble('rimGlow', 0.0, 0, 1),
      cameraTiltX: readDouble('cameraTiltX', 0.0, -1, 1),
      cameraTiltY: readDouble('cameraTiltY', 0.0, -1, 1),
      cameraZoom: readDouble('cameraZoom', 1.0, 0.6, 1.8),
      cameraRotationDeg:
          readDouble('cameraRotationDeg', 0.0, -30, 30),
    );
  }

  bool get isNeutral =>
      !lightingOn &&
      cameraTiltX == 0 &&
      cameraTiltY == 0 &&
      cameraZoom == 1 &&
      cameraRotationDeg == 0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LogoLightingCameraSettings &&
            lightingOn == other.lightingOn &&
            lightAngleDeg == other.lightAngleDeg &&
            lightIntensity == other.lightIntensity &&
            shadowDepth == other.shadowDepth &&
            rimGlow == other.rimGlow &&
            cameraTiltX == other.cameraTiltX &&
            cameraTiltY == other.cameraTiltY &&
            cameraZoom == other.cameraZoom &&
            cameraRotationDeg == other.cameraRotationDeg;
  }

  @override
  int get hashCode => Object.hash(
        lightingOn,
        lightAngleDeg,
        lightIntensity,
        shadowDepth,
        rimGlow,
        cameraTiltX,
        cameraTiltY,
        cameraZoom,
        cameraRotationDeg,
      );
}

// -----------------------------------------------------------------------------
// PRESETS
// -----------------------------------------------------------------------------

class LogoLightPreset {
  final String id;
  final String name;
  final LogoLightingCameraSettings settings;

  const LogoLightPreset({
    required this.id,
    required this.name,
    required this.settings,
  });
}

const List<LogoLightPreset> kLogoLightPresets = [
  LogoLightPreset(
    id: 'none',
    name: 'No Light',
    settings: LogoLightingCameraSettings.defaults,
  ),
  LogoLightPreset(
    id: 'studio_soft',
    name: 'Studio Soft',
    settings: LogoLightingCameraSettings(
      lightingOn: true,
      lightAngleDeg: -50,
      lightIntensity: 0.45,
      shadowDepth: 0.3,
      rimGlow: 0.15,
    ),
  ),
  LogoLightPreset(
    id: 'dramatic_side',
    name: 'Dramatic Side',
    settings: LogoLightingCameraSettings(
      lightingOn: true,
      lightAngleDeg: 5,
      lightIntensity: 0.85,
      shadowDepth: 0.7,
      rimGlow: 0.3,
      cameraTiltY: 0.15,
    ),
  ),
  LogoLightPreset(
    id: 'top_light',
    name: 'Top Light',
    settings: LogoLightingCameraSettings(
      lightingOn: true,
      lightAngleDeg: -90,
      lightIntensity: 0.65,
      shadowDepth: 0.5,
      rimGlow: 0.2,
      cameraTiltX: -0.1,
    ),
  ),
  LogoLightPreset(
    id: 'neon_rim',
    name: 'Neon Rim',
    settings: LogoLightingCameraSettings(
      lightingOn: true,
      lightAngleDeg: 160,
      lightIntensity: 0.5,
      shadowDepth: 0.35,
      rimGlow: 0.9,
    ),
  ),
  LogoLightPreset(
    id: 'stage_tilt',
    name: 'Stage Tilt',
    settings: LogoLightingCameraSettings(
      lightingOn: true,
      lightAngleDeg: -35,
      lightIntensity: 0.6,
      shadowDepth: 0.45,
      rimGlow: 0.25,
      cameraTiltX: 0.2,
      cameraTiltY: -0.25,
      cameraZoom: 1.1,
      cameraRotationDeg: -4,
    ),
  ),
];

// -----------------------------------------------------------------------------
// PAINTER
// -----------------------------------------------------------------------------

class LogoLightingCameraPainter extends CustomPainter {
  final ui.Image logoImage;
  final LogoLightingCameraSettings settings;
  final Color background;

  static const Color accentCyan = Color(0xFF22D3EE);

  LogoLightingCameraPainter({
    required this.logoImage,
    required this.settings,
    this.background = const Color(0xFF050914),
  });

  Rect _fittedRect(Size size) {
    final imageWidth = logoImage.width.toDouble();
    final imageHeight = logoImage.height.toDouble();

    if (imageWidth <= 0 || imageHeight <= 0) {
      return Rect.zero;
    }

    final scale = math.min(
      size.width / imageWidth,
      size.height / imageHeight,
    );

    final width = imageWidth * scale;
    final height = imageHeight * scale;

    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  void _drawLogo(
    Canvas canvas,
    Rect destination, {
    ColorFilter? colorFilter,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..blendMode = blendMode;

    if (colorFilter != null) {
      paint.colorFilter = colorFilter;
    }

    canvas.drawImageRect(
      logoImage,
      Rect.fromLTWH(
        0,
        0,
        logoImage.width.toDouble(),
        logoImage.height.toDouble(),
      ),
      destination,
      paint,
    );
  }

  Float64List _cameraMatrix(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final rotation =
        settings.cameraRotationDeg * math.pi / 180;

    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);

    final zoom = settings.cameraZoom;

    final tiltY = settings.cameraTiltY * 0.0016;
    final tiltX = -settings.cameraTiltX * 0.0016;

    // Column-major 4x4 perspective matrix.
    final matrix = Float64List(16);

    // Rotation and zoom.
    matrix[0] = cosR * zoom;
    matrix[1] = sinR * zoom;
    matrix[4] = -sinR * zoom;
    matrix[5] = cosR * zoom;

    // Perspective.
    matrix[3] = tiltY;
    matrix[7] = tiltX;

    // Z and homogeneous coordinates.
    matrix[10] = 1;
    matrix[15] = 1;

    // Translation around canvas centre.
    matrix[12] = cx -
        matrix[0] * cx -
        matrix[4] * cy;
    matrix[13] = cy -
        matrix[1] * cx -
        matrix[5] * cy;

    matrix[14] = 0;

    return matrix;
  }

  void _drawDirectionalShade(Canvas canvas, Size size) {
    final angle = settings.lightAngleDeg * math.pi / 180;

    final dx = math.cos(angle);
    final dy = math.sin(angle);

    final center = Offset(size.width / 2, size.height / 2);

    final distance = math.sqrt(
      size.width * size.width + size.height * size.height,
    );

    final lightPoint = Offset(
      center.dx + dx * distance * 0.5,
      center.dy + dy * distance * 0.5,
    );

    final farPoint = Offset(
      center.dx - dx * distance * 0.5,
      center.dy - dy * distance * 0.5,
    );

    final alpha = (settings.shadowDepth * 0.55 * 255)
        .round()
        .clamp(0, 255);

    final paint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = ui.Gradient.linear(
        lightPoint,
        farPoint,
        <Color>[
          Colors.transparent,
          Color.fromARGB(alpha, 0, 0, 0),
        ],
      );

    canvas.drawRect(
      Offset.zero & size,
      paint,
    );
  }

  void _drawHighlight(Canvas canvas, Size size) {
    final angle = settings.lightAngleDeg * math.pi / 180;

    final dx = math.cos(angle);
    final dy = math.sin(angle);

    final center = Offset(size.width / 2, size.height / 2);

    final distance = math.sqrt(
      size.width * size.width + size.height * size.height,
    );

    final lightPoint = Offset(
      center.dx + dx * distance * 0.5,
      center.dy + dy * distance * 0.5,
    );

    final fadePoint = Offset(
      center.dx - dx * distance * 0.05,
      center.dy - dy * distance * 0.05,
    );

    final alpha = (settings.lightIntensity * 0.28 * 255)
        .round()
        .clamp(0, 255);

    final paint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = ui.Gradient.linear(
        lightPoint,
        fadePoint,
        <Color>[
          Color.fromARGB(alpha, 255, 255, 255),
          Colors.transparent,
        ],
      );

    canvas.drawRect(
      Offset.zero & size,
      paint,
    );
  }

  void _drawRimGlow(
    Canvas canvas,
    Rect destination,
    Size size,
  ) {
    if (settings.rimGlow <= 0) return;

    final angle = settings.lightAngleDeg * math.pi / 180;

    final dx = math.cos(angle);
    final dy = math.sin(angle);

    const shiftDistance = 2.5;

    final shiftedRect = destination.shift(
      Offset(
        dx * shiftDistance,
        dy * shiftDistance,
      ),
    );

    final alpha = (settings.rimGlow * 0.35 * 255)
        .round()
        .clamp(0, 255);

    final glowPaint = Paint()
      ..colorFilter = ColorFilter.mode(
        accentCyan.withAlpha(alpha),
        BlendMode.srcIn,
      )
      ..blendMode = BlendMode.screen
      ..filterQuality = FilterQuality.high;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    canvas.drawImageRect(
      logoImage,
      Rect.fromLTWH(
        0,
        0,
        logoImage.width.toDouble(),
        logoImage.height.toDouble(),
      ),
      shiftedRect,
      glowPaint,
    );

    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final canvasRect = Offset.zero & size;

    // Background.
    canvas.drawRect(
      canvasRect,
      Paint()..color = background,
    );

    final destination = _fittedRect(size);

    if (destination.isEmpty) return;

    // Exact neutral output: plain contain-fitted image.
    if (settings.isNeutral) {
      _drawLogo(canvas, destination);
      return;
    }

    // Camera transform.
    canvas.save();

    if (settings.cameraTiltX != 0 ||
        settings.cameraTiltY != 0 ||
        settings.cameraZoom != 1 ||
        settings.cameraRotationDeg != 0) {
      canvas.transform(_cameraMatrix(size));
    }

    // Base logo.
    _drawLogo(canvas, destination);

    // Lighting passes.
    if (settings.lightingOn) {
      // 1. Rim glow.
      _drawRimGlow(canvas, destination, size);

      // 2. Directional shade.
      _drawDirectionalShade(canvas, size);

      // 3. Highlight.
      _drawHighlight(canvas, size);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoLightingCameraPainter oldDelegate) {
    return !identical(oldDelegate.logoImage, logoImage) ||
        oldDelegate.settings != settings ||
        oldDelegate.background != background;
  }
}

// -----------------------------------------------------------------------------
// CONTROL PANEL
// -----------------------------------------------------------------------------

class LogoLightingCameraPanel extends StatelessWidget {
  final LogoLightingCameraSettings settings;
  final ValueChanged<LogoLightingCameraSettings> onChanged;

  static const Color _background = Color(0xFF050914);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _blue = Color(0xFF2E7CF6);
  static const Color _purple = Color(0xFF8B5CF6);

  const LogoLightingCameraPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  LinearGradient get _gradient => const LinearGradient(
        colors: [
          _blue,
          _purple,
          _cyan,
        ],
      );

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withAlpha(15),
        ),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          color: _cyan,
          size: 19,
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(LogoLightPreset preset) {
    final selected = settings == preset.settings;

    return GestureDetector(
      onTap: () => onChanged(preset.settings),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: selected ? _gradient : null,
          color: selected ? null : Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withAlpha(20),
          ),
        ),
        child: Text(
          preset.name,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onValueChanged,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(2)}${suffix ?? ''}',
                style: const TextStyle(
                  color: _cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: _cyan,
              inactiveTrackColor: Colors.white24,
              thumbColor: _cyan,
              overlayColor: Color(0x1E22D3EE),
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: 7,
              ),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              activeColor: _cyan,
              inactiveColor: Colors.white24,
              onChanged: onValueChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _cyan.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.light_mode_rounded,
            color: _cyan,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lighting',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Enable studio lighting effects',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: settings.lightingOn,
          activeThumbColor: _cyan,
          onChanged: (value) {
            onChanged(settings.copyWith(lightingOn: value));
          },
        ),
      ],
    );
  }

  Widget _buildResetButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () {
          onChanged(LogoLightingCameraSettings.defaults);
        },
        icon: const Icon(
          Icons.restart_alt_rounded,
          size: 18,
        ),
        label: const Text('Reset'),
        style: TextButton.styleFrom(
          foregroundColor: _cyan,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: _background,
          sliderTheme: const SliderThemeData(
            activeTrackColor: _cyan,
            inactiveTrackColor: Colors.white24,
            thumbColor: _cyan,
            overlayColor: Color(0x3322D3EE),
            trackHeight: 3,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Presets.
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    'Lighting Presets',
                    Icons.auto_awesome_rounded,
                  ),
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 8,
                    runSpacing: 9,
                    children: kLogoLightPresets
                        .map(_buildPresetChip)
                        .toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Lighting controls.
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    'Light Settings',
                    Icons.wb_sunny_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildSwitch(),
                  const SizedBox(height: 15),

                  _buildSlider(
                    label: 'Light Angle',
                    value: settings.lightAngleDeg,
                    min: -180,
                    max: 180,
                    suffix: '°',
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(lightAngleDeg: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Light Intensity',
                    value: settings.lightIntensity,
                    min: 0,
                    max: 1,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(lightIntensity: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Shadow Depth',
                    value: settings.shadowDepth,
                    min: 0,
                    max: 1,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(shadowDepth: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Rim Glow',
                    value: settings.rimGlow,
                    min: 0,
                    max: 1,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(rimGlow: v));
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Camera controls.
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    'Camera Controls',
                    Icons.camera_alt_rounded,
                  ),
                  const SizedBox(height: 18),

                  _buildSlider(
                    label: 'Camera Tilt X',
                    value: settings.cameraTiltX,
                    min: -1,
                    max: 1,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(cameraTiltX: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Camera Tilt Y',
                    value: settings.cameraTiltY,
                    min: -1,
                    max: 1,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(cameraTiltY: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Camera Zoom',
                    value: settings.cameraZoom,
                    min: 0.6,
                    max: 1.8,
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(cameraZoom: v));
                    },
                  ),

                  _buildSlider(
                    label: 'Rotation',
                    value: settings.cameraRotationDeg,
                    min: -30,
                    max: 30,
                    suffix: '°',
                    onValueChanged: (v) {
                      onChanged(settings.copyWith(
                        cameraRotationDeg: v,
                      ));
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            _buildResetButton(),
          ],
        ),
      ),
    );
  }
}
