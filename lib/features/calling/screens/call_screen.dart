import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/services/auth_service.dart';
import '../../contacts/providers/contacts_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  final bool isIncoming;

  const CallScreen({super.key, required this.userId,
      this.isVideo = false, this.isIncoming = false});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {

  Timer? _timer;
  StreamSubscription? _callStateSub;
  StreamSubscription? _remoteStreamSub;
  int _seconds = 0;
  bool _isMicMuted   = false;
  bool _isCamMuted   = false;
  bool _isSpeakerOn  = false;
  bool _isLocalMain  = false;
  bool _showControls = true;
  Timer? _controlsTimer;
  Offset _thumbnailOffset = const Offset(16, 60);

  // Voice call animations
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;
  late Animation<double> _pulse;
  late Animation<double> _wave;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _waveCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 3))..repeat();
    _wave = Tween<double>(begin: 0, end: 1).animate(_waveCtrl);

    Future.microtask(() {
      final service = ref.read(webRTCServiceProvider);
      if (!widget.isIncoming) {
        service.startCall(widget.userId, widget.isVideo);
      } else {
        // Incoming — joinCall already called from IncomingCallScreen
        // Just subscribe to state
      }
      _callStateSub = service.callState.listen((s) {
        if (!mounted) return;
        setState(() {});
        if (s == CallState.active && _timer == null) _startTimer();
        if (s == CallState.ended && mounted) context.go('/contacts');
      });
      _remoteStreamSub = service.remoteStream$.listen((_) {
        if (mounted) setState(() {});
      });
    });

    _resetControlsTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.isVideo) setState(() => _showControls = false);
    });
  }

  String _formatDuration(int s) =>
      "${(s ~/ 3600).toString().padLeft(2, '0')}:"
      "${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:"
      "${(s % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _timer?.cancel();
    _callStateSub?.cancel();
    _remoteStreamSub?.cancel();
    _controlsTimer?.cancel();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webrtc    = ref.read(webRTCServiceProvider);
    final hasRemote = webrtc.remoteRenderer.srcObject != null;
    final contacts  = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact   = contacts.where((c) => c.id == widget.userId).firstOrNull;
    final name      = contact?.name ?? widget.userId;
    final photoUrl  = (contact?.isProfilePicHidden == true) ? null : contact?.profilePic;
    final initials  = name.trim().split(" ").take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : "").join();
    final callState = webrtc.callStateStreamValue;

    return widget.isVideo
        ? _buildVideoCall(webrtc, hasRemote, name)
        : _buildVoiceCall(webrtc, name, photoUrl, initials, callState);
  }

  // ─────────────────────────────────────────────
  // VIDEO CALL UI
  // ─────────────────────────────────────────────
  Widget _buildVideoCall(WebRTCService webrtc, bool hasRemote, String name) {
    final showLocalFull = !hasRemote || _isLocalMain;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetControlsTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [

            // Main video feed
            // Always show local video as background while connecting
            RTCVideoView(
              hasRemote && !showLocalFull
                  ? webrtc.remoteRenderer
                  : webrtc.localRenderer,
              mirror: !hasRemote || showLocalFull,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            // Connecting overlay when no remote yet
            if (!hasRemote)
              Container(
                color: Colors.black.withOpacity(0.35),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 200),
                    const CircularProgressIndicator(
                        color: Colors.white38, strokeWidth: 1.5),
                    const SizedBox(height: 16),
                    Text("Waiting for \$name...",
                      style: const TextStyle(color: Colors.white54, fontSize: 15)),
                  ]),
                ),
              ),

            // PiP thumbnail
            if (hasRemote)
              Positioned(
                top: _thumbnailOffset.dy,
                right: _thumbnailOffset.dx,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() =>
                      _thumbnailOffset += Offset(-d.delta.dx, d.delta.dy)),
                  onDoubleTap: () => setState(() => _isLocalMain = !_isLocalMain),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 100, height: 144,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white38, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: RTCVideoView(
                        _isLocalMain ? webrtc.remoteRenderer : webrtc.localRenderer,
                        mirror: !_isLocalMain,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),

            // Top bar — timer + name
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 16, right: 16, bottom: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.45), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      // Timer top right
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, color: Color(0xFF4CAF50),
                                size: 8),
                            const SizedBox(width: 6),
                            Text(_formatDuration(_seconds),
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 14,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom controls
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 32,
                      left: 24, right: 24, top: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.45), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _videoBtn(Icons.mic_off, _isMicMuted, "Mute", () {
                        setState(() => _isMicMuted = !_isMicMuted);
                        webrtc.localStream?.getAudioTracks()
                            .forEach((t) => t.enabled = !_isMicMuted);
                      }),
                      _videoBtn(Icons.videocam_off, _isCamMuted, "Camera", () {
                        setState(() => _isCamMuted = !_isCamMuted);
                        webrtc.localStream?.getVideoTracks()
                            .forEach((t) => t.enabled = !_isCamMuted);
                      }),
                      _videoBtn(Icons.flip_camera_ios, false, "Flip", () =>
                          webrtc.localStream?.getVideoTracks()[0].switchCamera()),
                      _videoBtn(Icons.volume_up, _isSpeakerOn, "Speaker", () {
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                        Helper.setSpeakerphoneOn(_isSpeakerOn);
                      }),
                      // End call
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              webrtc.endCall();
                              context.go('/contacts');
                            },
                            child: Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 16, spreadRadius: 2)],
                              ),
                              child: const Icon(Icons.call_end,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text("End", style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                        ],
                      ),
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

  Widget _videoWaiting(String name) => Container(
    color: const Color(0xFF0D1117),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5),
        const SizedBox(height: 20),
        Text("Waiting for $name...",
          style: const TextStyle(color: Colors.white54, fontSize: 16)),
      ]),
    ),
  );

  Widget _videoBtn(IconData icon, bool active, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // VOICE CALL UI — Award winning
  // ─────────────────────────────────────────────
  Widget _buildVoiceCall(WebRTCService webrtc, String name,
      String? photoUrl, String initials, CallState callState) {

    final isActive  = callState == CallState.active;
    final isRinging = callState == CallState.outgoing || callState == CallState.incoming;
    final statusText = isActive ? _formatDuration(_seconds)
        : isRinging ? "Ringing..."
        : "Connecting...";

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // Blurred background
          if (photoUrl != null)
            Image.network(photoUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _voiceGradient())
          else
            _voiceGradient(),

          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),

          // Animated sound waves (when active)
          if (isActive)
            AnimatedBuilder(
              animation: _wave,
              builder: (_, __) => CustomPaint(
                painter: _WavePainter(_wave.value),
              ),
            ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Avatar with pulse
                ScaleTransition(
                  scale: _pulse,
                  child: Stack(alignment: Alignment.center, children: [
                    // Outer ring glow
                    if (isActive || isRinging)
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          width: 160 + (_pulseCtrl.value * 20),
                          height: 160 + (_pulseCtrl.value * 20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                  0.15 * (1 - _pulseCtrl.value)),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(
                            color: Colors.white.withOpacity(0.15),
                            blurRadius: 30, spreadRadius: 5)],
                      ),
                      child: ClipOval(
                        child: photoUrl != null
                          ? Image.network(photoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _initialsBox(initials))
                          : _initialsBox(initials),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 32),

                // Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 16)],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Status / timer
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(statusText,
                    key: ValueKey(statusText),
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF4CAF50)
                          : Colors.white54,
                      fontSize: 18,
                      fontWeight: isActive
                          ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // Controls row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _voiceBtn(
                        icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                        label: _isMicMuted ? "Unmute" : "Mute",
                        active: _isMicMuted,
                        onTap: () {
                          setState(() => _isMicMuted = !_isMicMuted);
                          webrtc.localStream?.getAudioTracks()
                              .forEach((t) => t.enabled = !_isMicMuted);
                        },
                      ),
                      // End call — centre, larger
                      GestureDetector(
                        onTap: () { webrtc.endCall(); context.go('/contacts'); },
                        child: Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: Colors.red.withOpacity(0.5),
                                blurRadius: 24, spreadRadius: 4)],
                          ),
                          child: const Icon(Icons.call_end,
                              color: Colors.white, size: 34),
                        ),
                      ),
                      _voiceBtn(
                        icon: _isSpeakerOn
                            ? Icons.volume_up : Icons.volume_down,
                        label: "Speaker",
                        active: _isSpeakerOn,
                        onTap: () {
                          setState(() => _isSpeakerOn = !_isSpeakerOn);
                          Helper.setSpeakerphoneOn(_isSpeakerOn);
                        },
                      ),
                    ],
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceGradient() => Container(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter,
        radius: 1.5,
        colors: [Color(0xFF1A2340), Color(0xFF0D1117), Color(0xFF000000)],
      ),
    ),
  );

  Widget _initialsBox(String initials) => Container(
    color: const Color(0xFF1E2533),
    child: Center(child: Text(initials,
      style: const TextStyle(color: Colors.white,
          fontSize: 52, fontWeight: FontWeight.w600))),
  );

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
          width: 60, height: 60,
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
}

// ── Sound wave painter for active voice calls ──────────────────────────────
class _WavePainter extends CustomPainter {
  final double progress;
  _WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5;

    for (int i = 1; i <= 4; i++) {
      final radius = 80.0 + i * 40 + (progress * 30);
      final opacity = (1.0 - (i / 5) - progress * 0.3).clamp(0.0, 1.0);
      paint.color = Colors.white.withOpacity(opacity * 0.25);
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
