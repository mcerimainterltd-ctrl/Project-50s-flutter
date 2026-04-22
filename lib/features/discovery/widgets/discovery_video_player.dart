import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class DiscoveryVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String posterUrl;

  const DiscoveryVideoPlayer({Key? key, required this.videoUrl, required this.posterUrl}) : super(key: key);

  @override
  _DiscoveryVideoPlayerState createState() => _DiscoveryVideoPlayerState();
}

class _DiscoveryVideoPlayerState extends State<DiscoveryVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) => setState(() {}))
      ..setLooping(true)
      ..setVolume(0)
      ..play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller))
        : Image.network(widget.posterUrl, fit: BoxFit.cover);
  }
}
