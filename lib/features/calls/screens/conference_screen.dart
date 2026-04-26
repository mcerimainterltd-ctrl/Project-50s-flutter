
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../contacts/providers/contacts_provider.dart';

// ── Conference state ──────────────────────────────────────────────────────────
enum ConferenceLayout { grid, spotlight, sidebar }

class ConferenceParticipant {
  final String peerId, displayName;
  bool muted, videoMuted, handRaised;
  ConferenceParticipant({
    required this.peerId, required this.displayName,
    this.muted = false, this.videoMuted = false, this.handRaised = false,
  });
}

class ConferenceState {
  final String?  roomId;
  final bool     isHost, micOn, camOn;
  final ConferenceLayout layout;
  final List<ConferenceParticipant> participants;
  const ConferenceState({
    this.roomId, this.isHost = false,
    this.micOn = true, this.camOn = true,
    this.layout = ConferenceLayout.grid,
    this.participants = const [],
  });
  bool get inConference => roomId != null;
  ConferenceState copyWith({
    String? roomId, bool? isHost, bool? micOn, bool? camOn,
    ConferenceLayout? layout, List<ConferenceParticipant>? participants,
    bool clearRoom = false,
  }) => ConferenceState(
    roomId:       clearRoom ? null : (roomId ?? this.roomId),
    isHost:       isHost       ?? this.isHost,
    micOn:        micOn        ?? this.micOn,
    camOn:        camOn        ?? this.camOn,
    layout:       layout       ?? this.layout,
    participants: participants ?? this.participants,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final conferenceProvider =
    StateNotifierProvider<ConferenceNotifier, ConferenceState>(
        ConferenceNotifier.new);

class ConferenceNotifier extends StateNotifier<ConferenceState> {
  final Ref _ref;
  static const _maxParticipants = 6;

  ConferenceNotifier(this._ref) : super(const ConferenceState()) {
    _listenSocket();
  }

  void _listenSocket() {
    final socket = _ref.read(socketServiceProvider);
    socket.rawSocket?.on('conference:peer-joined', (data) {
      final map  = Map<String, dynamic>.from(data);
      final peer = map['peerId'] as String;
      final name = map['displayName'] as String? ?? peer;
      if (peer == _ref.read(currentUserProvider)?.xameId) return;
      if (state.participants.length >= _maxParticipants - 1) return;
      state = state.copyWith(participants: [
        ...state.participants,
        ConferenceParticipant(peerId: peer, displayName: name),
      ]);
    });

    socket.rawSocket?.on('conference:peer-left', (data) {
      final map  = Map<String, dynamic>.from(data);
      final peer = map['peerId'] as String;
      state = state.copyWith(participants:
          state.participants.where((p) => p.peerId != peer).toList());
    });

    socket.rawSocket?.on('conference:mic-toggle', (data) {
      final map   = Map<String, dynamic>.from(data);
      final peer  = map['userId'] as String;
      final muted = map['muted'] as bool? ?? false;
      state = state.copyWith(participants: state.participants.map((p) =>
          p.peerId == peer ? (p..muted = muted) : p).toList());
    });

    socket.rawSocket?.on('conference:raise-hand', (data) {
      final map    = Map<String, dynamic>.from(data);
      final peer   = map['userId'] as String;
      final raised = map['raised'] as bool? ?? false;
      state = state.copyWith(participants: state.participants.map((p) =>
          p.peerId == peer ? (p..handRaised = raised) : p).toList());
    });

    socket.rawSocket?.on('conference:muted-by-host', (_) {
      state = state.copyWith(micOn: false);
    });

    socket.rawSocket?.on('conference:removed-by-host', (_) {
      leave();
    });

    socket.rawSocket?.on('conference:room-closed', (_) {
      state = state.copyWith(clearRoom: true, participants: []);
    });
  }

  Future<void> create() async {
    final user = _ref.read(currentUserProvider);
    if (user == null || state.inConference) return;
    final roomId = 'room-${DateTime.now().millisecondsSinceEpoch}';
    await _join(roomId, true);
  }

  Future<void> join(String roomId) async {
    if (state.inConference) return;
    await _join(roomId, false);
  }

  Future<void> _join(String roomId, bool isHost) async {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    if (user == null) return;
    state = state.copyWith(roomId: roomId, isHost: isHost, participants: []);
    socket.rawSocket?.emit('conference:join', {
      'roomId':      roomId,
      'userId':      user.xameId,
      'displayName': user.firstName,
      'isHost':      isHost,
    });
  }

  void leave() {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    if (state.roomId != null) {
      socket.rawSocket?.emit('conference:leave', {
        'roomId': state.roomId, 'userId': user?.xameId,
      });
    }
    state = state.copyWith(clearRoom: true, participants: []);
  }

  void toggleMic() {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    final newVal = !state.micOn;
    state = state.copyWith(micOn: newVal);
    socket.rawSocket?.emit('conference:mic-toggle', {
      'roomId': state.roomId, 'userId': user?.xameId, 'muted': !newVal,
    });
  }

  void toggleCam() => state = state.copyWith(camOn: !state.camOn);

  void cycleLayout() {
    final layouts = ConferenceLayout.values;
    final next    = layouts[(state.layout.index + 1) % layouts.length];
    state = state.copyWith(layout: next);
  }

  void raiseHand() {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    socket.rawSocket?.emit('conference:raise-hand', {
      'roomId': state.roomId, 'userId': user?.xameId, 'raised': true,
    });
  }

  void muteParticipant(String peerId) {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    if (!state.isHost) return;
    socket.rawSocket?.emit('conference:mute-peer', {
      'roomId': state.roomId, 'hostId': user?.xameId, 'peerId': peerId,
    });
  }

  void removeParticipant(String peerId) {
    final user   = _ref.read(currentUserProvider);
    final socket = _ref.read(socketServiceProvider);
    if (!state.isHost) return;
    socket.rawSocket?.emit('conference:remove-peer', {
      'roomId': state.roomId, 'hostId': user?.xameId, 'peerId': peerId,
    });
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

          // Start button
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

          // Join by room ID
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
class _ActiveConferenceView extends ConsumerWidget {
  const _ActiveConferenceView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conf = ref.watch(conferenceProvider);
    final total = conf.participants.length + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Text('Room: ${conf.roomId}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20)),
              child: Text('$total participant${total != 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11))),
            const Spacer(),
            // Copy room ID
            IconButton(
              icon: const Icon(Icons.link_rounded, color: Colors.white54),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: conf.roomId!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Room ID copied!'),
                  duration: Duration(seconds: 2)));
              }),
            // Layout toggle
            IconButton(
              icon: Icon(
                conf.layout == ConferenceLayout.grid
                    ? Icons.grid_view_rounded
                    : conf.layout == ConferenceLayout.spotlight
                        ? Icons.personal_video_rounded
                        : Icons.view_sidebar_rounded,
                color: Colors.white54),
              onPressed: () =>
                  ref.read(conferenceProvider.notifier).cycleLayout()),
          ]),
        ),

