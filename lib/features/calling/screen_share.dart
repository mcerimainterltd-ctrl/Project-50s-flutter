import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Service ───────────────────────────────────────────────────────────────────
class ScreenShareService {
  final SocketService _socket;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _stream;
  MediaStreamTrack? _originalVideoTrack;
  bool _isSharing = false;
  bool _isPaused  = false;
  final List<VoidCallback> _onStopCallbacks = [];
  final ValueNotifier<ScreenShareState> state =
      ValueNotifier(ScreenShareState.idle);

  ScreenShareService(this._socket);

  bool get isSharing => _isSharing;

  void addPeerConnection(String peerId, RTCPeerConnection pc) {
    _peerConnections[peerId] = pc;
    if (_isSharing) {
      final screenTrack = _stream?.getVideoTracks().firstOrNull;
      if (screenTrack != null) _replaceTrackForPeer(pc, screenTrack);
    }
  }

  void removePeerConnection(String peerId) =>
      _peerConnections.remove(peerId);

  void setCameraTrack(MediaStreamTrack? track) {
    if (track != null) _originalVideoTrack = track;
  }

  void onStop(VoidCallback fn) => _onStopCallbacks.add(fn);

  Future<void> start() async {
    if (_isSharing) await stop();
    try {
      _stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {'cursor': 'always', 'width': {'max': 1920},
            'height': {'max': 1080}, 'frameRate': {'max': 30}},
        'audio': false,
      });
      _isSharing = true;
      _isPaused  = false;
      final screenTrack = _stream!.getVideoTracks().firstOrNull;
      if (screenTrack != null) {
        await _replaceAllPeers(screenTrack);
        screenTrack.onEnded = () => stop();
      }
      _socket.emit('screen-share:started', null);
      state.value = ScreenShareState.sharing;
    } catch (e) {
      debugPrint('[ScreenShare] Start error: $e');
      await stop(); rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isSharing) return;
    _stream?.getTracks().forEach((t) => t.stop());
    _stream    = null;
    _isSharing = false;
    _isPaused  = false;
    if (_originalVideoTrack != null) {
      await _replaceAllPeers(_originalVideoTrack!);
      _originalVideoTrack = null;
    }
    _socket.emit('screen-share:stopped', null);
    state.value = ScreenShareState.idle;
    for (final fn in _onStopCallbacks) { fn(); }
  }

  void pause() {
    if (!_isSharing || _isPaused) return;
    _isPaused = true;
    _stream?.getVideoTracks().forEach((t) => t.enabled = false);
    _socket.emit('screen-share:paused', null);
    state.value = ScreenShareState.paused;
  }

  void resume() {
    if (!_isSharing || !_isPaused) return;
    _isPaused = false;
    _stream?.getVideoTracks().forEach((t) => t.enabled = true);
    _socket.emit('screen-share:resumed', null);
    state.value = ScreenShareState.sharing;
  }

  Future<void> toggle() async =>
      _isSharing ? await stop() : await start();

  Future<void> _replaceAllPeers(MediaStreamTrack track) async {
    for (final pc in _peerConnections.values) {
      await _replaceTrackForPeer(pc, track);
    }
  }

  Future<void> _replaceTrackForPeer(
      RTCPeerConnection pc, MediaStreamTrack track) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(track); break;
        }
      }
    } catch (e) { debugPrint('[ScreenShare] replaceTrack error: $e'); }
  }

  void dispose() { stop(); state.dispose(); }
}

enum ScreenShareState { idle, sharing, paused }

// ── Presentation Banner ───────────────────────────────────────────────────────
class ScreenShareBanner extends StatelessWidget {
  final ScreenShareService service;
  ScreenShareBanner({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScreenShareState>(
      valueListenable: service.state,
      builder: (_, state, __) {
        if (state == ScreenShareState.idle) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.xSurface,
            border: Border(
                bottom: BorderSide(color: context.xMuted.withValues(alpha: 0.1))),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              // Live indicator
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: state == ScreenShareState.paused
                      ? Colors.orange : context.xAccent,
                  shape: BoxShape.circle,
                  boxShadow: state == ScreenShareState.sharing ? [
                    BoxShadow(color: context.xAccent.withValues(alpha: 0.5),
                        blurRadius: 6),
                  ] : null,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  state == ScreenShareState.paused
                      ? 'Screen share paused'
                      : 'You are presenting',
                  style: TextStyle(color: context.xText, fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
              // Pause/Resume
              GestureDetector(
                onTap: () => state == ScreenShareState.paused
                    ? service.resume() : service.pause(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.xText.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    state == ScreenShareState.paused ? 'Resume' : 'Pause',
                    style: TextStyle(color: context.xText.withValues(alpha: 0.7),
                        fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              SizedBox(width: 8),
              // Stop
              GestureDetector(
                onTap: () => service.stop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.xDanger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: context.xDanger.withValues(alpha: 0.3)),
                  ),
                  child: Text('Stop',
                      style: TextStyle(color: context.xDanger,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
