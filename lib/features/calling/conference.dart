import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/config/constants.dart';
import 'screen_share.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _kMaxParticipants    = 6;
const _kVadIntervalMs      = 150;
const _kVadThreshold       = 0.015;
const _kSpeakerDebounceMs  = 800;

enum ConferenceLayout { grid, spotlight, sidebar }

// ── Models ────────────────────────────────────────────────────────────────────
class ConferenceParticipant {
  final String peerId;
  final String displayName;
  MediaStream? stream;
  bool muted;
  bool videoMuted;
  bool handRaised;
  RTCPeerConnection? pc;

  ConferenceParticipant({
    required this.peerId,
    required this.displayName,
    this.stream,
    this.muted      = false,
    this.videoMuted = false,
    this.handRaised = false,
    this.pc,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────
class ConferenceService {
  final SocketService       _socket;
  final ScreenShareService  _screenShare;
  final String              _userId;
  final String              _displayName;

  String?            _roomId;
  bool               _isHost         = false;
  ConferenceLayout   _layout         = ConferenceLayout.grid;
  String?            _activeSpeakerId;
  String?            _screenSharerId;
  MediaStream?       _localStream;
  Timer?             _speakerDebounce;

  final Map<String, ConferenceParticipant> _participants = {};

  // Notifier for UI rebuild
  final ValueNotifier<ConferenceServiceState> state =
      ValueNotifier(ConferenceServiceState.idle);

  // Callbacks for UI
  void Function(String message)?                    onNotification;
  void Function(String peerId, bool raised)?        onHandRaised;
  void Function(String peerId, bool muted)?         onMicToggle;

  ConferenceService({
    required SocketService socket,
    required ScreenShareService screenShare,
    required String userId,
    required String displayName,
  })  : _socket      = socket,
        _screenShare = screenShare,
        _userId      = userId,
        _displayName = displayName {
    _bindSocketHandlers();
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  String?                           get roomId       => _roomId;
  bool                              get isInRoom     => _roomId != null;
  bool                              get isHost       => _isHost;
  ConferenceLayout                  get layout       => _layout;
  MediaStream?                      get localStream  => _localStream;
  Map<String, ConferenceParticipant> get participants =>
      Map.unmodifiable(_participants);

  // ── Public API ────────────────────────────────────────────────────────────
  Future<void> create() async {
    if (_roomId != null) { _notify('Already in a conference'); return; }
    final roomId = 'room-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await _joinRoom(roomId, isHost: true);
  }

  Future<void> join(String roomId) async {
    if (_roomId != null) { _notify('Already in a conference'); return; }
    await _joinRoom(roomId, isHost: false);
  }

  Future<void> leave() async {
    if (_roomId == null) return;
    await _teardown(notify: true);
  }

  void setLayout(ConferenceLayout layout) {
    _layout = layout;
    state.notifyListeners();
  }

  void toggleMic() {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    _socket.emit('conference:mic-toggle', {
      'roomId': _roomId,
      'userId': _userId,
      'muted':  !track.enabled,
    });
    state.notifyListeners();
  }

  void toggleCamera() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    state.notifyListeners();
  }

  void toggleHand() {
    final p = _participants[_userId];
    final raised = !(p?.handRaised ?? false);
    if (p != null) p.handRaised = raised;
    _socket.emit('conference:raise-hand', {
      'roomId': _roomId,
      'userId': _userId,
      'raised': raised,
    });
    state.notifyListeners();
  }

  Future<void> toggleScreenShare() async {
    if (_screenShare.isSharing) {
      await _screenShare.stop();
      _screenSharerId = null;
    } else {
      try {
        _screenShare.setCameraTrack(
            _localStream?.getVideoTracks().firstOrNull);
        _participants.forEach((id, p) {
          if (p.pc != null) _screenShare.addPeerConnection(id, p.pc!);
        });
        await _screenShare.start();
        _screenSharerId = _userId;
        setLayout(ConferenceLayout.spotlight);
      } catch (e) {
        _notify('Screen share failed: $e');
      }
    }
    state.notifyListeners();
  }

  void mutePeer(String peerId) {
    _socket.emit('conference:mute-peer', {
      'roomId': _roomId,
      'peerId': peerId,
      'hostId': _userId,
    });
  }

  void removePeer(String peerId) {
    _socket.emit('conference:remove-peer', {
      'roomId': _roomId,
      'peerId': peerId,
      'hostId': _userId,
    });
  }

  String? copyInviteLink() => _roomId;

  // ── Room join / teardown ──────────────────────────────────────────────────
  Future<void> _joinRoom(String roomId, {required bool isHost}) async {
    try {
      _roomId  = roomId;
      _isHost  = isHost;

      _localStream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': true,
      });

      _socket.emit('conference:join', {
        'roomId':      roomId,
        'userId':      _userId,
        'displayName': _displayName,
        'isHost':      isHost,
      });

      state.value = ConferenceServiceState.inRoom;
      _notify(isHost ? 'Conference created' : 'Joined conference');
    } catch (e) {
      debugPrint('[Conference] Join error: $e');
      _notify('Failed to start conference: $e');
      await _teardown(notify: false);
    }
  }

  Future<void> _teardown({required bool notify}) async {
    for (final p in _participants.values) {
      _closePeer(p.peerId);
    }
    _participants.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;

    if (notify && _roomId != null) {
      _socket.emit('conference:leave', {
        'roomId': _roomId,
        'userId': _userId,
      });
    }

    _roomId          = null;
    _isHost          = false;
    _activeSpeakerId = null;
    _screenSharerId  = null;
    _speakerDebounce?.cancel();

    state.value = ConferenceServiceState.idle;
    if (notify) _notify('Left conference');
  }

  // ── Peer connection ───────────────────────────────────────────────────────
  Future<void> _createPeer(String peerId, String displayName,
      {required bool isInitiator}) async {
    if (_participants.containsKey(peerId)) return;

    final pc = await createPeerConnection({
      'iceServers': AppConstants.iceServers,
    });

    final participant = ConferenceParticipant(
      peerId:      peerId,
      displayName: displayName,
      stream:      null,
      pc:          pc,
    );

    _participants[peerId] = participant;

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        participant.stream = event.streams.first;
        state.notifyListeners();
      }
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket.emit('conference:ice', {
          'roomId':    _roomId,
          'to':        peerId,
          'from':      _userId,
          'candidate': candidate.toMap(),
        });
      }
    };

    pc.onIceConnectionState = (iceState) {
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _removeParticipant(peerId);
      }
    };

    _screenShare.addPeerConnection(peerId, pc);

    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket.emit('conference:offer', {
        'roomId':      _roomId,
        'to':          peerId,
        'from':        _userId,
        'offer':       offer.toMap(),
        'displayName': _displayName,
      });
    }

    state.notifyListeners();
  }

  void _closePeer(String peerId) {
    final p = _participants[peerId];
    if (p == null) return;
    p.pc?.close();
    p.stream?.dispose();
    _screenShare.removePeerConnection(peerId);
    _participants.remove(peerId);
  }

  void _removeParticipant(String peerId) {
    _closePeer(peerId);
    state.notifyListeners();
  }

  Future<void> _handleOffer(
      String from, String displayName, Map<String, dynamic> offer) async {
    if (_roomId == null) return;
    if (!_participants.containsKey(from)) {
      await _createPeer(from, displayName, isInitiator: false);
    }
    final p = _participants[from];
    if (p?.pc == null) return;
    await p!.pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']));
    final answer = await p.pc!.createAnswer();
    await p.pc!.setLocalDescription(answer);
    _socket.emit('conference:answer', {
      'roomId': _roomId,
      'to':     from,
      'from':   _userId,
      'answer': answer.toMap(),
    });
  }

  Future<void> _handleAnswer(
      String from, Map<String, dynamic> answer) async {
    final p = _participants[from];
    if (p?.pc == null) return;
    await p!.pc!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']));
  }

  Future<void> _handleIce(
      String from, Map<String, dynamic> candidate) async {
    final p = _participants[from];
    if (p?.pc == null) return;
    await p!.pc!.addCandidate(RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMLineIndex'],
    ));
  }

  // ── Socket handlers ───────────────────────────────────────────────────────
  void _bindSocketHandlers() {
    // Raw socket listeners via SocketService emit/on pattern
    // Wire these from your socket_service by adding conference streams,
    // or call these handlers directly from a socket listener in your app.
  }

  // Call these from your socket listener in app.dart / main socket handler:
  void handlePeerJoined(Map<String, dynamic> data) {
    final peerId      = data['peerId']      as String?;
    final displayName = data['displayName'] as String? ?? '';
    if (peerId == null || peerId == _userId) return;
    if (_participants.length >= _kMaxParticipants - 1) {
      _notify('Conference is full (max $_kMaxParticipants participants)');
      return;
    }
    _notify('$displayName joined the conference');
    _createPeer(peerId, displayName, isInitiator: true);
  }

  void handlePeerLeft(Map<String, dynamic> data) {
    final peerId      = data['peerId']      as String?;
    final displayName = data['displayName'] as String? ?? '';
    if (peerId == null) return;
    _notify('$displayName left the conference');
    _removeParticipant(peerId);
  }

  void handleOffer(Map<String, dynamic> data) {
    final from        = data['from']        as String?;
    final displayName = data['displayName'] as String? ?? '';
    final offer       = data['offer']       as Map<String, dynamic>?;
    if (from == null || offer == null) return;
    _handleOffer(from, displayName, offer);
  }

  void handleAnswer(Map<String, dynamic> data) {
    final from   = data['from']   as String?;
    final answer = data['answer'] as Map<String, dynamic>?;
    if (from == null || answer == null) return;
    _handleAnswer(from, answer);
  }

  void handleIce(Map<String, dynamic> data) {
    final from      = data['from']      as String?;
    final candidate = data['candidate'] as Map<String, dynamic>?;
    if (from == null || candidate == null) return;
    _handleIce(from, candidate);
  }

  void handleMicToggle(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final muted  = data['muted']  as bool? ?? false;
    if (userId == null) return;
    final p = _participants[userId];
    if (p != null) {
      p.muted = muted;
      state.notifyListeners();
    }
    onMicToggle?.call(userId, muted);
  }

  void handleRaiseHand(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final raised = data['raised'] as bool? ?? false;
    if (userId == null) return;
    final p = _participants[userId];
    if (p != null) {
      p.handRaised = raised;
      state.notifyListeners();
    }
    if (raised) _notify('${p?.displayName ?? userId} raised their hand ✋');
    onHandRaised?.call(userId, raised);
  }

  void handleMutedByHost(_) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
    _notify('You were muted by the host');
    state.notifyListeners();
  }

  void handleRemovedByHost(_) {
    _notify('You were removed from the conference');
    _teardown(notify: false);
  }

  void handleScreenShareStarted(Map<String, dynamic> data) {
    _screenSharerId = data['userId'] as String?;
    setLayout(ConferenceLayout.spotlight);
  }

  void handleScreenShareStopped(_) {
    _screenSharerId = null;
    setLayout(ConferenceLayout.grid);
  }

  void handleRoomClosed(_) {
    _notify('Conference ended by host');
    _teardown(notify: false);
  }

  void _notify(String msg) => onNotification?.call(msg);

  void dispose() {
    _teardown(notify: false);
    state.dispose();
  }
}

