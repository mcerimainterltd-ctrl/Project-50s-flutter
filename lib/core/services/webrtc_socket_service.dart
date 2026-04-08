import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/constants.dart';

class WebRTCSocketService {
  static final WebRTCSocketService _instance = WebRTCSocketService._internal();
  factory WebRTCSocketService() => _instance;
  WebRTCSocketService._internal();

  IO.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  final _onCallOffer = StreamController<Map<String, dynamic>>.broadcast();
  final _onMakeAnswer = StreamController<Map<String, dynamic>>.broadcast();
  final _onIceCandidate = StreamController<Map<String, dynamic>>.broadcast();
  final _onCallAccepted = StreamController<Map<String, dynamic>>.broadcast();
  final _onCallRejected = StreamController<Map<String, dynamic>>.broadcast();
  final _onCallEnded = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onCallOffer => _onCallOffer.stream;
  Stream<Map<String, dynamic>> get onMakeAnswer => _onMakeAnswer.stream;
  Stream<Map<String, dynamic>> get onIceCandidate => _onIceCandidate.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _onCallAccepted.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _onCallRejected.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _onCallEnded.stream;

  void connect(String userId) {
    if (_socket?.connected == true) return;
    _socket = IO.io(
      AppConstants.serverUrl,
      IO.OptionBuilder()
          .setQuery({'userId': userId})
          .setTransports(['websocket'])
          .setPath('/socket.io/')
          .enableReconnection()
          .setReconnectionDelay(1000)
          .build(),
    );
    _socket?.onConnect((_) {
      _connected = true;
      debugPrint('✅ WebRTC socket connected for $userId');
      _socket?.on('call-user', (d) => _onCallOffer.add(d));
      _socket?.on('make-answer', (d) => _onMakeAnswer.add(d));
      _socket?.on('ice-candidate', (d) => _onIceCandidate.add(d));
      _socket?.on('call-accepted', (d) => _onCallAccepted.add(d));
      _socket?.on('call-rejected', (d) => _onCallRejected.add(d));
      _socket?.on('call-ended', (d) => _onCallEnded.add(d));
    });
    _socket?.connect();
  }

  void emitCallOffer(String to, Map<String, dynamic> offer, String callType) {
    _socket?.emit('call-user', {'recipientId': to, 'offer': offer, 'callType': callType});
  }
  void emitMakeAnswer(String to, Map<String, dynamic> answer) {
    _socket?.emit('make-answer', {'recipientId': to, 'answer': answer});
  }
  void emitIceCandidate(String to, Map<String, dynamic> candidate) {
    _socket?.emit('ice-candidate', {'recipientId': to, 'candidate': candidate});
  }
  void emitCallAccepted(String to) {
    _socket?.emit('call-accepted', {'recipientId': to});
  }
  void emitCallRejected(String to, String reason) {
    _socket?.emit('call-rejected', {'recipientId': to, 'reason': reason});
  }
  void emitCallEnded(String to) {
    _socket?.emit('call-ended', {'recipientId': to});
  }

  void dispose() {
    _socket?.disconnect();
    _onCallOffer.close(); _onMakeAnswer.close(); _onIceCandidate.close();
    _onCallAccepted.close(); _onCallRejected.close(); _onCallEnded.close();
  }
}
