import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/webrtc_service.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/constants.dart';
import '../screen_share.dart';
import '../conference.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.userId,
    this.isVideo = false,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isMicMuted   = false;
  bool _isCamMuted   = false;
  bool _isSpeakerOn  = false;
  bool _isLocalMain  = false;
  bool _isScreenSharing = false;
  late ScreenShareService  _screenShare;
  ConferenceService?       _conference;
  bool _showControls = true;
  String? _callEndReason;
  Offset _thumbnailOffset = const Offset(20, 100);

  int    _seconds      = 0;
  Timer? _timer;
  bool   _timerStarted = false;

  @override
  void initState() {
    super.initState();
    final socket = ref.read(socketServiceProvider);
    final user   = ref.read(currentUserProvider);
    _screenShare = ScreenShareService(socket);
    if (user != null) {
      _conference   = ConferenceService(
        socket:      socket,
        screenShare: _screenShare,
        userId:      user.xameId,
        displayName: user.preferredName ?? user.firstName,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(webRTCServiceProvider);
      service.initRenderers();
      if (!widget.isIncoming) {
        service.startCall(widget.userId, widget.isVideo);
      } else {
        service.joinCall(widget.isVideo);
      }
      service.callState.listen((s) async {
        if (!mounted) return;
        setState(() {});
        if (s == CallState.active && !_timerStarted) _startTimer();
        if (s == CallState.ended && mounted) {
          final webrtc = ref.read(webRTCServiceProvider);
          // Show declined screen only to caller when recipient declines
          if (!widget.isIncoming && !_timerStarted) {
            setState(() => _callEndReason = 'Declined');
          } else {
            setState(() => _callEndReason = 'Call Ended');
          }
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) context.go('/contacts');
        }
      });
      service.remoteStream$.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  void _startTimer() {
    if (_timerStarted) return;
    _timerStarted = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final webrtc   = ref.watch(webRTCServiceProvider);
    final hasRemote = webrtc.remoteRenderer.srcObject != null;
    final contacts  = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact   = contacts.where((c) => c.id == widget.userId).firstOrNull;
    final name      = contact?.name ?? widget.userId;
    final photoUrl  = (contact?.isProfilePicHidden == true) ? null : contact?.profilePic;
    final initials  = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    if (hasRemote && !_timerStarted) _startTimer();

    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    // Show end reason overlay
    if (_callEndReason != null) {
      return _endReasonScreen(_callEndReason!, photoUrl, name, initials);
    }

    return widget.isVideo
        ? _videoUI(webrtc, hasRemote, name, topPad, botPad)
        : _voiceUI(webrtc, name, photoUrl, initials, topPad, botPad);
  }

  // ═══════════════════════════════════════════════════════════
  // VIDEO CALL
  // ═══════════════════════════════════════════════════════════
  Widget _videoUI(WebRTCService webrtc, bool hasRemote, String name,
      double topPad, double botPad) {
    final showLocalFull = !hasRemote || _isLocalMain;

    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: hasRemote
          ? AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                onPressed: _openAddCall,
                backgroundColor: Colors.white24,
                child: const Icon(Icons.person_add_outlined,
                    color: Colors.white, size: 20)))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [

            // ── Main video ──────────────────────────────────────────
            RTCVideoView(
              showLocalFull ? webrtc.localRenderer : webrtc.remoteRenderer,
              mirror: showLocalFull,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),

            // ── Connecting overlay ──────────────────────────────────
            if (!hasRemote)
              Positioned(
                bottom: botPad + 180, left: 0, right: 0,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(
                      color: Colors.white38, strokeWidth: 1.5),
                  const SizedBox(height: 14),
                  Text(
                      widget.isIncoming
                          ? 'Connecting...'
                          : webrtc.isRinging
                              ? 'Ringing...'
                              : 'Calling $name...',
                      style: const TextStyle(color: Colors.white60, fontSize: 15)),
                ]),
              ),

            // ── PiP thumbnail ───────────────────────────────────────
            if (hasRemote)
              Positioned(
                top: _thumbnailOffset.dy,
                right: _thumbnailOffset.dx,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() =>
                      _thumbnailOffset += Offset(-d.delta.dx, d.delta.dy)),
                  onDoubleTap: () =>
                      setState(() => _isLocalMain = !_isLocalMain),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 110, height: 160,
                      child: RTCVideoView(
                        _isLocalMain
                            ? webrtc.remoteRenderer
                            : webrtc.localRenderer,
                        mirror: !_isLocalMain,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Top bar ─────────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.only(
                      top: topPad + 14, left: 16, right: 16, bottom: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xBB000000), Colors.transparent],
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(name,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 18, fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)]))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.circle,
                            color: Color(0xFF4CAF50), size: 8),
                        const SizedBox(width: 6),
                        Text(_fmt(_seconds),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Bottom controls ─────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: EdgeInsets.only(
                      bottom: botPad + 36, left: 20, right: 20, top: 32),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xBB000000), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _vBtn(Icons.mic_off, _isMicMuted, 'Mute', () {
                        setState(() => _isMicMuted = !_isMicMuted);
                        webrtc.localStream?.getAudioTracks()
                            .forEach((t) => t.enabled = !_isMicMuted);
                      }),
                      _vBtn(Icons.videocam_off, _isCamMuted, 'Camera', () {
                        setState(() => _isCamMuted = !_isCamMuted);
                        webrtc.localStream?.getVideoTracks()
                            .forEach((t) => t.enabled = !_isCamMuted);
                      }),
                      _vBtn(Icons.flip_camera_ios, false, 'Flip', () =>
                          webrtc.localStream?.getVideoTracks()[0].switchCamera()),
                      _vBtn(Icons.volume_up, _isSpeakerOn, 'Speaker', () {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        Helper.setSpeakerphoneOn(_isSpeakerOn);
                      }),
                      _vBtn(Icons.screen_share_outlined, _isScreenSharing, "Share", _toggleScreenShare),
                      _endBtn(webrtc),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // VOICE CALL
  // ═══════════════════════════════════════════════════════════
  Widget _voiceUI(WebRTCService webrtc, String name, String? photoUrl,
      String initials, double topPad, double botPad) {

    final callState  = webrtc.callStateStreamValue;
    final isActive   = callState == CallState.active || _timerStarted;
    final statusText = isActive
        ? _fmt(_seconds)
        : callState == CallState.outgoing
            ? (webrtc.isRinging ? 'Ringing...' : 'Calling $name...')
            : 'Connecting...';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Blurred background ──────────────────────────────────
          if (photoUrl != null)
            CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _voiceBg(),
            )
          else
            _voiceBg(),

          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.75),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(children: [
              const Spacer(flex: 2),

              // ── Avatar ───────────────────────────────────────────
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Transform.scale(
                    scale: v, child: Opacity(opacity: v, child: child)),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.15), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 75,
                    backgroundColor: const Color(0xFF30363D),
                    backgroundImage: photoUrl != null
                        ? CachedNetworkImageProvider(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(initials,
                            style: const TextStyle(fontSize: 45,
                                color: Colors.white,
                                fontWeight: FontWeight.bold))
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Name ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 34,
                      fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              ),

              const SizedBox(height: 12),

              // ── Status / timer ────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(statusText,
                  key: ValueKey(statusText),
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF00FF88) : Colors.white54,
                    fontSize: 18,
                    fontWeight: isActive
                        ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // ── Controls ──────────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(
                    left: 40, right: 40, bottom: botPad + 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _voiceBtn(
                      icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                      label: _isMicMuted ? 'Unmute' : 'Mute',
                      active: _isMicMuted,
                      onTap: () {
                        setState(() => _isMicMuted = !_isMicMuted);
                        webrtc.localStream?.getAudioTracks()
                            .forEach((t) => t.enabled = !_isMicMuted);
                      },
                    ),
                    _endBtn(webrtc, size: 76),
                    _voiceBtn(
                      icon: _isSpeakerOn
                          ? Icons.volume_up : Icons.volume_off,
                      label: 'Speaker',
                      active: _isSpeakerOn,
                      onTap: () {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        Helper.setSpeakerphoneOn(_isSpeakerOn);
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════
  Widget _endReasonScreen(String reason, String? photoUrl,
      String name, String initials) {
    final isDeclined = reason == 'Declined';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (photoUrl != null)
          CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _voiceBg())
        else
          _voiceBg(),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(color: Colors.black.withOpacity(0.75)),
        ),
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFF1E2533),
            backgroundImage: photoUrl != null
                ? CachedNetworkImageProvider(photoUrl) : null,
            child: photoUrl == null
                ? Text(initials, style: const TextStyle(
                    fontSize: 32, color: Colors.white,
                    fontWeight: FontWeight.w600))
                : null,
          ),
          const SizedBox(height: 24),
          Text(name, style: const TextStyle(color: Colors.white,
              fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: isDeclined
                  ? Colors.red.withOpacity(0.15)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDeclined
                    ? Colors.red.withOpacity(0.4)
                    : Colors.white24),
            ),
            child: Text(reason,
              style: TextStyle(
                color: isDeclined
                    ? const Color(0xFFFF5252) : Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              )),
          ),
        ])),
      ]),
    );
  }

  Widget _voiceBg() => Container(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter, radius: 1.4,
        colors: [Color(0xFF1A2340), Color(0xFF0D1117), Color(0xFF000000)],
      ),
    ),
  );

  Future<void> _toggleScreenShare() async {
    try {
      await _screenShare.toggle();
      setState(() => _isScreenSharing = _screenShare.isSharing);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Screen share failed: $e")));
    }
  }


  void _openConference() {
    if (_conference == null) return;
    _conference!.create();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConferenceOverlay(service: _conference!),
    );
  }

  void _openAddCall() {
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    final user     = ref.read(currentUserProvider);
    if (user == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddCallSheet(
        contacts:      contacts,
        currentUserId: user.xameId,
        onSelect: (contactId) {
          Navigator.pop(context);
          ref.read(webRTCServiceProvider).startCall(contactId, false);
        },
      ),
    );
  }
  Widget _vBtn(IconData icon, bool active, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: active ? Colors.black : Colors.white, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(
            color: Colors.white60, fontSize: 10)),
      ]),
    );
  }

  Widget _voiceBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 62, height: 62,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white12,
            shape: BoxShape.circle,
            boxShadow: active ? [BoxShadow(
                color: Colors.white.withOpacity(0.2),
                blurRadius: 12, spreadRadius: 2)] : [],
          ),
          child: Icon(icon,
              color: active ? Colors.black : Colors.white, size: 26),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(
            color: Colors.white60, fontSize: 12)),
      ]),
    );
  }

  Widget _endBtn(WebRTCService webrtc, {double size = 62}) {
    return GestureDetector(
      onTap: () { webrtc.endCall(); context.go('/contacts'); },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: Colors.red.withOpacity(0.45),
                blurRadius: 20, spreadRadius: 3)],
          ),
          child: Icon(Icons.call_end, color: Colors.white,
              size: size * 0.48),
        ),
        const SizedBox(height: 8),
        const Text('End', style: TextStyle(
            color: Colors.white60, fontSize: 12)),
      ]),
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
          color: XameColors.darkSurface,
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
                    color: XameColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_outlined,
                      color: XameColors.primary, size: 20),
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
                  color: XameColors.darkCard,
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
                      color: XameColors.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: XameColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                            c.name.isNotEmpty
                                ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: XameColors.primary,
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
                          color: XameColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: XameColors.primary
                                  .withValues(alpha: 0.3)),
                        ),
                        child: const Text('Add',
                            style: TextStyle(color: XameColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
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
