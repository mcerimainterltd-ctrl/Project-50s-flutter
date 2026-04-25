import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/services/socket_service.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/models/xame_user.dart';
import '../../messaging/sms_templates.dart';
import '../../../core/theme/app_theme.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});
  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  StreamSubscription? _endedSub;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    final socket = ref.read(socketServiceProvider);
    _endedSub = socket.callEnded.listen((_) {
      if (mounted) context.pop();
    });
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        ref.read(webRTCServiceProvider).rejectCall();
        context.pop();
      }
    });
  }

  @override
  void dispose() {
    _endedSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webrtc = ref.watch(webRTCServiceProvider);
    final userId = webrtc.currentRemoteUserId ?? "";
    final isVideo = webrtc.isIncomingVideo;

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
                        icon: Icons.message_outlined,
                        label: "Reply",
                        color: Colors.blueAccent,
                        onTap: () => QuickReplySheet.show(
                          context,
                          callerId:      userId,
                          socket:        ref.read(socketServiceProvider),
                          currentUserId: ref.read(currentUserProvider)?.xameId ?? "",
                          onDecline: () {
                            webrtc.rejectCall();
                            context.pop();
                          },
                        ),
                      ),

                      _buildControl(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        label: "Accept",
                        color: const Color(0xFF00FF88), // XamePage Accent
                        onTap: () {
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

// ── Add Call Sheet ────────────────────────────────────────────────────────────
class _AddCallSheet extends StatefulWidget {
  final List<ContactModel> contacts;
  final String currentUserId;
  final void Function(String contactId) onSelect;

  const _AddCallSheet({required this.contacts, required this.currentUserId,
      required this.onSelect});

  @override
  State<_AddCallSheet> createState() => _AddCallSheetState();
}

class _AddCallSheetState extends State<_AddCallSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contacts
        .where((c) => c.id != widget.currentUserId)
        .where((c) => _search.isEmpty ||
            c.name.toLowerCase().contains(_search.toLowerCase()) ||
            c.id.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: context.xPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_outlined,
                      color: context.xPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Add to Call', style: TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Select a contact to add',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ]),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: Colors.white30),
                    prefixIcon: Icon(Icons.search,
                        color: Colors.white30, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = filtered[i];
                return GestureDetector(
                  onTap: () => widget.onSelect(c.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.xCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: context.xPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: context.xPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(
                              color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                          Text(c.id, style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                        ],
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.xPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.xPrimary
                              .withValues(alpha: 0.3)),
                        ),
                        child: const Text('Add',
                            style: TextStyle(color: context.xPrimary,
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
