import 'dart:async';
import 'webrtc_signaling_client.dart';

class WebRTCSocketService implements ISignalingClient {
  final dynamic _socket;
  final _offerController = StreamController<Map<String, dynamic>>.broadcast();
  final _answerController = StreamController<Map<String, dynamic>>.broadcast();
  final _iceController = StreamController<Map<String, dynamic>>.broadcast();

  @override Stream<Map<String, dynamic>> get onCallOffer => _offerController.stream;
  @override Stream<Map<String, dynamic>> get onAnswer => _answerController.stream;
  @override Stream<Map<String, dynamic>> get onIceCandidate => _iceController.stream;

  WebRTCSocketService(this._socket) {
    if (_socket != null) {
      _socket.on('call-user', (data) => _offerController.add(Map<String, dynamic>.from(data)));
      _socket.on('make-answer', (data) => _answerController.add(Map<String, dynamic>.from(data)));
      _socket.on('ice-candidate', (data) => _iceController.add(Map<String, dynamic>.from(data)));
    }
  }

  void connect(String userId) {
    if (_socket != null) {
      _socket.emit('join', userId);
    }
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    if (_socket != null) {
      _socket.emit(event, data);
    }
  }
}
