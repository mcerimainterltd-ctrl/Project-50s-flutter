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
  MediaStream? localStream;
  
  final _callStateController = StreamController<CallState>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<String> get callTimer => Stream.periodic(const Duration(seconds: 1), (i) => "00:${i.toString().padLeft(2, '0')}");

  WebRTCService(this._socket) {
    _listenToSocket();
  }

  void _listenToSocket() {
    _socket.onCallOffer.listen((data) {
      _incomingCallCtrl.add(true);
      _callStateController.add(CallState.incoming);
    });

    _socket.onMakeAnswer.listen((data) async {
      if (_pc != null) {
        var answer = data['answer'];
        await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
        _callStateController.add(CallState.active);
      }
    });

    _socket.onIceCandidate.listen((data) {
      if (_pc != null) {
        var cand = data['candidate'];
        _pc!.addCandidate(RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']));
      }
    });
  }

  Future<void> startCall(String userId, dynamic type) async {
    _callStateController.add(CallState.outgoing);
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    
    _pc!.onIceCandidate = (candidate) => _socket.sendIceCandidate(userId, candidate);
    _pc!.onTrack = (event) => _remoteStreamController.add(event.streams[0]);

    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': type == 'video'});
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));

    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, offer, type.toString());
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    await _pc?.close();
    _pc = null;
  }

  // UI Stubs to keep build stable
  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isLoudspeakerOn = false;
  void toggleAudio() {}
  void toggleVideo() {}
  Future<void> toggleSpeaker() async {}
  Future<void> toggleCamera() async {}
}
