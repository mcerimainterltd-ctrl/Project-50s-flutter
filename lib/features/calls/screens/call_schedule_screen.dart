import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/webrtc_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../contacts/providers/contacts_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class ScheduledCall {
  final String scheduleId, callerId, recipientId, callType, recurrence;
  final int    callAt;
  ScheduledCall({
    required this.scheduleId, required this.callerId,
    required this.recipientId, required this.callType,
    required this.callAt, this.recurrence = 'once',
  });
  factory ScheduledCall.fromJson(Map<String, dynamic> j) => ScheduledCall(
    scheduleId:  j['scheduleId']  as String,
    callerId:    j['callerId']    as String,
    recipientId: j['recipientId'] as String,
    callType:    j['callType']    as String? ?? 'voice',
    callAt:      (j['callAt'] as num).toInt(),
    recurrence:  j['recurrence'] as String? ?? 'once',
  );
}

// ── Notification helpers ───────────────────────────────────────────────────────
final _notifs     = FlutterLocalNotificationsPlugin();
bool  _notifsInit = false;

Future<void> _ensureNotifsInit() async {
  if (_notifsInit) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios     = DarwinInitializationSettings();
  await _notifs.initialize(
      const InitializationSettings(android: android, iOS: ios));
  _notifsInit = true;
}

