
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../contacts/providers/contacts_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class ScheduledMessage {
  final String  scheduleId, senderId, recipientId, recipientName;
  final String? text, fileUrl, fileName;
  final int     sendAt;
  ScheduledMessage({
    required this.scheduleId, required this.senderId,
    required this.recipientId, required this.recipientName,
    this.text, this.fileUrl, this.fileName,
    required this.sendAt,
  });
  factory ScheduledMessage.fromJson(Map<String, dynamic> j) => ScheduledMessage(
    scheduleId:    j['scheduleId']    as String,
    senderId:      j['senderId']      as String,
    recipientId:   j['recipientId']   as String,
    recipientName: j['recipientName'] as String? ?? j['recipientId'] as String,
    text:          j['text']          as String?,
    fileUrl:       j['file'] != null ? (j['file']['url'] as String?) : null,
    fileName:      j['file'] != null ? (j['file']['name'] as String?) : null,
    sendAt:        (j['sendAt'] as num).toInt(),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final scheduledMessagesProvider =
    StateNotifierProvider<ScheduledMessagesNotifier, List<ScheduledMessage>>(
        ScheduledMessagesNotifier.new);

class ScheduledMessagesNotifier extends StateNotifier<List<ScheduledMessage>> {
  final Ref _ref;
  final _dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));

  ScheduledMessagesNotifier(this._ref) : super([]) {
    _load();
    _listenSocket();
  }

  Future<void> _load() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await _dio.get('/api/schedule/${user.xameId}');
      if (res.data['success'] == true) {
        state = (res.data['messages'] as List)
            .map((m) => ScheduledMessage.fromJson(
                Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
  }

  void _listenSocket() {
    final socket = _ref.read(socketServiceProvider);
    socket.rawSocket?.on('scheduled-message-sent', (data) {
      final map = Map<String, dynamic>.from(data);
      final id  = map['scheduleId'] as String;
      state     = state.where((m) => m.scheduleId != id).toList();
    });
  }

  Future<bool> create({
    required String senderId,
    required String recipientId,
    required String recipientName,
    String?  text,
    String?  fileUrl,
    String?  fileName,
    String?  fileMime,
    required int    sendAt,
  }) async {
    try {
      final res = await _dio.post('/api/schedule/create', data: {
        'senderId':    senderId,
        'recipientId': recipientId,
        'text':        text,
        'file':        fileUrl != null
            ? {'url': fileUrl, 'name': fileName, 'type': fileMime}
            : null,
        'sendAt': sendAt,
      });
      if (res.data['success'] == true) {
        state = [...state,
            ScheduledMessage.fromJson(
                Map<String, dynamic>.from(res.data['message']))];
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> cancel(String scheduleId, String userId) async {
    try {
      await _dio.delete('/api/schedule/$scheduleId',
          data: {'userId': userId});
      state = state.where((m) => m.scheduleId != scheduleId).toList();
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> refresh() => _load();
}

// ── Message Schedule Screen ───────────────────────────────────────────────────
class MessageScheduleScreen extends ConsumerWidget {
  const MessageScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages  = ref.watch(scheduledMessagesProvider);
    final contacts  = ref.watch(contactsProvider).valueOrNull ?? [];
    final user      = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.xBg,
      body: messages.isEmpty
          ? _emptyState(context)
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(scheduledMessagesProvider.notifier).refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final msg     = messages[i];
                  final contact = contacts.where((c) =>
                      c.id == msg.recipientId).firstOrNull;
                  final name    = contact?.name ?? msg.recipientName;
                  final dt      = DateTime.fromMillisecondsSinceEpoch(msg.sendAt);
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
                          color: context.xAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                        child: Icon(Icons.schedule_send_rounded,
                            color: context.xAccent, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To: $name',
                              style: TextStyle(color: context.xText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          if (msg.text != null && msg.text!.isNotEmpty)
                            Text(msg.text!,
                                style: TextStyle(
                                    color: context.xMuted, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          if (msg.fileName != null)
                            Text('📎 ${msg.fileName}',
                                style: TextStyle(
                                    color: context.xMuted, fontSize: 12)),
                          const SizedBox(height: 3),
                          Text('📅 $fmt',
                              style: TextStyle(
                                  color: context.xMuted, fontSize: 11)),
                        ],
                      )),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: context.xDanger, size: 20),
                        onPressed: () async {
                          if (user == null) return;
                          await ref
                              .read(scheduledMessagesProvider.notifier)
                              .cancel(msg.scheduleId, user.xameId);
                        }),
                    ]),
                  );
                },
              )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showComposeSheet(context),
        backgroundColor: context.xAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.schedule_send_rounded),
        label: const Text('Schedule Message',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: context.xCard, shape: BoxShape.circle,
          border: Border.all(
              color: context.xAccent.withValues(alpha: 0.3))),
        child: Icon(Icons.schedule_send_rounded,
            color: context.xAccent, size: 56)),
      const SizedBox(height: 24),
      Text('No Scheduled Messages',
          style: TextStyle(color: context.xText,
              fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Schedule messages to send later',
          style: TextStyle(color: context.xMuted, fontSize: 14)),
      const SizedBox(height: 32),
      Builder(builder: (ctx) => ElevatedButton.icon(
        onPressed: () => _showComposeSheet(ctx),
        icon: const Icon(Icons.add),
        label: const Text('Schedule a Message',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.xAccent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))),
      )),
    ],
  ));

  void _showComposeSheet(BuildContext context,
      {String? recipientId, String? recipientName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComposeScheduledSheet(
        preselectedId:   recipientId,
        preselectedName: recipientName,
      ),
    );
  }
}

