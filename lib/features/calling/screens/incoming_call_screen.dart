import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/services/auth_service.dart';
import '../../contacts/providers/contacts_provider.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});
  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _pulse;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webrtc   = ref.watch(webRTCServiceProvider);
    final callerId = webrtc.currentRemoteUserId ?? "";
    final isVideo  = webrtc.isIncomingVideo;
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final self     = ref.read(currentUserProvider);

    // Resolve caller info — saved contact name takes priority over xameId
    final contact  = contacts.where((c) => c.id == callerId).firstOrNull;
    final name     = contact?.name ?? callerId;
    final photoUrl = (contact?.isProfilePicHidden == true) ? null : contact?.profilePic;
    final initials = name.trim().isEmpty ? "?"
        : name.trim().split(" ").take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : "").join();

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Background: blurred avatar or gradient ──────────────────
          if (photoUrl != null)
            Image.network(photoUrl, fit: BoxFit.cover, width: size.width, height: size.height,
              errorBuilder: (_, __, ___) => _gradientBg())
          else
            _gradientBg(),

          // Dark blur overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),

          // ── Content ────────────────────────────────────────────────
          SlideTransition(
            position: _slideUp,
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Call type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isVideo ? Icons.videocam : Icons.call,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(isVideo ? "Incoming Video Call" : "Incoming Voice Call",
                        style: const TextStyle(color: Colors.white70, fontSize: 13,
                            letterSpacing: 0.5)),
                  ]),
                ),

                const SizedBox(height: 36),

                // ── Pulsing avatar ─────────────────────────────────
                ScaleTransition(
                  scale: _pulse,
                  child: Stack(alignment: Alignment.center, children: [
                    // Outer glow ring
                    Container(
                      width: 148, height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.white.withOpacity(0.08),
                              blurRadius: 30, spreadRadius: 10),
                        ],
                      ),
                    ),
                    // Avatar
                    Container(
                      width: 128, height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.4),
                              blurRadius: 20, spreadRadius: 4),
                        ],
                      ),
                      child: ClipOval(
                        child: photoUrl != null
                          ? Image.network(photoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _initialsWidget(initials))
                          : _initialsWidget(initials),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 28),

                // Caller name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                    ),
                  ),
                ),

                // XameID subtitle if name differs
                if (name != callerId) ...[
                  const SizedBox(height: 6),
                  Text("@\$callerId",
                    style: TextStyle(color: Colors.white.withOpacity(0.5),
                        fontSize: 14, letterSpacing: 0.3)),
                ],

                const Spacer(flex: 3),

                // ── Action buttons ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [

                      // Decline
                      _ActionButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFE53935),
                        label: "Decline",
                        onTap: () {
                          webrtc.rejectCall();
                          context.pop();
                        },
                      ),

                      // Accept
                      _ActionButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        color: const Color(0xFF43A047),
                        label: "Accept",
                        onTap: () async {
                          await webrtc.joinCall(isVideo);
                          if (context.mounted) {
                            context.push('/call/\$callerId?video=\${isVideo ? 'true' : 'false'}&incoming=true');
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 64),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientBg() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D1117), Color(0xFF1A1F2E), Color(0xFF0D1117)],
      ),
    ),
  );

  Widget _initialsWidget(String initials) => Container(
    color: const Color(0xFF1E2533),
    child: Center(
      child: Text(initials,
        style: const TextStyle(color: Colors.white, fontSize: 44,
            fontWeight: FontWeight.w600)),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon, required this.color,
    required this.label, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5),
                    blurRadius: 20, spreadRadius: 4),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70,
            fontSize: 13, letterSpacing: 0.3)),
      ],
    );
  }
}