Future<void> _showCallNotif(ScheduledCall call, String contactName) async {
  await _ensureNotifsInit();
  final id        = call.scheduleId.hashCode.abs() % 100000;
  final typeLabel = call.callType == 'video' ? '📹 Video' : '🎙️ Voice';
  await _notifs.show(
    id, '$typeLabel Call — $contactName', 'Starting now...',
    const NotificationDetails(
      android: AndroidNotificationDetails('scheduled_calls', 'Scheduled Calls',
          channelDescription: 'Scheduled call reminders',
          importance: Importance.max, priority: Priority.high),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

Future<void> _cancelNotif(String scheduleId) async {
  await _ensureNotifsInit();
  await _notifs.cancel(scheduleId.hashCode.abs() % 100000);
}

// ── Provider ──────────────────────────────────────────────────────────────────
final scheduledCallsProvider =
    StateNotifierProvider<ScheduledCallsNotifier, List<ScheduledCall>>(
        ScheduledCallsNotifier.new);

class ScheduledCallsNotifier extends StateNotifier<List<ScheduledCall>> {
  final Ref                  _ref;
  final _dio   = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final _timers = <String, Timer>{};

  ScheduledCallsNotifier(this._ref) : super([]) {
    _load();
    _listenSocket();
  }

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await _dio.get('/api/schedule-call/${user.xameId}');
      if (res.data['success'] == true) {
        final calls = (res.data['calls'] as List)
            .map((c) => ScheduledCall.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        state = calls;
        for (final call in calls) _scheduleLocalTimer(call);
      }
    } catch (_) {}
  }

  void _listenSocket() {
    Future.doWhile(() async {
      if (!mounted) return false;
      final raw = _ref.read(socketServiceProvider).rawSocket;
      if (raw != null) {
        raw.on('scheduled-call-due', (data) async {
          final map         = Map<String, dynamic>.from(data);
          final scheduleId  = map['scheduleId']  as String?;
          final recipientId = map['recipientId'] as String?;
          final callType    = map['callType']    as String? ?? 'voice';
          if (scheduleId == null || recipientId == null) return;
          // cancel local timer since server fired first
          _timers[scheduleId]?.cancel();
          _timers.remove(scheduleId);
          final call     = state.where((c) => c.scheduleId == scheduleId).firstOrNull;
          final contacts = _ref.read(contactsProvider).valueOrNull ?? [];
          final contact  = contacts.where((c) => c.id == recipientId).firstOrNull;
          if (call != null) await _showCallNotif(call, contact?.name ?? recipientId);
          try {
            await _ref.read(webRTCServiceProvider).startCall(recipientId, callType == 'video');
          } catch (e) { debugPrint('[CallSchedule] socket auto-dial error: $e'); }
          if (call == null || call.recurrence == 'once') {
            state = state.where((c) => c.scheduleId != scheduleId).toList();
          }
        });
        return false;
      }
      await Future.delayed(const Duration(seconds: 2));
      return true;
    });
  }

  void _scheduleLocalTimer(ScheduledCall call) {
    _timers[call.scheduleId]?.cancel();
    final due   = DateTime.fromMillisecondsSinceEpoch(call.callAt);
    final delay = due.difference(DateTime.now());
    if (delay.isNegative) return;
    _timers[call.scheduleId] = Timer(delay, () => _onLocalDue(call));
  }

  Future<void> _onLocalDue(ScheduledCall call) async {
    final contacts = _ref.read(contactsProvider).valueOrNull ?? [];
    final contact  = contacts.where((c) => c.id == call.recipientId).firstOrNull;
    await _showCallNotif(call, contact?.name ?? call.recipientId);
    try {
      await _ref.read(webRTCServiceProvider).startCall(call.recipientId, call.callType == 'video');
    } catch (e) { debugPrint('[CallSchedule] local auto-dial error: $e'); }
    if (call.recurrence == 'daily') {
      final next = ScheduledCall(
        scheduleId: call.scheduleId, callerId: call.callerId,
        recipientId: call.recipientId, callType: call.callType,
        callAt: call.callAt + const Duration(days: 1).inMilliseconds,
        recurrence: 'daily',
      );
      state = [...state.where((c) => c.scheduleId != call.scheduleId), next];
      _scheduleLocalTimer(next);
    } else if (call.recurrence == 'weekly') {
      final next = ScheduledCall(
        scheduleId: call.scheduleId, callerId: call.callerId,
        recipientId: call.recipientId, callType: call.callType,
        callAt: call.callAt + const Duration(days: 7).inMilliseconds,
        recurrence: 'weekly',
      );
      state = [...state.where((c) => c.scheduleId != call.scheduleId), next];
      _scheduleLocalTimer(next);
    } else {
      _timers.remove(call.scheduleId);
      state = state.where((c) => c.scheduleId != call.scheduleId).toList();
    }
  }

  Future<bool> create({
    required String callerId,
    required String recipientId,
    required String callType,
    required int    callAt,
    String recurrence = 'once',
  }) async {
    try {
      final res = await _dio.post('/api/schedule-call/create', data: {
        'callerId':    callerId,   'recipientId': recipientId,
        'callType':    callType,   'callAt':      callAt,
        'recurrence':  recurrence,
      });
      if (res.data['success'] == true) {
        final call = ScheduledCall.fromJson(
            Map<String, dynamic>.from(res.data['call']));
        state = [...state, call];
        _scheduleLocalTimer(call);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> cancel(String scheduleId, String userId) async {
    try {
      await _dio.delete('/api/schedule-call/$scheduleId',
          data: {'userId': userId});
      await _cancelNotif(scheduleId);
      _timers[scheduleId]?.cancel();
      _timers.remove(scheduleId);
      state = state.where((c) => c.scheduleId != scheduleId).toList();
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> refresh() => _load();
}

// ── Schedule Call Screen ──────────────────────────────────────────────────────
class CallScheduleScreen extends ConsumerStatefulWidget {
  const CallScheduleScreen({super.key});
  @override
  ConsumerState<CallScheduleScreen> createState() => _CallScheduleScreenState();
}

class _CallScheduleScreenState extends ConsumerState<CallScheduleScreen> {
  @override
  Widget build(BuildContext context) {
    final calls    = ref.watch(scheduledCallsProvider);
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final user     = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.xBg,
      body: calls.isEmpty
          ? _emptyState(context)
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(scheduledCallsProvider.notifier).refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: calls.length,
                itemBuilder: (_, i) {
                  final call    = calls[i];
                  final contact = contacts.where((c) =>
                      c.id == call.recipientId).firstOrNull;
                  final name    = contact?.name ?? call.recipientId;
                  final dt      = DateTime.fromMillisecondsSinceEpoch(call.callAt);
                  final fmt     = DateFormat('MMM d, y  h:mm a').format(dt);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.xCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: context.xMuted.withValues(alpha: 0.2))),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: context.xPrimary.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                        child: Icon(
                          call.callType == 'video'
                              ? Icons.videocam_outlined
                              : Icons.call_outlined,
                          color: context.xPrimary, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: TextStyle(color: context.xText,
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(fmt,
                              style: TextStyle(
                                  color: context.xMuted, fontSize: 12)),
                          Text(call.callType == 'video'
                                  ? '📹 Video call' : '🎙️ Voice call',
                              style: TextStyle(
                                  color: context.xMuted, fontSize: 11)),
                        ],
                      )),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: context.xDanger, size: 20),
                        onPressed: () async {
                          if (user == null) return;
                          final ok = await ref
                              .read(scheduledCallsProvider.notifier)
                              .cancel(call.scheduleId, user.xameId);
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Scheduled call cancelled'),
                              backgroundColor: context.xCard));
                          }
                        }),
                    ]),
                  );
                },
              )),
    );
  }

  Widget _emptyState(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: context.xCard, shape: BoxShape.circle,
          border: Border.all(color: context.xPrimary.withValues(alpha: 0.3))),
        child: Icon(Icons.schedule_outlined,
            color: context.xPrimary, size: 56)),
      const SizedBox(height: 24),
      Text('No Scheduled Calls',
          style: TextStyle(color: context.xText,
              fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Schedule a call with any contact',
          style: TextStyle(color: context.xMuted, fontSize: 14)),
      const SizedBox(height: 32),
      ElevatedButton.icon(
        onPressed: () => _showScheduleSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Schedule a Call',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.xPrimary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))),
      ),
    ],
  ));

  void _showScheduleSheet(BuildContext context, {String? recipientId, String? recipientName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleCallSheet(
        preselectedId:   recipientId,
        preselectedName: recipientName,
      ),
    );
  }
}

