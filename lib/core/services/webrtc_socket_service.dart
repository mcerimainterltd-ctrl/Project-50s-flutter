import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

final webRTCSocketServiceProvider = Provider((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return WebRTCSocketService(socketService);
});

class WebRTCSocketService {
  final SocketService _baseSocket;
  WebRTCSocketService(this._baseSocket);

  // Directly mapping to your existing SocketService streams
  Stream<IncomingCallData> get onCallOffer => _baseSocket.incomingCall;
  Stream<CallAnswerData> get onMakeAnswer => _baseSocket.callAnswer;
  Stream<IceCandidateData> get onIceCandidate => _baseSocket.iceCandidate;

  // Use your existing emit helpers
  void connect(String userId) => _baseSocket.connect(userId);
  
  void sendCallOffer(String to, dynamic offer, String type) => 
      _baseSocket.emitCallUser(to, offer, type);

  void sendAnswer(String to, dynamic answer) => 
      _baseSocket.emitMakeAnswer(to, answer);

  void sendIceCandidate(String to, dynamic candidate) => 
      _baseSocket.emitIceCandidate(to, candidate);
}
