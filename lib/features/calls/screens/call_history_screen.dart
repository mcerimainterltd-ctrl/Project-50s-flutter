import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../../core/services/socket_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class CallRecord {
  final String callId, callerId, recipientId, callType, status;
  final DateTime startTime;
  final int duration;
  final bool seen;

  CallRecord({
    required this.callId, required this.callerId, required this.recipientId,
    required this.callType, required this.status, required this.startTime,
    required this.duration, required this.seen,
  });

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
    callId:      j['callId']      ?? '',
    callerId:    j['callerId']    ?? '',
    recipientId: j['recipientId'] ?? '',
    callType:    j['callType']    ?? 'voice',
    status:      j['status']      ?? 'ended',
    startTime:   (DateTime.tryParse(j['startTime'] ?? '') ?? DateTime.now()).toLocal(),
    duration:    j['duration']    ?? 0,
    seen:        j['seen']        ?? true,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final callHistoryProvider = StreamProvider
    .family<List<CallRecord>, String>((ref, userId) async* {
  // Yield cache immediately
  final cached = CacheService.loadCallHistory()
      .map((c) => CallRecord.fromJson(c)).toList();
  yield cached;

  // Fetch fresh from API
  try {
    final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
    final res  = await dio.get('/api/call-history/$userId');
    if (res.data['success'] == true) {
      final fresh = (res.data['calls'] as List)
          .map((c) => CallRecord.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      await CacheService.saveCallHistory(res.data['calls']
          .map<Map<String,dynamic>>((c) => Map<String,dynamic>.from(c)).toList());
      yield fresh;
    }
  } catch (_) {}
});

// ── Screen ────────────────────────────────────────────────────────────────────
class CallHistoryScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const CallHistoryScreen({super.key, this.onBack});
  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {
        _filter = ['all', 'missed', 'incoming', 'outgoing'][_tabs.index];
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markSeen();
      _listenToCallEvents();
    });
  }

  final List<StreamSubscription> _subs = [];

  void _listenToCallEvents() {
    final socket = ref.read(socketServiceProvider);
    final webrtc = ref.read(webRTCServiceProvider);
    final user   = ref.read(currentUserProvider);
    if (user == null) return;

    void refresh() {
      if (mounted) {
        ref.invalidate(callHistoryProvider(user.xameId));
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) ref.invalidate(callHistoryProvider(user.xameId));
        });
      }
    }

    _subs.add(webrtc.callState.listen((_) => refresh()));
    _subs.add(socket.callEnded.listen((_) => refresh()));
    _subs.add(socket.callRejected.listen((_) => refresh()));
    _subs.add(socket.missedCallCount.listen((_) => refresh()));
  }

  Future<void> _markSeen() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    ref.read(contactsProvider.notifier).clearAllMissedCalls();
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      await dio.patch('/api/call-history/${user.xameId}/seen');
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final sub in _subs) { sub.cancel(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user     = ref.watch(currentUserProvider);
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final history  = ref.watch(callHistoryProvider(user?.xameId ?? ''));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: const Color(0xFF0A0A0F),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 60),
              title: const Text('Calls',
                style: TextStyle(color: Colors.white, fontSize: 28,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D1117), Color(0xFF0A0A0F)],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.white54),
                onPressed: () => _confirmClear(user?.xameId ?? ''),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: _FilterTabs(controller: _tabs),
            ),
          ),
        ],
        body: history.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00FF88), strokeWidth: 1.5)),
          error: (e, _) => const Center(
              child: Text('Failed to load calls',
                  style: TextStyle(color: Colors.white38))),
          data: (calls) {
            final filtered = _filterCalls(calls, user?.xameId ?? '');
            if (filtered.isEmpty) return _emptyState();
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final call    = filtered[i];
                final isMe    = call.callerId == user?.xameId;
                final peerId  = isMe ? call.recipientId : call.callerId;
                final contact = contacts.where((c) => c.id == peerId).firstOrNull;
                final name    = contact?.name ?? peerId;
                final photo   = contact?.isProfilePicHidden == true
                    ? null : contact?.profilePic;
                final showDate = i == 0 ||
                    !_sameDay(filtered[i - 1].startTime, call.startTime);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate) _DateDivider(date: call.startTime),
                    _CallTile(
                      call: call,
                      isOutgoing: isMe,
                      name: name,
                      photoUrl: photo,
                      peerId: peerId,
                      onTap: () => _recall(peerId, call.callType),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<CallRecord> _filterCalls(List<CallRecord> calls, String userId) {
    const missedStatuses = ['missed', 'no-answer', 'offline'];
    const answeredStatuses = ['ended', 'accepted'];
    switch (_filter) {
      case 'missed':
        // Missed = I was the recipient AND call was never answered
        return calls.where((c) =>
            (c.recipientId == userId || c.callerId == userId) &&
            missedStatuses.contains(c.status)).toList();
      case 'incoming':
        // Incoming = I was the recipient AND call was answered
        return calls.where((c) =>
            c.recipientId == userId &&
            answeredStatuses.contains(c.status)).toList();
      case 'outgoing':
        // Outgoing = I was the caller
        return calls.where((c) =>
            c.callerId == userId &&
            !missedStatuses.contains(c.status)).toList();
      default:
        return calls;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _recall(String peerId, String callType) {
    context.push('/call/$peerId?video=${callType == 'video'}&incoming=false');
  }

  Future<void> _confirmClear(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Call History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('This will delete all your call records.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Clear',
                  style: TextStyle(color: Color(0xFFE53935),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
        await dio.delete('/api/call-history/$userId');
        ref.invalidate(callHistoryProvider(userId));
      } catch (_) {}
    }
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.05),
        ),
        child: const Icon(Icons.call_outlined, color: Colors.white24, size: 36),
      ),
      const SizedBox(height: 20),
      const Text('No calls yet',
        style: TextStyle(color: Colors.white38, fontSize: 16,
            fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      const Text('Your call history will appear here',
        style: TextStyle(color: Colors.white24, fontSize: 13)),
    ]),
  );
}

