import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

// RE-DEFINING THE ENUM YOUR UI EXPECTS
enum CallState { idle, outgoing, incoming, active, ended }

final webRTCSocketServiceProvider = StateProvider<WebRTCSocketService?>((ref) => null);

final webRTCServiceProvider = Provider((ref) {
  final socket = ref.watch(webRTCSocketServiceProvider);
  return WebRTCService(socket);
});

class WebRTCService {
  final WebRTCSocketService? _socket;
  RTCPeerConnection? _pc;
  MediaStream? localStream; // RESTORED FOR UI
  String? currentRemoteUserId; // RESTORED FOR UI
  bool isIncomingVideo = true; // RESTORED FOR UI
  
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  dynamic _pendingOffer;

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallController = StreamController<bool>.broadcast();

  // GETTERS REQUIRED BY YOUR UI (app.dart and screens)
  Stream<CallState> get callState => _callStateController.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallController.stream;

  WebRTCService(this._socket) {
    _socket?.onCallOffer.listen((data) {
      currentRemoteUserId = data['callerId'];
      _pendingOffer = data['offer'];
      isIncomingVideo = data['type'] == 'video';
      _incomingCallController.add(true);
      _callStateController.add(CallState.incoming);
    });

    _socket?.onAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data['answer']['sdp'], data['answer']['type']));
        _remoteDescriptionSet = true;
        for (var c in _pendingIce) { await _pc!.addCandidate(c); }
        _pendingIce.clear();
        _callStateController.add(CallState.active);
      }
    });

    _socket?.onIceCandidate.listen((data) {
      final c = RTCIceCandidate(data['candidate']['candidate'], data['candidate']['sdpMid'], data['candidate']['sdpMLineIndex']);
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
    _socket?.emit('call-user', {'to': userId, 'offer': {'sdp': offer.sdp, 'type': offer.type}, 'type': isVideo ? 'video' : 'voice'});
  }

  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    await _setup(isVideo);
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    var answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket?.emit('make-answer', {'to': currentRemoteUserId!, 'answer': {'sdp': answer.sdp, 'type': answer.type}});
    for (var c in _pendingIce) { await _pc!.addCandidate(c); }
    _pendingIce.clear();
    _callStateController.add(CallState.active);
  }

  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _pc!.onIceCandidate = (c) => _socket?.emit('ice-candidate', {'to': currentRemoteUserId!, 'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}});
    _pc!.onTrack = (e) => e.streams.isNotEmpty ? _remoteStreamController.add(e.streams[0]) : null;
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': v});
    localStream!.getTracks().forEach((t) => _pc!.addTrack(t, localStream!));
  }

  void endCall() {
    _callStateController.add(CallState.ended);
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }
}
