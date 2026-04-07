import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum CallState { idle, calling, ringing, connected, busy, failed }

class WebRTCService {
  final IO.Socket _socket;
  final _callStateCtrl = StreamController<CallState>.broadcast();
  final _callTimerCtrl = StreamController<String>.broadcast();
  final _remoteStreamCtrl = StreamController<MediaStream?>.broadcast();
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  Stream<CallState> get callState => _callStateCtrl.stream;
  Stream<MediaStream?> get remoteStream$ => _remoteStreamCtrl.stream;
  Stream<String> get callTimer => _callTimerCtrl.stream;
  MediaStream? get localStream => _localStream;

  WebRTCService(this._socket) {
    _socket.on("offer", (data) async {
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(data["sdp"], data["type"])
      );
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _socket.emit("answer", answer.toMap());
    });

    _socket.on("answer", (data) async {
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(data["sdp"], data["type"])
      );
    });

    _socket.on("ice-candidate", (data) {
      _peerConnection?.addCandidate(
        RTCIceCandidate(data["candidate"], data["sdpMid"], data["sdpMLineIndex"])
      );
    });
  }

  Future<void> startCall() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _socket.emit("offer", offer.toMap());
  }

  Future<void> initializeMedia(Map<String, dynamic> mediaConstraints) async {
    Map<String, dynamic> configuration = {
      "iceServers": [{"urls": "stun:stun.l.google.com:19302"}]
    };
    Map<String, dynamic> loopbackConstraints = {
      "mandatory": {},
      "optional": [{"DtlsSrtpKeyAgreement": true}]
    };

    _peerConnection = await createPeerConnection(configuration, loopbackConstraints);
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

    _peerConnection?.onAddStream = (MediaStream stream) {
      _remoteStreamCtrl.add(stream);
    };

    await _peerConnection?.addStream(_localStream!);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _socket.emit("ice-candidate", candidate.toMap());
    };
  }

  void dispose() {
    _callStateCtrl.close();
    _callTimerCtrl.close();
    _remoteStreamCtrl.close();
    _localStream?.dispose();
    _peerConnection?.dispose();
  }
}
