/// MOTION GRAPHICS STUDIO — live preview widget (Build M1).
///
/// [MotionSceneView] plays a [MotionScene] in real time through
/// the shared painter — the same evaluator + painter the frame
/// renderer uses, so what the Gallery shows is what export will
/// produce (parity by construction, Logo Cube rule).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion_painter.dart';
import 'motion_scene.dart';

/// A self-animating, looping preview of [scene].
class MotionSceneView extends StatefulWidget {
  const MotionSceneView({
    super.key,
    required this.scene,
    this.images = const {},
    this.playing = true,
  });

  final MotionScene scene;
  final Map<String, ui.Image> images;

  /// Cards pass false to hold a still first frame (not used by
  /// the M1 Gallery — every card animates — but kept for the
  /// low-tier performance work in later phases).
  final bool playing;

  @override
  State<MotionSceneView> createState() => _MotionSceneViewState();
}

class _MotionSceneViewState extends State<MotionSceneView>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    if (widget.playing) {
      _ticker = createTicker((elapsed) {
        final d = widget.scene.durationSec;
        if (d <= 0) return;
        setState(() {
          _t = (elapsed.inMicroseconds / 1000000.0) % d;
        });
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: MotionScenePainter(
        scene: widget.scene,
        t: _t,
        images: widget.images,
      ),
      size: Size.infinite,
    );
  }
}
