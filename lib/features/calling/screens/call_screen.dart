import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen({super.key, required this.userId, this.isVideo = false, this.isIncoming = false});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _timer;
  int _seconds = 0;
  bool _isMicMuted = false;
  bool _isCamMuted = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    Future.microtask(() {
      final service = ref.read(webRTCServiceProvider);
      if (!widget.isIncoming) {
        service.startCall(widget.userId, widget.isVideo);
      }
      service.callState.listen((s) {
        if (s == CallState.ended && mounted) context.go('/contacts');
      });
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          // Remote Video / Background
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: widget.isVideo && webrtc.remoteRenderer.srcObject != null
                  ? RTCVideoView(webrtc.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(child: CircleAvatar(radius: 60, backgroundColor: Colors.white10, child: Text(widget.userId[0], style: const TextStyle(fontSize: 40)))),
            ),
          ),
          
          // Local Video Thumbnail
          if (widget.isVideo && !_isCamMuted)
            Positioned(
              top: 50, right: 20, width: 110, height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: RTCVideoView(webrtc.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),

          // Top Info (Timer)
          Positioned(
            top: 60, left: 0, right: 0,
            child: Column(
              children: [
                Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_formatDuration(_seconds), style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 1.2)),
              ],
            ),
          ),

          // Bottom Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.only(bottom: 50, left: 20, right: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlBtn(Icons.mic_off, _isMicMuted, () => setState(() => _isMicMuted = !_isMicMuted)),
                  if (widget.isVideo) _controlBtn(Icons.videocam_off, _isCamMuted, () => setState(() => _isCamMuted = !_isCamMuted)),
                  if (widget.isVideo) _controlBtn(Icons.flip_camera_ios, false, () => webrtc.localStream?.getVideoTracks()[0].switchCamera()),
                  FloatingActionButton(
                    heroTag: "hangup",
                    backgroundColor: Colors.red,
                    onPressed: () { webrtc.endCall(); context.go('/contacts'); },
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.white : Colors.white10),
        child: Icon(icon, color: isActive ? Colors.black : Colors.white),
      ),
    );
  }
}
