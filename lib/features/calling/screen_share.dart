import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xamepage/core/services/socket_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────
class ScreenShareService {
  final SocketService _socket;

  // peerId → RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};

  MediaStream? _stream;
  MediaStreamTrack? _originalVideoTrack;
  bool _isSharing = false;
  bool _isPaused  = false;

  final List<VoidCallback> _onStopCallbacks = [];

  // Notifier for UI banner
  final ValueNotifier<ScreenShareState> state =
      ValueNotifier(ScreenShareState.idle);

  ScreenShareService(this._socket);

  bool get isSharing => _isSharing;

  // ── Platform support check ────────────────────────────────────────────────
  static ScreenShareSupport checkSupport() {
    // flutter_webrtc supports getDisplayMedia on Android and desktop
    // iOS does not support getDisplayMedia
    return const ScreenShareSupport(
      supported: true, // checked at runtime via try/catch
      reason: null,
    );
  }

  // ── Peer connection management ────────────────────────────────────────────
  void addPeerConnection(String peerId, RTCPeerConnection pc) {
    _peerConnections[peerId] = pc;
    // If already sharing, push screen track to new peer immediately
    if (_isSharing) {
      final screenTrack = _stream?.getVideoTracks().firstOrNull;
      if (screenTrack != null) {
        _replaceTrackForPeer(pc, screenTrack);
      }
    }
  }

  void removePeerConnection(String peerId) {
    _peerConnections.remove(peerId);
  }

  void setCameraTrack(MediaStreamTrack? track) {
    if (track != null) _originalVideoTrack = track;
  }

  void onStop(VoidCallback fn) => _onStopCallbacks.add(fn);

  // ── Start screen share ────────────────────────────────────────────────────
  Future<void> start() async {
    if (_isSharing) await stop();

    try {
      _stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'cursor': 'always',
          'width':  {'max': 1920},
          'height': {'max': 1080},
          'frameRate': {'max': 30},
        },
        'audio': false,
      });

      _isSharing = true;
      _isPaused  = false;

      final screenTrack = _stream!.getVideoTracks().firstOrNull;
      if (screenTrack != null) {
        await _replaceAllPeers(screenTrack);
        // Handle native "Stop sharing" button
        screenTrack.onEnded = () => stop();
      }

      _socket.emit('screen-share:started', null);
      state.value = ScreenShareState.sharing;
    } catch (e) {
      debugPrint('[ScreenShare] Start error: $e');
      await stop();
      rethrow;
    }
  }

  // ── Stop screen share ─────────────────────────────────────────────────────
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

  // ── Pause / Resume ────────────────────────────────────────────────────────
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

  // ── Toggle ────────────────────────────────────────────────────────────────
  Future<void> toggle() async {
    if (_isSharing) {
      await stop();
    } else {
      await start();
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────
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
          await sender.replaceTrack(track);
          break;
        }
      }
    } catch (e) {
      debugPrint('[ScreenShare] replaceTrack error: $e');
    }
  }

  void dispose() {
    stop();
    state.dispose();
  }
}

// ── Support info ──────────────────────────────────────────────────────────────
class ScreenShareSupport {
  final bool supported;
  final String? reason;
  const ScreenShareSupport({required this.supported, this.reason});
}

enum ScreenShareState { idle, sharing, paused }

// ── Presentation Banner Widget ────────────────────────────────────────────────
class ScreenShareBanner extends StatelessWidget {
  final ScreenShareService service;

  const ScreenShareBanner({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScreenShareState>(
      valueListenable: service.state,
      builder: (_, state, __) {
        if (state == ScreenShareState.idle) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.shade700,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state == ScreenShareState.paused
                          ? 'Paused – Screen Share'
                          : 'You are presenting',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (state == ScreenShareState.paused) {
                        service.resume();
                      } else {
                        service.pause();
                      }
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(state == ScreenShareState.paused
                        ? 'Resume' : 'Pause'),
                  ),
                  TextButton(
                    onPressed: () => service.stop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Stop Sharing'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
