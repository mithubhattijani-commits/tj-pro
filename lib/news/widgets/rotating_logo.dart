/// 3D rotating logo bug for the News Studio template (Phase 3).
///
/// LOGO 3D ROTATION (user order 20 Nov 2026, see
/// ~/workspace/tj-pro-news-maker/rotation-decision.md): the logo
/// 3D-rotates in the template — preview AND export — and a user-replaced
/// logo rotates the same way. A static circular image is NEVER shown.
///
/// Preview mechanism (this file): a Flutter [Transform] with
/// [Matrix4.rotationY], driven by an [AnimationController] that
/// oscillates (yoyo) rotationY between about -0.7 and +0.7 rad over
/// ~6 s. This mirrors the original asset's swing (turn toward the
/// camera and back), the logo text never mirrors, and the loop is
/// seamless by construction. A full 0→2π spin was rejected: the text
/// reads backwards for half the turn. Rotation is ALWAYS ON — there is
/// no toggle and no static path.
///
/// Export mechanism (Phase 7): the pre-rendered rotating loop
/// (`logo-rotating-alpha.mov`, ping-ponged) for the default logo, or a
/// generated rotating loop for a user-replaced logo — see
/// rotation-decision.md. The PNG template renderer
/// ([renderLiveTemplateImage] with `includeLogo: false`) leaves the
/// logo out for exactly that overlay pass.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The 3D swing: ±0.7 rad over ~6 s (one way), yoyo.
const double kLogoSwingRadians = 0.7;
const Duration kLogoSwingDuration = Duration(seconds: 6);

/// Rotating channel logo.
///
/// [logoPath] is the gallery-picked logo file (null = the channel's
/// initial-letter tile — §14 rule 7: each channel shows ITS OWN initial,
/// never a copied logo). [initial] is that letter (defaults to 'N').
/// The tile rotates exactly like a picked logo: rotation is always on.
class RotatingLogo extends StatefulWidget {
  const RotatingLogo({
    super.key,
    this.logoPath,
    this.initial = 'N',
    this.size = 64,
  });

  final String? logoPath;
  final String initial;
  final double size;

  @override
  State<RotatingLogo> createState() => _RotatingLogoState();
}

class _RotatingLogoState extends State<RotatingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kLogoSwingDuration,
  )..repeat(reverse: true);

  late final Animation<double> _angle = Tween<double>(
    begin: -kLogoSwingRadians,
    end: kLogoSwingRadians,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(_angle.value),
          child: child,
        );
      },
      child: _LogoImage(
        logoPath: widget.logoPath,
        initial: widget.initial,
        size: widget.size,
      ),
    );
  }
}

/// The logo image itself (no animation): a picked file, or the
/// initial-letter tile when there is none (or the file is unreadable).
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
  });

  final String? logoPath;
  final String initial;
  final double size;

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
          RotatingLogo(
            logoPath: widget.logoPath,
            initial: widget.initial,
            size: widget.size,
          ),
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

/// Pure helper (unit-testable): the rotationY angle at a 0..1 yoyo
/// progress — -0.7 rad at the start, +0.7 at the turn, back again.
/// Text never mirrors because the swing never passes ±π/2.
double logoSwingAngle(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return -kLogoSwingRadians + 2 * kLogoSwingRadians * p;
}

/// Max absolute rotation used by the swing (kept < π/2 so the logo
/// text never reads backwards).
double get logoSwingMaxRadians => kLogoSwingRadians;

/// Sanity: the swing angle never reaches the mirror point.
bool get logoSwingNeverMirrors =>
    kLogoSwingRadians < math.pi / 2;
