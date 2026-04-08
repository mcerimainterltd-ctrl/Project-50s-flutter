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
  late final StreamSubscription _stateSub;
  late final StreamSubscription _timerSub;
  late final StreamSubscription _remoteSub;

  Offset _thumbnailOffset = const Offset(16, 60);
  bool _isDragging = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _webrtc = ref.read(webRTCServiceProvider);
    _initRenderers();
    _startCall();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    _stateSub = _webrtc.callState.listen((state) {
      if (state == CallState.ended && mounted) context.go('/contacts');
    });
    _timerSub = _webrtc.callTimer.listen((_) => mounted ? setState(() {}) : null);
    _remoteSub = _webrtc.remoteStream$.listen((stream) {
      _remoteRenderer.srcObject = stream;
    });
    await _webrtc.startCall(widget.userId, widget.isVideo ? 'video' : 'voice');
    if (_webrtc.localStream != null) {
      _localRenderer.srcObject = _webrtc.localStream;
    }
  }

  Future<void> _endCall() async {
    await _webrtc.endCall();
    if (mounted) context.go('/contacts');
  }

  void _swapVideos() {
    setState(() {
      final temp = _localRenderer.srcObject;
      _localRenderer.srcObject = _remoteRenderer.srcObject;
      _remoteRenderer.srcObject = temp;
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _timerSub.cancel();
    _remoteSub.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _toggleFullscreen,
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
          if (widget.isVideo && _webrtc.localStream != null && !_isFullscreen)
            Positioned(
              left: _thumbnailOffset.dx,
              top: _thumbnailOffset.dy,
              child: GestureDetector(
                onPanStart: (_) => _isDragging = true,
                onPanUpdate: (details) {
                  setState(() {
                    _thumbnailOffset = Offset(
                      (_thumbnailOffset.dx + details.delta.dx).clamp(0.0, screenSize.width - 120),
                      (_thumbnailOffset.dy + details.delta.dy).clamp(0.0, screenSize.height - 180),
                    );
                  });
                },
                onPanEnd: (_) => _isDragging = false,
                onDoubleTap: _swapVideos,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.isVideo && _webrtc.localStream != null && _isFullscreen)
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: _toggleFullscreen,
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          if (!_isFullscreen)
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  CircleAvatar(radius: 45, child: Text(widget.userId[0])),
                  const SizedBox(height: 16),
                  Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 24)),
                  const SizedBox(height: 8),
                  StreamBuilder<CallState>(
                    stream: _webrtc.callState,
                    builder: (ctx, snap) {
                      final state = snap.data ?? CallState.outgoing;
                      String label;
                      switch (state) {
                        case CallState.outgoing: label = 'Calling...'; break;
                        case CallState.active: label = '00:00'; break;
                        case CallState.incoming: label = 'Incoming...'; break;
                        default: label = 'Ended'; break;
                      }
                      return Text(label, style: const TextStyle(color: Colors.white54));
                    },
                  ),
                  StreamBuilder<String>(
                    stream: _webrtc.callTimer,
                    builder: (ctx, snap) {
                      final timer = snap.data ?? '00:00';
                      return Text(timer, style: const TextStyle(color: Colors.white, fontSize: 24));
                    },
                  ),
                ],
              ),
            ),
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallBtn(
                      icon: _webrtc.isAudioMuted ? Icons.mic_off : Icons.mic,
                      label: _webrtc.isAudioMuted ? 'Unmute' : 'Mute',
                      color: _webrtc.isAudioMuted ? Colors.white : Colors.white54,
                      onTap: () => setState(() => _webrtc.toggleAudio()),
                    ),
                    _CallBtn(
                      icon: Icons.call_end,
                      label: 'End',
                      color: XameColors.danger,
                      size: 72,
                      onTap: _endCall,
                    ),
                    _CallBtn(
                      icon: _webrtc.isLoudspeakerOn ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      color: _webrtc.isLoudspeakerOn ? XameColors.primary : Colors.white54,
                      onTap: () async {
                        await _webrtc.toggleSpeaker();
                        setState(() {});
                      },
                    ),
                  ],
                ),
                if (widget.isVideo) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallBtn(
                        icon: _webrtc.isVideoMuted ? Icons.videocam_off : Icons.videocam,
                        label: _webrtc.isVideoMuted ? 'Cam off' : 'Cam on',
                        color: _webrtc.isVideoMuted ? Colors.white : Colors.white54,
                        onTap: () => setState(() => _webrtc.toggleVideo()),
                      ),
                      _CallBtn(
                        icon: Icons.flip_camera_android,
                        label: 'Flip',
                        color: Colors.white54,
                        onTap: () async => await _webrtc.toggleCamera(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _CallBtn({required this.icon, required this.label, required this.color, required this.onTap, this.size = 56});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color == XameColors.danger ? XameColors.danger : Colors.white.withOpacity(0.15),
          ),
          child: Icon(icon, color: color == XameColors.danger ? Colors.white : color, size: size * 0.45),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    ),
  );
}