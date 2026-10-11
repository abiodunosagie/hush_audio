import 'dart:math';

import 'package:flutter/material.dart';

/// A ring that fills with the engine's master gain, so fades are visible.
class LevelRing extends StatelessWidget {
  const LevelRing({super.key, required this.level, this.size = 72});

  /// 0 to 1.
  final double level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          level: level.clamp(0, 1),
          track: scheme.onSurface.withValues(alpha: 0.12),
          fill: scheme.primary,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.level, required this.track, required this.fill});

  final double level;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, 2 * pi, false, paint..color = track);
    if (level > 0) {
      canvas.drawArc(arc, -pi / 2, 2 * pi * level, false, paint..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.level != level || old.track != track || old.fill != fill;
}
