import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/constants.dart';
import 'socket_service.dart';

final webRTCServiceProvider = Provider<WebRTCService>((ref) =>
  WebRTCService(ref.read(socketServiceProvider)));

enum CallState { idle, outgoing, incoming, active, ended }

class PeerEntry {
  RTCPeerConnection pc;
  MediaStream?      stream;
  bool              onHold;
  PeerEntry({required this.pc, this.stream, this.onHold = false});
}

class WebRTCService {
  final SocketService _socket;
  final Map<String, PeerEntry> _peers = {};
  MediaStream? localStream;
  MediaStream? remoteStream;
  final List<RTCIceCandidate> _pendingIce = [];
  bool callActive = false, isAudioMuted = false, isVideoMuted = false, isLoudspeakerOn = false;
  int    _timerSeconds = 0;
  Timer? _timerTimer;
  Timer? _timeoutTimer;
  static const _bridge = MethodChannel(AppConstants.channelAndroidBridge);

  final _callStateCtrl    = StreamController<CallState>.broadcast();
  final _callTimerCtrl    = StreamController<String>.broadcast();
  final _peersCtrl        = StreamController<Map<String, PeerEntry>>.broadcast();
  final _remoteStreamCtrl = StreamController<MediaStream>.broadcast();

  Stream<CallState>              get callState    => _callStateCtrl.stream;
  Stream<String>                 get callTimer    => _callTimerCtrl.stream;
  Stream<Map<String,PeerEntry>>  get peersChanged => _peersCtrl.stream;
  Stream<MediaStream>            get remoteStream$ => _remoteStreamCtrl.stream;
  Map<String, PeerEntry>         get peers        => Map.unmodifiable(_peers);

  WebRTCService(this._socket) { _listenSocket(); }

  void _listenSocket() {
    _socket.callAnswer.listen((d)   async => await handleAnswer(d.answer, d.senderId));
    _socket.iceCandidate.listen((d)       => handleNewIceCandidate(d.candidate, d.senderId));
    _socket.callEnded.listen((_)    async => await exitVideoCall());
    _socket.callRejected.listen((d) async {
      if (d.reason == 'ended') { await exitVideoCall(); return; }
      if (d.senderId != null && _peers.containsKey(d.senderId)) removePeer(d.senderId!);
      if (_peers.isEmpty) await exitVideoCall();
    });
  }

