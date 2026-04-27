
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../contacts/providers/contacts_provider.dart';

// ── Peer model ────────────────────────────────────────────────────────────────
class _ConferencePeer {
  final String peerId, displayName;
  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  bool muted, videoMuted, handRaised;

  _ConferencePeer({
    required this.peerId,
    required this.displayName,
    required this.pc,
    required this.renderer,
    this.muted = false,
    this.videoMuted = false,
    this.handRaised = false,
  });
}

// ── RTC config ────────────────────────────────────────────────────────────────
const _rtcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ]
};

// ── Conference state ──────────────────────────────────────────────────────────
enum ConferenceLayout { grid, spotlight, sidebar }

class ConferenceState {
  final String?  roomId;
  final bool     isHost, micOn, camOn;
  final ConferenceLayout layout;
  final int participantCount;
  const ConferenceState({
    this.roomId, this.isHost = false,
    this.micOn = true, this.camOn = true,
    this.layout = ConferenceLayout.grid,
    this.participantCount = 0,
  });
  bool get inConference => roomId != null;
  ConferenceState copyWith({
    String? roomId, bool? isHost, bool? micOn, bool? camOn,
    ConferenceLayout? layout, int? participantCount, bool clearRoom = false,
  }) => ConferenceState(
    roomId:           clearRoom ? null : (roomId ?? this.roomId),
    isHost:           isHost           ?? this.isHost,
    micOn:            micOn            ?? this.micOn,
    camOn:            camOn            ?? this.camOn,
    layout:           layout           ?? this.layout,
    participantCount: participantCount ?? this.participantCount,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
final conferenceProvider =
    StateNotifierProvider<ConferenceNotifier, ConferenceState>(
        ConferenceNotifier.new);

class ConferenceNotifier extends StateNotifier<ConferenceState> {
  final Ref _ref;
  static const _maxPeers = 5; // 6 total incl. self

  // Local media
  MediaStream?      _localStream;
  RTCVideoRenderer? _localRenderer;

  // Peers: peerId → _ConferencePeer
  final Map<String, _ConferencePeer> _peers = {};

  // Stream for UI to observe peer list changes
  final _peersController = StreamController<List<_ConferencePeer>>.broadcast();
  Stream<List<_ConferencePeer>> get peersStream => _peersController.stream;

  // Local renderer for UI
  RTCVideoRenderer? get localRenderer => _localRenderer;

  ConferenceNotifier(this._ref) : super(const ConferenceState()) {
    _listenSocket();
  }

  List<_ConferencePeer> get peers => List.unmodifiable(_peers.values);

  void _listenSocket() {
    final socket = _ref.read(socketServiceProvider);

    socket.rawSocket?.on('conference:peer-joined', (data) async {
      final map  = Map<String, dynamic>.from(data as Map);
      final peer = map['peerId'] as String;
      final name = map['displayName'] as String? ?? peer;
      final me   = _ref.read(currentUserProvider)?.xameId;
      if (peer == me || _peers.containsKey(peer)) return;
      if (_peers.length >= _maxPeers) return;
      await _createPeer(peer, name, isInitiator: true);
    });

    socket.rawSocket?.on('conference:offer', (data) async {
      if (!state.inConference) return;
      final map  = Map<String, dynamic>.from(data as Map);
      final from = map['from'] as String;
      final name = map['displayName'] as String? ?? from;
      final offer = RTCSessionDescription(
        map['offer']['sdp'] as String, map['offer']['type'] as String);
      if (!_peers.containsKey(from)) {
        await _createPeer(from, name, isInitiator: false);
      }
      final peer = _peers[from]!;
      await peer.pc.setRemoteDescription(offer);
      final answer = await peer.pc.createAnswer();
      await peer.pc.setLocalDescription(answer);
      socket.rawSocket?.emit('conference:answer', {
        'roomId': state.roomId, 'to': from,
        'from': _ref.read(currentUserProvider)?.xameId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
    });

    socket.rawSocket?.on('conference:answer', (data) async {
      final map  = Map<String, dynamic>.from(data as Map);
      final from = map['from'] as String;
      final peer = _peers[from];
      if (peer == null) return;
      final answer = RTCSessionDescription(
        map['answer']['sdp'] as String, map['answer']['type'] as String);
      await peer.pc.setRemoteDescription(answer);
    });

    socket.rawSocket?.on('conference:ice', (data) async {
      final map  = Map<String, dynamic>.from(data as Map);
      final from = map['from'] as String;
      final peer = _peers[from];
      if (peer == null) return;
      final ice = RTCIceCandidate(
        map['candidate']['candidate'] as String,
        map['candidate']['sdpMid'] as String?,
        map['candidate']['sdpMLineIndex'] as int?);
      await peer.pc.addCandidate(ice);
    });

    socket.rawSocket?.on('conference:peer-left', (data) async {
      final map  = Map<String, dynamic>.from(data as Map);
      final peer = map['peerId'] as String;
      await _removePeer(peer);
    });

    socket.rawSocket?.on('conference:muted-by-host', (_) {
      state = state.copyWith(micOn: false);
      _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
    });

    socket.rawSocket?.on('conference:removed-by-host', (_) => leave());
    socket.rawSocket?.on('conference:room-closed', (_) => leave());

    socket.rawSocket?.on('conference:mic-toggle', (data) {
      final map   = Map<String, dynamic>.from(data as Map);
      final peer  = map['userId'] as String;
      final muted = map['muted'] as bool? ?? false;
      if (_peers.containsKey(peer)) {
        _peers[peer]!.muted = muted;
        _notifyPeers();
      }
    });

    socket.rawSocket?.on('conference:raise-hand', (data) {
      final map    = Map<String, dynamic>.from(data as Map);
      final peer   = map['userId'] as String;
      final raised = map['raised'] as bool? ?? false;
      if (_peers.containsKey(peer)) {
        _peers[peer]!.handRaised = raised;
        _notifyPeers();
      }
    });
  }

  Future<void> create() async {
    if (state.inConference) return;
    final roomId = 'room-${DateTime.now().millisecondsSinceEpoch}';
    await _joinRoom(roomId, true);
  }

  Future<void> join(String roomId) async {
    if (state.inConference) return;
    await _joinRoom(roomId, false);
  }

  Future<void> _joinRoom(String roomId, bool isHost) async {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    if (user == null) return;

    // Init local renderer
    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();

    // Get camera + mic
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 640, 'height': 480},
    });
    _localRenderer!.srcObject = _localStream;

    state = state.copyWith(roomId: roomId, isHost: isHost);

    socket.rawSocket?.emit('conference:join', {
      'roomId':      roomId,
      'userId':      user.xameId,
      'displayName': user.firstName,
      'isHost':      isHost,
    });
  }

  Future<void> _createPeer(String peerId, String displayName,
      {required bool isInitiator}) async {
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;

    final pc       = await createPeerConnection(_rtcConfig);
    final renderer = RTCVideoRenderer();
    await renderer.initialize();

    final peer = _ConferencePeer(
        peerId: peerId, displayName: displayName, pc: pc, renderer: renderer);
    _peers[peerId] = peer;

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    // Remote track → renderer
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams[0];
        _notifyPeers();
      }
    };

