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
  void initState() {
    super.initState();
    // Listen for state changes (Active, Ended, etc.)
    Future.microtask(() {
      ref.read(webRTCServiceProvider).callState.listen((state) {
        if (state == CallState.ended) {
          if (mounted) context.go('/contacts');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    // SYNC: Use the service state instead of a local variable
    final currentState = webrtc.callStateStreamValue; // We will add this getter

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Text(
              currentState == CallState.active ? "Connected" : "Calling...",
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () {
                ref.read(webRTCServiceProvider).endCall();
                context.go('/contacts');
              },
              child: const Icon(Icons.call_end),
            ),
          ),
        ],
      ),
    );
  }
}
