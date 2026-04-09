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
  CallState _currentStatus = CallState.outgoing;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    final webrtc = ref.read(webRTCServiceProvider);
    
    _stateSub = webrtc.callState.listen((s) => setState(() => _currentStatus = s));
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
    final bool isLive = _currentStatus == CallState.active;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            // Ensure the RTCVideoView is inside a ConstrainedBox to prevent 'Half-Screen'
            Positioned.fill(
              child: OverflowBox(
                maxWidth: size.width,
                maxHeight: size.height,
                child: RTCVideoView(
                  isLive ? _remoteRenderer : _localRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
            Positioned(
              bottom: 50, left: 0, right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () { ref.read(webRTCServiceProvider).endCall(); context.go('/contacts'); },
                  child: const Icon(Icons.call_end),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
