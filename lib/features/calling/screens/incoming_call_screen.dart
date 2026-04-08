import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  @override
  Widget build(BuildContext context) {
    final pending = pendingCall;
    if (pending == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/contacts'));
      return const SizedBox.shrink();
    }
    final isVideo = pending.callType == 'video';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 55, child: Text(pending.callerId[0])),
            const SizedBox(height: 20),
            Text(pending.callerId, style: const TextStyle(color: Colors.white, fontSize: 28)),
            const SizedBox(height: 8),
            Text('Incoming ${isVideo ? 'video' : 'voice'} call...', style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    ref.read(webRTCServiceProvider).handleIncomingCall(pending.offer, pending.callerId, isVideo: isVideo);
                    pendingCall = null;
                    context.go('/call/${pending.callerId}?video=$isVideo');
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.call, color: Colors.white),
                ),
                FloatingActionButton(
                  onPressed: () {
                    ref.read(webRTCServiceProvider).endCall();
                    pendingCall = null;
                    context.go('/contacts');
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