// ── Schedule Sheet ────────────────────────────────────────────────────────────
class _ScheduleCallSheet extends ConsumerStatefulWidget {
  final String? preselectedId, preselectedName;
  const _ScheduleCallSheet({this.preselectedId, this.preselectedName});
  @override
  ConsumerState<_ScheduleCallSheet> createState() => _ScheduleCallSheetState();
}

class _ScheduleCallSheetState extends ConsumerState<_ScheduleCallSheet> {
  String   _callType   = 'voice';
  String   _recurrence = 'once';
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 1));
  String?  _recipientId, _recipientName;
  bool     _loading = false;
  String   _search  = '';

  @override
  void initState() {
    super.initState();
    _recipientId   = widget.preselectedId;
    _recipientName = widget.preselectedName;
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final filtered = _search.isEmpty ? contacts
        : contacts.where((c) =>
            c.name.toLowerCase().contains(_search.toLowerCase())).toList();
    final user = ref.watch(currentUserProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('📞 Schedule Call',
              style: const TextStyle(color: Colors.white,
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Contact picker
          if (_recipientId == null) ...[
            TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '🔍 Search contact...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true, fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12)),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: context.xPrimary.withValues(alpha: 0.2),
                      child: Text(c.name[0].toUpperCase(),
                          style: TextStyle(color: context.xPrimary,
                              fontWeight: FontWeight.w700))),
                    title: Text(c.name,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 14)),
                    onTap: () => setState(() {
                      _recipientId   = c.id;
                      _recipientName = c.name;
                    }),
                  );
                }),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.xPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: context.xPrimary.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(Icons.person_outline, color: context.xPrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_recipientName ?? _recipientId!,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w600))),
                GestureDetector(
                  onTap: () => setState(() {
                    _recipientId = null; _recipientName = null;
                  }),
                  child: const Icon(Icons.close,
                      color: Colors.white38, size: 16)),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // Call type
          Text('Call Type',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            _typeBtn('voice', '🎙️ Voice', context),
            const SizedBox(width: 10),
            _typeBtn('video', '📹 Video', context),
          ]),
          const SizedBox(height: 16),

          // Date & Time
          Text('When',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _dateTile(context)),
            const SizedBox(width: 10),
            Expanded(child: _timeTile(context)),
          ]),
          const SizedBox(height: 16),

          // Recurrence
          Text('Repeat', style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            _recBtn('once',   '🔂 Once'),
            const SizedBox(width: 8),
            _recBtn('daily',  '📅 Daily'),
            const SizedBox(width: 8),
            _recBtn('weekly', '🗓️ Weekly'),
          ]),
          const SizedBox(height: 24),

          // Schedule button
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              onPressed: (_loading || _recipientId == null || user == null)
                  ? null
                  : () async {
                      final now = DateTime.now();
                      if (_selectedDate.isBefore(now)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Please select a future time')));
                        return;
                      }
                      setState(() => _loading = true);
                      final ok = await ref
                          .read(scheduledCallsProvider.notifier)
                          .create(
                            callerId:    user.xameId,
                            recipientId: _recipientId!,
                            callType:    _callType,
                            callAt:      _selectedDate.millisecondsSinceEpoch,
                          );
                      if (mounted) {
                        setState(() => _loading = false);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? '✅ Call scheduled for ${DateFormat('MMM d, h:mm a').format(_selectedDate)}'
                              : '❌ Failed to schedule call'),
                          backgroundColor: ok ? context.xPrimary : context.xDanger));
                      }
                    },
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('✅ Schedule Call',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15)),
            )),
        ],
      )),
    );
  }

  Widget _recBtn(String type, String label) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _recurrence = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _recurrence == type
              ? context.xPrimary.withValues(alpha: 0.15)
              : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _recurrence == type ? context.xPrimary : Colors.white12)),
        child: Text(label,
            style: TextStyle(
                color: _recurrence == type ? context.xPrimary : Colors.white54,
                fontWeight: _recurrence == type ? FontWeight.w700 : FontWeight.normal,
                fontSize: 12)),
      ),
    ),
  );

  Widget _typeBtn(String type, String label, BuildContext context) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() => _callType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _callType == type
              ? context.xPrimary.withValues(alpha: 0.15)
              : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _callType == type
                ? context.xPrimary : Colors.white12)),
        child: Text(label,
          style: TextStyle(
            color: _callType == type ? context.xPrimary : Colors.white54,
            fontWeight: _callType == type
                ? FontWeight.w700 : FontWeight.normal,
            fontSize: 13)),
      ),
    ));

  Widget _dateTile(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: context.xPrimary)),
          child: child!));
      if (picked != null) setState(() => _selectedDate = DateTime(
        picked.year, picked.month, picked.day,
        _selectedDate.hour, _selectedDate.minute));
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Date', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(DateFormat('MMM d, y').format(_selectedDate),
          style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ));

  Widget _timeTile(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: context.xPrimary)),
          child: child!));
      if (picked != null) setState(() => _selectedDate = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        picked.hour, picked.minute));
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Time', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(DateFormat('h:mm a').format(_selectedDate),
          style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ));
}
