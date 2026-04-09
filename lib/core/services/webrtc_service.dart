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
  final List<RTCIceCandidate> _remoteCandidates = []; // BUFFER for early candidates

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
        // Process buffered candidates once description is set
        for (var c in _remoteCandidates) { await _pc!.addCandidate(c); }
        _remoteCandidates.clear();
      }
    });

    _socket.onIceCandidate.listen((data) {
      final candidate = RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']);
      if (_pc != null && _pc!.remoteDescription != null) {
        _pc!.addCandidate(candidate);
      } else {
        _remoteCandidates.add(candidate); // Buffer until PC is ready
      }
    });
  }

  Future<void> startCall(String userId, bool isVideo) async {
    _currentRemoteUserId = userId;
    _callStateController.add(CallState.outgoing);
    
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}, {'urls': 'stun:stun1.l.google.com:19302'}]
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

    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo});
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));

    var offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, {'sdp': offer.offer['sdp'], 'type': offer.offer['type']}, 'video');
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    _incomingCallCtrl.add(false);
    _remoteCandidates.clear();
    await localStream?.dispose();
    await _pc?.close();
    _pc = null;
  }
}
