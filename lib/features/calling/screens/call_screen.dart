import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/theme/app_theme.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  const CallScreen({super.key, required this.userId, required this.isVideo});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late WebRTCService _webrtc;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _stateSub;
  StreamSubscription? _remoteSub;

  @override
  void initState() {
    super.initState();
    _webrtc = ref.read(webRTCServiceProvider);
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _stateSub = _webrtc.callState.listen((s) { if (s == CallState.ended && mounted) context.go('/contacts'); });
    _remoteSub = _webrtc.remoteStream$.listen((s) { if (mounted) setState(() => _remoteRenderer.srcObject = s); });
    
    await _webrtc.startCall(widget.userId, widget.isVideo);
    if (mounted && _webrtc.localStream != null) {
      setState(() => _localRenderer.srcObject = _webrtc.localStream);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel(); _remoteSub?.cancel();
    _localRenderer.dispose(); _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          
          // Floating Local Preview
          if (widget.isVideo)
            Positioned(
              right: 16, top: 60,
              child: Container(
                width: 110, height: 160,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white30, width: 1)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            ),

          // Top Header
          Positioned(
            top: 60, left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10)])),
                const Text("Connected", style: TextStyle(color: Colors.greenAccent, fontSize: 14)),
              ],
            ),
          ),

          // Bottom Modern Controls
          Positioned(
            bottom: 40, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: Icon(_webrtc.isAudioMuted ? Icons.mic_off : Icons.mic, color: Colors.white), onPressed: () => setState(() => _webrtc.toggleAudio())),
                  GestureDetector(
                    onTap: () => _webrtc.endCall(),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 30),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.flip_camera_android, color: Colors.white), onPressed: () => _webrtc.toggleCamera()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
