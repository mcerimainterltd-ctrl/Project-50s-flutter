import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ── Model ─────────────────────────────────────────────────────────────────────
class ScheduledCall {
  final String scheduleId;
  final String recipientId;
  final String callType;
  final int callAt;

  const ScheduledCall({
    required this.scheduleId,
    required this.recipientId,
    required this.callType,
    required this.callAt,
  });

  factory ScheduledCall.fromJson(Map<String, dynamic> j) => ScheduledCall(
    scheduleId:  j['scheduleId'] as String,
    recipientId: j['recipientId'] as String,
    callType:    j['callType'] as String? ?? 'voice',
    callAt:      j['callAt'] as int,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class CallScheduleService {
  final SocketService _socket;
  final String _userId;
  final FlutterLocalNotificationsPlugin _notifs =
      FlutterLocalNotificationsPlugin();

  List<ScheduledCall> _calls = [];

  // Called when a scheduled call is due — wire to your call initiation logic
  void Function(String recipientId, String callType)? onCallDue;

  CallScheduleService(this._socket, this._userId) {
    _initNotifs();
    _listenSocket();
  }

  Future<void> _initNotifs() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifs.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
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
    } catch (e) {
      debugPrint('[CallSchedule] Load error: $e');
    }
  }

  void _listenSocket() {
    _socket.emit('schedule-call-listen', null);
    // Listen for due events via raw socket
    _socket.emit('subscribe:schedule', {'userId': _userId});
  }

  // Call this from your socket handler when 'scheduled-call-due' fires
  void handleDue(Map<String, dynamic> data) {
    final scheduleId  = data['scheduleId'] as String?;
    final recipientId = data['recipientId'] as String?;
    final callType    = data['callType'] as String? ?? 'voice';
    if (scheduleId == null || recipientId == null) return;
    _calls.removeWhere((c) => c.scheduleId == scheduleId);
    onCallDue?.call(recipientId, callType);
  }

  Future<ScheduledCall?> create({
    required String recipientId,
    required String callType,
    required DateTime callAt,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/schedule-call/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'callerId':   _userId,
          'recipientId': recipientId,
          'callType':   callType,
          'callAt':     callAt.millisecondsSinceEpoch,
        }),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final call = ScheduledCall.fromJson(
            Map<String, dynamic>.from(d['call']));
        _calls.add(call);
        await _scheduleLocalNotif(call);
        return call;
      }
    } catch (e) {
      debugPrint('[CallSchedule] Create error: $e');
    }
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
      await _cancelLocalNotif(scheduleId);
    } catch (e) {
      debugPrint('[CallSchedule] Cancel error: $e');
    }
  }

  List<ScheduledCall> get calls => List.unmodifiable(_calls);

  Future<void> _scheduleLocalNotif(ScheduledCall call) async {
    final id = call.scheduleId.hashCode.abs() % 100000;
    final scheduledDate = DateTime.fromMillisecondsSinceEpoch(call.callAt)
        .toLocal();
    if (scheduledDate.isBefore(DateTime.now())) return;
    await _notifs.zonedSchedule(
      id,
      '📞 Scheduled Call',
      'Time to call ${call.recipientId}',
      _toTZDateTime(scheduledDate),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_calls', 'Scheduled Calls',
          channelDescription: 'Reminders for scheduled calls',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _cancelLocalNotif(String scheduleId) async {
    final id = scheduleId.hashCode.abs() % 100000;
    await _notifs.cancel(id);
  }

  // Simple TZ helper — works without timezone package
  dynamic _toTZDateTime(DateTime dt) => dt;
}

// ── Schedule Call Dialog ──────────────────────────────────────────────────────
class ScheduleCallDialog extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final CallScheduleService service;

  const ScheduleCallDialog({
    super.key,
    required this.recipientId,
    required this.recipientName,
    required this.service,
  });

  static Future<void> show(BuildContext context, {
    required String recipientId,
    required String recipientName,
    required CallScheduleService service,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ScheduleCallDialog(
        recipientId:   recipientId,
        recipientName: recipientName,
        service:       service,
      ),
    );
  }

  @override
  State<ScheduleCallDialog> createState() => _ScheduleCallDialogState();
}

class _ScheduleCallDialogState extends State<ScheduleCallDialog> {
  String _callType = 'voice';
  DateTime _selectedDateTime = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selectedDateTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('📞 Schedule Call'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('To: ${widget.recipientName}',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          const Text('Call Type',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TypeBtn(
                  label: '🎙️ Voice',
                  selected: _callType == 'voice',
                  onTap: () => setState(() => _callType = 'voice'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TypeBtn(
                  label: '📹 Video',
                  selected: _callType == 'video',
                  onTap: () => setState(() => _callType = 'video'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickDateTime,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedDateTime.year}-'
                    '${_selectedDateTime.month.toString().padLeft(2, '0')}-'
                    '${_selectedDateTime.day.toString().padLeft(2, '0')}  '
                    '${_selectedDateTime.hour.toString().padLeft(2, '0')}:'
                    '${_selectedDateTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            ScheduledCallsListDialog.show(context, service: widget.service);
          },
          child: const Text('📋 View'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : () async {
            if (_selectedDateTime.isBefore(DateTime.now())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a future time')));
              return;
            }
            setState(() => _loading = true);
            final call = await widget.service.create(
              recipientId: widget.recipientId,
              callType:    _callType,
              callAt:      _selectedDateTime,
            );
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(call != null
                  ? 'Call scheduled for ${_selectedDateTime.toString().substring(0, 16)}'
                  : 'Failed to schedule call'),
              ));
            }
          },
          child: const Text('✅ Schedule'),
        ),
      ],
    );
  }
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : null,
            )),
      ),
    );
  }
}

// ── Scheduled Calls List Dialog ───────────────────────────────────────────────
class ScheduledCallsListDialog extends StatefulWidget {
  final CallScheduleService service;

  const ScheduledCallsListDialog({super.key, required this.service});

  static Future<void> show(BuildContext context,
      {required CallScheduleService service}) {
    return showDialog(
      context: context,
      builder: (_) => ScheduledCallsListDialog(service: service),
    );
  }

  @override
  State<ScheduledCallsListDialog> createState() =>
      _ScheduledCallsListDialogState();
}

class _ScheduledCallsListDialogState
    extends State<ScheduledCallsListDialog> {

  List<ScheduledCall> get _calls => widget.service.calls;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('📋 Scheduled Calls'),
      content: SizedBox(
        width: double.maxFinite,
        child: _calls.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No scheduled calls',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _calls.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _calls[i];
                    final icon = c.callType == 'video' ? '📹' : '🎙️';
                    final dt = DateTime.fromMillisecondsSinceEpoch(c.callAt);
                    return ListTile(
                      dense: true,
                      title: Text('$icon To: ${c.recipientId}',
                          style: const TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      subtitle: Text(
                          '📅 ${dt.toString().substring(0, 16)}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 20),
                        onPressed: () async {
                          await widget.service.cancel(c.scheduleId);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
