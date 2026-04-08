import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

// 1. Restore the Provider so app.dart can find this class
final webRTCServiceProvider = Provider((ref) {
  final socket = ref.watch(webRTCSocketServiceProvider);
  return WebRTCService(socket);
});

enum CallState { idle, outgoing, incoming, active, ended }

class WebRTCService {
  final WebRTCSocketService _socket;
  MediaStream? localStream;
  Map<String, RTCPeerConnection> peers = {};

  // 2. Restore UI Controllers so the screens don't crash
  final _callTimerController = StreamController<String>.broadcast();
  Stream<String> get callTimer => _callTimerController.stream;

  WebRTCService(this._socket);

  Map<String, dynamic> configuration = {
    'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
  };

  Future<void> startCall(String remoteUserId, bool isVideo) async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };

    localStream = await navigator.mediaDevices.getUserMedia(constraints);
    RTCPeerConnection pc = await createPeerConnection(configuration);
    peers[remoteUserId] = pc;

    localStream!.getTracks().forEach((track) {
      pc.addTrack(track, localStream!);
    });

    RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    _socket.sendCallOffer(remoteUserId, offer, isVideo ? 'video' : 'voice');
  }

  Future<void> handleAnswer(String remoteUserId, dynamic answer) async {
    var pc = peers[remoteUserId];
    if (pc != null) {
      await pc.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type'])
      );
    }
  }

  // Added missing UI methods to prevent 'Undefined method' errors
  void toggleAudio() {}
  void toggleVideo() {}
  Future<void> toggleSpeaker() async {}
  Future<void> toggleCamera() async {}

  void endCall() {
    localStream?.dispose();
    peers.forEach((key, pc) => pc.dispose());
    peers.clear();
  }
}
