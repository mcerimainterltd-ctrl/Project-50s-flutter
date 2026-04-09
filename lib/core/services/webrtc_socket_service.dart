import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

// THIS WAS THE MISSING LINK CAUSING THE BUILD 104 FAILURE
final webRTCSocketServiceProvider = Provider((ref) {
  // Replace with your actual socket initialization if different
  final socket = IO.io('https://your-socket-server.com', 
    IO.OptionBuilder().setTransports(['websocket']).build());
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

  void connect(String userId) {
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
