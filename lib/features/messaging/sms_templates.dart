import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xamepage/core/services/socket_service.dart';

// ── Default templates ─────────────────────────────────────────────────────────
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
    try {
      return List<String>.from(jsonDecode(raw));
    } catch (_) {
      return List.from(_defaultTemplates);
    }
  }

  Future<void> _save(List<String> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(templates));
  }

  Future<bool> addTemplate(String text) async {
    final t = await getTemplates();
    final trimmed = text.trim();
    if (trimmed.isEmpty || t.contains(trimmed)) return false;
    t.add(trimmed);
    await _save(t);
    return true;
  }

  Future<void> deleteTemplate(int index) async {
    final t = await getTemplates();
    if (index < 0 || index >= t.length) return;
    t.removeAt(index);
    await _save(t);
  }

  Future<void> editTemplate(int index, String newText) async {
    final t = await getTemplates();
    if (index < 0 || index >= t.length || newText.trim().isEmpty) return;
    t[index] = newText.trim();
    await _save(t);
  }

  Future<void> resetToDefaults() async {
    await _save(List.from(_defaultTemplates));
  }
}

// ── Quick Reply Sheet (shown on incoming call) ────────────────────────────────
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
      builder: (_) => QuickReplySheet(
        callerId: callerId,
        socket: socket,
        currentUserId: currentUserId,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<QuickReplySheet> createState() => _QuickReplySheetState();
}

class _QuickReplySheetState extends State<QuickReplySheet> {
  final _svc = SmsTemplatesService();
  List<String> _templates = [];
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc.getTemplates().then((t) => setState(() => _templates = t));
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    widget.socket.emit('send-message', {
      'recipientId': widget.callerId,
      'message': {
        'id': msgId,
        'text': text.trim(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    });
    widget.onDecline();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💬 Quick Reply',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates.map((t) => GestureDetector(
              onTap: () => _send(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                  color: Colors.white12,
                ),
                child: Text(t,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            )).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  decoration: InputDecoration(
                    hintText: 'Type a custom reply...',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: _send,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _send(_customCtrl.text),
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Manage Templates Dialog ───────────────────────────────────────────────────
class ManageTemplatesDialog extends StatefulWidget {
  const ManageTemplatesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ManageTemplatesDialog(),
    );
  }

  @override
  State<ManageTemplatesDialog> createState() => _ManageTemplatesDialogState();
}

class _ManageTemplatesDialogState extends State<ManageTemplatesDialog> {
  final _svc = SmsTemplatesService();
  List<String> _templates = [];
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final t = await _svc.getTemplates();
    if (mounted) setState(() => _templates = t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('💬 SMS Templates'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_templates[i], style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Text('✏️'),
                        onPressed: () async {
                          final ctrl =
                              TextEditingController(text: _templates[i]);
                          final result = await showDialog<String>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Edit Template'),
                              content: TextField(controller: ctrl),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, ctrl.text),
                                    child: const Text('Save')),
                              ],
                            ),
                          );
                          if (result != null) {
                            await _svc.editTemplate(i, result);
                            _reload();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 18),
                        onPressed: () async {
                          await _svc.deleteTemplate(i);
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Add new template...',
                      isDense: true,
                    ),
                    onSubmitted: (_) async {
                      if (await _svc.addTemplate(_addCtrl.text)) {
                        _addCtrl.clear();
                        _reload();
                      }
                    },
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (await _svc.addTemplate(_addCtrl.text)) {
                      _addCtrl.clear();
                      _reload();
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await _svc.resetToDefaults();
            _reload();
          },
          child: const Text('↺ Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
