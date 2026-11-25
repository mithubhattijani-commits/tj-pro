/// 3D rotating logo bug for the News Studio template.
///
/// Build 12 (v1.9.0, fix-list point #12) — SUPERSEDES the
/// 20 Nov 2026 swing decision (`rotation-decision.md`). That
/// decision oscillated the logo ±0.7 rad because a FLAT logo's
/// text reads backwards for half of a full spin. The user's
/// direct order of 2026-11-25 demands continuous full 360°
/// rotation, with the CUBE as the chosen form: the image is
/// textured onto a real 3D cube's faces (broadcast cube
/// logos), so every face reads upright on its own pass.
///
/// Preview mechanism (this file): [LogoCubeView] paints the
/// shared cube engine (`lib/services/logo_cube.dart`) with an
/// [AnimationController] sweeping 0 → 2π over 6 s, repeating
/// (never reversing). The export renders the SAME geometry
/// into PNG frames (`LogoLoopService`) — preview and export
/// cannot drift. Rotation is ON by default; the preset's
/// rotate switch (Logo tool) can hold the cube at a still 3/4
/// angle instead.
///
/// A logo VIDEO (point #13) is a different source: when the
/// preset carries keyed frames for it, [LogoBug] and the Final
/// preview show [KeyedLogoFlipbook] — the honestly keyed
/// frames — instead of the cube.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/logo_cube.dart';
import '../../services/logo_loop_service.dart';
import 'keyed_logo_flipbook.dart';

/// One full revolution of the preview cube.
const Duration kLogoRotationDuration = Duration(seconds: 6);

/// Pure helper (unit-testable): the continuous rotation angle
/// at [progress] (0..1 of one revolution) — a linear sweep
/// 0 → 2π. Progress 0 and 1 are the same angle (seamless).
double logoRotationAngle(double progress) => logoCubeAngle(progress);

/// The rotating CUBE logo: [logoPath]'s image textured onto a
/// 3D cube (null = the channel's initial-letter tile, textured
/// the same way — §14 rule 7: each channel shows ITS OWN
/// initial, never a copied logo).
class LogoCubeView extends StatefulWidget {
  const LogoCubeView({
    super.key,
    this.logoPath,
    this.initial = 'N',
    this.size = 64,
    this.animate = true,
  });

  final String? logoPath;
  final String initial;
  final double size;

  /// False = hold a still 3/4 cube view (the rotate switch is
  /// off). The cube form stays — only the motion stops.
  final bool animate;

  @override
  State<LogoCubeView> createState() => _LogoCubeViewState();
}

class _LogoCubeViewState extends State<LogoCubeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kLogoRotationDuration,
  );

  ui.Image? _texture;
  String? _textureKey;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.value = 0.1;
    }
    unawaited(_loadTexture());
  }

  @override
  void didUpdateWidget(LogoCubeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0.1;
      }
    }
    if (widget.logoPath != oldWidget.logoPath ||
        widget.initial != oldWidget.initial) {
      unawaited(_loadTexture());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _texture?.dispose();
    super.dispose();
  }

  Future<void> _loadTexture() async {
    final key = '${widget.logoPath}|${widget.initial}';
    if (_textureKey == key) return;
    _textureKey = key;
    try {
      ui.Image? image;
      final path = widget.logoPath;
      if (path != null && File(path).existsSync()) {
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        image = frame.image;
      } else {
        image = await LogoLoopService.renderLogoTileTexture(
          initial: widget.initial,
          size: 256,
        );
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _texture;
      setState(() => _texture = image);
      old?.dispose();
    } catch (_) {
      // Texture failed — the flat fallback in build() shows the
      // image / tile directly; the logo never disappears.
    }
  }

  @override
  Widget build(BuildContext context) {
    final texture = _texture;
    if (texture == null) {
      return _LogoImage(
        logoPath: widget.logoPath,
        initial: widget.initial,
        size: widget.size,
      );
    }
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _LogoCubePainter(
        texture: texture,
        animation: _controller,
      ),
    );
  }
}

