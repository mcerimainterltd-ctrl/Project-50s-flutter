import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final webRTCSocketServiceProvider = Provider((ref) => WebRTCSocketService());

class WebRTCSocketService {
  void connect(String userId) {}
  
  // The missing methods the compiler is asking for:
  void sendCallOffer(String to, RTCSessionDescription offer, String type) {
    // Logic to emit 'call-offer' to your Node.js server
  }

  void sendIceCandidate(String to, RTCIceCandidate candidate) {
    // Logic to emit 'ice-candidate' to your Node.js server
  }

  Stream<dynamic> get onCallOffer => const Stream.empty();
  Stream<dynamic> get onIceCandidate => const Stream.empty();
  Stream<dynamic> get onMakeAnswer => const Stream.empty();
}
