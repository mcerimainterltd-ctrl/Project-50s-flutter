// flutter_webrtc temporarily stubbed — will be re-added after base APK builds
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import 'socket_service.dart';

final webRTCServiceProvider = Provider<WebRTCService>((ref) =>
  WebRTCService(ref.read(socketServiceProvider)));

enum CallState { idle, outgoing, incoming, active, ended }

class WebRTCService {
  final SocketService _socket;
  bool callActive = false, isAudioMuted = false, isVideoMuted = false, isLoudspeakerOn = false;
  static const _bridge = MethodChannel(AppConstants.channelAndroidBridge);

  final _callStateCtrl = StreamController<CallState>.broadcast();
  final _callTimerCtrl = StreamController<String>.broadcast();

  Stream<CallState> get callState  => _callStateCtrl.stream;
  Stream<String>    get callTimer  => _callTimerCtrl.stream;

  WebRTCService(this._socket);

  Future<void> startCall(String recipientId, String callType) async =>
      debugPrint('WebRTC stubbed — startCall($recipientId, $callType)');

  Future<void> handleIncomingCall(dynamic offer, String callerId, {bool isVideo = false}) async =>
      debugPrint('WebRTC stubbed — handleIncomingCall($callerId)');

  Future<void> handleAnswer(dynamic answer, String fromUserId) async =>
      debugPrint('WebRTC stubbed — handleAnswer($fromUserId)');

  void handleNewIceCandidate(dynamic candidate, String fromUserId) =>
      debugPrint('WebRTC stubbed — handleNewIceCandidate($fromUserId)');

  Future<void> exitVideoCall() async => debugPrint('WebRTC stubbed — exitVideoCall()');
  Future<void> endCall()       async => debugPrint('WebRTC stubbed — endCall()');
  void toggleAudio()  => debugPrint('WebRTC stubbed — toggleAudio()');
  void toggleVideo()  => debugPrint('WebRTC stubbed — toggleVideo()');
  Future<void> toggleCamera()  async => debugPrint('WebRTC stubbed — toggleCamera()');
  Future<void> toggleSpeaker() async => debugPrint('WebRTC stubbed — toggleSpeaker()');
  void dispose() { _callStateCtrl.close(); _callTimerCtrl.close(); }
}
