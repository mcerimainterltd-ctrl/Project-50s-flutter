import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/services/socket_service.dart'; 
// Assuming socketServiceProvider is defined in socket_service.dart based on your grep

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) {
  // We use your existing, proven socket provider
  final socket = ref.watch(socketServiceProvider);
  return WebRTCService(socket);
});

class WebRTCService {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // Call this in your constructor or main.dart
  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  CallState _callState = CallState.idle;
  final SocketService _socket;
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  String? currentRemoteUserId;
  bool isIncomingVideo = true;
  
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  dynamic _pendingOffer;

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallController = StreamController<bool>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  CallState get callStateStreamValue => _callState;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallController.stream;

  WebRTCService(this._socket) { 
    _socket.callEnded.listen((data) {
      _handleRemoteHangup();
    });
     initRenderers();
    // Listening to YOUR existing SocketService streams
    _socket.incomingCall.listen((data) {
      if (data.callerId == _socket.currentUserId) return; // Ignore self
      currentRemoteUserId = data.callerId;
      _pendingOffer = data.offer;
      isIncomingVideo = data.callType == 'video';
      _incomingCallController.add(true);
      _callState = CallState.incoming; _callStateController.add(CallState.incoming);
    });

    _socket.callAnswer.listen((data) async {
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(data.answer['sdp'], data.answer['type']));
        _remoteDescriptionSet = true;
        for (var c in _pendingIce) { await _pc!.addCandidate(c); }
        _pendingIce.clear();
        Helper.setSpeakerphoneOn(isIncomingVideo); _callState = CallState.active; _callStateController.add(CallState.active);
      }
    });

    _socket.iceCandidate.listen((data) {
      final c = RTCIceCandidate(data.candidate['candidate'], data.candidate['sdpMid'], data.candidate['sdpMLineIndex']);
      if (_pc != null && _remoteDescriptionSet) { _pc!.addCandidate(c); } 
      else { _pendingIce.add(c); }
    });
  }

  Future<void> startCall(String userId, bool isVideo) async {
    currentRemoteUserId = userId;
    _callState = CallState.outgoing; _callStateController.add(CallState.outgoing);
    // 1. Setup hardware first
    await _setup(isVideo);
    
    // 2. Create Offer (This now contains the media info)
    var offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    // Using YOUR existing emit method
    _socket.emitCallUser(userId, {'sdp': offer.sdp, 'type': offer.type}, isVideo ? 'video' : 'voice');
  }

  Future<void> joinCall(bool isVideo) async {
    if (_pendingOffer == null) return;
    // 1. Setup hardware and WAIT for tracks to be added
    await _setup(isVideo); 
    
    // 2. Set remote info
    await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']));
    _remoteDescriptionSet = true;
    
    // 3. Create Answer (Now it will include the tracks we added in _setup)
    var answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket.emitMakeAnswer(currentRemoteUserId!, {'sdp': answer.sdp, 'type': answer.type});
    for (var c in _pendingIce) { await _pc!.addCandidate(c); }
    _pendingIce.clear();
    Helper.setSpeakerphoneOn(isIncomingVideo); _callState = CallState.active; _callStateController.add(CallState.active);
  }

  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({
      'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}],
      'sdpSemantics': 'unified-plan'
    });
    
    _pc!.onIceConnectionState = (s) => print('[ICE] state: \$s');
    _pc!.onConnectionState = (s) => print('[CONN] state: \$s');
    _pc!.onIceCandidate = (c) => _socket.emitIceCandidate(currentRemoteUserId!, {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        // Force the stream to the renderer immediately
        _remoteRenderer.srcObject = e.streams[0];
        
        // Ensure all incoming tracks are enabled
        for (var track in e.streams[0].getTracks()) {
          track.enabled = true;
        }
        
        _remoteStreamController.add(e.streams[0]);
        print("Remote stream attached and tracks enabled");
      }
    };

    // We MUST await the hardware before moving to the next step in joinCall/startCall
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true, 
      'video': v ? {'facingMode': 'user'} : false
    });
    
    _localRenderer.srcObject = localStream;
    // Notify listeners that the stream is ready to be rendered
    _callStateController.add(_callState);
    for (var track in localStream!.getTracks()) {
      track.enabled = true;
      await _pc!.addTrack(track, localStream!);
    }
  }

  
  void rejectCall() {
    _socket.emitCallRejected(currentRemoteUserId ?? "", "declined");
    _callState = CallState.ended; _callStateController.add(CallState.ended);
    _incomingCallController.add(false);
  }

  void endCall() {
    _socket.emitCallEnded(currentRemoteUserId ?? "");
    _cleanup();
    _callState = CallState.ended; _callStateController.add(CallState.ended);
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }

  void _handleRemoteHangup() {
    _callState = CallState.ended;
    _callStateController.add(CallState.ended);
    _cleanup();
  }

  void _cleanup() {
    localStream?.getTracks().forEach((t) => t.stop());
    localStream?.dispose();
    localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }

}