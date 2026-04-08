import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/webrtc_service.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});
  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  // Added back the missing foundation variable
  dynamic pendingCall; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Incoming Call...", style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red, size: 40),
                  onPressed: () {
                    ref.read(webRTCServiceProvider).endCall();
                    setState(() => pendingCall = null);
                    Navigator.pop(context);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.green, size: 40),
                  onPressed: () {
                    // Accept logic
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
