// Updated: 2026-04-23
import 'package:flutter/material.dart';
import 'dart:ui';

class SoccerScoreOverlay extends StatelessWidget {
  final String homeTeam;
  final String awayTeam;
  final String score;
  final String matchTime;

  SoccerScoreOverlay({
    Key? key,
    required this.homeTeam,
    required this.awayTeam,
    required this.score,
    required this.matchTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(homeTeam, style: TextStyle(color: context.xText, fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: context.xText, borderRadius: BorderRadius.circular(4)),
                child: Text(score, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              SizedBox(width: 8),
              Text(awayTeam, style: TextStyle(color: context.xText, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(matchTime, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
