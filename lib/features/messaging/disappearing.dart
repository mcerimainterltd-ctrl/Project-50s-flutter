import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xamepage/core/services/socket_service.dart';

// ── Timer presets ─────────────────────────────────────────────────────────────
class TimerOption {
  final String value;
  final String label;
  final int ms;
  const TimerOption({required this.value, required this.label, required this.ms});
}

const timerOptions = [
  TimerOption(value: 'off', label: 'Off',      ms: 0),
  TimerOption(value: '30s', label: '30 sec',   ms: 30000),
  TimerOption(value: '5m',  label: '5 min',    ms: 300000),
  TimerOption(value: '1h',  label: '1 hour',   ms: 3600000),
  TimerOption(value: '24h', label: '24 hours', ms: 86400000),
  TimerOption(value: '7d',  label: '7 days',   ms: 604800000),
  TimerOption(value: '90d', label: '90 days',  ms: 7776000000),
];

// ── Active timer entry ────────────────────────────────────────────────────────
class _TimerEntry {
  final Timer timer;
  final int expiresAt;
  final String? contactId;
  _TimerEntry({required this.timer, required this.expiresAt, this.contactId});
}

// ── Provider ──────────────────────────────────────────────────────────────────
final disappearingProvider = Provider<DisappearingService>((ref) {
  final socket = ref.read(socketServiceProvider);
  return DisappearingService(socket);
});

// ── Service ───────────────────────────────────────────────────────────────────
class DisappearingService {
  final SocketService _socket;
  final Map<String, _TimerEntry> _activeTimers = {};

  // Callbacks registered by messaging layer
  void Function(String messageId, String? contactId)? onDelete;

  DisappearingService(this._socket) {
    _socket.disappearExpired.listen((data) {
      cancelTimer(data.messageId);
      onDelete?.call(data.messageId, data.contactId);
    });
  }

  // ── Stamp outgoing message with expiresAt ─────────────────────────────────
  Future<Map<String, dynamic>> stampMessage(
      Map<String, dynamic> msg, String contactId) async {
    final ms = await _getTimerMs(contactId);
    if (ms == 0) return msg;
    final expiresAt = DateTime.now().millisecondsSinceEpoch + ms;
    final label = timerOptions.firstWhere((o) => o.ms == ms,
        orElse: () => timerOptions.first).label;
    return {...msg, 'expiresAt': expiresAt, 'timerLabel': label};
  }

  // ── Schedule client-side deletion ─────────────────────────────────────────
  void scheduleDelete(String messageId, int expiresAt, String? contactId) {
    cancelTimer(messageId);
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      onDelete?.call(messageId, contactId);
      return;
    }
    final timer = Timer(Duration(milliseconds: remaining), () {
      _activeTimers.remove(messageId);
      onDelete?.call(messageId, contactId);
    });
    _activeTimers[messageId] = _TimerEntry(
      timer: timer, expiresAt: expiresAt, contactId: contactId);
  }

  // ── Restore timers on login/reload ────────────────────────────────────────
  void restoreTimers(List<Map<String, dynamic>> messages) {
    int restored = 0;
    for (final msg in messages) {
      final expiresAt = msg['expiresAt'] as int?;
      final id = msg['id'] as String?;
      if (expiresAt == null || id == null) continue;
      final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
      if (remaining <= 0) continue;
      scheduleDelete(id, expiresAt, msg['contactId'] as String?);
      restored++;
    }
    if (restored > 0) debugPrint('[Disappearing] Restored $restored timer(s)');
  }

  void cancelTimer(String messageId) {
    _activeTimers[messageId]?.timer.cancel();
    _activeTimers.remove(messageId);
  }

  int? getRemainingMs(String messageId) {
    final entry = _activeTimers[messageId];
    if (entry == null) return null;
    return (entry.expiresAt - DateTime.now().millisecondsSinceEpoch)
        .clamp(0, double.maxFinite.toInt());
  }

  // ── Timer persistence ─────────────────────────────────────────────────────
  Future<String> getChatTimer(String contactId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('xame:disappear:$contactId') ?? 'off';
  }

  Future<void> setChatTimer(String contactId, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == 'off') {
      await prefs.remove('xame:disappear:$contactId');
    } else {
      await prefs.setString('xame:disappear:$contactId', value);
    }
  }

  Future<int> _getTimerMs(String contactId) async {
    final value = await getChatTimer(contactId);
    return timerOptions.firstWhere((o) => o.value == value,
        orElse: () => timerOptions.first).ms;
  }

  // ── Format remaining time ─────────────────────────────────────────────────
  static String formatRemaining(int ms) {
    if (ms < 60000)    return '${(ms / 1000).ceil()}s';
    if (ms < 3600000)  return '${(ms / 60000).ceil()}m';
    if (ms < 86400000) return '${(ms / 3600000).ceil()}h';
    return '${(ms / 86400000).ceil()}d';
  }
}

// ── Timer Dialog Widget ───────────────────────────────────────────────────────
class DisappearingTimerDialog extends ConsumerStatefulWidget {
  final String contactId;
  final SocketService socket;
  final String currentUserId;

  const DisappearingTimerDialog({
    super.key,
    required this.contactId,
    required this.socket,
    required this.currentUserId,
  });

  static Future<void> show(BuildContext context, {
    required String contactId,
    required SocketService socket,
    required String currentUserId,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => DisappearingTimerDialog(
        contactId: contactId,
        socket: socket,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  ConsumerState<DisappearingTimerDialog> createState() =>
      _DisappearingTimerDialogState();
}

class _DisappearingTimerDialogState
    extends ConsumerState<DisappearingTimerDialog> {
  String _current = 'off';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(disappearingProvider);
    final val = await svc.getChatTimer(widget.contactId);
    if (mounted) setState(() => _current = val);
  }

  Future<void> _select(String value) async {
    final svc = ref.read(disappearingProvider);
    await svc.setChatTimer(widget.contactId, value);
    widget.socket.emit('disappearing:timer-set', {
      'contactId': widget.contactId,
      'userId': widget.currentUserId,
      'value': value,
    });
    setState(() => _current = value);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⏱️ Disappearing Messages',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Messages will automatically disappear after the selected time.',
              style: TextStyle(fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          ...timerOptions.map((opt) {
            final active = _current == opt.value;
            return GestureDetector(
              onTap: () => _select(opt.value),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                  ),
                  color: active
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(opt.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        )),
                    if (active)
                      Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
