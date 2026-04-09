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
    // Re-initialize the camera streams on entry
    Future.microtask(() {
      final service = ref.read(webRTCServiceProvider);
      if (widget.isIncoming) {
        // Handled by joinCall in the previous screen
      } else {
        service.startCall(widget.userId, widget.isVideo);
      }
      
      service.callState.listen((state) {
        if (state == CallState.ended && mounted) context.go('/contacts');
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
          // 1. FULL SCREEN: Remote Video
          Positioned.fill(
            child: RTCVideoView(webrtc.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
          
          // 2. THUMBNAIL: Local Camera (The "Selfie" view)
          if (widget.isVideo)
            Positioned(
              top: 40,
              right: 20,
              width: 120,
              height: 180,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.hardEdge,
                child: RTCVideoView(webrtc.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),

          // 3. UI OVERLAY: Names and Buttons
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    ref.read(webRTCServiceProvider).endCall();
                    context.go('/contacts');
                  },
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
