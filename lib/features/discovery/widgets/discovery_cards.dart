import 'package:flutter/material.dart';
import 'live_pulse.dart';

class MediaDiscoverCard extends StatelessWidget {
  final String mediaUrl;
  final String title;
  final String category;
  final bool isLive;

  const MediaDiscoverCard({
    Key? key, 
    required this.mediaUrl, 
    required this.title, 
    required this.category,
    this.isLive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        image: DecorationImage(image: NetworkImage(mediaUrl), fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32.0),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, Colors.black87],
              ),
            ),
          ),
          // Live Pulse Positioned
          if (isLive)
            const Positioned(top: 20, right: 20, child: LivePulseIndicator()),
          
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
