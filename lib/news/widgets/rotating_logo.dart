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
import '../../services/logo_parts_service.dart';
import '../logo_parts.dart';
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
    this.facePaths = const {},
    this.tiltX = kLogoCubeTiltX,
    this.speedSec = 6,
    this.clockwise = true,
    this.pedestal = false,
  });

  final String? logoPath;
  final String initial;
  final double size;

  /// False = hold a still 3/4 cube view (the rotate switch is
  /// off). The cube form stays — only the motion stops.
  final bool animate;

  /// Build 13 (point #19): per-face images (logo_cube face
  /// keys -> file paths); a face without an entry keeps the
  /// main logo texture.
  final Map<String, String> facePaths;

  /// Build 13 (point #19): the cube VIEW tilt — the default
  /// here is the historic fixed tilt so non-News-Studio callers
  /// render exactly as before; the News Studio passes the
  /// preset's user control (default 0 = 'Samne').
  final double tiltX;

  /// Build 13 (point #19): seconds per full revolution.
  final double speedSec;

  /// Build 13 (point #19): spin direction.
  final bool clockwise;

  /// Build 13 (point #19): draw the base plate under the cube.
  final bool pedestal;

  @override
  State<LogoCubeView> createState() => _LogoCubeViewState();
}

class _LogoCubeViewState extends State<LogoCubeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.speedSec),
  );

  static Duration _durationFor(double speedSec) => Duration(
        milliseconds: (speedSec.clamp(1, 20) * 1000).round(),
      );

  ui.Image? _texture;
  String? _textureKey;

  /// Build 13: decoded per-face textures (face index -> image).
  Map<int, ui.Image> _faceTextures = {};

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
    if (widget.speedSec != oldWidget.speedSec) {
      _controller.duration = _durationFor(widget.speedSec);
      if (widget.animate) _controller.repeat();
    }
    if (widget.logoPath != oldWidget.logoPath ||
        widget.initial != oldWidget.initial ||
        !_sameFaces(widget.facePaths, oldWidget.facePaths)) {
      unawaited(_loadTexture());
    }
  }

  static bool _sameFaces(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    _texture?.dispose();
    for (final img in _faceTextures.values) {
      img.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTexture() async {
    final faceKey = (widget.facePaths.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value}')
        .join(';');
    final key = '${widget.logoPath}|${widget.initial}|$faceKey';
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
      // Build 13: per-face textures, decoded the same fail-soft
      // way — an undecodable face file just leaves that face on
      // the main texture.
      final faces = <int, ui.Image>{};
      for (final entry in widget.facePaths.entries) {
        final idx = logoCubeFaceIndex(entry.key);
        if (idx < 0) continue;
        try {
          final bytes = await File(entry.value).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          faces[idx] = frame.image;
        } catch (_) {}
      }
      if (!mounted) {
        image.dispose();
        for (final img in faces.values) {
          img.dispose();
        }
        return;
      }
      final old = _texture;
      final oldFaces = _faceTextures;
      setState(() {
        _texture = image;
        _faceTextures = faces;
      });
      old?.dispose();
      for (final img in oldFaces.values) {
        img.dispose();
      }
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
        tiltX: widget.tiltX,
        clockwise: widget.clockwise,
        pedestal: widget.pedestal,
        faceTextures: _faceTextures.isEmpty ? null : _faceTextures,
      ),
    );
  }
}

class _LogoCubePainter extends CustomPainter {
  _LogoCubePainter({
    required this.texture,
    required this.animation,
    required this.tiltX,
    required this.clockwise,
    required this.pedestal,
    required this.faceTextures,
  }) : super(repaint: animation);

  final ui.Image texture;
  final Animation<double> animation;
  final double tiltX;
  final bool clockwise;
  final bool pedestal;
  final Map<int, ui.Image>? faceTextures;

  @override
  void paint(Canvas canvas, Size size) {
    paintLogoCube(
      canvas,
      center: Offset(size.width / 2, size.height / 2),
      size: size.width * 0.92,
      angleY: logoCubeAngleFor(animation.value, clockwise: clockwise),
      texture: texture,
      tiltX: tiltX,
      faceTextures: faceTextures,
      pedestal: pedestal,
    );
  }

