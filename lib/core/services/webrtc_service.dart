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
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  
  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isLoudspeakerOn = false;

  final _callStateController = StreamController<CallState>.broadcast();
  final _callTimerController = StreamController<String>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();

  // Explicitly defined Getters for the UI
  Stream<CallState> get callState => _callStateController.stream;
  Stream<String> get callTimer => _callTimerController.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  MediaStream? get localStream => _localStream;

  WebRTCService(this._socket) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socket.onCallOffer.listen((data) {
      _incomingCallCtrl.add(true);
      _callStateController.add(CallState.incoming);
    });
    
    _socket.onIceCandidate.listen((data) {
      final candidate = data['candidate'];
      if (_pc != null && candidate != null) {
        _pc!.addCandidate(RTCIceCandidate(
          candidate['candidate'], candidate['sdpMid'], candidate['sdpMLineIndex'],
        ));
      }
    });
  }

  Future<void> startCall(String userId, String type) async {
    _callStateController.add(CallState.outgoing);
  }

  Future<void> handleIncomingCall(dynamic offer, String callerId, {bool isVideo = false}) async {
    _callStateController.add(CallState.active);
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    _pc?.close();
    _pc = null;
  }

  void toggleAudio() => isAudioMuted = !isAudioMuted;
  void toggleVideo() => isVideoMuted = !isVideoMuted;
  Future<void> toggleSpeaker() async => isLoudspeakerOn = !isLoudspeakerOn;
  Future<void> toggleCamera() async {}
}
