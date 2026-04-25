import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/theme/app_theme.dart';

const _defaultTemplates = [
  "Can't talk right now, I'll call you back.",
  "I'm in a meeting. I'll call you soon.",
  "On my way, will call when free.",
  "Please send me a message instead.",
  "I'm driving. I'll call you later.",
];
const _storageKey = 'xamepage_sms_templates';

// ── Service ───────────────────────────────────────────────────────────────────
class SmsTemplatesService {
  Future<List<String>> getTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return List.from(_defaultTemplates);
    try { return List<String>.from(jsonDecode(raw)); }
    catch (_) { return List.from(_defaultTemplates); }
  }

  Future<void> _save(List<String> t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(t));
  }

  Future<bool> addTemplate(String text) async {
    final t = await getTemplates();
    final trimmed = text.trim();
    if (trimmed.isEmpty || t.contains(trimmed)) return false;
    t.add(trimmed); await _save(t); return true;
  }

  Future<void> deleteTemplate(int index) async {
    final t = await getTemplates();
    if (index < 0 || index >= t.length) return;
    t.removeAt(index); await _save(t);
  }

  Future<void> editTemplate(int index, String newText) async {
    final t = await getTemplates();
    if (index < 0 || index >= t.length || newText.trim().isEmpty) return;
    t[index] = newText.trim(); await _save(t);
  }

  Future<void> resetToDefaults() async => _save(List.from(_defaultTemplates));
}

// ── Quick Reply Sheet ─────────────────────────────────────────────────────────
class QuickReplySheet extends StatefulWidget {
  final String callerId;
  final SocketService socket;
  final String currentUserId;
  final VoidCallback onDecline;

  const QuickReplySheet({
    super.key,
    required this.callerId,
    required this.socket,
    required this.currentUserId,
    required this.onDecline,
  });

  static Future<void> show(BuildContext context, {
    required String callerId,
    required SocketService socket,
    required String currentUserId,
    required VoidCallback onDecline,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QuickReplySheet(
        callerId: callerId, socket: socket,
        currentUserId: currentUserId, onDecline: onDecline,
      ),
    );
  }

  @override
  State<QuickReplySheet> createState() => _QuickReplySheetState();
}

class _QuickReplySheetState extends State<QuickReplySheet> {
  final _svc        = SmsTemplatesService();
  final _customCtrl = TextEditingController();
  List<String> _templates = [];

  @override
  void initState() {
    super.initState();
    _svc.getTemplates().then((t) => setState(() => _templates = t));
  }

  @override
  void dispose() { _customCtrl.dispose(); super.dispose(); }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    widget.socket.emit('send-message', {
      'recipientId': widget.callerId,
      'message': {'id': msgId, 'text': text.trim(),
          'ts': DateTime.now().millisecondsSinceEpoch},
    });
    widget.onDecline();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.xSurface;
    return Container(
      decoration: BoxDecoration(
        color: context.xSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          )),
          // Header
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: context.xPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.message_outlined,
                  color: context.xPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Quick Reply',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: () => ManageTemplatesDialog.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Manage',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Template chips
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _templates.map((t) => GestureDetector(
              onTap: () => _send(t),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: context.xCard,
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(t,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),
          // Custom input
          Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _customCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Type a custom reply...',
                    hintStyle: TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: _send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_customCtrl.text),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [context.xPrimary,
                        context.xSurface],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Manage Templates Dialog ───────────────────────────────────────────────────
class ManageTemplatesDialog extends StatefulWidget {
  const ManageTemplatesDialog({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const ManageTemplatesDialog(),
  );

  @override
  State<ManageTemplatesDialog> createState() => _ManageTemplatesDialogState();
}

class _ManageTemplatesDialogState extends State<ManageTemplatesDialog> {
  final _svc     = SmsTemplatesService();
  final _addCtrl = TextEditingController();
  List<String> _templates = [];

  @override
  void initState() { super.initState(); _reload(); }

  @override
  void dispose() { _addCtrl.dispose(); super.dispose(); }

  Future<void> _reload() async {
    final t = await _svc.getTemplates();
    if (mounted) setState(() => _templates = t);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                    color: context.xPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.message_outlined,
                      color: context.xPrimary, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('SMS Templates',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await _svc.resetToDefaults();
                    _reload();
                  },
                  child: Text('Reset',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 16),
              // Add input
              Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.xCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      controller: _addCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Add new template...',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                      onSubmitted: (_) async {
                        if (await _svc.addTemplate(_addCtrl.text)) {
                          _addCtrl.clear(); _reload();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    if (await _svc.addTemplate(_addCtrl.text)) {
                      _addCtrl.clear(); _reload();
                    }
                  },
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: context.xPrimary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 20),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          ),
          // List
          Expanded(
            child: _templates.isEmpty
                ? Center(child: Text('No templates',
                    style: TextStyle(color: Colors.white38)))
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: _templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.xCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(_templates[i],
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            final ctrl2 = TextEditingController(
                                text: _templates[i]);
                            final result = await showDialog<String>(
                              context: context,
                              builder: (_) => _EditDialog(ctrl: ctrl2),
                            );
                            if (result != null) {
                              await _svc.editTemplate(i, result);
                              _reload();
                            }
                          },
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.edit_outlined,
                                color: Colors.white54, size: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () async {
                            await _svc.deleteTemplate(i);
                            _reload();
                          },
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: context.xDanger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.delete_outline,
                                color: context.xDanger, size: 15),
                          ),
                        ),
                      ]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _EditDialog extends StatelessWidget {
  final TextEditingController ctrl;
  const _EditDialog({required this.ctrl});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.xCard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Edit Template',
            style: TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: XameColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: ctrl, autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, ctrl.text),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: XameColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('Save',
                    style: TextStyle(color: Colors.black,
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ]),
    ),
  );
}