// ── Filter Tabs ───────────────────────────────────────────────────────────────
class _FilterTabs extends StatelessWidget {
  final TabController controller;
  const _FilterTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: const Color(0xFF00FF88),
      indicatorWeight: 2,
      labelColor: const Color(0xFF00FF88),
      unselectedLabelColor: Colors.white38,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          letterSpacing: 0.3),
      dividerColor: Colors.white10,
      tabs: const [
        Tab(text: 'All'),
        Tab(text: 'Missed'),
        Tab(text: 'Incoming'),
        Tab(text: 'Outgoing'),
      ],
    );
  }
}

// ── Date Divider ──────────────────────────────────────────────────────────────
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final label = date.year == now.year && date.month == now.month &&
            date.day == now.day
        ? 'Today'
        : date.year == now.year && date.month == now.month &&
                date.day == now.day - 1
            ? 'Yesterday'
            : DateFormat('MMMM d, yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(label,
        style: const TextStyle(color: Colors.white38, fontSize: 12,
            fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }
}

// ── Call Tile ─────────────────────────────────────────────────────────────────
class _CallTile extends StatelessWidget {
  final CallRecord call;
  final bool isOutgoing;
  final String name, peerId;
  final String? photoUrl;
  final VoidCallback onTap;

  const _CallTile({
    required this.call, required this.isOutgoing, required this.name,
    required this.peerId, this.photoUrl, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMissed   = (call.status == 'missed' || call.status == 'no-answer' || call.status == 'offline') && !isOutgoing;
    final isDeclined = call.status == 'rejected';
    final isVideo    = call.callType == 'video';
    final nameColor  = isMissed ? const Color(0xFFE53935)
        : isDeclined ? const Color(0xFFFF9800)
        : Colors.white;
    final initials   = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, width: 1)),
            child: ClipOval(
              child: photoUrl != null
                ? CachedNetworkImage(imageUrl: photoUrl!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _initialsAvatar(initials))
                : _initialsAvatar(initials),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                  style: TextStyle(color: nameColor, fontSize: 16,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  _DirectionIcon(isOutgoing: isOutgoing, isMissed: isMissed,
                      isDeclined: isDeclined),
                  const SizedBox(width: 5),
                  Text(_statusLabel(),
                    style: TextStyle(
                      color: isMissed ? const Color(0xFFE53935)
                          : isDeclined ? const Color(0xFFFF9800)
                          : Colors.white38,
                      fontSize: 12)),
                  if (call.duration > 0) ...[
                    const Text(' · ',
                        style: TextStyle(color: Colors.white24, fontSize: 12)),
                    Text(_fmtDuration(call.duration),
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(DateFormat('h:mm a').format(call.startTime),
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF88).withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF00FF88).withOpacity(0.3)),
                  ),
                  child: Icon(
                    isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                    color: const Color(0xFF00FF88), size: 16),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _initialsAvatar(String initials) => Container(
    color: const Color(0xFF1E2533),
    child: Center(child: Text(initials,
      style: const TextStyle(color: Colors.white, fontSize: 18,
          fontWeight: FontWeight.w600))),
  );

  String _statusLabel() {
    if (isOutgoing) {
      switch (call.status) {
        case 'accepted':
        case 'ended':    return 'Outgoing';
        case 'rejected': return 'Declined';
        case 'missed':
        case 'no-answer': return 'No answer';
        case 'offline':  return 'Unavailable';
        default:         return 'Outgoing';
      }
    } else {
      switch (call.status) {
        case 'accepted':
        case 'ended':    return 'Incoming';
        case 'rejected': return 'Declined';
        case 'missed':
        case 'no-answer': return 'Missed';
        case 'offline':  return 'Missed';
        default:         return 'Incoming';
      }
    }
  }

  String _fmtDuration(int s) {
    if (s < 60)   return '${s}s';
    if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  }
}

// ── Direction Icon ────────────────────────────────────────────────────────────
class _DirectionIcon extends StatelessWidget {
  final bool isOutgoing, isMissed, isDeclined;
  const _DirectionIcon({required this.isOutgoing, required this.isMissed,
      this.isDeclined = false});

  @override
  Widget build(BuildContext context) {
    return Icon(
      isOutgoing ? Icons.call_made : Icons.call_received,
      size: 13,
      color: isMissed ? const Color(0xFFE53935)
          : isDeclined ? const Color(0xFFFF9800)
          : isOutgoing ? const Color(0xFF00FF88)
          : Colors.white38,
    );
  }
}
