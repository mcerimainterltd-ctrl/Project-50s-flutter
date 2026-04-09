import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webrtc = ref.watch(webRTCServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 20),
            const Text("Incoming Call", style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 60),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // DECLINE BUTTON
                FloatingActionButton(
                  heroTag: "decline",
                  backgroundColor: Colors.red,
                  onPressed: () {
                    webrtc.endCall();
                    context.go('/contacts');
                  },
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
                // ANSWER BUTTON (The Fix)
                FloatingActionButton(
                  heroTag: "answer",
                  backgroundColor: Colors.green,
                  onPressed: () {
                    // This calls the method we added in Build 86
                    // It uses the cached _currentRemoteUserId from the service
                    context.push('/call/${webrtc.currentRemoteUserId ?? "unknown"}?video=true');
                  },
                  child: const Icon(Icons.call, color: Colors.white),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
