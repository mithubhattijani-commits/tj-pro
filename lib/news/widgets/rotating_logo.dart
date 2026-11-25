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
    this.partsScene,
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

  /// Redesign Build 2: the parts SCENE (glow + base) that
  /// rides with [parts]; null = the Build 1 defaults
  /// (glow off, cut base).
  final LogoPartsScene? partsScene;

  @override
  Widget build(BuildContext context) {
    if (parts.isNotEmpty) {
      return LogoPartsView(
        parts: parts,
        size: size,
        animate: animate,
        scene: partsScene,
      );
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

/// Logo Parts (element model): the parts animation — the
/// cut base plus every part's box region of the master,
/// rotating parts turning around their own box centre, all
/// through [LogoPartsService.paintParts] (the exact painter
/// the export frames use).
class LogoPartsView extends StatefulWidget {
  const LogoPartsView({
    super.key,
    required this.parts,
    required this.size,
    this.animate = true,
    this.scene,
  });

  final List<LogoPart> parts;
  final double size;
  final bool animate;

  /// Redesign Build 2: the parts SCENE (glow + base);
  /// null = defaults (glow off, cut base).
  final LogoPartsScene? scene;

  @override
  State<LogoPartsView> createState() => _LogoPartsViewState();
}

class _LogoPartsViewState extends State<LogoPartsView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.Image? _master;
  String _masterKey = '';

  /// The AUTO glow colour, resolved from the master when it
  /// loads (the scene's own colour, when set, wins in the
  /// painter — this is only the fallback).
  int? _autoGlowArgb;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _controller.repeat();
    unawaited(_loadMaster());
  }

  @override
  void didUpdateWidget(LogoPartsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
    if (_keyOf(widget.parts) != _masterKey) {
      unawaited(_loadMaster());
    }
  }

  /// The master texture depends only on the parts' shared
  /// source — box/setting changes repaint, never reload.
  String _keyOf(List<LogoPart> parts) =>
      parts.isEmpty ? '' : parts.first.sourcePath;

  Future<void> _loadMaster() async {
    final key = _keyOf(widget.parts);
    final master = await LogoPartsService.loadMasterTexture(
      key.isEmpty ? null : key,
    );
    final autoGlow =
        master == null ? null : await LogoPartsService.dominantColorOfImage(
            master,
          );
    if (!mounted) {
      master?.dispose();
      return;
    }
    final old = _master;
    setState(() {
      _master = master;
      _masterKey = key;
      _autoGlowArgb = autoGlow;
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    _master?.dispose();
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
            master: _master,
            tSec: _controller.value * kLogoPartsLoopSec,
            scene: widget.scene,
            autoGlowArgb: _autoGlowArgb,
          ),
        ),
      ),
    );
  }
}

class _LogoPartsPainter extends CustomPainter {
  _LogoPartsPainter({
    required this.parts,
    required this.master,
    required this.tSec,
    required this.scene,
    required this.autoGlowArgb,
  });

  final List<LogoPart> parts;
  final ui.Image? master;
  final double tSec;
  final LogoPartsScene? scene;
  final int? autoGlowArgb;

  @override
  void paint(Canvas canvas, Size size) {
    LogoPartsService.paintParts(
      canvas,
      size,
      parts,
      master,
      tSec,
      scene: scene,
      autoGlowColorArgb: autoGlowArgb,
    );
  }

  @override
  bool shouldRepaint(_LogoPartsPainter old) =>
      old.tSec != tSec ||
      old.master != master ||
      old.parts != parts ||
      old.scene != scene ||
      old.autoGlowArgb != autoGlowArgb;
}

/// Point #22 (element model): ONE part's own live preview —
/// the widget the Logo Parts section puts in each part's row.
/// It shows the part's own box region of the master, turning
/// (or staying still) by its OWN settings — rotate switch,
/// direction, speed and style — through the same shared
/// painter ([LogoPartsService.paintPart]) the combined
/// preview and the export frames use. Changing a control
/// rebuilds the row with the new part and the motion changes
/// immediately.
class LogoPartPreview extends StatefulWidget {
  const LogoPartPreview({
    super.key,
    required this.part,
    required this.size,
  });

