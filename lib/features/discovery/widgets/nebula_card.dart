import 'package:flutter/material.dart';
import 'dart:ui';

class NebulaCard extends StatelessWidget {
  final double glowIntensity;
  final int index;

  const NebulaCard({
    super.key, 
    required this.glowIntensity,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 500,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.1 + (0.2 * glowIntensity)),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Stack(
            children: [
              // Cinematic Glow Layer
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.withOpacity(0.2 * glowIntensity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white.withOpacity(0.2 + (0.6 * glowIntensity)),
                  size: 80,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
