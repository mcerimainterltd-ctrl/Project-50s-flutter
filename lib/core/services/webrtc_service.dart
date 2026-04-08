import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) {
  final socket = ref.watch(webRTCSocketServiceProvider);
  return WebRTCService(socket);
});

class WebRTCService {
  final WebRTCSocketService _socket;
  MediaStream? localStream;
  Map<String, RTCPeerConnection> peers = {};

  // UI Properties restored for app.dart and call_screen.dart
  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isLoudspeakerOn = false;

  final _callStateController = StreamController<CallState>.broadcast();
  final _callTimerController = StreamController<String>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<String> get callTimer => _callTimerController.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;

  WebRTCService(this._socket);

  Map<String, dynamic> configuration = {
    'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
  };

  Future<void> startCall(String remoteUserId, dynamic isVideoInput) async {
    // Fix: Handle both bool and String 'video'/'voice' from the UI
    bool isVideo = isVideoInput == true || isVideoInput == 'video';
    
    _callStateController.add(CallState.outgoing);
    
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
      _callStateController.add(CallState.active);
      await pc.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type'])
      );
    }
  }

  // Restore UI interaction methods
  void toggleAudio() => isAudioMuted = !isAudioMuted;
  void toggleVideo() => isVideoMuted = !isVideoMuted;
  Future<void> toggleSpeaker() async => isLoudspeakerOn = !isLoudspeakerOn;
  Future<void> toggleCamera() async {}

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    localStream?.dispose();
    peers.forEach((key, pc) => pc.dispose());
    peers.clear();
  }
}
