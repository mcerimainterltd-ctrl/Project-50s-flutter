import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class BroadcastList {
  final String listId;
  final String name;
  final List<String> members;

  const BroadcastList({
    required this.listId,
    required this.name,
    required this.members,
  });

  factory BroadcastList.fromJson(Map<String, dynamic> j) => BroadcastList(
    listId:  j['listId']  as String,
    name:    j['name']    as String,
    members: List<String>.from(j['members'] ?? []),
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class BroadcastService {
  final SocketService _socket;
  final String _userId;
  List<BroadcastList> _lists = [];

  BroadcastService(this._socket, this._userId);

  List<BroadcastList> get lists => List.unmodifiable(_lists);

  Future<void> load() async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/broadcast/$_userId'));
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _lists = (d['lists'] as List)
            .map((l) => BroadcastList.fromJson(Map<String, dynamic>.from(l)))
            .toList();
      }
    } catch (e) { debugPrint('[Broadcast] Load error: $e'); }
  }

  Future<BroadcastList?> createList(String name, List<String> members) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/broadcast/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerId': _userId, 'name': name, 'members': members}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final list = BroadcastList.fromJson(Map<String, dynamic>.from(d['list']));
        _lists.insert(0, list);
        return list;
      }
    } catch (e) { debugPrint('[Broadcast] Create error: $e'); }
    return null;
  }

  Future<void> updateList(String listId, String name, List<String> members) async {
    try {
      final res = await http.put(
        Uri.parse('${AppConstants.serverUrl}/api/broadcast/$listId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerId': _userId, 'name': name, 'members': members}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final i = _lists.indexWhere((l) => l.listId == listId);
        if (i != -1) {
          _lists[i] = BroadcastList.fromJson(Map<String, dynamic>.from(d['list']));
        }
      }
    } catch (e) { debugPrint('[Broadcast] Update error: $e'); }
  }

  Future<void> deleteList(String listId) async {
    try {
      await http.delete(
        Uri.parse('${AppConstants.serverUrl}/api/broadcast/$listId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerId': _userId}),
      );
      _lists.removeWhere((l) => l.listId == listId);
    } catch (e) { debugPrint('[Broadcast] Delete error: $e'); }
  }

  Future<void> send({
    required List<String> recipients,
    required String text,
  }) async {
    for (final recipientId in recipients) {
      final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          recipientId.hashCode.toRadixString(36);
      _socket.emit('send-message', {
        'recipientId': recipientId,
        'message': {
          'id': msgId,
          'text': text,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      });
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}

// ── Broadcast Screen ──────────────────────────────────────────────────────────
class BroadcastScreen extends StatefulWidget {
  final BroadcastService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;

  const BroadcastScreen({
    super.key,
    required this.service,
    required this.contacts,
    required this.currentUserId,
  });

  static Future<void> show(BuildContext context, {
    required BroadcastService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BroadcastScreen(
        service: service,
        contacts: contacts,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  @override
  Widget build(BuildContext context) {
    final lists = widget.service.lists;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📢 Mass Messaging',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _openNewBroadcast(context),
                    child: const Text('📨 New Broadcast'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _openManageLists(context),
                    child: const Text('📋 Manage Broadcast Lists'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Saved Lists',
                  style: TextStyle(fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: lists.isEmpty
                ? const Center(
                    child: Text('No saved lists yet',
                        style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: lists.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = lists[i];
                      return ListTile(
                        title: Text(l.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${l.members.length} recipients'),
                        trailing: FilledButton(
                          onPressed: () => _openNewBroadcast(context,
                              preselected: l.members),
                          child: const Text('Send'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openNewBroadcast(BuildContext context, {List<String>? preselected}) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewBroadcastSheet(
        service:      widget.service,
        contacts:     widget.contacts,
        currentUserId: widget.currentUserId,
        preselected:  preselected,
      ),
    );
  }

  void _openManageLists(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => _ManageListsDialog(
        service:      widget.service,
        contacts:     widget.contacts,
        currentUserId: widget.currentUserId,
      ),
    );
  }
}

// ── New Broadcast Sheet ───────────────────────────────────────────────────────
class _NewBroadcastSheet extends StatefulWidget {
  final BroadcastService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final List<String>? preselected;

  const _NewBroadcastSheet({
    required this.service,
    required this.contacts,
    required this.currentUserId,
    this.preselected,
  });

  @override
  State<_NewBroadcastSheet> createState() => _NewBroadcastSheetState();
}

class _NewBroadcastSheetState extends State<_NewBroadcastSheet> {
  late Set<String> _selected;
  final _textCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.preselected ?? []);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.contacts
        .where((c) => c['id'] != widget.currentUserId)
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📨 New Broadcast',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Select Recipients',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: ListView(
              children: contacts.map((c) {
                final id = c['id'] as String;
                final name = c['name'] as String? ?? id;
                return CheckboxListTile(
                  dense: true,
                  title: Text(name),
                  value: _selected.contains(id),
                  onChanged: (v) => setState(() =>
                      v! ? _selected.add(id) : _selected.remove(id)),
                );
              }).toList(),
            ),
          ),
          TextField(
            controller: _textCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Type your message...',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    if (_selected.isEmpty) {
                      _snack('Select at least one contact');
                      return;
                    }
                    final name = await _promptText(context, 'Enter list name:');
                    if (name == null || name.isEmpty) return;
                    await widget.service.createList(name, _selected.toList());
                    _snack('List saved!');
                  },
                  child: const Text('💾 Save List'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _sending ? null : () async {
                    if (_selected.isEmpty) { _snack('Select recipients'); return; }
                    if (_textCtrl.text.trim().isEmpty) { _snack('Type a message'); return; }
                    setState(() => _sending = true);
                    await widget.service.send(
                      recipients: _selected.toList(),
                      text: _textCtrl.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _snack('✅ Sent to ${_selected.length} contacts!');
                    }
                  },
                  child: const Text('📤 Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _promptText(BuildContext context, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }
}

// ── Manage Lists Dialog ───────────────────────────────────────────────────────
class _ManageListsDialog extends StatefulWidget {
  final BroadcastService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;

  const _ManageListsDialog({
    required this.service,
    required this.contacts,
    required this.currentUserId,
  });

  @override
  State<_ManageListsDialog> createState() => _ManageListsDialogState();
}

class _ManageListsDialogState extends State<_ManageListsDialog> {
  List<BroadcastList> get _lists => widget.service.lists;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('📋 Broadcast Lists'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _NewBroadcastSheet(
                    service: widget.service,
                    contacts: widget.contacts,
                    currentUserId: widget.currentUserId,
                  ),
                );
              },
              child: const Text('+ New List'),
            ),
            const SizedBox(height: 8),
            if (_lists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No lists yet', style: TextStyle(color: Colors.grey)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _lists.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = _lists[i];
                    return ListTile(
                      dense: true,
                      title: Text(l.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${l.members.length} members'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 20),
                        onPressed: () async {
                          await widget.service.deleteList(l.listId);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
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
