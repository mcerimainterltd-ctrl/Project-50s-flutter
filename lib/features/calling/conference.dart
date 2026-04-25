import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/theme/app_theme.dart';
import 'screen_share.dart';

const _kMaxParticipants = 6;

enum ConferenceLayout { grid, spotlight, sidebar }
enum ConferenceServiceState { idle, inRoom }

// ── Models ────────────────────────────────────────────────────────────────────
class ConferenceParticipant {
  final String peerId, displayName;
  MediaStream? stream;
  bool muted, videoMuted, handRaised;
  RTCPeerConnection? pc;

  ConferenceParticipant({required this.peerId, required this.displayName,
      this.stream, this.muted = false, this.videoMuted = false,
      this.handRaised = false, this.pc});
}

// ── Service ───────────────────────────────────────────────────────────────────
class ConferenceService {
  final SocketService      _socket;
  final ScreenShareService _screenShare;
  final String             _userId;
  final String             _displayName;

  String?            _roomId;
  bool               _isHost         = false;
  ConferenceLayout   _layout         = ConferenceLayout.grid;
  String?            _screenSharerId;
  MediaStream?       _localStream;

  final Map<String, ConferenceParticipant> _participants = {};
  final ValueNotifier<ConferenceServiceState> state =
      ValueNotifier(ConferenceServiceState.idle);

  void Function(String message)?             onNotification;
  void Function(String peerId, bool raised)? onHandRaised;
  void Function(String peerId, bool muted)?  onMicToggle;

  ConferenceService({required SocketService socket,
      required ScreenShareService screenShare,
      required String userId, required String displayName})
      : _socket      = socket,
        _screenShare = screenShare,
        _userId      = userId,
        _displayName = displayName;

  String?                              get roomId      => _roomId;
  bool                                 get isInRoom    => _roomId != null;
  bool                                 get isHost      => _isHost;
  ConferenceLayout                     get layout      => _layout;
  MediaStream?                         get localStream => _localStream;
  Map<String, ConferenceParticipant>   get participants =>
      Map.unmodifiable(_participants);

  // ── Public API ────────────────────────────────────────────────────────────
  Future<void> create() async {
    if (_roomId != null) { _notify('Already in a conference'); return; }
    await _joinRoom(
        'room-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        isHost: true);
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
    _socket.emit('conference:mic-toggle', {'roomId': _roomId,
        'userId': _userId, 'muted': !track.enabled});
    state.notifyListeners();
  }

  void toggleCamera() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    state.notifyListeners();
  }

