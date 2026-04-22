import 'package:flutter/material.dart';
import 'dart:ui';

class SoccerScoreOverlay extends StatelessWidget {
  final String homeTeam;
  final String awayTeam;
  final String score;
  final String matchTime;

  const SoccerScoreOverlay({
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
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(homeTeam, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Text(score, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.black, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Text(awayTeam, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              Text(matchTime, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
