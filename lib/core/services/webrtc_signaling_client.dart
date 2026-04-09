import 'dart:async';

abstract class ISignalingClient {
  Stream<Map<String, dynamic>> get onCallOffer;
  Stream<Map<String, dynamic>> get onAnswer;
  Stream<Map<String, dynamic>> get onIceCandidate;
  
  void emit(String event, Map<String, dynamic> data);
}
