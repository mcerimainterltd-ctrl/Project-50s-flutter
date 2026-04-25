import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'live_pulse.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class DiscoveryStoriesBar extends StatelessWidget {
  final List<Map<String, dynamic>>? users;
  const DiscoveryStoriesBar({Key? key, this.users}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final list = users ?? List.generate(8, (i) => {
      'name':     i == 0 ? 'You' : 'User $i',
      'avatar':   'https://i.pravatar.cc/150?img=${i + 10}',
      'hasSeen':  i == 0,
      'isOnline': i % 3 == 0,
    });
    return SizedBox(
      height: 106,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        itemBuilder: (_, i) => _StoryRing(
          name:     list[i]['name']     as String,
          avatar:   list[i]['avatar']   as String,
          hasSeen:  list[i]['hasSeen']  as bool? ?? false,
          isOnline: list[i]['isOnline'] as bool? ?? false,
          isFirst:  i == 0,
          onTap:    list[i]['onTap']    as VoidCallback?,
        ),
      ),
    );
  }
}

class _StoryRing extends StatefulWidget {
  final String name, avatar;
  final bool   hasSeen, isOnline, isFirst;
  final VoidCallback? onTap;
  const _StoryRing({Key? key,
    required this.name, required this.avatar,
    required this.hasSeen, required this.isOnline,
    required this.isFirst, this.onTap}) : super(key: key);
  @override
  State<_StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<_StoryRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: Duration(seconds: 3))
      ..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap ?? () {},
    child: Container(
      width: 72,
      margin: const EdgeInsets.only(right: 12),
      child: Column(children: [
        SizedBox(width: 66, height: 66,
          child: Stack(alignment: Alignment.center, children: [
            if (!widget.hasSeen)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  size: Size(66, 66),
                  painter: _GradientRingPainter(_ctrl.value)),
              )
            else
              Container(width: 66, height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.xMuted.withValues(alpha: 0.25), width: 2))),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: XameColors.darkSurface),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: widget.avatar, fit: BoxFit.cover,
                  placeholder: (_, __) =>
                    Container(color: XameColors.darkSurface),
                  errorWidget: (_, __, ___) => Container(
                    color: XameColors.darkSurface,
                    child: Icon(Icons.person,
                        color: context.xMuted.withValues(alpha: 0.5), size: 28)),
                ),
              ),
            ),
            if (widget.isOnline)
              Positioned(bottom: 2, right: 2,
                child: Container(width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: XameColors.accent,
                    border: Border.all(
                        color: XameColors.darkBg, width: 2)))),
            if (widget.isFirst)
              Positioned(bottom: 0, right: 0,
                child: Container(width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: XameColors.primary),
                  child: Icon(Icons.add,
                      color: context.xText, size: 14))),
          ]),
        ),
        SizedBox(height: 6),
        Text(widget.name,
          style: TextStyle(
              color: context.xText.withValues(alpha: 0.7), fontSize: 11,
              fontWeight: FontWeight.w500),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _GradientRingPainter extends CustomPainter {
  final double progress;
  _GradientRingPainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final rect  = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader      = SweepGradient(
        startAngle: progress * 2 * pi,
        endAngle:   progress * 2 * pi + 2 * pi,
        colors: const [
          XameColors.secondary, XameColors.primary,
          XameColors.accent, XameColors.danger,
          XameColors.secondary,
        ],
      ).createShader(rect);
    canvas.drawArc(rect, 0, 2 * pi, false, paint);
  }
  @override
  bool shouldRepaint(_GradientRingPainter old) => old.progress != progress;
}
