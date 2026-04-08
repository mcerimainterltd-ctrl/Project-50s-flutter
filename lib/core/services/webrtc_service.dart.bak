import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum CallState { idle, calling, ringing, connected, busy, failed }

class WebRTCService {
  final IO.Socket _socket;
  static WebRTCService? _instance;
  static WebRTCService get instance => _instance!;
  static WebRTCService? get instanceOrNull => _instance;

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
      _socket.emit("answer", {
        "sdp": answer.sdp,
        "type": answer.type,
      });
    });
  }
}
