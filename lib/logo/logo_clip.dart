import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Factory that creates a reveal/logo painter for a given [image], reveal
/// [progress] (0.0..1.0), and post-reveal [spinAngle] in radians.
typedef LogoClipRevealPainterBuilder = CustomPainter Function(
  ui.Image image,
  double progress,
  double spinAngle,
);

/// Factory that creates a backdrop painter for a given [backdropId] and [glow]
/// intensity (0.0..1.0).
typedef LogoClipBackdropPainterBuilder = CustomPainter Function(
  String backdropId,
  double glow,
);

/// Immutable configuration for a rendered Logo Clip.
class LogoClipSettings {
  static const List<int> allowedDurationsSec = <int>[3, 5, 8];

  static const List<String> allowedAspectIds = <String>[
    'wide',
    'square',
    'portrait',
  ];

  static const Map<String, int> revealDurationsMs = <String, int>{
    'fade_zoom': 1200,
    'slide_wipe': 1000,
    'shine_sweep': 1400,
    'bounce_in': 1100,
    'spin_reveal': 1300,
    'rise_glow': 1500,
    'none': 0,
  };

  static const List<String> allowedBackdropIds = <String>[
    'midnight_studio',
    'royal_stage',
    'neon_grid',
    'soft_spotlight',
    'deep_ocean',
    'plain_dark',
  ];

  static const LogoClipSettings defaults = LogoClipSettings();

  final int durationSec;
  final String aspectId;
  final String revealStyleId;
  final String backdropId;
  final double backdropGlow;
  final bool spinAfterReveal;
  final double spinSpeed;

  const LogoClipSettings({
    int durationSec = 5,
    String aspectId = 'wide',
    String revealStyleId = 'fade_zoom',
    String backdropId = 'midnight_studio',
    double backdropGlow = 0.6,
    this.spinAfterReveal = false,
    double spinSpeed = 1.0,
  })  : durationSec = durationSec <= 4 ? 3 : (durationSec <= 6 ? 5 : 8),
        aspectId = (aspectId == 'square' ||
                aspectId == 'wide' ||
                aspectId == 'portrait')
            ? aspectId
            : 'wide',
        revealStyleId = (revealStyleId == 'fade_zoom' ||
                revealStyleId == 'slide_wipe' ||
                revealStyleId == 'shine_sweep' ||
                revealStyleId == 'bounce_in' ||
                revealStyleId == 'spin_reveal' ||
                revealStyleId == 'rise_glow' ||
                revealStyleId == 'none')
            ? revealStyleId
            : 'fade_zoom',
        backdropId = (backdropId == 'midnight_studio' ||
                backdropId == 'royal_stage' ||
                backdropId == 'neon_grid' ||
                backdropId == 'soft_spotlight' ||
                backdropId == 'deep_ocean' ||
                backdropId == 'plain_dark')
            ? backdropId
            : 'plain_dark',
        backdropGlow = (backdropGlow != backdropGlow)
            ? 0.6
            : (backdropGlow < 0.0
                ? 0.0
                : (backdropGlow > 1.0 ? 1.0 : backdropGlow)),
        spinSpeed = (spinSpeed != spinSpeed)
            ? 1.0
            : (spinSpeed < 0.5 ? 0.5 : (spinSpeed > 3.0 ? 3.0 : spinSpeed));

  int get revealDurationMs => revealDurationsMs[revealStyleId] ?? 0;

  Size get outputSize {
    switch (aspectId) {
      case 'square':
        return const Size(1080, 1080);
      case 'portrait':
        return const Size(1080, 1920);
      case 'wide':
      default:
        return const Size(1920, 1080);
    }
  }

