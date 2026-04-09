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
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  dynamic _pendingOffer;
  bool _isIncomingVideo = true;

  String? get currentRemoteUserId => _currentRemoteUserId;
  bool get isIncomingVideo => _isIncomingVideo;

  final _callStateController = StreamController<CallState>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;

  WebRTCService(this._socket) {
    _socket.onCallOffer.listen((data) {
      _currentRemoteUserId = data.callerId;
      _pendingOffer = data.offer;
      _isIncomingVideo = data.type == 'video';
      _callStateController.add(CallState.incoming);
      _incomingCallCtrl.add(true);
    });

    _socket.onMakeAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data.answer['sdp'], data.answer['type']));
        _remoteDescriptionSet = true;
        for (var c in _pendingIce) { await _pc!.addCandidate(c); }
        _pendingIce.clear();
        _callStateController.add(CallState.active);
      }
    });

    _socket.onIceCandidate.listen((data) {
      final c = RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']);
      if (_pc != null && _remoteDescriptionSet) { _pc!.addCandidate(c); } 
      else { _pendingIce.add(c); }
    });
  }

  Future<void> startCall(String userId, bool isVideo) async {
    _currentRemoteUserId = userId;
    _callStateController.add(CallState.outgoing);
    await _setupPeerConnection(isVideo);
    RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.sendCallOffer(userId, {'sdp': offer.sdp, 'type': offer.type}, isVideo ? 'video' : 'voice');
  }

  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    await _setupPeerConnection(isVideo);
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    RTCSessionDescription answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket.sendCallAnswer(_currentRemoteUserId!, {'sdp': answer.sdp, 'type': answer.type});
    for (var c in _pendingIce) { await _pc!.addCandidate(c); }
    _pendingIce.clear();
    _callStateController.add(CallState.active);
  }

  Future<void> _setupPeerConnection(bool isVideo) async {
    _pc = await createPeerConnection({'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]});
    _pc!.onIceCandidate = (c) => _socket.sendIceCandidate(_currentRemoteUserId!, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteStreamController.add(e.streams[0]);
        _callStateController.add(CallState.active);
      }
    };
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo});
    localStream!.getTracks().forEach((track) => _pc!.addTrack(track, localStream!));
  }

  Future<void> endCall() async {
    _callStateController.add(CallState.ended);
    _incomingCallCtrl.add(false);
    _remoteDescriptionSet = false;
    _pendingIce.clear();
    await localStream?.dispose();
    await _pc?.close();
    _pc = null;
    localStream = null;
  }
}
