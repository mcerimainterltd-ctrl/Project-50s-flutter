import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isVideo;
  const CallScreen({super.key, required this.userId, required this.isVideo});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late WebRTCService _webrtc;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _stateSub;
  StreamSubscription? _remoteSub;
  
  Offset _thumbnailOffset = const Offset(20, 60);
  bool _isSwapped = false;
  CallState _status = CallState.outgoing;

  @override
  void initState() {
    super.initState();
    _webrtc = ref.read(webRTCServiceProvider);
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _stateSub = _webrtc.callState.listen((s) => setState(() => _status = s));
    _remoteSub = _webrtc.remoteStream$.listen((s) => setState(() => _remoteRenderer.srcObject = s));
    await _webrtc.startCall(widget.userId, true);
    if (_webrtc.localStream != null) setState(() => _localRenderer.srcObject = _webrtc.localStream);
  }

  @override
  void dispose() {
    _stateSub?.cancel(); _remoteSub?.cancel();
    _localRenderer.dispose(); _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isActive = _status == CallState.active;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            // BACKGROUND VIDEO (Forces Full Screen)
            Positioned.fill(
              child: Container(
                width: size.width,
                height: size.height,
                child: RTCVideoView(
                  (isActive && !_isSwapped) ? _remoteRenderer : _localRenderer,
                  mirror: !(isActive && !_isSwapped),
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

            // DRAGGABLE THUMBNAIL
            if (isActive)
              Positioned(
                left: _thumbnailOffset.dx,
                top: _thumbnailOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _thumbnailOffset += d.delta),
                  onDoubleTap: () => setState(() => _isSwapped = !_isSwapped),
                  child: Container(
                    width: 120, height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RTCVideoView(
                        _isSwapped ? _remoteRenderer : _localRenderer,
                        mirror: !_isSwapped,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),

            // UI CONTROLS
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Column(
                children: [
                  if (!isActive) Text(widget.userId, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () { _webrtc.endCall(); context.go('/contacts'); },
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
