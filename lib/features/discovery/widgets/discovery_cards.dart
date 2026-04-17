import 'package:flutter/material.dart';
import 'live_pulse.dart';
import 'discovery_video_player.dart';

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
    // Production Mock: Only use video for 'Live' items or specific indices
    final bool useVideo = isLive || title.contains("Pacific");
    const String mockVideo = "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4";

    return Container(
      height: 450,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32.0),
        child: Stack(
          children: [
            if (useVideo)
              DiscoveryVideoPlayer(videoUrl: mockVideo, posterUrl: mediaUrl)
            else
              Image.network(mediaUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity),

            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.black87],
                ),
              ),
            ),

            if (isLive)
              const Positioned(top: 20, right: 20, child: LivePulseIndicator()),
            
            Positioned(
              bottom: 25, left: 25, right: 25,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
