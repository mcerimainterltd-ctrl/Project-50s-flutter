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
          // 1. REMOTE VIDEO (Only if video call)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: widget.isVideo 
                ? (webrtc.remoteRenderer.srcObject != null 
                    ? RTCVideoView(webrtc.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : const Center(child: CircularProgressIndicator(color: Colors.white24)))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(radius: 50, backgroundColor: Colors.blueGrey, child: Text(widget.userId[0].toUpperCase(), style: const TextStyle(fontSize: 40))),
                      const SizedBox(height: 20),
                      const Text("Voice Call Active", style: TextStyle(color: Colors.white54)),
                    ],
                  ),
            ),
          ),
          
          // 2. LOCAL THUMBNAIL (Video only)
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

          // 3. CONTROLS (ALWAYS VISIBLE)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton(
                        heroTag: "mic",
                        backgroundColor: Colors.white10,
                        onPressed: () {}, // Toggle mic logic
                        child: const Icon(Icons.mic, color: Colors.white),
                      ),
                      const SizedBox(width: 30),
                      FloatingActionButton(
                        heroTag: "end",
                        backgroundColor: Colors.red,
                        onPressed: () {
                          ref.read(webRTCServiceProvider).endCall();
                          context.go('/contacts');
                        },
                        child: const Icon(Icons.call_end, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
