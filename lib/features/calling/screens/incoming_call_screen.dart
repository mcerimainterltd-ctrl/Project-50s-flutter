import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' show ModalRoute;
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
  StreamSubscription? _stateSub;
  Timer? _timeoutTimer;

  bool _isPopping = false;

  void _safePop() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    ref.read(webRTCServiceProvider).clearIncomingCall();
    context.go('/contacts');
  }

  @override
  void initState() {
    super.initState();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && args.containsKey('offer')) {
      final webrtc = ref.read(webRTCServiceProvider);
      webrtc.setIncomingCall(args['callerId'], args['offer'], args['callType'] ?? 'voice');
    }
    final socket = ref.read(socketServiceProvider);
    final webrtcSvc = ref.read(webRTCServiceProvider);
    _stateSub = webrtcSvc.callState.listen((state) {
      if (!mounted || _isPopping) return;
      if (state == CallState.ended) {
        _safePop();
      }
    });
    _endedSub = socket.callEnded.listen((_) {
      // Caller ended before recipient answered — record as missed
      final webrtc = ref.read(webRTCServiceProvider);
      final callerId = webrtc.currentRemoteUserId;
      if (callerId != null) {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final callId = ref.read(webRTCServiceProvider).currentCallId;
          socket.emit('call-unanswered', {
            'recipientId': user.xameId,
            'callerId':    callerId,
            'callId':      callId ?? '',
          });
        }
      }
      _safePop();
    });
    _timeoutTimer = Timer(Duration(seconds: 60), () {
      if (mounted) {
        ref.read(webRTCServiceProvider).rejectCall();
        _safePop();
      }
    });
  }

  @override
  void dispose() {
    _endedSub?.cancel();
    _stateSub?.cancel();
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
      backgroundColor: context.xBg,
      body: Stack(
        children: [
          // 1. Full Screen Blurred Background
          Positioned.fill(
            child: profilePic != null
                ? CachedNetworkImage(
                    imageUrl: profilePic,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(color: context.xSurface),
                  )
                : Container(color: context.xSurface),
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
                Spacer(flex: 2),
                
                // Centered Avatar with Entrance Animation
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: Opacity(opacity: value, child: child));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: context.xText.withOpacity(0.15), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 75,
                      backgroundColor: context.xCard,
                      backgroundImage: profilePic != null ? CachedNetworkImageProvider(profilePic) : null,
                      child: profilePic == null
                          ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                              style: TextStyle(fontSize: 45, color: context.xText, fontWeight: FontWeight.bold))
                          : null,
                    ),
                  ),
                ),

                SizedBox(height: 32),
                
                // Caller Name / ID
                Text(
                  displayName,
                  style: TextStyle(color: context.xText, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                if (displayName != userId && userId.isNotEmpty)
                  Text(
                    "@$userId",
                    style: TextStyle(color: context.xText.withOpacity(0.4), fontSize: 16, fontWeight: FontWeight.w500),
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
                          _safePop();
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
                            _safePop();
                          },
                        ),
                      ),

                      _buildControl(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        label: "Accept",
                        color: context.xAccent,
                        onTap: () async {
                          if (_isPopping) return;
                          _isPopping = true;
                          await webrtc.joinCall(isVideo);
                          if (!mounted) return;
                          context.pushReplacement('/call/$userId?video=$isVideo&incoming=true');
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
            child: Icon(icon, color: isAccept ? Colors.black : XameColors.darkBg, size: 32),
          ),
        ),
        SizedBox(height: 12),
        Text(label, style: TextStyle(color: XameColors.darkBg.withValues(alpha: 0.54), fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PulsingCallType extends StatefulWidget {
  final String text;
  _PulsingCallType({required this.text});
  @override
  State<_PulsingCallType> createState() => _PulsingCallTypeState();
}

class _PulsingCallTypeState extends State<_PulsingCallType> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