        // Participant grid
        Expanded(child: _ParticipantGrid(conf: conf)),

        // Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CtrlBtn(
                icon: conf.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: conf.micOn ? 'Mute' : 'Unmute',
                color: conf.micOn ? Colors.white : Colors.red,
                onTap: () => ref.read(conferenceProvider.notifier).toggleMic()),
              _CtrlBtn(
                icon: conf.camOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: conf.camOn ? 'Camera' : 'Cam Off',
                color: conf.camOn ? Colors.white : Colors.red,
                onTap: () => ref.read(conferenceProvider.notifier).toggleCam()),
              _CtrlBtn(
                icon: Icons.pan_tool_rounded,
                label: 'Raise Hand',
                color: Colors.white,
                onTap: () => ref.read(conferenceProvider.notifier).raiseHand()),
              _CtrlBtn(
                icon: Icons.call_end_rounded,
                label: 'Leave',
                color: Colors.white,
                bg: Colors.red,
                onTap: () => ref.read(conferenceProvider.notifier).leave()),
            ]),
        ),
      ])),
    );
  }
}

class _ParticipantGrid extends ConsumerWidget {
  final ConferenceState conf;
  const _ParticipantGrid({required this.conf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user  = ref.watch(currentUserProvider);
    final peers = conf.participants;
    final all   = [
      ConferenceParticipant(
          peerId: user?.xameId ?? 'me',
          displayName: '${user?.firstName ?? 'You'} (You)'),
      ...peers,
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: all.length <= 2 ? 1 : 2,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
        childAspectRatio: all.length <= 2 ? 16 / 9 : 1),
      itemCount: all.length,
      itemBuilder: (_, i) {
        final p    = all[i];
        final isMe = p.peerId == (user?.xameId ?? 'me');
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16)),
          child: Stack(children: [
            // Avatar
            Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: isMe
                      ? context.xPrimary.withValues(alpha: 0.3)
                      : context.xAccent.withValues(alpha: 0.3),
                  child: Text(
                    p.displayName.isNotEmpty
                        ? p.displayName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isMe ? context.xPrimary : context.xAccent,
                      fontSize: 24, fontWeight: FontWeight.w700))),
                const SizedBox(height: 8),
                Text(p.displayName,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),

            // Muted indicator
            if (p.muted)
              Positioned(top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.mic_off_rounded,
                      color: Colors.white, size: 12))),

            // Hand raised
            if (p.handRaised)
              const Positioned(top: 8, right: 8,
                child: Text('✋', style: TextStyle(fontSize: 20))),

            // Host controls
            if (ref.watch(conferenceProvider).isHost && !isMe)
              Positioned(bottom: 8, right: 8,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _MiniBtn(
                    icon: Icons.mic_off_rounded,
                    onTap: () => ref.read(conferenceProvider.notifier)
                        .muteParticipant(p.peerId)),
                  const SizedBox(width: 4),
                  _MiniBtn(
                    icon: Icons.person_remove_rounded,
                    color: Colors.red,
                    onTap: () => ref.read(conferenceProvider.notifier)
                        .removeParticipant(p.peerId)),
                ])),
          ]),
        );
      });
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final Color?   bg;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.label,
      required this.color, required this.onTap, this.bg});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: bg ?? Colors.white12, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22)),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    ]));
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final Color?   color;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color ?? Colors.white70, size: 14)));
}
