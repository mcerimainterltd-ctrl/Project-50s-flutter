import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'socket_service.dart';

// This MUST match what WebRTCService is looking for
final webRTCSocketServiceProvider = Provider((ref) => WebRTCSocketService());

class WebRTCSocketService {
  void connect(String userId) {
    // Connection logic
  }
  Stream<dynamic> get onCallOffer => const Stream.empty();
  Stream<dynamic> get onIceCandidate => const Stream.empty();
  Stream<dynamic> get onMakeAnswer => const Stream.empty();
}
