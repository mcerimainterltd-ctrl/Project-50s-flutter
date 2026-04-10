import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming;
  
  const CallScreen({
    super.key, 
    required this.userId, 
    required this.isVideo,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isMicMuted = false;
  bool _isCamMuted = false;
  bool _isSpeakerOn = true;
  bool _isLocalMain = false;
  bool _showControls = true;
  Offset _thumbnailOffset = const Offset(20, 100);
  
  int _seconds = 0;
  Timer? _timer;
  bool _timerStarted = false;

  @override
  void initState() {
    super.initState();
    // Safely ensure renderers are ready for the UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webRTCServiceProvider).initRenderers();
    });
  }

  void _startTimer() {
    if (_timerStarted) return;
    _timerStarted = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final hasRemote = webrtc.remoteRenderer.srcObject != null;
    
    // Start timer only when the remote stream arrives
    if (hasRemote && !_timerStarted) {
      _startTimer();
    }

    final bool showLocalFull = !hasRemote || _isLocalMain;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // 1. Full Screen Video View
            Positioned.fill(
              child: RTCVideoView(
                showLocalFull ? webrtc.localRenderer : webrtc.remoteRenderer,
                mirror: showLocalFull,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

            // 2. Cinematic Connecting Overlay
            if (!hasRemote)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      const CircularProgressIndicator(color: Colors.white30, strokeWidth: 2),
                      const SizedBox(height: 24),
                      Text(
                        "Calling ${widget.userId}...",
                        style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.8),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),

            // 3. Floating PiP Thumbnail
            if (widget.isVideo && hasRemote)
              Positioned(
                top: _thumbnailOffset.dy,
                right: _thumbnailOffset.dx,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _thumbnailOffset += Offset(-d.delta.dx, d.delta.dy)),
                  onDoubleTap: () => setState(() => _isLocalMain = !_isLocalMain),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 110, height: 160,
                      color: Colors.black,
                      child: RTCVideoView(
                        _isLocalMain ? webrtc.remoteRenderer : webrtc.localRenderer,
                        mirror: !_isLocalMain,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),

            // 4. Top Bar (Name + Timer)
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.only(top: topPad + 12, left: 20, right: 20, bottom: 30),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      if (_timerStarted) _buildTimerBadge(),
                    ],
                  ),
                ),
              ),
            ),

            // 5. Bottom Controls
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.only(bottom: botPad + 30, top: 40),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(Icons.mic_off, _isMicMuted, () {
                        setState(() => _isMicMuted = !_isMicMuted);
                        webrtc.localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMicMuted);
                      }),
                      if (widget.isVideo)
                        _btn(Icons.videocam_off, _isCamMuted, () {
                          setState(() => _isCamMuted = !_isCamMuted);
                          webrtc.localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCamMuted);
                        }),
                      _btn(Icons.volume_up, _isSpeakerOn, () {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        Helper.setSpeakerphoneOn(_isSpeakerOn);
                      }),
                      _hangupBtn(webrtc),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
      child: Text(_formatDuration(_seconds), style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }

  Widget _btn(IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(color: active ? Colors.white : Colors.white10, shape: BoxShape.circle),
        child: Icon(icon, color: active ? Colors.black : Colors.white, size: 24),
      ),
    );
  }

  Widget _hangupBtn(WebRTCService webrtc) {
    return InkWell(
      onTap: () {
        webrtc.endCall();
        context.go('/contacts');
      },
      child: Container(
        width: 65, height: 65,
        decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle),
        child: const Icon(Icons.call_end, color: Colors.white, size: 30),
      ),
    );
  }
}
