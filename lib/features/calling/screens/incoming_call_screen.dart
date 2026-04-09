import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/theme/app_theme.dart';

class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final userId = webrtc.currentRemoteUserId ?? "Unknown User";

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient/Image
          Container(color: const Color(0xFF1A1A1A)),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: XameColors.primary.withOpacity(0.2),
                        child: Text(userId[0].toUpperCase(), 
                          style: const TextStyle(fontSize: 40, color: Colors.white)),
                      ),
                      const SizedBox(height: 24),
                      Text(userId, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      const Text("Incoming Video Call...", style: TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionBtn(icon: Icons.call_end, color: Colors.red, label: "Decline", 
                        onTap: () { webrtc.endCall(); context.go('/contacts'); }),
                      _ActionBtn(icon: Icons.videocam, color: Colors.green, label: "Answer", 
                        onTap: () => context.push('/call/$userId?video=true')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 75, height: 75,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: 35),
        ),
      ),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
    ],
  );
}