  Future<RTCPeerConnection> _createPc(String userId) async {
    final pc = await createPeerConnection({'iceServers': AppConstants.iceServers, 'sdpSemantics': 'unified-plan'});
    pc.onTrack = (e) {
      if (e.streams.isEmpty) return;
      final s = e.streams[0];
      if (_peers[userId] != null) _peers[userId]!.stream = s;
      remoteStream = s;
      _remoteStreamCtrl.add(s);
      if (_timerTimer == null) _startTimer();
      _peersCtrl.add(Map.from(_peers));
    };
    pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected && _timerTimer == null) _startTimer();
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) removePeer(userId);
    };
    pc.onIceCandidate = (c) { if (c != null) _socket.emitIceCandidate(userId, c.toMap()); };
    return pc;
  }

  Future<void> startCall(String recipientId, String callType) async {
    try {
      final hasVideo = callType == 'video';
      localStream ??= await navigator.mediaDevices.getUserMedia({'audio': true, 'video': hasVideo});
      isLoudspeakerOn = false;
      await _setAudioMode(true);
      final pc = await _createPc(recipientId);
      _peers[recipientId] = PeerEntry(pc: pc);
      localStream!.getTracks().forEach((t) => pc.addTrack(t, localStream!));
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket.emitCallUser(recipientId, offer.toMap(), callType);
      callActive = true;
      _callStateCtrl.add(CallState.outgoing);
      _peersCtrl.add(Map.from(_peers));
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(Duration(seconds: AppConstants.callTimeoutSeconds), () {
        if (!callActive || _peers.isEmpty || (_peers.length == 1 && _peers.values.first.stream == null))
          exitVideoCall();
      });
    } catch (e) { debugPrint('Call error: $e'); await exitVideoCall(); rethrow; }
  }

  Future<void> handleIncomingCall(dynamic offer, String callerId, {bool isVideo = false}) async {
    try {
      localStream ??= await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo});
      isLoudspeakerOn = false;
      await _setAudioMode(true);
      final pc = await _createPc(callerId);
      _peers[callerId] = PeerEntry(pc: pc);
      localStream!.getTracks().forEach((t) => pc.addTrack(t, localStream!));
      await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _socket.emitMakeAnswer(callerId, answer.toMap());
      for (final c in _pendingIce) { try { await pc.addCandidate(c); } catch (_) {} }
      _pendingIce.clear();
      callActive = true;
      _callStateCtrl.add(CallState.active);
      _peersCtrl.add(Map.from(_peers));
    } catch (e) { debugPrint('Incoming call error: $e'); await exitVideoCall(); rethrow; }
  }

  Future<void> handleAnswer(dynamic answer, String fromUserId) async {
    final peer = _peers[fromUserId] ?? (_peers.isNotEmpty ? _peers.values.first : null);
    if (peer == null) return;
    try {
      await peer.pc.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
      for (final c in _pendingIce) { try { await peer.pc.addCandidate(c); } catch (_) {} }
      _pendingIce.clear();
      _callStateCtrl.add(CallState.active);
    } catch (e) { debugPrint('Answer error: $e'); await exitVideoCall(); }
  }

  void handleNewIceCandidate(dynamic candidate, String fromUserId) {
    final peer = _peers[fromUserId] ?? (_peers.isNotEmpty ? _peers.values.first : null);
    final ice  = RTCIceCandidate(candidate['candidate'], candidate['sdpMid'], candidate['sdpMLineIndex']);
    if (peer == null) { _pendingIce.add(ice); return; }
    peer.pc.addCandidate(ice).catchError((e) => debugPrint('ICE error: $e'));
  }

  Future<void> addCall(String recipientId) async {
    if (!callActive || localStream == null) return;
    _peers.forEach((_, p) { p.onHold = true; p.stream?.getAudioTracks().forEach((t) => t.enabled = false); });
    try {
      final pc = await _createPc(recipientId);
      _peers[recipientId] = PeerEntry(pc: pc);
      localStream!.getTracks().forEach((t) => pc.addTrack(t, localStream!));
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket.emitCallUser(recipientId, offer.toMap(), 'voice');
      _peersCtrl.add(Map.from(_peers));
    } catch (e) {
      _peers.forEach((_, p) { p.onHold = false; p.stream?.getAudioTracks().forEach((t) => t.enabled = true); });
    }
  }

  void mergeCalls() {
    if (_peers.length < 2) return;
    _peers.forEach((_, p) { p.onHold = false; p.stream?.getAudioTracks().forEach((t) => t.enabled = true); });
    _peersCtrl.add(Map.from(_peers));
  }

  void removePeer(String userId) {
    final peer = _peers[userId]; if (peer == null) return;
    peer.pc.onTrack = null; peer.pc.onIceConnectionState = null; peer.pc.onIceCandidate = null;
    peer.pc.close(); peer.stream?.getTracks().forEach((t) => t.stop());
    _peers.remove(userId); _peersCtrl.add(Map.from(_peers));
    if (_peers.isEmpty) exitVideoCall();
  }

  Future<void> exitVideoCall() async {
    _timeoutTimer?.cancel();
    _peers.keys.toList().forEach((uid) => _socket.emitCallEnded(uid));
    await endCall();
    _callStateCtrl.add(CallState.ended);
  }

  Future<void> endCall() async {
    for (final p in _peers.values) {
      try { p.pc.onTrack = null; p.pc.onIceConnectionState = null; p.pc.onIceCandidate = null; await p.pc.close(); } catch (_) {}
    }
    _peers.clear();
    localStream?.getTracks().forEach((t) => t.stop()); await localStream?.dispose(); localStream = null;
    remoteStream?.getTracks().forEach((t) => t.stop()); await remoteStream?.dispose(); remoteStream = null;
    _pendingIce.clear(); _stopTimer();
    isAudioMuted = false; isVideoMuted = false; isLoudspeakerOn = false; callActive = false;
    await _setAudioMode(false); _peersCtrl.add({});
  }

  void toggleAudio()  { isAudioMuted = !isAudioMuted; localStream?.getAudioTracks().forEach((t) => t.enabled = !isAudioMuted); }
  void toggleVideo()  { isVideoMuted = !isVideoMuted; localStream?.getVideoTracks().forEach((t) => t.enabled = !isVideoMuted); }
  Future<void> toggleCamera() async {
    final tracks = localStream?.getVideoTracks(); if (tracks == null || tracks.isEmpty) return;
    await Helper.switchCamera(tracks[0]);
  }
  Future<void> toggleSpeaker() async {
    isLoudspeakerOn = !isLoudspeakerOn;
    try { await _bridge.invokeMethod('setSpeaker', isLoudspeakerOn); }
    catch (_) { await Helper.setSpeakerphoneOn(isLoudspeakerOn); }
  }

  void _startTimer() {
    _timerSeconds = 0; _timerTimer?.cancel(); _callTimerCtrl.add('00:00');
    _timerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _timerSeconds++;
      final m = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
      final s = (_timerSeconds  % 60).toString().padLeft(2, '0');
      _callTimerCtrl.add('$m:$s');
    });
  }
  void _stopTimer() { _timerTimer?.cancel(); _timerTimer = null; _timerSeconds = 0; }
  Future<void> _setAudioMode(bool on) async { try { await _bridge.invokeMethod('setCallAudioMode', on); } catch (_) {} }
}
