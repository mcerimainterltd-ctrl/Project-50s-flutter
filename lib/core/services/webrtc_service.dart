import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webrtc_socket_service.dart';

enum CallState { idle, outgoing, incoming, active, ended }

class WebRTCService {
  final WebRTCSocketService _socket;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _currentPeerId;
  bool _isVideoCall = false;
  List<RTCRtpSender> _localStreamSenders = [];

  final _callStateController = StreamController<CallState>.broadcast();
  final _callTimerController = StreamController<String>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _incomingCallCtrl = StreamController<bool>.broadcast();
  Timer? _timer;
  int _startTime = 0;

  bool isAudioMuted = false;
  bool isVideoMuted = false;
  bool isLoudspeakerOn = false;

  Stream<CallState> get callState => _callStateController.stream;
  Stream<String> get callTimer => _callTimerController.stream;
  MediaStream? get localStream => _localStream;
  Stream<MediaStream> get remoteStream$ => _remoteStreamController.stream;
  Stream<bool> get onIncomingCall => _incomingCallCtrl.stream;

  WebRTCService(this._socket) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socket.onCallOffer.listen((data) {
      final callerId = data['callerId'] ?? data['from'];
      final offer = data['offer'];
      final callType = data['callType'] ?? 'voice';
      _handleIncomingOffer(callerId, offer, callType);
    });
    _socket.onMakeAnswer.listen((data) {
      final answer = data['answer'];
      _pc?.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
    });
    _socket.onIceCandidate.listen((data) {
      final candidate = data['candidate'];
      if (candidate != null && _pc != null) {
        _pc!.addCandidate(RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ));
      }
    });
    _socket.onCallAccepted.listen((_) {
      _callStateController.add(CallState.active);
      _startTimer();
    });
    _socket.onCallRejected.listen((_) => _endCallInternal());
    _socket.onCallEnded.listen((_) => _endCallInternal());
  }

  Future<void> startCall(String peerId, String callType) async {
    _currentPeerId = peerId;
    _isVideoCall = callType == 'video';
    _callStateController.add(CallState.outgoing);

    int attempts = 0;
    while (!_socket.isConnected && attempts < 50) {
      await Future.delayed(Duration(milliseconds: 100));
      attempts++;
    }
    if (!_socket.isConnected) {
      _callStateController.add(CallState.ended);
      return;
    }

    final mediaConstraints = {
      'audio': true,
      'video': _isVideoCall ? {'facingMode': 'user'} : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    await _createPeerConnection();
    for (var track in _localStream!.getTracks()) {
      final sender = await _pc!.addTrack(track, _localStream!);
      _localStreamSenders.add(sender);
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _socket.emitCallOffer(peerId, offer.toMap(), callType);
  }

  Future<void> handleIncomingCall(dynamic offerData, String callerId, {bool isVideo = false}) async {
    _currentPeerId = callerId;
    _isVideoCall = isVideo;
    _callStateController.add(CallState.incoming);

    final mediaConstraints = {
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    await _createPeerConnection();
    for (var track in _localStream!.getTracks()) {
      final sender = await _pc!.addTrack(track, _localStream!);
      _localStreamSenders.add(sender);
    }

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _pc!.setRemoteDescription(offer);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    _socket.emitMakeAnswer(callerId, answer.toMap());
  }

  void _handleIncomingOffer(String callerId, dynamic offerData, String callType) {
    pendingCall = PendingCall(callerId, offerData, callType);
    _incomingCallCtrl.add(true);
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (candidate) {
      if (candidate != null && _currentPeerId != null) {
        _socket.emitIceCandidate(_currentPeerId!, candidate.toMap());
      }
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream!);
        _callStateController.add(CallState.active);
        _startTimer();
      }
    };
    _pc!.onConnectionState = (state) {
      if (state == 'closed' || state == 'disconnected') _endCallInternal();
    };
  }

  void _startTimer() {
    _startTime = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      final elapsed = (DateTime.now().millisecondsSinceEpoch - _startTime) ~/ 1000;
      final minutes = (elapsed ~/ 60).toString().padLeft(2, '0');
      final seconds = (elapsed % 60).toString().padLeft(2, '0');
      _callTimerController.add('$minutes:$seconds');
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _callTimerController.add('00:00');
  }

  Future<void> endCall() async {
    if (_currentPeerId != null) _socket.emitCallEnded(_currentPeerId!);
    _endCallInternal();
  }

  void _endCallInternal() {
    _stopTimer();
    _callStateController.add(CallState.ended);
    _localStream?.getTracks().forEach((track) => track.stop());
    _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    _currentPeerId = null;
    _localStreamSenders.clear();
  }

  Future<void> exitVideoCall() async => endCall();

  void toggleAudio() {
    isAudioMuted = !isAudioMuted;
    _localStream?.getAudioTracks().forEach((track) => track.enabled = !isAudioMuted);
  }
  void toggleVideo() {
    isVideoMuted = !isVideoMuted;
    _localStream?.getVideoTracks().forEach((track) => track.enabled = !isVideoMuted);
  }
  Future<void> toggleCamera() async {
    if (!_isVideoCall) return;
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks == null || videoTracks.isEmpty) return;
    final currentFacing = videoTracks.first.getSettings()['facingMode'];
    final newFacing = currentFacing == 'user' ? 'environment' : 'user';
    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {'facingMode': newFacing},
    });
    final newVideoTrack = newStream.getVideoTracks().first;
    RTCRtpSender? videoSender;
    for (var sender in _localStreamSenders) {
      if (sender.track == videoTracks.first) {
        videoSender = sender;
        break;
      }
    }
    if (videoSender != null) {
      await _pc?.removeTrack(videoSender);
      _localStreamSenders.remove(videoSender);
    }
    final newSender = await _pc?.addTrack(newVideoTrack, _localStream!);
    if (newSender != null) _localStreamSenders.add(newSender);
    _localStream?.removeTrack(videoTracks.first);
    _localStream?.addTrack(newVideoTrack);
    videoTracks.first.stop();
  }
  Future<void> toggleSpeaker() async {
    isLoudspeakerOn = !isLoudspeakerOn;
    await Helper.setSpeakerphoneOn(isLoudspeakerOn);
  }
  void dispose() {
    _endCallInternal();
    _callStateController.close();
    _callTimerController.close();
    _remoteStreamController.close();
    _incomingCallCtrl.close();
  }
}

final webRTCServiceProvider = Provider<WebRTCService>((ref) => WebRTCService(WebRTCSocketService()));

PendingCall? pendingCall;
class PendingCall {
  final String callerId;
  final Map<String, dynamic> offer;
  final String callType;
  PendingCall(this.callerId, this.offer, this.callType);
}
