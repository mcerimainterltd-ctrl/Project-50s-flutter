import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

// This fulfills the 'Undefined name' error in app.dart and webrtc_service.dart
// We use a StateProvider so it's empty (null) by default and won't crash the build
final webRTCSocketServiceProvider = StateProvider<WebRTCSocketService?>((ref) => null);

class WebRTCSocketService {
  final dynamic _socket;
  
  final _onCallOffer = StreamController<dynamic>.broadcast();
  final _onMakeAnswer = StreamController<dynamic>.broadcast();
  final _onIceCandidate = StreamController<dynamic>.broadcast();

  Stream<dynamic> get onCallOffer => _onCallOffer.stream;
  Stream<dynamic> get onMakeAnswer => _onMakeAnswer.stream;
  Stream<dynamic> get onIceCandidate => _onIceCandidate.stream;

  WebRTCSocketService(this._socket) {
    if (_socket != null) {
      _socket.on('call-user', (data) => _onCallOffer.add(data));
      _socket.on('make-answer', (data) => _onMakeAnswer.add(data));
      _socket.on('ice-candidate', (data) => _onIceCandidate.add(data));
    }
  }

  // Required by lib/app.dart:30:16
  void connect(String userId) {
    _socket?.emit('join', userId);
  }

  void sendCallOffer(String to, dynamic offer, String type) => _socket?.emit('call-user', {'to': to, 'offer': offer, 'type': type});
  void sendCallAnswer(String to, dynamic answer) => _socket?.emit('make-answer', {'to': to, 'answer': answer});
  void sendIceCandidate(String to, dynamic candidate) => _socket?.emit('ice-candidate', {'to': to, 'candidate': candidate});
}