// ── Compose Sheet ─────────────────────────────────────────────────────────────
class ComposeScheduledSheet extends ConsumerStatefulWidget {
  final String? preselectedId, preselectedName;
  const ComposeScheduledSheet({this.preselectedId, this.preselectedName});
  @override
  ConsumerState<ComposeScheduledSheet> createState() =>
      ComposeScheduledSheetState();
}

class ComposeScheduledSheetState
    extends ConsumerState<ComposeScheduledSheet> {
  final _textCtrl = TextEditingController();
  String?  _recipientId, _recipientName;
  String?  _fileUrl, _fileName, _fileMime;
  DateTime _sendAt   = DateTime.now().add(const Duration(hours: 1));
  bool     _loading  = false;
  bool     _uploading = false;
  String   _search   = '';

  @override
  void initState() {
    super.initState();
    _recipientId   = widget.preselectedId;
    _recipientName = widget.preselectedName;
  }

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _uploading = true);
    try {
      final dio     = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final formData = FormData.fromMap({
        'file':        await MultipartFile.fromFile(file.path!,
            filename: file.name),
        'senderId':    ref.read(currentUserProvider)?.xameId ?? '',
        'recipientId': 'scheduled',
        'messageId':   DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final res = await dio.post('/api/upload-file', data: formData);
      if (res.data['success'] == true) {
        setState(() {
          _fileUrl  = res.data['url'] as String;
          _fileName = file.name;
          _fileMime = file.extension;
        });
      }
    } catch (_) {}
    setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final filtered = _search.isEmpty ? contacts
        : contacts.where((c) =>
            c.name.toLowerCase().contains(_search.toLowerCase())).toList();
    final user = ref.watch(currentUserProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141420),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('🕐 Schedule Message',
              style: TextStyle(color: Colors.white,
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
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          context.xAccent.withValues(alpha: 0.2),
                      child: Text(c.name[0].toUpperCase(),
                          style: TextStyle(color: context.xAccent,
                              fontSize: 12, fontWeight: FontWeight.w700))),
                    title: Text(c.name,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13)),
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
                color: context.xAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: context.xAccent.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(Icons.person_outline,
                    color: context.xAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    _recipientName ?? _recipientId!,
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
          const SizedBox(height: 12),

          // Message text
          TextField(
            controller: _textCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type your message...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true, fillColor: const Color(0xFF1E1E2E),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(14)),
          ),
          const SizedBox(height: 8),

          // File attachment
          GestureDetector(
            onTap: _uploading ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12)),
              child: Row(children: [
                Icon(Icons.attach_file_rounded,
                    color: _fileUrl != null
                        ? context.xAccent : Colors.white38,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  _uploading ? 'Uploading...'
                      : (_fileName ?? 'Attach file (optional)'),
                  style: TextStyle(
                    color: _fileUrl != null
                        ? context.xAccent : Colors.white38,
                    fontSize: 13))),
                if (_fileUrl != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _fileUrl = null; _fileName = null; _fileMime = null;
                    }),
                    child: const Icon(Icons.close,
                        color: Colors.white38, size: 16)),
              ]),
            )),
          const SizedBox(height: 16),

          // Date & Time
          const Text('Send At',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _dateTile(context)),
            const SizedBox(width: 10),
            Expanded(child: _timeTile(context)),
          ]),
          const SizedBox(height: 24),

          // Schedule button
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.xAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
              onPressed: (_loading || _uploading ||
                      _recipientId == null || user == null ||
                      (_textCtrl.text.trim().isEmpty && _fileUrl == null))
                  ? null
                  : () async {
                      if (_sendAt.isBefore(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Please select a future time')));
                        return;
                      }
                      setState(() => _loading = true);
                      final ok = await ref
                          .read(scheduledMessagesProvider.notifier)
                          .create(
                            senderId:      user.xameId,
                            recipientId:   _recipientId!,
                            recipientName: _recipientName ?? _recipientId!,
                            text:          _textCtrl.text.trim().isEmpty
                                ? null : _textCtrl.text.trim(),
                            fileUrl:  _fileUrl,
                            fileName: _fileName,
                            fileMime: _fileMime,
                            sendAt: _sendAt.millisecondsSinceEpoch,
                          );
                      if (mounted) {
                        setState(() => _loading = false);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? '✅ Message scheduled for ${DateFormat('MMM d, h:mm a').format(_sendAt)}'
                              : '❌ Failed to schedule message'),
                          backgroundColor: ok
                              ? context.xAccent : context.xDanger));
                      }
                    },
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('✅ Schedule Message',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15)),
            )),
        ],
      )),
    );
  }

  Widget _dateTile(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: _sendAt,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: context.xAccent)),
          child: child!));
      if (picked != null) setState(() => _sendAt = DateTime(
        picked.year, picked.month, picked.day,
        _sendAt.hour, _sendAt.minute));
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const Text('Date',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(DateFormat('MMM d, y').format(_sendAt),
          style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600)),
      ])));

  Widget _timeTile(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_sendAt),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(primary: context.xAccent)),
          child: child!));
      if (picked != null) setState(() => _sendAt = DateTime(
        _sendAt.year, _sendAt.month, _sendAt.day,
        picked.hour, picked.minute));
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const Text('Time',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(DateFormat('h:mm a').format(_sendAt),
          style: const TextStyle(color: Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600)),
      ])));
}
