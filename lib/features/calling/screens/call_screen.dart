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
  
  // Award-Winning Interaction Variables
  Offset _thumbnailOffset = const Offset(20, 50); 
  bool _isLocalMain = false;

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
        if (s == CallState.active && _timer == null) {
          _startTimer();
        }
        if (s == CallState.ended && mounted) {
          context.go('/contacts');
        }
      });
    });
  }

  void _startTimer() => _timer = Timer.periodic(const Duration(seconds: 1), (t) => mounted ? setState(() => _seconds++) : null);

  String _formatDuration(int s) => "${(s / 60).floor().toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final hasRemote = webrtc.remoteRenderer.srcObject != null;

    // Logic: Local is full screen ONLY if remote is missing OR if toggled
    final bool showLocalFull = !hasRemote || _isLocalMain;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          // 1. MAIN RENDERER (Full Screen)
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _isLocalMain = !_isLocalMain),
              child: Container(
                color: Colors.black,
                child: widget.isVideo 
                  ? RTCVideoView(
                      showLocalFull ? webrtc.localRenderer : webrtc.remoteRenderer,
                      mirror: showLocalFull,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(child: CircleAvatar(radius: 60, backgroundColor: Colors.white10, child: Text(widget.userId[0], style: const TextStyle(fontSize: 40)))),
              ),
            ),
          ),

          // 2. DRAGGABLE THUMBNAIL (Shows only if remote exists)
          if (widget.isVideo && hasRemote)
            Positioned(
              top: _thumbnailOffset.dy,
              right: _thumbnailOffset.dx,
              child: GestureDetector(
                onPanUpdate: (details) => setState(() => _thumbnailOffset += Offset(-details.delta.dx, details.delta.dy)),
                onDoubleTap: () => setState(() => _isLocalMain = !_isLocalMain),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    width: 110, height: 160,
                    color: Colors.black54,
                    child: RTCVideoView(
                      _isLocalMain ? webrtc.remoteRenderer : webrtc.localRenderer,
                      mirror: !_isLocalMain,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          // 3. UI OVERLAYS (Timer & Controls - Preserved from 139)
          Positioned(
            top: 60, left: 0, right: 0,
            child: Column(
              children: [
                Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_formatDuration(_seconds), style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
          ),

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
                    heroTag: "hangup", backgroundColor: Colors.red,
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