  LogoClipSettings copyWith({
    int? durationSec,
    String? aspectId,
    String? revealStyleId,
    String? backdropId,
    double? backdropGlow,
    bool? spinAfterReveal,
    double? spinSpeed,
  }) {
    return LogoClipSettings(
      durationSec: durationSec ?? this.durationSec,
      aspectId: aspectId ?? this.aspectId,
      revealStyleId: revealStyleId ?? this.revealStyleId,
      backdropId: backdropId ?? this.backdropId,
      backdropGlow: backdropGlow ?? this.backdropGlow,
      spinAfterReveal: spinAfterReveal ?? this.spinAfterReveal,
      spinSpeed: spinSpeed ?? this.spinSpeed,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'durationSec': durationSec,
      'aspectId': aspectId,
      'revealStyleId': revealStyleId,
      'backdropId': backdropId,
      'backdropGlow': backdropGlow,
      'spinAfterReveal': spinAfterReveal,
      'spinSpeed': spinSpeed,
    };
  }

  factory LogoClipSettings.fromJson(Map<dynamic, dynamic> json) {
    Object? readField(String key) {
      try {
        return json[key];
      } catch (_) {
        return null;
      }
    }

    final Object? rawDuration = readField('durationSec');
    final Object? rawAspect = readField('aspectId');
    final Object? rawReveal = readField('revealStyleId');
    final Object? rawBackdrop = readField('backdropId');
    final Object? rawGlow = readField('backdropGlow');
    final Object? rawSpinAfter = readField('spinAfterReveal');
    final Object? rawSpinSpeed = readField('spinSpeed');

    return LogoClipSettings(
      durationSec: rawDuration is int ? rawDuration : 5,
      aspectId: rawAspect is String ? rawAspect : 'wide',
      revealStyleId: rawReveal is String ? rawReveal : 'fade_zoom',
      backdropId: rawBackdrop is String ? rawBackdrop : 'midnight_studio',
      backdropGlow:
          (rawGlow is num && rawGlow.isFinite) ? rawGlow.toDouble() : 0.6,
      spinAfterReveal: rawSpinAfter is bool ? rawSpinAfter : false,
      spinSpeed: (rawSpinSpeed is num && rawSpinSpeed.isFinite)
          ? rawSpinSpeed.toDouble()
          : 1.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogoClipSettings &&
        other.durationSec == durationSec &&
        other.aspectId == aspectId &&
        other.revealStyleId == revealStyleId &&
        other.backdropId == backdropId &&
        other.backdropGlow == backdropGlow &&
        other.spinAfterReveal == spinAfterReveal &&
        other.spinSpeed == spinSpeed;
  }

  @override
  int get hashCode => Object.hash(
        durationSec,
        aspectId,
        revealStyleId,
        backdropId,
        backdropGlow,
        spinAfterReveal,
        spinSpeed,
      );

  @override
  String toString() {
    return 'LogoClipSettings('
        'durationSec: $durationSec, '
        'aspectId: $aspectId, '
        'revealStyleId: $revealStyleId, '
        'backdropId: $backdropId, '
        'backdropGlow: $backdropGlow, '
        'spinAfterReveal: $spinAfterReveal, '
        'spinSpeed: $spinSpeed)';
  }
}

/// Returns reveal progress in [0.0, 1.0] at [timeMs].
double logoClipRevealProgress(LogoClipSettings s, int timeMs) {
  if (s.revealStyleId == 'none') return 1.0;
  final int revealMs = s.revealDurationMs;
  if (revealMs <= 0) return 1.0;
  if (timeMs <= 0) return 0.0;
  if (timeMs >= revealMs) return 1.0;
  return timeMs / revealMs;
}

/// Returns post-reveal spin angle in radians at [timeMs].
double logoClipSpinAngle(LogoClipSettings s, int timeMs) {
  if (!s.spinAfterReveal) return 0.0;
  final int revealMs = s.revealDurationMs;
  if (timeMs <= revealMs) return 0.0;
  final int postRevealMs = timeMs - revealMs;
  final double periodMs = 12000.0 / s.spinSpeed;
  return (postRevealMs / periodMs) * (2.0 * math.pi);
}

/// Returns total frame count for [s] at [fps] (clamped to 1..60).
int logoClipFrameCount(LogoClipSettings s, int fps) {
  final int clampedFps = fps < 1 ? 1 : (fps > 60 ? 60 : fps);
  return s.durationSec * clampedFps;
}

/// Deterministic frame compositor for a Logo Clip.
class LogoClipPainter extends CustomPainter {
  const LogoClipPainter({
    required this.logoImage,
    required this.settings,
    required this.timeMs,
    required this.backdropPainter,
    required this.revealPainterFor,
  });

