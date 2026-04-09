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
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _stateSub;
  StreamSubscription? _remoteSub;
  CallState _status = CallState.outgoing;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    final webrtc = ref.read(webRTCServiceProvider);
    
    _stateSub = webrtc.callState.listen((s) => setState(() => _status = s));
    _remoteSub = webrtc.remoteStream$.listen((s) => setState(() => _remoteRenderer.srcObject = s));
    
    await webrtc.startCall(widget.userId, widget.isVideo);
    if (webrtc.localStream != null) setState(() => _localRenderer.srcObject = webrtc.localStream);
  }

  @override
  void dispose() {
    _stateSub?.cancel(); _remoteSub?.cancel();
    _localRenderer.dispose(); _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLive = _status == CallState.active;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          // VIDEO LAYER (Only shows if it's a video call)
          if (widget.isVideo)
            Positioned.fill(
              child: RTCVideoView(
                isLive ? _remoteRenderer : _localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          
          // VOICE UI LAYER (Shows if not a video call or before video connects)
          if (!widget.isVideo)
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.blueGrey,
                    child: Text(widget.userId[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white)),
                  ),
                  const SizedBox(height: 24),
                  Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(isLive ? "On Call" : "Calling...", style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            ),

          // CALL CONTROLS
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Center(
              child: FloatingActionButton(
                heroTag: "end_call",
                backgroundColor: Colors.red,
                onPressed: () { ref.read(webRTCServiceProvider).endCall(); context.go('/contacts'); },
                child: const Icon(Icons.call_end, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
