import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

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

  void sendCallOffer(String to, dynamic offer, String type) {
    _socket.emit('call-user', {'to': to, 'offer': offer, 'type': type});
  }

  // WE ARE EXPLICITLY DEFINING THIS NOW TO PREVENT COMPILER ERRORS
  void sendCallAnswer(String to, dynamic answer) {
    _socket.emit('make-answer', {'to': to, 'answer': answer});
  }

  void sendIceCandidate(String to, dynamic candidate) {
    _socket.emit('ice-candidate', {'to': to, 'candidate': candidate});
  }
}