    // ICE candidates
    pc.onIceCandidate = (candidate) {
      socket.rawSocket?.emit('conference:ice', {
        'roomId': state.roomId, 'to': peerId, 'from': me,
        'candidate': {
          'candidate':     candidate.candidate,
          'sdpMid':        candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _removePeer(peerId);
      }
    };

    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      socket.rawSocket?.emit('conference:offer', {
        'roomId': state.roomId, 'to': peerId, 'from': me,
        'displayName': _ref.read(currentUserProvider)?.firstName,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
    }

    state = state.copyWith(participantCount: _peers.length);
    _notifyPeers();
  }

  Future<void> _removePeer(String peerId) async {
    final peer = _peers.remove(peerId);
    if (peer != null) {
      await peer.pc.close();
      await peer.renderer.dispose();
    }
    state = state.copyWith(participantCount: _peers.length);
    _notifyPeers();
  }

  void _notifyPeers() {
    _peersController.add(List.unmodifiable(_peers.values));
  }

  Future<void> leave() async {
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;
    if (state.roomId != null) {
      socket.rawSocket?.emit('conference:leave',
          {'roomId': state.roomId, 'userId': me});
    }
    for (final peer in _peers.values) {
      await peer.pc.close();
      await peer.renderer.dispose();
    }
    _peers.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    await _localRenderer?.dispose();
    _localRenderer = null;
    state = state.copyWith(clearRoom: true, participantCount: 0);
    _notifyPeers();
  }

  void toggleMic() {
    final newVal = !state.micOn;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = newVal);
    state = state.copyWith(micOn: newVal);
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;
    socket.rawSocket?.emit('conference:mic-toggle', {
      'roomId': state.roomId, 'userId': me, 'muted': !newVal,
    });
  }

  void toggleCam() {
    final newVal = !state.camOn;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = newVal);
    state = state.copyWith(camOn: newVal);
  }

