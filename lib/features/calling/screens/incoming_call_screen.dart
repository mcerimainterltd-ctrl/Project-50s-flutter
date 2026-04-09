import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final userId = webrtc.currentRemoteUserId ?? "Unknown";
    final isVideo = webrtc.isIncomingVideo;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          CircleAvatar(radius: 50, child: Text(userId[0].toUpperCase(), style: const TextStyle(fontSize: 32))),
          const SizedBox(height: 20),
          Text(userId, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text("Incoming ${isVideo ? 'Video' : 'Voice'} Call...", style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FloatingActionButton(
                heroTag: "decline", backgroundColor: Colors.red,
                onPressed: () => webrtc.endCall(),
                child: const Icon(Icons.call_end, color: Colors.white),
              ),
              FloatingActionButton(
                heroTag: "accept", backgroundColor: Colors.green,
                onPressed: () => context.push('/call/$userId?video=$isVideo&incoming=true'),
                child: Icon(isVideo ? Icons.videocam : Icons.call, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