  @override
  bool shouldRepaint(_LogoCubePainter oldDelegate) =>
      oldDelegate.texture != texture ||
      oldDelegate.tiltX != tiltX ||
      oldDelegate.clockwise != clockwise ||
      oldDelegate.pedestal != pedestal ||
      oldDelegate.faceTextures != faceTextures;
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
    this.facePaths = const {},
    this.tiltX = kLogoCubeTiltX,
    this.speedSec = 6,
    this.clockwise = true,
    this.pedestal = false,
    this.parts = const [],
  });

  final String? logoPath;
  final String initial;
  final double size;
  final bool animate;

  /// Build 13 (point #19): the cube settings (see LogoCubeView).
  final Map<String, String> facePaths;
  final double tiltX;
  final double speedSec;
  final bool clockwise;
  final bool pedestal;

  /// Build 13 (point 6 — Logo Parts Engine): when the preset
  /// has working parts, they replace the cube/still — each part
  /// animating on its own settings, through the same painter
  /// the export frames use.
  final List<LogoPart> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isNotEmpty) {
      return LogoPartsView(parts: parts, size: size, animate: animate);
    }
    return LogoCubeView(
      logoPath: logoPath,
      initial: initial,
      size: size,
      animate: animate,
      facePaths: facePaths,
      tiltX: tiltX,
      speedSec: speedSec,
      clockwise: clockwise,
      pedestal: pedestal,
    );
  }
}

/// Build 13 (point 6): the parts animation — every part drawn
/// full-frame, rotating parts turning around their own
/// centroid, all through [LogoPartsService.paintParts] (the
/// exact painter the export frames use).
class LogoPartsView extends StatefulWidget {
  const LogoPartsView({
    super.key,
    required this.parts,
    required this.size,
    this.animate = true,
  });

  final List<LogoPart> parts;
  final double size;
  final bool animate;

  @override
  State<LogoPartsView> createState() => _LogoPartsViewState();
}

class _LogoPartsViewState extends State<LogoPartsView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Map<String, ui.Image> _textures = const {};
  String _textureKey = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _controller.repeat();
    unawaited(_loadTextures());
  }

  @override
  void didUpdateWidget(LogoPartsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
    if (_keyOf(widget.parts) != _textureKey) {
      unawaited(_loadTextures());
    }
  }

  String _keyOf(List<LogoPart> parts) =>
      parts.map((e) => '${e.id}:${e.imagePath}').join('|');

  Future<void> _loadTextures() async {
    final key = _keyOf(widget.parts);
    final textures = await LogoPartsService.loadPartTextures(widget.parts);
    if (!mounted) {
      for (final img in textures.values) {
        img.dispose();
      }
      return;
    }
    final old = _textures;
    setState(() {
      _textures = textures;
      _textureKey = key;
    });
    for (final img in old.values) {
      img.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final img in _textures.values) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _LogoPartsPainter(
            parts: widget.parts,
            textures: _textures,
            tSec: _controller.value * kLogoPartsLoopSec,
          ),
        ),
      ),
    );
  }
}

class _LogoPartsPainter extends CustomPainter {
  _LogoPartsPainter({
    required this.parts,
    required this.textures,
    required this.tSec,
  });

  final List<LogoPart> parts;
  final Map<String, ui.Image> textures;
  final double tSec;

  @override
  void paint(Canvas canvas, Size size) {
    LogoPartsService.paintParts(canvas, size, parts, textures, tSec);
  }

  @override
  bool shouldRepaint(_LogoPartsPainter old) =>
      old.tSec != tSec || old.textures != textures || old.parts != parts;
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
    this.cubeFacePaths = const {},
    this.cubeTiltX = kLogoCubeTiltX,
    this.cubeSpeedSec = 6,
    this.cubeClockwise = true,
    this.cubePedestal = false,
    this.parts = const [],
  });

  final String? logoPath;
  final String initial;
  final double size;

  /// Build 13 (point #19): the cube settings for the image
  /// (cube) source; the video source ignores them.
  final Map<String, String> cubeFacePaths;
  final double cubeTiltX;
  final double cubeSpeedSec;
  final bool cubeClockwise;
  final bool cubePedestal;

  /// Build 13 (point 6): the Logo Parts working list for the
  /// image source (see RotatingLogo.parts).
  final List<LogoPart> parts;

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
      facePaths: widget.cubeFacePaths,
      tiltX: widget.cubeTiltX,
      speedSec: widget.cubeSpeedSec,
      clockwise: widget.cubeClockwise,
      pedestal: widget.cubePedestal,
      parts: widget.parts,
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
