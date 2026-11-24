/// Photo Editor shared low-level widgets (Master Plan Phase 7
/// split): the slider row and the preview painters, previously
/// private classes at the bottom of photo_editor_screen.dart.
/// Pure widgets/painters — no editor state. Values unchanged.
library;

import 'package:flutter/material.dart';

import '../../services/photo_pipeline.dart';

class PhotoSliderRow extends StatelessWidget {
  const PhotoSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

/// Transparency checkerboard (Cutout preview).
class PhotoCheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF999999);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y) % 2 == 0) continue;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painted strokes overlay (Remove mask / Cutout eraser / Doodle).
class PhotoStrokePainter extends CustomPainter {
  PhotoStrokePainter({
    required this.strokes,
    required this.current,
    required this.mode,
    required this.doodleColor,
  });

  final List<StrokePath> strokes;
  final StrokePath? current;
  final String mode;
  final Color doodleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...strokes, ?current];
    for (final s in all) {
      final color = mode == 'doodle'
          ? Color(s.argb)
          : mode == 'erase'
          ? Colors.white.withValues(alpha: 0.55)
          : Colors.red.withValues(alpha: 0.45);
      final paint = Paint()
        ..color = color
        ..strokeWidth = s.widthFrac * size.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final dotPaint = Paint()..color = color;
      final radius = s.widthFrac * size.width / 2;
      for (var i = 0; i < s.points.length; i++) {
        final pt = Offset(
          s.points[i].dx * size.width,
          s.points[i].dy * size.height,
        );
        canvas.drawCircle(pt, radius, dotPaint);
        if (i > 0) {
          final prev = Offset(
            s.points[i - 1].dx * size.width,
            s.points[i - 1].dy * size.height,
          );
          canvas.drawLine(prev, pt, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PhotoStrokePainter oldDelegate) => true;
}

/// Tone-curve editor graph: grid + the channel's control polyline.
class PhotoCurvePainter extends CustomPainter {
  PhotoCurvePainter({required this.points, required this.channel});

  final List<Offset> points;
  final String channel;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E1E1E),
    );
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final t = size.width * i / 4;
      canvas.drawLine(Offset(t, 0), Offset(t, size.height), grid);
      canvas.drawLine(Offset(0, t), Offset(size.width, t), grid);
    }
    final color = switch (channel) {
      'r' => Colors.red,
      'g' => Colors.green,
      'b' => Colors.blue,
      _ => Colors.white,
    };
    final sorted = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final pt = Offset(
        sorted[i].dx * size.width,
        (1 - sorted[i].dy) * size.height,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final p in sorted) {
      canvas.drawCircle(
        Offset(p.dx * size.width, (1 - p.dy) * size.height),
        5,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PhotoCurvePainter oldDelegate) => true;
}