  final LogoPart part;
  final double size;

  @override
  State<LogoPartPreview> createState() => _LogoPartPreviewState();
}

class _LogoPartPreviewState extends State<LogoPartPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.Image? _master;
  String _masterPath = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    // Build 2: Pulse breathes even when the rotate switch is
    // off — the row preview animates for either motion.
    if (widget.part.rotate || widget.part.pulseOn) _controller.repeat();
    unawaited(_loadMaster());
  }

  @override
  void didUpdateWidget(LogoPartPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wantsMotion = widget.part.rotate || widget.part.pulseOn;
    if (wantsMotion && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!wantsMotion && _controller.isAnimating) {
      _controller.stop();
    }
    if (widget.part.sourcePath != _masterPath) {
      unawaited(_loadMaster());
    }
  }

  Future<void> _loadMaster() async {
    final path = widget.part.sourcePath;
    final master = await LogoPartsService.loadMasterTexture(path);
    if (!mounted) {
      master?.dispose();
      return;
    }
    final old = _master;
    setState(() {
      _master = master;
      _masterPath = path;
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    _master?.dispose();
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
          painter: LogoPartPreviewPainter(
            part: widget.part,
            texture: _master,
            tSec: _controller.value * kLogoPartsLoopSec,
          ),
        ),
      ),
    );
  }
}

/// The painter behind [LogoPartPreview] — public so the
/// row-preview behaviour is directly testable (its [angle] is
/// the part's live angle at the painter's loop time).
/// [texture] is the MASTER logo image; the painter draws the
/// part's box region of it.
class LogoPartPreviewPainter extends CustomPainter {
  LogoPartPreviewPainter({
    required this.part,
    required this.texture,
    required this.tSec,
  });

  final LogoPart part;
  final ui.Image? texture;
  final double tSec;

  /// The part's rotation angle right now (0 when its rotate
  /// switch is off — [LogoPartsService.partAngleAt] owns that
  /// rule, shared with the combined preview and export).
  double get angle => LogoPartsService.partAngleAt(part, tSec);

  @override
  void paint(Canvas canvas, Size size) {
    final tex = texture;
    if (tex == null) return;
    LogoPartsService.paintPart(canvas, size, part, tex, tSec);
  }

  @override
  bool shouldRepaint(LogoPartPreviewPainter old) =>
      old.tSec != tSec ||
      old.texture != texture ||
      old.part.rotate != part.rotate ||
      old.part.direction != part.direction ||
      old.part.speedSec != part.speedSec ||
      old.part.rotationStyle != part.rotationStyle ||
      old.part.motionMode != part.motionMode ||
      old.part.swingDeg != part.swingDeg ||
      old.part.pulseOn != part.pulseOn ||
      old.part.pulseStrength != part.pulseStrength ||
      old.part.delaySec != part.delaySec ||
      old.part.pivotDx != part.pivotDx ||
      old.part.pivotDy != part.pivotDy ||
      old.part.box != part.box ||
      old.part.sourcePath != part.sourcePath;
}

/// The interactive BIG preview of the Logo Parts tool
/// (redesign Build 1): the combined live animation with every
/// part's box outlined on top — the selected part in gold
/// with a resize handle at its bottom-right corner.
///
/// Gestures (fractions of the square canvas):
/// - tap → [onSelect] with the topmost hit part's id (or
///   null when the tap lands outside every box);
/// - drag inside the selected box → move it ([onBoxChanged]
///   fires live, so the effect is seen while dragging);
/// - drag the selected box's corner handle → resize it;
/// - with [drawMode] on, a drag rubber-bands a NEW box and
///   [onBoxDrawn] fires when the finger lifts.
class LogoPartsEditorPreview extends StatefulWidget {
  const LogoPartsEditorPreview({
    super.key,
    required this.parts,
    required this.size,
    required this.selectedId,
    required this.editable,
    required this.drawMode,
    required this.onSelect,
    required this.onBoxChanged,
    required this.onBoxDrawn,
    this.animate = true,
    this.scene,
  });