  void toggleHand() {
    final p      = _participants[_userId];
    final raised = !(p?.handRaised ?? false);
    if (p != null) p.handRaised = raised;
    _socket.emit('conference:raise-hand', {'roomId': _roomId,
        'userId': _userId, 'raised': raised});
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
      } catch (e) { _notify('Screen share failed: $e'); }
    }
    state.notifyListeners();
  }

  void mutePeer(String peerId) => _socket.emit('conference:mute-peer',
      {'roomId': _roomId, 'peerId': peerId, 'hostId': _userId});

  void removePeer(String peerId) => _socket.emit('conference:remove-peer',
      {'roomId': _roomId, 'peerId': peerId, 'hostId': _userId});

  String? copyInviteLink() => _roomId;

  // ── Room ──────────────────────────────────────────────────────────────────
  Future<void> _joinRoom(String roomId, {required bool isHost}) async {
    try {
      _roomId = roomId; _isHost = isHost;
      _localStream = await navigator.mediaDevices
          .getUserMedia({'video': true, 'audio': true});
      _socket.emit('conference:join', {'roomId': roomId, 'userId': _userId,
          'displayName': _displayName, 'isHost': isHost});
      state.value = ConferenceServiceState.inRoom;
      _notify(isHost ? 'Conference created' : 'Joined conference');
    } catch (e) {
      debugPrint('[Conference] Join error: $e');
      _notify('Failed to start conference: $e');
      await _teardown(notify: false);
    }
  }

  Future<void> _teardown({required bool notify}) async {
    for (final p in _participants.values) { _closePeer(p.peerId); }
    _participants.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    if (notify && _roomId != null) {
      _socket.emit('conference:leave',
          {'roomId': _roomId, 'userId': _userId});
    }
    _roomId = null; _isHost = false;
    _screenSharerId = null;
    state.value = ConferenceServiceState.idle;
    if (notify) _notify('Left conference');
  }

  // ── Peer connections ──────────────────────────────────────────────────────
  Future<void> _createPeer(String peerId, String displayName,
      {required bool isInitiator}) async {
    if (_participants.containsKey(peerId)) return;
    final pc = await createPeerConnection({'iceServers': AppConstants.iceServers});
    final participant = ConferenceParticipant(peerId: peerId,
        displayName: displayName, pc: pc);
    _participants[peerId] = participant;
    _localStream?.getTracks().forEach((t) => pc.addTrack(t, _localStream!));

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        participant.stream = event.streams.first;
        state.notifyListeners();
      }
    };
    pc.onIceCandidate = (c) {
      if (c.candidate != null) _socket.emit('conference:ice',
          {'roomId': _roomId, 'to': peerId, 'from': _userId,
           'candidate': c.toMap()});
    };
    pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          s == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _removeParticipant(peerId);
      }
    };
    _screenShare.addPeerConnection(peerId, pc);

    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket.emit('conference:offer', {'roomId': _roomId, 'to': peerId,
          'from': _userId, 'offer': offer.toMap(),
          'displayName': _displayName});
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

  Future<void> _handleOffer(String from, String displayName,
      Map<String, dynamic> offer) async {
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
    _socket.emit('conference:answer', {'roomId': _roomId, 'to': from,
        'from': _userId, 'answer': answer.toMap()});
  }

  Future<void> _handleAnswer(String from,
      Map<String, dynamic> answer) async {
    final p = _participants[from];
    if (p?.pc == null) return;
    await p!.pc!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']));
  }

  Future<void> _handleIce(String from,
      Map<String, dynamic> candidate) async {
    final p = _participants[from];
    if (p?.pc == null) return;
    await p!.pc!.addCandidate(RTCIceCandidate(candidate['candidate'],
        candidate['sdpMid'], candidate['sdpMLineIndex']));
  }

  // ── Socket event handlers (call from app socket listener) ─────────────────
  void handlePeerJoined(Map<String, dynamic> data) {
    final peerId      = data['peerId']      as String?;
    final displayName = data['displayName'] as String? ?? '';
    if (peerId == null || peerId == _userId) return;
    if (_participants.length >= _kMaxParticipants - 1) {
      _notify('Conference full (max $_kMaxParticipants)'); return;
    }
    _notify('$displayName joined');
    _createPeer(peerId, displayName, isInitiator: true);
  }

  void handlePeerLeft(Map<String, dynamic> data) {
    final peerId      = data['peerId']      as String?;
    final displayName = data['displayName'] as String? ?? '';
    if (peerId == null) return;
    _notify('$displayName left');
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
    if (p != null) { p.muted = muted; state.notifyListeners(); }
    onMicToggle?.call(userId, muted);
  }

  void handleRaiseHand(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final raised = data['raised'] as bool? ?? false;
    if (userId == null) return;
    final p = _participants[userId];
    if (p != null) { p.handRaised = raised; state.notifyListeners(); }
    if (raised) _notify('${p?.displayName ?? userId} raised hand ✋');
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

  void dispose() { _teardown(notify: false); state.dispose(); }
}

