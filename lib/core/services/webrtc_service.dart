import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

// This fulfills the requirement in webrtc_service.dart:10:34
final webRTCServiceProvider = Provider((ref) {
  final socketService = ref.watch(webRTCSocketServiceProvider);
  // Return a dummy service if null to prevent compilation failure
  return WebRTCService(socketService ?? WebRTCSocketService(null));
});

class WebRTCService {
  final WebRTCSocketService _socket;
  WebRTCService(this._socket);
  
  Future<void> startCall(String userId, bool isVideo) async {}
  Future<void> joinCall(bool isVideo) async {}
  void endCall() {}
}
