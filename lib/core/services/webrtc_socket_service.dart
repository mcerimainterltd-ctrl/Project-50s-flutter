import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart'; // Assuming your base socket logic is here

final webRTCSocketServiceProvider = Provider((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return WebRTCSocketService(socketService);
});

class WebRTCSocketService {
  final SocketService _baseSocket;
  
  WebRTCSocketService(this._baseSocket);

  // Streams for the WebRTC Service to listen to
  Stream<dynamic> get onCallOffer => _baseSocket.getResponse('call-user');
  Stream<dynamic> get onMakeAnswer => _baseSocket.getResponse('make-answer');
  Stream<dynamic> get onIceCandidate => _baseSocket.getResponse('ice-candidate');

  void sendCallOffer(String to, RTCSessionDescription offer, String type) {
    _baseSocket.emit('call-user', {
      'recipientId': to,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'callType': type,
    });
  }

  void sendAnswer(String to, RTCSessionDescription answer) {
    _baseSocket.emit('make-answer', {
      'to': to,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  void sendIceCandidate(String to, RTCIceCandidate candidate) {
    _baseSocket.emit('ice-candidate', {
      'to': to,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }
}
