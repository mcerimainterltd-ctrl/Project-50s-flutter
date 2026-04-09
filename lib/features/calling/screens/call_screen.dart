import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen({
    super.key, 
    required this.userId, 
    this.isVideo = false, 
    this.isIncoming = false
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 50, 
              backgroundColor: Colors.blueGrey,
              child: Text(
                widget.userId.isNotEmpty ? widget.userId[0].toUpperCase() : '?', 
                style: const TextStyle(fontSize: 32, color: Colors.white)
              )
            ),
            const SizedBox(height: 20),
            Text(
              widget.userId, 
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
            ),
            const Spacer(),
            FloatingActionButton(
              heroTag: "end_call_btn",
              backgroundColor: Colors.red,
              onPressed: () {
                webrtc.endCall();
                context.go('/contacts');
              },
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
