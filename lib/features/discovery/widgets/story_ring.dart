import 'dart:math';
import 'package:flutter/material.dart';

class StoryRingPainter extends CustomPainter {
  final bool hasUnseen;
  final int segmentCount;

  StoryRingPainter({required this.hasUnseen, this.segmentCount = 3});

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 3.0;
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (!hasUnseen) {
      paint.color = Colors.white.withOpacity(0.2);
      canvas.drawCircle(size.center(Offset.zero), size.width / 2, paint);
    } else {
      // Neon Gradient for active stories
      paint.shader = SweepGradient(
        colors: [Colors.blueAccent, Colors.purpleAccent, Colors.blueAccent],
      ).createShader(rect);

      double spacing = 0.2; 
      double arcLength = (2 * pi - (segmentCount * spacing)) / segmentCount;

      for (int i = 0; i < segmentCount; i++) {
        canvas.drawArc(
          rect.deflate(strokeWidth / 2),
          i * (arcLength + spacing) - pi / 2,
          arcLength,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class KineticStoryAvatar extends StatelessWidget {
  final String avatarUrl;
  final bool isActive;

  const KineticStoryAvatar({Key? key, required this.avatarUrl, this.isActive = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(75, 75),
            painter: StoryRingPainter(hasUnseen: isActive),
          ),
          CircleAvatar(
            radius: 32,
            backgroundImage: NetworkImage(avatarUrl),
            backgroundColor: Colors.grey[900],
          ),
        ],
      ),
    );
  }
}
