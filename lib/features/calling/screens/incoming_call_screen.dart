import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/webrtc_service.dart';
import '../../contacts/providers/contacts_provider.dart';

class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final userId = webrtc.currentRemoteUserId ?? "";
    final isVideo = webrtc.isIncomingVideo;

    // Resolve Identity from ContactModel
    final contactsAsync = ref.watch(contactsProvider);
    final contact = contactsAsync.valueOrNull?.where((c) => c.id == userId).firstOrNull;

    final String displayName = contact?.name ?? userId;
    final String? profilePic = (contact?.isProfilePicHidden ?? false) ? null : contact?.profilePic;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          // 1. Full Screen Blurred Background
          Positioned.fill(
            child: profilePic != null
                ? CachedNetworkImage(
                    imageUrl: profilePic,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(color: const Color(0xFF161B22)),
                  )
                : Container(color: const Color(0xFF161B22)),
          ),
          
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // 2. Main UI
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                
                // Centered Avatar with Entrance Animation
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: Opacity(opacity: value, child: child));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 75,
                      backgroundColor: const Color(0xFF30363D),
                      backgroundImage: profilePic != null ? CachedNetworkImageProvider(profilePic) : null,
                      child: profilePic == null
                          ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                              style: const TextStyle(fontSize: 45, color: Colors.white, fontWeight: FontWeight.bold))
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                
                // Caller Name / ID
                Text(
                  displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                if (displayName != userId && userId.isNotEmpty)
                  Text(
                    "@$userId",
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                
                const SizedBox(height: 16),
                
                // Pulsing Call Type
                _PulsingCallType(text: "INCOMING ${isVideo ? 'VIDEO' : 'VOICE'} CALL"),

                const Spacer(flex: 3),

                // Control Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildControl(
                        icon: Icons.close,
                        label: "Decline",
                        color: Colors.redAccent,
                        onTap: () {
                          webrtc.rejectCall();
                          context.pop();
                        },
                      ),
                      _buildControl(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        label: "Accept",
                        color: const Color(0xFF00FF88), // XamePage Accent
                        onTap: () {
                          webrtc.joinCall(isVideo);
                          context.push('/call/$userId?video=$isVideo&incoming=true');
                        },
                        isAccept: true,
                      ),
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

  Widget _buildControl({required IconData icon, required String label, required Color color, required VoidCallback onTap, bool isAccept = false}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 75, width: 75,
            decoration: BoxDecoration(
              color: isAccept ? color : color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
              boxShadow: isAccept ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, spreadRadius: 5)] : [],
            ),
            child: Icon(icon, color: isAccept ? Colors.black : Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PulsingCallType extends StatefulWidget {
  final String text;
  const _PulsingCallType({required this.text});
  @override
  State<_PulsingCallType> createState() => _PulsingCallTypeState();
}

class _PulsingCallTypeState extends State<_PulsingCallType> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.2, end: 0.7).animate(_ctrl),
      child: Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 3)),
    );
  }
}
