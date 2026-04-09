import 'dart:async';

class WebRTCSocketService {
  final dynamic _socket; // Works with any socket instance
  
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

  void connect(String userId) => _socket.emit('join', userId);
  void sendCallOffer(String to, dynamic offer, String type) => _socket.emit('call-user', {'to': to, 'offer': offer, 'type': type});
  void sendCallAnswer(String to, dynamic answer) => _socket.emit('make-answer', {'to': to, 'answer': answer});
  void sendIceCandidate(String to, dynamic candidate) => _socket.emit('ice-candidate', {'to': to, 'candidate': candidate});
}
