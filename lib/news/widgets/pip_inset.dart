/// The picture-in-picture inset (Phase 6) — a labelled frame drawn
/// in template previews at the stored position + size, so the user
/// sees exactly where the Phase 7 export will put the PIP video
/// ([pipOverlayFilter] in lib/services/fx_pack.dart). A frame with a
/// label, never a fake video.
library;

import 'package:flutter/material.dart';

class PipInset extends StatelessWidget {
  const PipInset({
    super.key,
    required this.position,
    required this.scale,
    required this.frameWidth,
  });

  /// A [ChannelPreset.pipPositionIds] id ('topLeft', 'topRight',
  /// 'bottomLeft', 'bottomRight').
  final String position;

  /// Inset width as a fraction of the frame width (0.15–0.5).
  final double scale;

  final double frameWidth;

  @override
  Widget build(BuildContext context) {
    final w = (frameWidth * scale.clamp(0.15, 0.5)).clamp(40.0, 160.0);
    final h = w * 9 / 16;
    const margin = 8.0;
    double? top;
    double? bottom;
    double? left;
    double? right;
    switch (position) {
      case 'topLeft':
        top = margin;
        left = margin;
      case 'topRight':
        top = margin;
        right = margin;
      case 'bottomLeft':
        bottom = margin;
        left = margin;
      default:
        bottom = margin;
        right = margin;
    }
    return Positioned(
      key: const Key('preview-pip-inset'),
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.black54,
          border: Border.all(color: const Color(0xFF7C3AED), width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Text(
          'PIP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
