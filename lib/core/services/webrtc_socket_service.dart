import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/providers/socket_provider.dart'; // Ensure this path is correct for your global socket

final webRTCSocketServiceProvider = Provider((ref) {
  // Hook into the existing socket provider instead of creating a new one
  final socket = ref.watch(socketProvider); 
  return WebRTCSocketService(socket);
});

class WebRTCSocketService {
  final IO.Socket _socket;
  
  final _onCallOffer = StreamController<dynamic>.broadcast();
  final _onMakeAnswer = StreamController<dynamic>.broadcast();
  final _onIceCandidate = StreamController<dynamic>.broadcast();

  Stream<dynamic> get onCallOffer => _onCallOffer.stream;
  Stream<dynamic> get onMakeAnswer => _onMakeAnswer.stream;
  Stream<dynamic> get onIceCandidate => _onIceCandidate.stream;

  WebRTCSocketService(this._socket) {
    _socket.on('call-user', (data) => _onCallOffer.add(data));
    _socket.on('make-answer', (data) => _onMakeAnswer.add(data));
    _socket.on('ice-candidate', (data) => _onIceCandidate.add(data));
  }

  // Use the existing logic your app expects for connecting
  void connect(String userId) {
    if (!_socket.connected) {
      _socket.connect();
    }
    _socket.emit('join', userId);
  }

  void sendCallOffer(String to, dynamic offer, String type) {
    _socket.emit('call-user', {'to': to, 'offer': offer, 'type': type});
  }

  void sendCallAnswer(String to, dynamic answer) {
    _socket.emit('make-answer', {'to': to, 'answer': answer});
  }

  void sendIceCandidate(String to, dynamic candidate) {
    _socket.emit('ice-candidate', {'to': to, 'candidate': candidate});
  }
}
