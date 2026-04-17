import 'dart:math';
import 'package:flutter/material.dart';

// ── Live pulse indicator — animated waveform bars ────────────────────────────
class LivePulseIndicator extends StatefulWidget {
  final Color color;
  final bool  compact;
  const LivePulseIndicator({
    Key? key,
    this.color   = const Color(0xFF00FF88),
    this.compact = false,
  }) : super(key: key);

  @override
  State<LivePulseIndicator> createState() => _LivePulseIndicatorState();
}

class _LivePulseIndicatorState extends State<LivePulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 6 : 8,
        vertical:   widget.compact ? 3 : 4),
      decoration: BoxDecoration(
        color:        Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(
          color: widget.color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!widget.compact) ...[
          Text('LIVE',
            style: TextStyle(
              color:       widget.color,
              fontSize:    9,
              fontWeight:  FontWeight.w900,
              letterSpacing: 1.2)),
          const SizedBox(width: 5),
        ],
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            children: List.generate(4, (i) {
              final h = 4.0 + sin(_ctrl.value * pi + i * 0.8) * 5;
              return Container(
                width:  2,
                height: h.clamp(2.0, 10.0),
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                decoration: BoxDecoration(
                  color:         widget.color,
                  borderRadius:  BorderRadius.circular(1)),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

// ── Online pulse dot ──────────────────────────────────────────────────────────
class OnlinePulseDot extends StatefulWidget {
  final double size;
  final Color  color;
  const OnlinePulseDot({
    Key? key,
    this.size  = 10,
    this.color = const Color(0xFF00FF88),
  }) : super(key: key);

  @override
  State<OnlinePulseDot> createState() => _OnlinePulseDotState();
}

class _OnlinePulseDotState extends State<OnlinePulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _scale   = Tween(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SizedBox(
    width:  widget.size * 2.4,
    height: widget.size * 2.4,
    child: Stack(alignment: Alignment.center, children: [
      AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Container(
            width:  widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withOpacity(_opacity.value)),
          ),
        ),
      ),
      Container(
        width:  widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color),
      ),
    ]),
  );
}

// ── Shimmer loader ────────────────────────────────────────────────────────────
class ShimmerBox extends StatefulWidget {
  final double width, height, radius;
  const ShimmerBox({
    Key? key,
    required this.width,
    required this.height,
    this.radius = 12,
  }) : super(key: key);

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width:  widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment(_anim.value - 1, 0),
          end:   Alignment(_anim.value,     0),
          colors: const [
            Color(0xFF1A1A2E),
            Color(0xFF2A2A3E),
            Color(0xFF1A1A2E),
          ],
        ),
      ),
    ),
  );
}
