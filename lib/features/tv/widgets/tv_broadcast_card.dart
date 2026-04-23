import 'package:flutter/material.dart';
import '../../discovery/widgets/live_pulse.dart';
import 'soccer_score_overlay.dart';

class TVBroadcastCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String image;
  final String homeTeam;
  final String awayTeam;
  final String score;
  final String matchTime;
  final bool isLive;

  const TVBroadcastCard({
    Key? key, 
    required this.title, 
    required this.subtitle, 
    required this.image,
    this.isLive = false,
    required this.homeTeam,
    required this.awayTeam,
    required this.score,
    required this.matchTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(image: NetworkImage(image), fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
              ),
            ),
          ),
          if (isLive) ...[
            const Positioned(
              top: 16,
              left: 16,
              child: SoccerScoreOverlay(
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                score: score,
                matchTime: matchTime,
              ),
            ),
            const Positioned(top: 16, right: 16, child: LivePulseIndicator()),
          ],
          Positioned(
            bottom: 20,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
