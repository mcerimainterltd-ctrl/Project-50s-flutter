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
  
  final _callStateController = StreamController<CallState>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  Stream<CallState> get callState => _callStateController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;

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
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ));
      }
    });
  }
}