  void cycleLayout() {
    final layouts = ConferenceLayout.values;
    final next    = layouts[(state.layout.index + 1) % layouts.length];
    state = state.copyWith(layout: next);
  }

  void raiseHand() {
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;
    socket.rawSocket?.emit('conference:raise-hand',
        {'roomId': state.roomId, 'userId': me, 'raised': true});
  }

  void muteParticipant(String peerId) {
    if (!state.isHost) return;
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;
    socket.rawSocket?.emit('conference:mute-peer',
        {'roomId': state.roomId, 'hostId': me, 'peerId': peerId});
  }

  void removeParticipant(String peerId) {
    if (!state.isHost) return;
    final socket = _ref.read(socketServiceProvider);
    final me     = _ref.read(currentUserProvider)?.xameId;
    socket.rawSocket?.emit('conference:remove-peer',
        {'roomId': state.roomId, 'hostId': me, 'peerId': peerId});
  }

  @override
  void dispose() {
    _peersController.close();
    super.dispose();
  }
}

// ── Conference Screen ─────────────────────────────────────────────────────────
class ConferenceScreen extends ConsumerWidget {
  const ConferenceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conf = ref.watch(conferenceProvider);
    if (conf.inConference) return const _ActiveConferenceView();
    return const _ConferenceLobby();
  }
}

// ── Lobby ─────────────────────────────────────────────────────────────────────
class _ConferenceLobby extends ConsumerWidget {
  const _ConferenceLobby();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    return Scaffold(
      backgroundColor: context.xBg,
      body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: context.xCard, shape: BoxShape.circle,
              border: Border.all(
                  color: context.xPrimary.withValues(alpha: 0.3))),
            child: Icon(Icons.groups_rounded,
                color: context.xPrimary, size: 56)),
          const SizedBox(height: 24),
          Text('Conference Call',
              style: TextStyle(color: context.xText,
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Host or join a group call with up to 6 people',
              style: TextStyle(color: context.xMuted, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  ref.read(conferenceProvider.notifier).create(),
              icon: const Icon(Icons.video_call_rounded),
              label: const Text('Start Conference',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(
              controller: ctrl,
              style: TextStyle(color: context.xText),
              decoration: InputDecoration(
                hintText: 'Enter Room ID to join',
                hintStyle: TextStyle(color: context.xMuted),
                filled: true, fillColor: context.xCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14)),
            )),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                ref.read(conferenceProvider.notifier).join(ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              child: const Text('Join',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ]),
      )),
    );
  }
}

// ── Active conference view ────────────────────────────────────────────────────
class _ActiveConferenceView extends ConsumerStatefulWidget {
  const _ActiveConferenceView();
  @override
  ConsumerState<_ActiveConferenceView> createState() =>
      _ActiveConferenceViewState();
}

class _ActiveConferenceViewState
    extends ConsumerState<_ActiveConferenceView> {
  List<_ConferencePeer> _peers = [];
  StreamSubscription? _peersSub;

  @override
  void initState() {
    super.initState();
    _peersSub = ref
        .read(conferenceProvider.notifier)
        .peersStream
        .listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conf      = ref.watch(conferenceProvider);
    final notifier  = ref.read(conferenceProvider.notifier);
    final user      = ref.watch(currentUserProvider);
    final total     = _peers.length + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Room: ${conf.roomId}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text('$total participant${total != 1 ? "s" : ""}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ])),
            IconButton(
              icon: const Icon(Icons.link_rounded, color: Colors.white54),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: conf.roomId!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Room ID copied!')));
              }),
            IconButton(
              icon: Icon(
                conf.layout == ConferenceLayout.grid
                    ? Icons.grid_view_rounded
                    : Icons.view_sidebar_rounded,
                color: Colors.white54),
              onPressed: () => notifier.cycleLayout()),
          ]),
        ),

        // Video grid
        Expanded(child: _VideoGrid(
          peers:         _peers,
          localRenderer: notifier.localRenderer,
          localName:     user?.firstName ?? 'You',
          conf:          conf,
          notifier:      notifier,
        )),

        // Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black87,
            border: Border(top: BorderSide(color: Colors.white12))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CtrlBtn(
                icon: conf.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: conf.micOn ? 'Mute' : 'Unmute',
                active: conf.micOn,
                onTap: () => notifier.toggleMic()),
              _CtrlBtn(
                icon: conf.camOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: conf.camOn ? 'Camera' : 'Cam Off',
                active: conf.camOn,
                onTap: () => notifier.toggleCam()),
              _CtrlBtn(
                icon: Icons.pan_tool_rounded,
                label: 'Hand',
                active: true,
                onTap: () => notifier.raiseHand()),
              _CtrlBtn(
                icon: Icons.call_end_rounded,
                label: 'Leave',
                active: false,
                danger: true,
                onTap: () => notifier.leave()),
            ]),
        ),
      ])),
    );
  }
}