enum ConferenceServiceState { idle, inRoom }

// ── Conference Overlay Widget ─────────────────────────────────────────────────
class ConferenceOverlay extends StatefulWidget {
  final ConferenceService service;

  const ConferenceOverlay({super.key, required this.service});

  @override
  State<ConferenceOverlay> createState() => _ConferenceOverlayState();
}

class _ConferenceOverlayState extends State<ConferenceOverlay> {
  ConferenceService get _svc => widget.service;

  @override
  void initState() {
    super.initState();
    _svc.state.addListener(_onStateChange);
    _svc.onNotification = (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    };
  }

  @override
  void dispose() {
    _svc.state.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_svc.state.value == ConferenceServiceState.idle) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildGrid()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _svc.participants.length + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _svc.leave(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room: ${_svc.roomId ?? ''}',
                    style: const TextStyle(color: Colors.white70,
                        fontSize: 12)),
                Text('$count participant${count != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white),
            onPressed: () {
              final layouts = ConferenceLayout.values;
              final next = layouts[
                  (layouts.indexOf(_svc.layout) + 1) % layouts.length];
              _svc.setLayout(next);
            },
          ),
          IconButton(
            icon: const Icon(Icons.link, color: Colors.white),
            onPressed: () {
              final roomId = _svc.copyInviteLink();
              if (roomId != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Room ID: $roomId')));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final allPeers = _svc.participants.values.toList();
    final localStream = _svc.localStream;

    if (allPeers.isEmpty) {
      return Center(
        child: localStream != null
            ? _buildVideoTile(
                stream: localStream,
                label: 'You',
                muted: false,
                handRaised: false,
              )
            : const Text('Starting camera...',
                style: TextStyle(color: Colors.white)),
      );
    }

    final tiles = <Widget>[
      if (localStream != null)
        _buildVideoTile(
          stream: localStream,
          label: 'You',
          muted: !(localStream.getAudioTracks().firstOrNull?.enabled ?? true),
          handRaised: false,
        ),
      ...allPeers.map((p) => _buildVideoTile(
            stream: p.stream,
            label: p.displayName,
            muted: p.muted,
            handRaised: p.handRaised,
          )),
    ];

    return GridView.count(
      crossAxisCount: tiles.length <= 2 ? 1 : 2,
      children: tiles,
    );
  }

  Widget _buildVideoTile({
    required MediaStream? stream,
    required String label,
    required bool muted,
    required bool handRaised,
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade900,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: stream != null
                ? RTCVideoView(
                    RTCVideoRenderer()..srcObject = stream,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : const Center(
                    child: Icon(Icons.person, color: Colors.white54,
                        size: 48)),
          ),
          Positioned(
            bottom: 8, left: 8,
            child: Row(
              children: [
                if (muted)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.mic_off, color: Colors.white,
                        size: 14),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 11)),
                ),
                if (handRaised)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('✋',
                        style: TextStyle(fontSize: 14)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final micEnabled = _svc.localStream
            ?.getAudioTracks()
            .firstOrNull
            ?.enabled ??
        true;
    final camEnabled = _svc.localStream
            ?.getVideoTracks()
            .firstOrNull
            ?.enabled ??
        true;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(
            icon: micEnabled ? Icons.mic : Icons.mic_off,
            label: micEnabled ? 'Mute' : 'Unmute',
            onTap: _svc.toggleMic,
          ),
          _CtrlBtn(
            icon: camEnabled ? Icons.videocam : Icons.videocam_off,
            label: camEnabled ? 'Cam Off' : 'Cam On',
            onTap: _svc.toggleCamera,
          ),
          _CtrlBtn(
            icon: Icons.pan_tool_outlined,
            label: 'Hand',
            active: _svc.participants[_svc._userId]?.handRaised ?? false,
            onTap: _svc.toggleHand,
          ),
          _CtrlBtn(
            icon: Icons.screen_share_outlined,
            label: 'Share',
            active: _svc._screenSharerId == _svc._userId,
            onTap: _svc.toggleScreenShare,
          ),
          _CtrlBtn(
            icon: Icons.call_end,
            label: 'Leave',
            danger: true,
            onTap: _svc.leave,
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: danger
                ? Colors.red
                : active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
