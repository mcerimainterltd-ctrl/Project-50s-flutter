import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum CallState { idle, calling, ringing, connected, busy, failed }

class WebRTCService {
  final IO.Socket _socket;
  static WebRTCService? _instance;
  static WebRTCService get instance => _instance!;

  final _callStateCtrl = StreamController<CallState>.broadcast();
  final _remoteStreamCtrl = StreamController<MediaStream?>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<MediaStream?> get remoteStream$ => _remoteStreamCtrl.stream;
  MediaStream? get localStream => _localStream;

  WebRTCService(this._socket) {
    _instance = this;
    _socket.on("offer", (data) async {
      _incomingCallCtrl.add(true);
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(data["sdp"], data["type"])
      );
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _socket.emit("answer", answer.toMap());
    });
  }

  Future<void> initializeMedia(Map<String, dynamic> mediaConstraints) async {
    _peerConnection = await createPeerConnection({
      "iceServers": [{"urls": "stun:stun.l.google.com:19302"}]
    }, {"mandatory": {}, "optional": [{"DtlsSrtpKeyAgreement": true}]});
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _peerConnection?.onAddStream = (stream) => _remoteStreamCtrl.add(stream);
    await _peerConnection?.addStream(_localStream!);
    _peerConnection?.onIceCandidate = (c) => _socket.emit("ice-candidate", c.toMap());
  }
}
