import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming; // Added to check if we are answering
  const CallScreen({super.key, required this.userId, required this.isVideo, this.isIncoming = false});

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
    
    if (widget.isIncoming) {
      await webrtc.joinCall(widget.isVideo);
    } else {
      await webrtc.startCall(widget.userId, widget.isVideo);
    }
    
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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: RTCVideoView(
              isLive ? _remoteRenderer : _localRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          Positioned(
            bottom: 50, left: 0, right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: () { ref.read(webRTCServiceProvider).endCall(); context.go('/contacts'); },
                child: const Icon(Icons.call_end, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