// ── Conference Overlay ────────────────────────────────────────────────────────
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
    _svc.state.addListener(_rebuild);
    _svc.onNotification = (msg) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: context.xCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    };
  }

  @override
  void dispose() { _svc.state.removeListener(_rebuild); super.dispose(); }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    if (_svc.state.value == ConferenceServiceState.idle) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: context.xBg,
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        Expanded(child: _buildGrid()),
        _buildControls(),
      ])),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final count = _svc.participants.length + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: context.xSurface,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => _svc.leave(),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: context.xCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 14),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room: ${_svc.roomId ?? ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text('$count participant${count != 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        )),
        // Layout toggle
        GestureDetector(
          onTap: () {
            final layouts = ConferenceLayout.values;
            _svc.setLayout(layouts[
                (layouts.indexOf(_svc.layout) + 1) % layouts.length]);
          },
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: context.xCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.grid_view_rounded,
                color: Colors.white70, size: 16),
          ),
        ),
        const SizedBox(width: 8),
        // Invite
        GestureDetector(
          onTap: () {
            final roomId = _svc.copyInviteLink();
            if (roomId != null) ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(
              content: Text('Room ID: $roomId'),
              backgroundColor: context.xCard,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ));
          },
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: context.xCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.link_rounded,
                color: Colors.white70, size: 16),
          ),
        ),
      ]),
    );
  }

  // ── Video Grid ────────────────────────────────────────────────────────────
  Widget _buildGrid() {
    final peers       = _svc.participants.values.toList();
    final localStream = _svc.localStream;
    final total       = peers.length + 1;

    if (total == 1) {
      return Center(child: localStream != null
          ? _videoTile(stream: localStream, label: 'You',
              muted: false, handRaised: false, large: true)
          : const CircularProgressIndicator(
              color: context.xPrimary, strokeWidth: 2));
    }

    return GridView.count(
      crossAxisCount: total <= 2 ? 1 : 2,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        if (localStream != null)
          _videoTile(
            stream: localStream, label: 'You',
            muted: !(_svc.localStream?.getAudioTracks()
                    .firstOrNull?.enabled ?? true),
            handRaised: false),
        ...peers.map((p) => _videoTile(
          stream: p.stream, label: p.displayName,
          muted: p.muted, handRaised: p.handRaised)),
      ],
    );
  }

  Widget _videoTile({required MediaStream? stream, required String label,
      required bool muted, required bool handRaised, bool large = false}) {
    return Container(
      decoration: BoxDecoration(
        color: context.xCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(fit: StackFit.expand, children: [
          // Video / placeholder
          stream != null
              ? RTCVideoView(
                  RTCVideoRenderer()..srcObject = stream,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Container(
                  color: context.xCard,
                  child: Center(child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [context.xPrimary, context.xSurface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: Text(
                        label.isNotEmpty ? label[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.black,
                            fontSize: 22, fontWeight: FontWeight.w800))),
                  ))),
          // Gradient overlay
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent]),
              ),
              child: Row(children: [
                if (muted)
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: context.xDanger.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.mic_off,
                        color: Colors.white, size: 12),
                  ),
                if (muted) const SizedBox(width: 4),
                Expanded(child: Text(label,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                if (handRaised)
                  const Text('✋', style: TextStyle(fontSize: 14)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────
  Widget _buildControls() {
    final micOn = _svc.localStream?.getAudioTracks()
            .firstOrNull?.enabled ?? true;
    final camOn = _svc.localStream?.getVideoTracks()
            .firstOrNull?.enabled ?? true;
    final sharing    = _svc._screenSharerId == _svc._userId;
    final handRaised = _svc.participants[_svc._userId]?.handRaised ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: const BoxDecoration(
        color: context.xSurface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ctrlBtn(
            icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: micOn ? 'Mute' : 'Unmute',
            active: !micOn,
            activeColor: context.xDanger,
            onTap: _svc.toggleMic),
          _ctrlBtn(
            icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: camOn ? 'Cam' : 'Cam Off',
            active: !camOn,
            activeColor: context.xDanger,
            onTap: _svc.toggleCamera),
          _ctrlBtn(
            icon: Icons.pan_tool_outlined,
            label: 'Hand',
            active: handRaised,
            activeColor: context.xAccent,
            onTap: _svc.toggleHand),
          _ctrlBtn(
            icon: Icons.screen_share_outlined,
            label: 'Share',
            active: sharing,
            activeColor: context.xPrimary,
            onTap: _svc.toggleScreenShare),
          // End button
          GestureDetector(
            onTap: _svc.leave,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: context.xDanger,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: context.xDanger.withValues(alpha: 0.4),
                    blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.call_end_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(height: 4),
              const Text('Leave',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn({required IconData icon, required String label,
      required bool active, required Color activeColor,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.15)
                : context.xCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.4)
                  : Colors.white10),
          ),
          child: Icon(icon,
              color: active ? activeColor : Colors.white70, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
            color: active ? activeColor : Colors.white38,
            fontSize: 10, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
