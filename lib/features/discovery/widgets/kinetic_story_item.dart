import 'dart:math' as math;
import 'package:flutter/material.dart';

class KineticStoryItem extends StatefulWidget {
  final String username;
  final String avatarUrl;
  final bool hasUnseen;
  final double radius;
  final VoidCallback? onTap;

  const KineticStoryItem({
    Key? key,
    required this.username,
    required this.avatarUrl,
    this.hasUnseen = true,
    this.radius = 80.0,
    this.onTap,
  }) : super(key: key);

  @override
  State<KineticStoryItem> createState() => _KineticStoryItemState();
}

class _KineticStoryItemState extends State<KineticStoryItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.hasUnseen) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Container(
                  width: widget.radius,
                  height: widget.radius,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: widget.hasUnseen ? [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.3 * (1 - _pulse.value)),
                        blurRadius: 15 * _pulse.value,
                        spreadRadius: 2 * _pulse.value,
                      )
                    ] : [],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Our Ultramodern Painter
                      CustomPaint(
                        size: Size(widget.radius, widget.radius),
                        painter: StoryNeonPainter(
                          progress: widget.hasUnseen ? _pulse.value : 1.0,
                          hasUnseen: widget.hasUnseen,
                        ),
                      ),
                      // The Avatar (standard widget for stability)
                      CircleAvatar(
                        radius: (widget.radius / 2) - 5,
                        backgroundImage: NetworkImage(widget.avatarUrl),
                        backgroundColor: Colors.black,
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 8),
            Text(
              widget.username,
              style: TextStyle(color: context.xText.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class StoryNeonPainter extends CustomPainter {
  final double progress;
  final bool hasUnseen;

  StoryNeonPainter({required this.progress, required this.hasUnseen});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    if (!hasUnseen) {
      paint.color = XameColors.darkBg.withOpacity(0.1);
      canvas.drawCircle(center, radius, paint);
    } else {
      // Ultramodern Gradient: Deep Blue to Neon Cyan
      paint.shader = const SweepGradient(
        colors: [Colors.blueAccent, Colors.cyanAccent, Colors.purpleAccent, Colors.blueAccent],
        stops: [0.0, 0.3, 0.6, 1.0],
      ).createShader(rect);

      // Create segmented gaps for a "tech" look
      double totalArc = 2 * math.pi;
      int segments = 3;
      double gap = 0.4;
      double segmentArc = (totalArc / segments) - gap;

      for (int i = 0; i < segments; i++) {
        double startAngle = (i * (segmentArc + gap)) - (math.pi / 2) + (progress * 0.5);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          segmentArc,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StoryNeonPainter oldDelegate) => oldDelegate.progress != progress;
}
