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
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  MediaStream? get localStream => _localStream;

  WebRTCService(this._socket) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socket.onCallOffer.listen((data) async {
      _incomingCallCtrl.add(true);
      _callStateController.add(CallState.incoming);
    });

    _socket.onMakeAnswer.listen((data) async {
      final answer = data['answer'];
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
      }
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
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
    });
    
    _pc!.onIceCandidate = (candidate) {
      _socket.sendIceCandidate(userId, candidate);
    };

    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, offer, type);
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    await _localStream?.dispose();
    await _pc?.close();
    _pc = null;
  }

  void toggleAudio() => isAudioMuted = !isAudioMuted;
  void toggleVideo() => isVideoMuted = !isVideoMuted;
  Future<void> toggleSpeaker() async => isLoudspeakerOn = !isLoudspeakerOn;
  Future<void> toggleCamera() async {}
}
