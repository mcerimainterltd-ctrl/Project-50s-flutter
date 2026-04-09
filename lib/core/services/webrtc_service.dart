import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';
import 'socket_service.dart';

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) {
  final socket = ref.watch(webRTCSocketServiceProvider);
  return WebRTCService(socket);
});

class WebRTCService {
  final WebRTCSocketService _socket;
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  String? _currentRemoteUserId;
  
  String? get currentRemoteUserId => _currentRemoteUserId;

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
      _currentRemoteUserId = data.callerId;
      _callStateController.add(CallState.incoming);
      _incomingCallCtrl.add(true); 
    });

    _socket.onMakeAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data.answer['sdp'], data.answer['type']));
        _callStateController.add(CallState.active);
      }
    });

    _socket.onIceCandidate.listen((data) {
      if (_pc != null && data.candidate != null) {
        _pc!.addCandidate(RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']));
      }
    });
  }

  Future<void> startCall(String userId, dynamic type) async {
    _currentRemoteUserId = userId;
    _callStateController.add(CallState.outgoing);
    
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true, 
      'video': type == 'video' || type == true
    });

    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _pc!.onIceCandidate = (candidate) => _socket.sendIceCandidate(userId, {
      'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex
    });
    _pc!.onTrack = (event) {
      _remoteStreamController.add(event.streams[0]);
      _callStateController.add(CallState.active);
    };
    
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));

    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, {'sdp': offer.sdp, 'type': offer.type}, type.toString());
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    _incomingCallCtrl.add(false);
    await localStream?.dispose();
    await _pc?.close();
    _pc = null;
    localStream = null;
  }
}
