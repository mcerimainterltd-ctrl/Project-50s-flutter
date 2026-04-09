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
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: webrtc.remoteRenderer.srcObject != null 
                  ? RTCVideoView(webrtc.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : const Center(child: CircularProgressIndicator(color: Colors.white24)),
            ),
          ),
          if (widget.isVideo)
            Positioned(
              top: 50,
              right: 20,
              width: 110,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  color: Colors.black54,
                  child: RTCVideoView(webrtc.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: () {
                  ref.read(webRTCServiceProvider).endCall();
                  context.go('/contacts');
                },
                child: const Icon(Icons.call_end, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
