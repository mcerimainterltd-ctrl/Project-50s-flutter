import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/services/audio_service.dart';
import 'package:xamepage/core/services/cache_service.dart';
import 'package:xamepage/core/config/constants.dart'; 
// Assuming socketServiceProvider is defined in socket_service.dart based on your grep

enum CallState { idle, outgoing, incoming, active, ended }

final webRTCServiceProvider = Provider((ref) {
  ref.keepAlive();
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
  String  callerDisplayName = 'Unknown';
  bool isIncomingVideo = true;
  
  final AudioService _audio = AudioService();
  static const _channel = MethodChannel('com.xamepage.app/call');
  bool _callCancelled = false;
  String callEndReason = ''; // 'declined', 'no-answer', 'cancelled', 'ended'
  Timer? _callTimeoutTimer;
  String? _currentCallId;
  String? get currentCallId => _currentCallId;
  DateTime? _callStartTime;
  bool isRinging = false;
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
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCallAnswered':
          await acceptCall();
          break;
        case 'onCallDeclined':
          await rejectCall();
          break;
      }
    });
    _socket.callEnded.listen((data) {
      _handleRemoteHangup();
    });

    _socket.callRinging.listen((_) {
      isRinging = true;
      _callStateController.add(_callState); // trigger UI rebuild
    });

    _socket.callRejected.listen((data) {
      _callCancelled = true;
      callEndReason = 'declined';
      _callTimeoutTimer?.cancel();
      _audio.stopAll();
      // Record as declined — recipient actively rejected the call
      if (_callState == CallState.outgoing && currentRemoteUserId != null) {
        _recordDeclinedCall(currentRemoteUserId!, isIncomingVideo ? 'video' : 'voice');
      }
      _cleanup();
      _callState = CallState.ended;
      _callStateController.add(CallState.ended);
    });
     initRenderers();
    // Listening to YOUR existing SocketService streams
    _socket.incomingCall.listen((data) async {
      if (data.callerId == _socket.currentUserId) return; // Ignore self
      if (_callState == CallState.incoming || _callState == CallState.active) return; // Already in a call
      currentRemoteUserId = data.callerId;
      _pendingOffer = data.offer;
      isIncomingVideo = data.callType == 'video';
      // Resolve caller display name from contacts cache
      final contacts = CacheService.loadContacts();
      final match = contacts.where((c) => c['id'] == data.callerId || c['xameId'] == data.callerId).firstOrNull;
      callerDisplayName = (match?['name'] as String?)?.isNotEmpty == true
          ? match!['name'] as String
          : data.callerId;
      _incomingCallController.add(true);
      await _audio.stopAll();
      await Helper.setSpeakerphoneOn(true);
      _audio.playRingtone();
      // Start foreground service + lock screen notification
      try {
        await _channel.invokeMethod('startCallService', {
          'callerName': callerDisplayName,
          'callType': isIncomingVideo ? 'video' : 'voice',
        });
        await _channel.invokeMethod('keepScreenOn');
      } catch (_) {}
      _callState = CallState.incoming;
      _callStateController.add(CallState.incoming);
      // Notify caller that this device is actually ringing
      _socket.emitCallRingingAck(data.callerId);
    });

    _socket.callAnswer.listen((data) async {
      // Recipient answered — stop outgoing ringtone and timeout
      _callTimeoutTimer?.cancel();
      _callCancelled = true;
      await _audio.stopAll();
      try { _channel.invokeMethod('dismissIncomingCall'); } catch (_) {}
      // Always update UI to active regardless of _pc state
      _callState = CallState.active;
      _callStateController.add(CallState.active);
      _incomingCallController.add(false);
      if (_pc != null) {
        try {
          await _pc!.setRemoteDescription(
              RTCSessionDescription(data.answer['sdp'], data.answer['type']));
          _remoteDescriptionSet = true;
          for (var c in _pendingIce) { await _pc!.addCandidate(c); }
          _pendingIce.clear();
          await Helper.setSpeakerphoneOn(false);
        } catch (e) {
          print('[WebRTC] setRemoteDescription error: \$e');
        }
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
    // Emit offer
    _socket.emitCallUser(userId, {'sdp': offer.sdp, 'type': offer.type}, isVideo ? 'video' : 'voice');
    // Only play outgoing if not already cancelled/answered
    if (!_callCancelled && _callState == CallState.outgoing) {
      await Helper.setSpeakerphoneOn(false);
      _audio.playOutgoing();
    }
    // Capture callId from server
    _socket.onCallInitiated((id) => _currentCallId = id);
    // Start timeout — record missed if no answer within callTimeoutSeconds
    _callStartTime = DateTime.now();
    _callTimeoutTimer = Timer(
      Duration(seconds: AppConstants.callTimeoutSeconds), () {
      if (_callState == CallState.outgoing) {
        callEndReason = 'no-answer';
        _recordMissedCall(userId, isVideo ? 'video' : 'voice');
        endCall(isTimeout: true);
      }
    });
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
    // Notify server call was accepted so CallHistory status updates
    _socket.emitCallAccepted(currentRemoteUserId!, callId: _currentCallId);
    for (var c in _pendingIce) { await _pc!.addCandidate(c); }
    _pendingIce.clear();
    await _audio.stopAll();
    await Helper.setSpeakerphoneOn(false);
    _callState = CallState.active;
    _callStateController.add(CallState.active);
  }


  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    try {
      final res = await http.get(
        Uri.parse('https://project-50s.onrender.com/api/ice-servers'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final servers = (data['iceServers'] as List).map((s) => Map<String, dynamic>.from(s)).toList();
        print('[ICE] Fetched \${servers.length} servers from Twilio NTS');
        return servers;
      }
    } catch (e) {
      print('[ICE] Failed to fetch, using fallback: \$e');
    }
    // Fallback — multiple STUN + open TURN for NAT traversal on older Android
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ];
  }

  Future<void> _setup(bool v) async {
    _pc = await createPeerConnection({
      'iceServers': await _fetchIceServers(),
      'sdpSemantics': 'unified-plan'
    });
    
    _pc!.onIceConnectionState = (s) => print('[ICE] state: \$s');
    _pc!.onConnectionState = (s) {
      print('[CONN] state: \$s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_callState != CallState.active) {
          _callState = CallState.active;
          _callStateController.add(CallState.active);
        }
      }
    };
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
    _callCancelled = true;
    _audio.stopAll();
    try { _channel.invokeMethod('stopCallService'); } catch (_) {}
    _socket.emitCallRejected(currentRemoteUserId ?? "", "declined");
    _callState = CallState.ended; _callStateController.add(CallState.ended);
    _incomingCallController.add(false);
  }

  void endCall({bool callerCancelled = false, bool isTimeout = false}) {
    _callCancelled = true;
    if (callerCancelled && callEndReason.isEmpty) callEndReason = 'cancelled';
    if (!callerCancelled && !isTimeout && callEndReason.isEmpty) callEndReason = 'ended';
    _audio.stopAll();
    try { _channel.invokeMethod('stopCallService'); } catch (_) {}
    try { _channel.invokeMethod('releaseScreen'); } catch (_) {}
    try { _channel.invokeMethod('dismissIncomingCall'); } catch (_) {}
    if (callerCancelled && currentRemoteUserId != null) {
      _socket.emitCallRejected(currentRemoteUserId!, "cancelled");
    } else if (!isTimeout) {
      _socket.emitCallEnded(currentRemoteUserId ?? "");
    }
    _incomingCallController.add(false);
    _cleanup();
    _callState = CallState.ended; _callStateController.add(CallState.ended);
    _pc?.close();
    _pc = null;
    _remoteDescriptionSet = false;
  }

  void clearIncomingCall() {
    currentRemoteUserId = null;
    _pendingOffer = null;
    _callState = CallState.idle;
    _incomingCallController.add(false);
  }

  void _handleRemoteHangup() {
    _callCancelled = true;
    _audio.stopAll();
    try { _channel.invokeMethod('stopCallService'); } catch (_) {}
    try { _channel.invokeMethod('releaseScreen'); } catch (_) {}
    try { _channel.invokeMethod('dismissIncomingCall'); } catch (_) {}
    // Only reset incoming state if we were actually in incoming state
    // (not active — emitting false on active call triggers ghost incoming screen)
    if (_callState == CallState.incoming) {
      _incomingCallController.add(false);
    }
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
    isRinging = false;
    _pendingOffer = null;
    _pendingIce.clear();
    _callCancelled = false;
    callEndReason = '';
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _currentCallId = null;
    currentRemoteUserId = null;
    _callState = CallState.idle;
  }

  void _recordDeclinedCall(String recipientId, String callType) {
    final callId = _currentCallId ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    final record = {
      'callId':      callId,
      'callerId':    _socket.currentUserId ?? '',
      'recipientId': recipientId,
      'callType':    callType,
      'status':      'rejected',
      'startTime':   (_callStartTime ?? DateTime.now()).toIso8601String(),
      'duration':    0,
      'seen':        false,
    };
    CacheService.addCallRecord(record);
  }

  void _recordMissedCall(String recipientId, String callType) {
    final callId = _currentCallId ?? 'local_\${DateTime.now().millisecondsSinceEpoch}';
    final record = {
      'callId':      callId,
      'callerId':    _socket.currentUserId ?? '',
      'recipientId': recipientId,
      'callType':    callType,
      'status':      'missed',
      'startTime':   (_callStartTime ?? DateTime.now()).toIso8601String(),
      'duration':    0,
      'seen':        false,
    };
    CacheService.addCallRecord(record);
    // Notify server so recipient gets missed call recorded
    _socket.emit('call-unanswered', {
      'recipientId': recipientId,
      'callId':      _currentCallId ?? '', // only send real server callId
    });
  }

}