// ── Video grid ────────────────────────────────────────────────────────────────
class _VideoGrid extends StatelessWidget {
  final List<_ConferencePeer> peers;
  final RTCVideoRenderer?     localRenderer;
  final String                localName;
  final ConferenceState       conf;
  final ConferenceNotifier    notifier;

  const _VideoGrid({
    required this.peers, required this.localRenderer,
    required this.localName, required this.conf, required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final total = peers.length + 1;
    final cols  = total <= 1 ? 1 : total <= 4 ? 2 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:  cols,
        crossAxisSpacing: 4, mainAxisSpacing: 4,
        childAspectRatio: total == 1 ? 9/16 : 1),
      itemCount: total,
      itemBuilder: (_, i) {
        // First tile = local video
        if (i == 0) {
          return _VideoTile(
            renderer:    localRenderer,
            displayName: '$localName (You)',
            muted:       !conf.micOn,
            handRaised:  false,
            isLocal:     true,
          );
        }
        final peer = peers[i - 1];
        return _VideoTile(
          renderer:    peer.renderer,
          displayName: peer.displayName,
          muted:       peer.muted,
          handRaised:  peer.handRaised,
          isLocal:     false,
          isHost:      conf.isHost,
          onMute:      () => notifier.muteParticipant(peer.peerId),
          onRemove:    () => notifier.removeParticipant(peer.peerId),
        );
      });
  }
}

// ── Single video tile ─────────────────────────────────────────────────────────
class _VideoTile extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final String            displayName;
  final bool              muted, handRaised, isLocal;
  final bool              isHost;
  final VoidCallback?     onMute, onRemove;

  const _VideoTile({
    required this.renderer, required this.displayName,
    required this.muted, required this.handRaised, required this.isLocal,
    this.isHost = false, this.onMute, this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12)),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        // Video feed
        if (renderer != null)
          Positioned.fill(child: RTCVideoView(
            renderer!,
            mirror: isLocal,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ))
        else
          Center(child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white12,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white,
                  fontSize: 22, fontWeight: FontWeight.w700)))),

        // Name bar
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent])),
            child: Row(children: [
              Expanded(child: Text(displayName,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (muted)
                const Icon(Icons.mic_off_rounded,
                    color: Colors.red, size: 12),
            ]))),

        // Hand raised
        if (handRaised)
          const Positioned(top: 6, right: 6,
            child: Text('✋', style: TextStyle(fontSize: 18))),

        // Host controls
        if (isHost && !isLocal)
          Positioned(top: 6, left: 6,
            child: Row(children: [
              if (onMute != null)
                _MiniIconBtn(
                    icon: Icons.mic_off_rounded, onTap: onMute!),
              const SizedBox(width: 4),
              if (onRemove != null)
                _MiniIconBtn(
                    icon: Icons.person_remove_rounded,
                    onTap: onRemove!, danger: true),
            ])),
      ])));
}

// ── Control button ────────────────────────────────────────────────────────────
class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     active, danger;
  final VoidCallback onTap;
  const _CtrlBtn({
    required this.icon, required this.label,
    required this.active, required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: danger
              ? Colors.red
              : active ? Colors.white12 : Colors.red.withValues(alpha: 0.3),
          shape: BoxShape.circle),
        child: Icon(icon,
            color: active ? Colors.white : Colors.red, size: 22)),
      const SizedBox(height: 6),
      Text(label,
          style: const TextStyle(color: Colors.white60, fontSize: 10)),
    ]));
}

class _MiniIconBtn extends StatelessWidget {
  final IconData icon;
  final bool     danger;
  final VoidCallback onTap;
  const _MiniIconBtn({
    required this.icon, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: danger ? Colors.red.withValues(alpha: 0.8) : Colors.black54,
        borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, color: Colors.white, size: 13)));
}
