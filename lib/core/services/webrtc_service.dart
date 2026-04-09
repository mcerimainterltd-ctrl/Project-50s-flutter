import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'socket_service.dart'; 
// Assuming socketServiceProvider is defined in socket_service.dart based on your grep
import 'package:xamepage/core/services/socket_service.dart'; 

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) {
  // We use your existing, proven socket provider
  final socket = ref.watch(socketServiceProvider);
  return WebRTCService(socket);
});

class WebRTCService {
  final SocketService _socket;
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  String? currentRemoteUserId;
  bool isIncomingVideo = true;
  
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  dynamic _pendingOffer;

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallController = StreamController<bool>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallController.stream;

  WebRTCService(this._socket) {
    // Listening to YOUR existing SocketService streams
    _socket.incomingCall.listen((data) {
      currentRemoteUserId = data.callerId;
      _pendingOffer = data.offer;
      isIncomingVideo = data.callType == 'video';
      _incomingCallController.add(true);
      _callStateController.add(CallState.incoming);
    });

    _socket.callAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data.answer['sdp'], data.answer['type']));
        _remoteDescriptionSet = true;
        for (var c in _pendingIce) { await _pc!.addCandidate(c); }
        _pendingIce.clear();
        _callStateController.add(CallState.active);
      }
    });

    _socket.iceCandidate.listen((data) {
      final c = RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']);
      if (_pc != null && _remoteDescriptionSet) { _pc!.addCandidate(c); } 
      else { _pendingIce.add(c); }
    });
  }

  Future<void> startCall(String userId, bool isVideo) async {
    currentRemoteUserId = userId;
    _callStateController.add(CallState.outgoing);
    await _setup(isVideo);
    var offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    // Using YOUR existing emit method
    _socket.emitCallUser(userId, {'sdp': offer.sdp, 'type': offer.type}, isVideo ? 'video' : 'voice');
  }

  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    await _setup(isVideo);
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    var answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket.emitMakeAnswer(currentRemoteUserId!, {'sdp': answer.sdp, 'type': answer.type});
    for (var c in _pendingIce) { await _pc!.addCandidate(c); }
    _pendingIce.clear();
    _callStateController.add(CallState.active);
  }

  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _pc!.onIceCandidate = (c) => _socket.emitIceCandidate(currentRemoteUserId!, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    _pc!.onTrack = (e) => e.streams.isNotEmpty ? _remoteStreamController.add(e.streams[0]) : null;
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': v});
    localStream!.getTracks().forEach((t) => _pc!.addTrack(t, localStream!));
  }

  void endCall() {
    _callStateController.add(CallState.ended);
    _socket.emitCallEnded(currentRemoteUserId ?? "");
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }
}