  final ui.Image logoImage;
  final LogoClipSettings settings;
  final int timeMs;
  final CustomPainter backdropPainter;
  final LogoClipRevealPainterBuilder revealPainterFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.save();
    backdropPainter.paint(canvas, size);
    canvas.restore();

    final double progress = logoClipRevealProgress(settings, timeMs);
    final double spinAngle = logoClipSpinAngle(settings, timeMs);
    final CustomPainter logoPainter =
        revealPainterFor(logoImage, progress, spinAngle);

    canvas.save();
    logoPainter.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoClipPainter oldDelegate) {
    return !identical(logoImage, oldDelegate.logoImage) ||
        settings != oldDelegate.settings ||
        timeMs != oldDelegate.timeMs ||
        !identical(backdropPainter, oldDelegate.backdropPainter) ||
        !identical(revealPainterFor, oldDelegate.revealPainterFor);
  }
}

/// Interactive preview and settings editor for a Logo Clip.
class LogoClipPreview extends StatefulWidget {
  const LogoClipPreview({
    super.key,
    required this.logoImage,
    required this.backdropPainterFor,
    required this.revealPainterFor,
    this.initialSettings = LogoClipSettings.defaults,
    this.onSettingsChanged,
  });

  final ui.Image logoImage;
  final LogoClipBackdropPainterBuilder backdropPainterFor;
  final LogoClipRevealPainterBuilder revealPainterFor;
  final LogoClipSettings initialSettings;
  final void Function(LogoClipSettings)? onSettingsChanged;

  @override
  State<LogoClipPreview> createState() => _LogoClipPreviewState();
}

