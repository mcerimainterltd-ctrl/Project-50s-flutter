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
    _setupStreams();
  }

  void _setupStreams() {
    _stateSub = _webrtc.callState.listen((state) {
      if (state == CallState.ended && mounted) context.go('/contacts');
    });
    _remoteSub = _webrtc.remoteStream$.listen((stream) {
      if (mounted) setState(() => _remoteRenderer.srcObject = stream);
    });
    _webrtc.startCall(widget.userId, widget.isVideo);
    if (_webrtc.localStream != null) {
      _localRenderer.srcObject = _webrtc.localStream;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _remoteSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video - FORCED FULL SCREEN
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
          // Controls
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red, size: 60),
                  onPressed: () => _webrtc.endCall(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