class _LogoCubePainter extends CustomPainter {
  _LogoCubePainter({required this.texture, required this.animation})
      : super(repaint: animation);

  final ui.Image texture;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    paintLogoCube(
      canvas,
      center: Offset(size.width / 2, size.height / 2),
      size: size.width * 0.92,
      angleY: logoCubeAngle(animation.value),
      texture: texture,
    );
  }

  @override
  bool shouldRepaint(_LogoCubePainter oldDelegate) =>
      oldDelegate.texture != texture;
}

/// The rotating channel logo (kept name — every template
/// preview mounts this). Build 12: renders the 3D cube.
class RotatingLogo extends StatelessWidget {
  const RotatingLogo({
    super.key,
    this.logoPath,
    this.initial = 'N',
    this.size = 64,
    this.animate = true,
  });

  final String? logoPath;
  final String initial;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return LogoCubeView(
      logoPath: logoPath,
      initial: initial,
      size: size,
      animate: animate,
    );
  }
}

/// The logo image itself (no animation): a picked file, or the
/// initial-letter tile when there is none (or the file is
/// unreadable). Used as the cube's loading/failure fallback.
class _LogoImage extends StatelessWidget {
  const _LogoImage({
    required this.logoPath,
    required this.initial,
    required this.size,
  });

  final String? logoPath;
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = logoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _InitialTile(initial: initial, size: size),
        ),
      );
    }
    return _InitialTile(initial: initial, size: size);
  }
}

class _InitialTile extends StatelessWidget {
  const _InitialTile({required this.initial, required this.size});
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Logo bug + time/date capsule, as it sits in the final template:
/// the rotating logo top-right with the capsule directly under it,
/// the SAME width as the logo, flipping time/date (per the Nigraan
/// house style — capsule shows the time, then the date, alternating
/// every few seconds).
class LogoBug extends StatefulWidget {
  const LogoBug({
    super.key,
    this.logoPath,
    this.initial = 'N',
    this.size = 64,
    this.logoMediaKind = 'image',
    this.keyedFramesDir,
    this.videoStillPath,
  });

  final String? logoPath;
  final String initial;
  final double size;

  /// Build 12 (point #13): 'video' when the preset's logo
  /// source is a logo VIDEO — the bug then plays the keyed
  /// frames ([keyedFramesDir]) instead of the cube.
  final String logoMediaKind;
  final String? keyedFramesDir;
  final String? videoStillPath;

  @override
  State<LogoBug> createState() => _LogoBugState();
}

class _LogoBugState extends State<LogoBug> {
  late DateTime _now = DateTime.now();
  bool _showTime = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh the clock every second; flip time/date every 3 s.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_now.second % 3 == 0) _showTime = !_showTime;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _logo() {
    if (widget.logoMediaKind == 'video') {
      final still = widget.videoStillPath;
      return KeyedLogoFlipbook(
        framesDir: widget.keyedFramesDir,
        width: widget.size,
        height: widget.size,
        fallback: still != null && File(still).existsSync()
            ? Image.file(
                File(still),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _InitialTile(
                  initial: widget.initial,
                  size: widget.size,
                ),
              )
            : _InitialTile(initial: widget.initial, size: widget.size),
      );
    }
    return RotatingLogo(
      logoPath: widget.logoPath,
      initial: widget.initial,
      size: widget.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final ampm = _now.hour < 12 ? 'AM' : 'PM';
    final time =
        '${hour12.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')} $ampm';
    final date =
        '${_now.day.toString().padLeft(2, '0')}-${_now.month.toString().padLeft(2, '0')}-${_now.year}';
    return SizedBox(
      width: widget.size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logo(),
          const SizedBox(height: 4),
          Container(
            width: widget.size,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              _showTime ? time : date,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
