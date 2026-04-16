import 'package:flutter/material.dart';
import 'dart:ui';

class NebulaCard extends StatelessWidget {
  final int index;
  final double glowIntensity;
  final Color primaryColor;
  final Color accentColor;

  const NebulaCard({
    super.key,
    required this.index,
    required this.glowIntensity,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 450,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: primaryColor.withOpacity(0.2 * glowIntensity), width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1 * glowIntensity),
            blurRadius: 20 * glowIntensity,
            spreadRadius: 5 * glowIntensity,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.1), Colors.transparent],
              ),
            ),
            child: Center(
              child: Text(
                'Aura #$index',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}