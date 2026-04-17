import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class DiscoveryVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String posterUrl;

  const DiscoveryVideoPlayer({Key? key, required this.videoUrl, required this.posterUrl}) : super(key: key);

  @override
  _DiscoveryVideoPlayerState createState() => _DiscoveryVideoPlayerState();
}

class _DiscoveryVideoPlayerState extends State<DiscoveryVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..setLooping(true)
      ..setVolume(0) // Muted by default for discovery
      ..initialize().then((_) {
        if (mounted) setState(() => _isInitialized = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.8) {
          _controller?.play();
        } else {
          _controller?.pause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster Image (shown while loading or when off-screen)
          Image.network(widget.posterUrl, fit: BoxFit.cover),
          
          if (_isInitialized)
            AnimatedOpacity(
              opacity: _isInitialized ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: VideoPlayer(_controller!),
            ),
            
          // Loading Indicator for Video
          if (!_isInitialized)
            const Center(child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2)),
        ],
      ),
    );
  }
}
