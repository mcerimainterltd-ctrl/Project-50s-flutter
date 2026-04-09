import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) => WebRTCService(ref.watch(webRTCSocketServiceProvider)));

class WebRTCService {
  final WebRTCSocketService _socket;
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  String? _currentRemoteUserId;
  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _iceBuffer = [];

  String? get currentRemoteUserId => _currentRemoteUserId;

  final _callStateController = StreamController<CallState>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;

  WebRTCService(this._socket) {
    _socket.onCallOffer.listen((data) {
      _currentRemoteUserId = data.callerId;
      _callStateController.add(CallState.incoming);
      _incomingCallCtrl.add(true);
    });

    _socket.onMakeAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data.answer['sdp'], data.answer['type']));
        _isRemoteDescriptionSet = true;
        for (var c in _iceBuffer) { await _pc!.addCandidate(c); }
        _iceBuffer.clear();
        _callStateController.add(CallState.active);
      }
    });

    _socket.onIceCandidate.listen((data) {
      final candidate = RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']);
      if (_pc != null && _isRemoteDescriptionSet) {
        _pc!.addCandidate(candidate);
      } else {
        _iceBuffer.add(candidate);
      }
    });
  }

  Future<void> startCall(String userId, bool isVideo) async {
    _currentRemoteUserId = userId;
    _callStateController.add(CallState.outgoing);
    
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
    });

    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _socket.sendIceCandidate(userId, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      }
    };

    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteStreamController.add(e.streams[0]);
        _callStateController.add(CallState.active);
      }
    };

    // DYNAMIC MEDIA CONSTRAINTS
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true, 
      'video': isVideo // Camera only turns on if isVideo is true
    });
    
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));

    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, {'sdp': offer.sdp, 'type': offer.type}, isVideo ? 'video' : 'voice');
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    _incomingCallCtrl.add(false);
    _isRemoteDescriptionSet = false;
    _iceBuffer.clear();
    await localStream?.dispose();
    await _pc?.close();
    _pc = null;
    localStream = null;
  }
}
