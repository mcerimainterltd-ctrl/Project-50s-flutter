import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class ScheduledCall {
  final String scheduleId, recipientId, callType;
  final int callAt;
  const ScheduledCall({required this.scheduleId, required this.recipientId,
      required this.callType, required this.callAt});
  factory ScheduledCall.fromJson(Map<String, dynamic> j) => ScheduledCall(
    scheduleId:  j['scheduleId']  as String,
    recipientId: j['recipientId'] as String,
    callType:    j['callType']    as String? ?? 'voice',
    callAt:      j['callAt']      as int,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class CallScheduleService {
  final SocketService _socket;
  final String _userId;
  final FlutterLocalNotificationsPlugin _notifs =
      FlutterLocalNotificationsPlugin();
  List<ScheduledCall> _calls = [];
  void Function(String recipientId, String callType)? onCallDue;

  CallScheduleService(this._socket, this._userId) { _initNotifs(); }

  Future<void> _initNotifs() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings();
    await _notifs.initialize(
        const InitializationSettings(android: android, iOS: ios));
  }

  Future<void> load() async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/schedule-call/$_userId'));
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _calls = (d['calls'] as List)
            .map((c) => ScheduledCall.fromJson(Map<String, dynamic>.from(c)))
            .toList();
      }
    } catch (e) { debugPrint('[CallSchedule] Load error: $e'); }
  }

  void handleDue(Map<String, dynamic> data) {
    final scheduleId  = data['scheduleId']  as String?;
    final recipientId = data['recipientId'] as String?;
    final callType    = data['callType']    as String? ?? 'voice';
    if (scheduleId == null || recipientId == null) return;
    _calls.removeWhere((c) => c.scheduleId == scheduleId);
    onCallDue?.call(recipientId, callType);
  }

  Future<ScheduledCall?> create({required String recipientId,
      required String callType, required DateTime callAt}) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/schedule-call/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'callerId': _userId, 'recipientId': recipientId,
            'callType': callType,
            'callAt': callAt.millisecondsSinceEpoch}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final call = ScheduledCall.fromJson(
            Map<String, dynamic>.from(d['call']));
        _calls.add(call);
        await _scheduleLocalNotif(call);
        return call;
      }
    } catch (e) { debugPrint('[CallSchedule] Create error: $e'); }
    return null;
  }

  Future<void> cancel(String scheduleId) async {
    try {
      await http.delete(
        Uri.parse('${AppConstants.serverUrl}/api/schedule-call/$scheduleId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId}),
      );
      _calls.removeWhere((c) => c.scheduleId == scheduleId);
      await _notifs.cancel(scheduleId.hashCode.abs() % 100000);
    } catch (e) { debugPrint('[CallSchedule] Cancel error: $e'); }
  }

  List<ScheduledCall> get calls => List.unmodifiable(_calls);

  Future<void> _scheduleLocalNotif(ScheduledCall call) async {
    final id = call.scheduleId.hashCode.abs() % 100000;
    final dt = DateTime.fromMillisecondsSinceEpoch(call.callAt).toLocal();
    if (dt.isBefore(DateTime.now())) return;
    await _notifs.zonedSchedule(
      id, '📞 Scheduled Call', 'Time to call ${call.recipientId}',
      dt as dynamic,
      const NotificationDetails(
        android: AndroidNotificationDetails('scheduled_calls', 'Scheduled Calls',
            channelDescription: 'Scheduled call reminders',
            importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

// ── Schedule Call Sheet ───────────────────────────────────────────────────────
class ScheduleCallDialog extends StatefulWidget {
  final String recipientId, recipientName;
  final CallScheduleService service;

  const ScheduleCallDialog({super.key, required this.recipientId,
      required this.recipientName, required this.service});

  static Future<void> show(BuildContext context, {
    required String recipientId, required String recipientName,
    required CallScheduleService service,
  }) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ScheduleCallDialog(recipientId: recipientId,
        recipientName: recipientName, service: service),
  );

  @override
  State<ScheduleCallDialog> createState() => _ScheduleCallDialogState();
}

class _ScheduleCallDialogState extends State<ScheduleCallDialog> {
  String   _callType     = 'voice';
  DateTime _selectedDT   = DateTime.now().add(const Duration(hours: 1));
  bool     _loading      = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context, initialDate: _selectedDT,
      firstDate: DateTime.now(),
      lastDate:  DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: const Color(0xFF00D4FF), surface: const Color(0xFF1E1E2E)),
        ), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDT),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: const Color(0xFF00D4FF), surface: const Color(0xFF1E1E2E)),
        ), child: child!),
    );
    if (time == null || !mounted) return;
    setState(() => _selectedDT = DateTime(date.year, date.month, date.day,
        time.hour, time.minute));
  }

  String get _formattedDT {
    final d = _selectedDT;
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        )),
        // Header
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule_outlined,
                color: const Color(0xFF00D4FF), size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Schedule Call', style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w700)),
            Text('To: ${widget.recipientName}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              ScheduledCallsListDialog.show(context,
                  service: widget.service);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text('View All',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        // Call type toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            _typeBtn('voice', '🎙️  Voice'),
            _typeBtn('video', '📹  Video'),
          ]),
        ),
        const SizedBox(height: 16),
        // Date/time picker
        GestureDetector(
          onTap: _pickDateTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  color: const Color(0xFF00D4FF), size: 18),
              const SizedBox(width: 12),
              Text(_formattedDT,
                  style: const TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              const Icon(Icons.edit_outlined,
                  color: Colors.white30, size: 16),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        // Schedule button
        GestureDetector(
          onTap: _loading ? null : () async {
            if (_selectedDT.isBefore(DateTime.now())) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please select a future time'),
                backgroundColor: const Color(0xFF1E1E2E),
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }
            setState(() => _loading = true);
            final call = await widget.service.create(
              recipientId: widget.recipientId,
              callType:    _callType,
              callAt:      _selectedDT,
            );
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(call != null
                    ? '📅 Call scheduled for $_formattedDT'
                    : 'Failed to schedule call'),
                backgroundColor: call != null
                    ? const Color(0xFF00FF88).withValues(alpha: 0.2)
                    : const Color(0xFF1E1E2E),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              gradient: _loading ? null : const LinearGradient(
                colors: [const Color(0xFF00D4FF), const Color(0xFF141420)]),
              color: _loading ? const Color(0xFF1E1E2E) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: const Color(0xFF00D4FF), strokeWidth: 2))
                : const Text('Schedule Call',
                    style: TextStyle(color: Colors.black, fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _typeBtn(String type, String label) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _callType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        decoration: BoxDecoration(
          color: _callType == type
              ? const Color(0xFF00D4FF).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: _callType == type
              ? Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.4))
              : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
              color: _callType == type ? const Color(0xFF00D4FF) : Colors.white38,
              fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ),
  );
}

