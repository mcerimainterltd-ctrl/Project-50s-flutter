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
    _initController();
  }

  void _initController() async {
    _controller = VideoPlayerController.network(widget.videoUrl);
    try {
      await _controller!.initialize();
      await _controller!.setLooping(true);
      await _controller!.setVolume(0);
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("Video init error: $e");
    }
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
        if (info.visibleFraction > 0.8 && _isInitialized) {
          _controller?.play();
        } else {
          _controller?.pause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(widget.posterUrl, fit: BoxFit.cover),
          if (_isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          if (!_isInitialized)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}