  final List<LogoPart> parts;
  final double size;
  final String? selectedId;

  /// Box gestures (move/resize/draw) — on in the Hisay tab.
  final bool editable;
  final bool drawMode;
  final bool animate;

  /// Redesign Build 2: the parts SCENE (glow + base);
  /// null = defaults (glow off, cut base).
  final LogoPartsScene? scene;
  final ValueChanged<String?> onSelect;
  final void Function(String id, LogoBox box) onBoxChanged;
  final ValueChanged<LogoBox> onBoxDrawn;

  @override
  State<LogoPartsEditorPreview> createState() =>
      _LogoPartsEditorPreviewState();
}

class _LogoPartsEditorPreviewState extends State<LogoPartsEditorPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.Image? _master;
  String _masterKey = '';

  /// The AUTO glow colour, resolved from the master when it
  /// loads (see LogoPartsView).
  int? _autoGlowArgb;

  // Drag state (fractions).
  Offset? _dragStart;
  LogoBox? _dragOrigBox;
  LogoBox? _rubberBand;
  int _dragKind = 0; // 0 none, 1 move, 2 resize, 3 draw

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _controller.repeat();
    unawaited(_loadMaster());
  }

  @override
  void didUpdateWidget(LogoPartsEditorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
    final key = widget.parts.isEmpty ? '' : widget.parts.first.sourcePath;
    if (key != _masterKey) unawaited(_loadMaster());
  }

  Future<void> _loadMaster() async {
    final key = widget.parts.isEmpty ? '' : widget.parts.first.sourcePath;
    final master = await LogoPartsService.loadMasterTexture(
      key.isEmpty ? null : key,
    );
    final autoGlow =
        master == null ? null : await LogoPartsService.dominantColorOfImage(
            master,
          );
    if (!mounted) {
      master?.dispose();
      return;
    }
    final old = _master;
    setState(() {
      _master = master;
      _masterKey = key;
      _autoGlowArgb = autoGlow;
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    _master?.dispose();
    super.dispose();
  }

  LogoPart? get _selected {
    for (final part in widget.parts) {
      if (part.id == widget.selectedId) return part;
    }
    return null;
  }

  Offset _frac(Offset local) =>
      Offset(local.dx / widget.size, local.dy / widget.size);

  void _tapUp(TapUpDetails d) {
    if (widget.drawMode) return;
    final f = _frac(d.localPosition);
    final idx = logoPartIndexAtPoint(widget.parts, f.dx, f.dy);
    widget.onSelect(idx < 0 ? null : widget.parts[idx].id);
  }

  void _panStart(DragStartDetails d) {
    if (!widget.editable) return;
    final f = _frac(d.localPosition);
    _dragStart = f;
    if (widget.drawMode) {
      _dragKind = 3;
      _rubberBand = LogoBox(x: f.dx, y: f.dy, w: 0, h: 0);
      return;
    }
    final sel = _selected;
    if (sel == null) return;
    final box = sel.box;
    // Corner handle: a generous zone around the bottom-right.
    final handle = Offset(box.right, box.bottom);
    if ((f.dx - handle.dx).abs() <= 0.09 &&
        (f.dy - handle.dy).abs() <= 0.09) {
      _dragKind = 2;
      _dragOrigBox = box;
      return;
    }
    if (box.containsPoint(f.dx, f.dy)) {
      _dragKind = 1;
      _dragOrigBox = box;
    }
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragKind == 0 || _dragStart == null) return;
    final f = _frac(d.localPosition);
    final start = _dragStart!;
    if (_dragKind == 3) {
      final x = f.dx < start.dx ? f.dx : start.dx;
      final y = f.dy < start.dy ? f.dy : start.dy;
      setState(() {
        _rubberBand = LogoBox(
          x: x,
          y: y,
          w: (f.dx - start.dx).abs(),
          h: (f.dy - start.dy).abs(),
        );
      });
      return;
    }
    final sel = _selected;
    final orig = _dragOrigBox;
    if (sel == null || orig == null) return;
    if (_dragKind == 1) {
      final dx = (f.dx - start.dx).clamp(-orig.x, 1 - orig.right);
      final dy = (f.dy - start.dy).clamp(-orig.y, 1 - orig.bottom);
      widget.onBoxChanged(
        sel.id,
        orig.copyWith(x: orig.x + dx, y: orig.y + dy),
      );
    } else if (_dragKind == 2) {
      widget.onBoxChanged(
        sel.id,
        LogoBox.clamped(
          x: orig.x,
          y: orig.y,
          w: f.dx - orig.x,
          h: f.dy - orig.y,
        ),
      );
    }
  }

  void _panEnd(DragEndDetails d) {
    if (_dragKind == 3 && _rubberBand != null) {
      final band = _rubberBand!;
      if (band.w >= 0.03 && band.h >= 0.03) {
        widget.onBoxDrawn(LogoBox.clamped(x: band.x, y: band.y, w: band.w, h: band.h));
      }
    }
    setState(() {
      _dragKind = 0;
      _dragStart = null;
      _dragOrigBox = null;
      _rubberBand = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: _tapUp,
      onPanStart: _panStart,
      onPanUpdate: _panUpdate,
      onPanEnd: _panEnd,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _LogoPartsEditorPainter(
              parts: widget.parts,
              master: _master,
              tSec: _controller.value * kLogoPartsLoopSec,
              selectedId: widget.selectedId,
              rubberBand: _rubberBand,
              scene: widget.scene,
              autoGlowArgb: _autoGlowArgb,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the combined animation plus the box outlines
/// (selected = gold + corner handle; rubber band while
/// drawing a new box).
class _LogoPartsEditorPainter extends CustomPainter {
  _LogoPartsEditorPainter({
    required this.parts,
    required this.master,
    required this.tSec,
    required this.selectedId,
    required this.rubberBand,
    required this.scene,
    required this.autoGlowArgb,
  });

  final List<LogoPart> parts;
  final ui.Image? master;
  final double tSec;
  final String? selectedId;
  final LogoBox? rubberBand;
  final LogoPartsScene? scene;
  final int? autoGlowArgb;

  @override
  void paint(Canvas canvas, Size size) {
    LogoPartsService.paintParts(
      canvas,
      size,
      parts,
      master,
      tSec,
      scene: scene,
      autoGlowColorArgb: autoGlowArgb,
    );
    for (final part in parts) {
      final rect = LogoPartsService.boxRectIn(size, part.box);
      final selected = part.id == selectedId;
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.2
          ..color = selected
              ? const Color(0xFFFFC800)
              : const Color(0x99FFFFFF),
      );
      if (selected) {
        const handle = 9.0;
        canvas.drawRect(
          Rect.fromLTWH(
            rect.right - handle / 2,
            rect.bottom - handle / 2,
            handle,
            handle,
          ),
          Paint()..color = const Color(0xFFFFC800),
        );
      }
    }
    final band = rubberBand;
    if (band != null) {
      canvas.drawRect(
        LogoPartsService.boxRectIn(size, band),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFC800),
      );
    }
  }

  @override
  bool shouldRepaint(_LogoPartsEditorPainter old) =>
      old.tSec != tSec ||
      old.master != master ||
      old.parts != parts ||
      old.selectedId != selectedId ||
      old.rubberBand != rubberBand ||
      old.scene != scene ||
      old.autoGlowArgb != autoGlowArgb;
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
    this.partsScene,
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

  /// Redesign Build 2: the parts SCENE (glow + base) riding
  /// with [parts] (see RotatingLogo.partsScene).
  final LogoPartsScene? partsScene;

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
      partsScene: widget.partsScene,
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
