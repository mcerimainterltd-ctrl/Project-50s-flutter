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
  RTCPeerConnection? _pc;
  
  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isLoudspeakerOn = false;

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<String> get callTimer => Stream.periodic(const Duration(seconds: 1), (i) => "00:${i.toString().padLeft(2, '0')}");

  WebRTCService(this._socket) {
    _listenToSocket();
  }

  void _listenToSocket() {
    // THIS activates the notification pop-up
    _socket.onCallOffer.listen((data) {
      _incomingCallCtrl.add(true);
      _callStateController.add(CallState.incoming);
    });
  }

  Future<void> startCall(String remoteUserId, dynamic isVideoInput) async {
    bool isVideo = isVideoInput == true || isVideoInput == 'video';
    _callStateController.add(CallState.outgoing);
    
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    });
    
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));
    
    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(remoteUserId, offer, isVideo ? 'video' : 'voice');
  }

  void toggleAudio() => isAudioMuted = !isAudioMuted;
  void toggleVideo() => isVideoMuted = !isVideoMuted;
  Future<void> toggleSpeaker() async => isLoudspeakerOn = !isLoudspeakerOn;
  Future<void> toggleCamera() async {}

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    await localStream?.dispose();
    await _pc?.close();
    _pc = null;
  }
}