// ── Scheduled Calls List Sheet ────────────────────────────────────────────────
class ScheduledCallsListDialog extends StatefulWidget {
  final CallScheduleService service;
  const ScheduledCallsListDialog({super.key, required this.service});

  static Future<void> show(BuildContext context,
      {required CallScheduleService service}) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ScheduledCallsListDialog(service: service),
      );

  @override
  State<ScheduledCallsListDialog> createState() =>
      _ScheduledCallsListDialogState();
}

class _ScheduledCallsListDialogState
    extends State<ScheduledCallsListDialog> {

  List<ScheduledCall> get _calls => widget.service.calls;

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.schedule_outlined,
                      color: const Color(0xFF00D4FF), size: 18),
                ),
                const SizedBox(width: 10),
                Text('Scheduled Calls (${_calls.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          Expanded(
            child: _calls.isEmpty
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.schedule_outlined,
                        color: Colors.white12, size: 48),
                    const SizedBox(height: 12),
                    const Text('No scheduled calls',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ])
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    itemCount: _calls.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _calls[i];
                      final isVideo = c.callType == 'video';
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isVideo ? Icons.videocam_outlined
                                      : Icons.mic_outlined,
                              color: const Color(0xFF00D4FF), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.recipientId,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.calendar_today_outlined,
                                    color: Colors.white38, size: 12),
                                const SizedBox(width: 4),
                                Text(_fmt(c.callAt),
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                              ]),
                            ],
                          )),
                          GestureDetector(
                            onTap: () async {
                              await widget.service.cancel(c.scheduleId);
                              setState(() {});
                            },
                            child: Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.delete_outline,
                                  color: const Color(0xFFE53935), size: 16),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