class _LogoClipPreviewState extends State<LogoClipPreview>
    with SingleTickerProviderStateMixin {
  static const Color _kBackground = Color(0xFF050914);
  static const Color _kCardFill = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color _kCardBorder = Color.fromRGBO(255, 255, 255, 0.12);
  static const Color _kSliderAccent = Color(0xFF22D3EE);
  static const Color _kSliderInactive = Color.fromRGBO(255, 255, 255, 0.16);
  static const double _kCardRadius = 22.0;

  static const LinearGradient _kAccentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[
      Color(0xFF2E7CF6),
      Color(0xFF8B5CF6),
      Color(0xFF22D3EE),
    ],
  );

  static const List<_OptionItem<int>> _kDurationOptions = <_OptionItem<int>>[
    _OptionItem<int>(value: 3, label: '3s'),
    _OptionItem<int>(value: 5, label: '5s'),
    _OptionItem<int>(value: 8, label: '8s'),
  ];

  static const List<_OptionItem<String>> _kAspectOptions =
      <_OptionItem<String>>[
    _OptionItem<String>(value: 'wide', label: 'Wide'),
    _OptionItem<String>(value: 'square', label: 'Square'),
    _OptionItem<String>(value: 'portrait', label: 'Portrait'),
  ];

  static const List<_OptionItem<String>> _kRevealOptions =
      <_OptionItem<String>>[
    _OptionItem<String>(value: 'none', label: 'None'),
    _OptionItem<String>(value: 'fade_zoom', label: 'Fade Zoom'),
    _OptionItem<String>(value: 'slide_wipe', label: 'Slide Wipe'),
    _OptionItem<String>(value: 'shine_sweep', label: 'Shine Sweep'),
    _OptionItem<String>(value: 'bounce_in', label: 'Bounce In'),
    _OptionItem<String>(value: 'spin_reveal', label: 'Spin Reveal'),
    _OptionItem<String>(value: 'rise_glow', label: 'Rise Glow'),
  ];

  static const List<_OptionItem<String>> _kBackdropOptions =
      <_OptionItem<String>>[
    _OptionItem<String>(value: 'midnight_studio', label: 'Midnight Studio'),
    _OptionItem<String>(value: 'royal_stage', label: 'Royal Stage'),
    _OptionItem<String>(value: 'neon_grid', label: 'Neon Grid'),
    _OptionItem<String>(value: 'soft_spotlight', label: 'Soft Spotlight'),
    _OptionItem<String>(value: 'deep_ocean', label: 'Deep Ocean'),
    _OptionItem<String>(value: 'plain_dark', label: 'Plain Dark'),
  ];

  late LogoClipSettings _settings;
  late AnimationController _controller;
  late CustomPainter _backdropPainter;

  int get _durationMs => _settings.durationSec * 1000;

  int get _currentTimeMs {
    final int total = _durationMs;
    if (total <= 0) return 0;
    return (_controller.value * total).round().clamp(0, total);
  }

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _backdropPainter = widget.backdropPainterFor(
      _settings.backdropId,
      _settings.backdropGlow,
    );
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant LogoClipPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.backdropPainterFor, oldWidget.backdropPainterFor)) {
      _backdropPainter = widget.backdropPainterFor(
        _settings.backdropId,
        _settings.backdropGlow,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateSettings(
    LogoClipSettings next, {
    bool restartReveal = false,
  }) {
    if (next == _settings) return;

    final bool durationChanged = next.durationSec != _settings.durationSec;
    final bool backdropChanged = next.backdropId != _settings.backdropId ||
        next.backdropGlow != _settings.backdropGlow;
    final bool wasPlaying = _controller.isAnimating;
    final int previousTimeMs = _currentTimeMs;

    if (backdropChanged) {
      _backdropPainter = widget.backdropPainterFor(
        next.backdropId,
        next.backdropGlow,
      );
    }

    if (durationChanged) {
      final int nextDurationMs = next.durationSec * 1000;
      // Preserve the time PROPORTION across the duration change (being at
      // 50% of the old clip keeps you at 50% of the new one), not the
      // absolute millisecond position.
      final double previousFraction = _durationMs > 0
          ? (previousTimeMs / _durationMs).clamp(0.0, 1.0)
          : 0.0;
      _controller.duration = Duration(milliseconds: nextDurationMs);
      if (restartReveal || previousFraction >= 1.0) {
        _controller.value = 0.0;
      } else {
        _controller.value = previousFraction;
      }
      if (wasPlaying) {
        _controller.repeat();
      }
    } else if (restartReveal) {
      _controller.value = 0.0;
      if (wasPlaying) {
        _controller.repeat();
      }
    }

    setState(() {
      _settings = next;
    });
    widget.onSettingsChanged?.call(next);
  }

  void _togglePlayPause() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      if (_controller.value >= 1.0) {
        _controller.value = 0.0;
      }
      _controller.repeat();
    }
    setState(() {});
  }

  void _handleScrub(double timeMs) {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    final int total = _durationMs;
    _controller.value =
        total > 0 ? (timeMs / total).clamp(0.0, 1.0) : 0.0;
    setState(() {});
  }

  String _formatSeconds(int ms) {
    return '${(ms / 1000.0).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final double previewHeight = MediaQuery.sizeOf(context).height * 0.46;
    final Size outputSize = _settings.outputSize;
    final double aspectRatio = outputSize.width / outputSize.height;

    return Material(
      color: _kBackground,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                height: previewHeight,
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    color: _kCardFill,
                    borderRadius: BorderRadius.circular(_kCardRadius),
                    border: Border.all(color: _kCardBorder),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kCardRadius - 8),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: aspectRatio,
                          child: ClipRect(
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _controller,
                                builder: (BuildContext context, Widget? child) {
                                  return CustomPaint(
                                    size: Size.infinite,
                                    painter: LogoClipPainter(
                                      logoImage: widget.logoImage,
                                      settings: _settings,
                                      timeMs: _currentTimeMs,
                                      backdropPainter: _backdropPainter,
                                      revealPainterFor: widget.revealPainterFor,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildPlaybackCard(),
                    const SizedBox(height: 12),
                    _buildChipSection<int>(
                      title: 'Duration',
                      options: _kDurationOptions,
                      selectedValue: _settings.durationSec,
                      onSelected: (int sec) =>
                          _updateSettings(_settings.copyWith(durationSec: sec)),
                    ),
                    const SizedBox(height: 12),
                    _buildChipSection<String>(
                      title: 'Aspect',
                      options: _kAspectOptions,
                      selectedValue: _settings.aspectId,
                      onSelected: (String id) =>
                          _updateSettings(_settings.copyWith(aspectId: id)),
                    ),
                    const SizedBox(height: 12),
                    _buildChipSection<String>(
                      title: 'Reveal',
                      options: _kRevealOptions,
                      selectedValue: _settings.revealStyleId,
                      onSelected: (String id) => _updateSettings(
                        _settings.copyWith(revealStyleId: id),
                        restartReveal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildBackdropCard(),
                    const SizedBox(height: 12),
                    _buildSpinCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackCard() {
    final bool isPlaying = _controller.isAnimating;
    final int totalMs = _durationMs;

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildPlayPauseButton(isPlaying: isPlaying),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, Widget? child) {
                    final int currentMs = _currentTimeMs;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              _formatSeconds(currentMs),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _formatSeconds(totalMs),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: _sliderTheme(context),
                          child: Slider(
                            min: 0.0,
                            max: totalMs.toDouble(),
                            value: currentMs.toDouble().clamp(
                                  0.0,
                                  totalMs.toDouble(),
                                ),
                            onChanged: _handleScrub,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton({required bool isPlaying}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _togglePlayPause,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _kAccentGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                isPlaying ? 'Pause' : 'Play',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipSection<T>({
    required String title,
    required List<_OptionItem<T>> options,
    required T selectedValue,
    required ValueChanged<T> onSelected,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < options.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  _buildChip(
                    label: options[i].label,
                    selected: options[i].value == selectedValue,
                    onTap: () => onSelected(options[i].value),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Backdrop',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _kBackdropOptions.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  _buildChip(
                    label: _kBackdropOptions[i].label,
                    selected: _kBackdropOptions[i].value ==
                        _settings.backdropId,
                    onTap: () => _updateSettings(
                      _settings.copyWith(
                        backdropId: _kBackdropOptions[i].value,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Backdrop glow',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              Text(
                '${(_settings.backdropGlow * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              min: 0.0,
              max: 1.0,
              value: _settings.backdropGlow,
              onChanged: (double value) => _updateSettings(
                _settings.copyWith(backdropGlow: value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Spin after reveal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Switch(
                value: _settings.spinAfterReveal,
                activeTrackColor: _kSliderAccent,
                inactiveTrackColor: _kCardBorder,
                inactiveThumbColor: Colors.white70,
                onChanged: (bool value) => _updateSettings(
                  _settings.copyWith(spinAfterReveal: value),
                ),
              ),
            ],
          ),
          if (_settings.spinAfterReveal) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Spin speed',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${_settings.spinSpeed.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: _sliderTheme(context),
              child: Slider(
                min: 0.5,
                max: 3.0,
                value: _settings.spinSpeed,
                onChanged: (double value) => _updateSettings(
                  _settings.copyWith(spinSpeed: value),
                ),
              ),
            ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? _kAccentGradient : null,
            color: selected ? null : _kCardFill,
            borderRadius: BorderRadius.circular(14),
            border: selected ? null : Border.all(color: _kCardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardFill,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: _kCardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderTheme.of(context).copyWith(
      activeTrackColor: _kSliderAccent,
      inactiveTrackColor: _kSliderInactive,
      thumbColor: _kSliderAccent,
      overlayColor: const Color.fromRGBO(34, 211, 238, 0.20),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    );
  }
}

class _OptionItem<T> {
  const _OptionItem({required this.value, required this.label});

  final T value;
  final String label;
}
