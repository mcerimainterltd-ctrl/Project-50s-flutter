import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

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
  
  Offset _thumbnailOffset = const Offset(20, 60);
  bool _isSwapped = false;
  CallState _currentStatus = CallState.outgoing;

  @override
  void initState() {
    super.initState();
    _webrtc = ref.read(webRTCServiceProvider);
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    _stateSub = _webrtc.callState.listen((s) {
      if (mounted) setState(() => _currentStatus = s);
      if (s == CallState.ended && mounted) context.go('/contacts');
    });

    _remoteSub = _webrtc.remoteStream$.listen((s) {
      if (mounted) setState(() => _remoteRenderer.srcObject = s);
    });

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
    final bool isCallActive = _currentStatus == CallState.active;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // MAIN VIDEO: Shows Local if calling, Remote if active
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _isSwapped = !_isSwapped),
              child: RTCVideoView(
                (isCallActive && !_isSwapped) ? _remoteRenderer : _localRenderer,
                mirror: !(isCallActive && !_isSwapped),
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

          // DRAGGABLE THUMBNAIL: Appears only when call is active
          if (isCallActive)
            Positioned(
              left: _thumbnailOffset.dx,
              top: _thumbnailOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _thumbnailOffset += details.delta;
                  });
                },
                onDoubleTap: () => setState(() => _isSwapped = !_isSwapped),
                child: Container(
                  width: 120, height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 2),
                    boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black54)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RTCVideoView(
                      _isSwapped ? _remoteRenderer : _localRenderer,
                      mirror: !_isSwapped,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),

          // OVERLAY UI
          SafeArea(
            child: Column(
              children: [
                if (!isCallActive) ...[
                  const SizedBox(height: 100),
                  Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const Text("Calling...", style: TextStyle(color: Colors.white70, fontSize: 18)),
                ],
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () => _webrtc.endCall(),
                    child: const Icon(Icons.call_end, size: 30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
