import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class BroadcastList {
  final String listId, name;
  final List<String> members;
  const BroadcastList({required this.listId, required this.name,
      required this.members});
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
        _lists.insert(0, list); return list;
      }
    } catch (e) { debugPrint('[Broadcast] Create error: $e'); }
    return null;
  }

  Future<void> updateList(String listId, String name,
      List<String> members) async {
    try {
      final res = await http.put(
        Uri.parse('${AppConstants.serverUrl}/api/broadcast/$listId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerId': _userId, 'name': name, 'members': members}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final i = _lists.indexWhere((l) => l.listId == listId);
        if (i != -1) _lists[i] = BroadcastList.fromJson(
            Map<String, dynamic>.from(d['list']));
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

  Future<void> send({required List<String> recipients,
      required String text}) async {
    for (final recipientId in recipients) {
      final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          recipientId.hashCode.toRadixString(36);
      _socket.emit('send-message', {
        'recipientId': recipientId,
        'message': {'id': msgId, 'text': text,
            'ts': DateTime.now().millisecondsSinceEpoch},
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

  const BroadcastScreen({super.key, required this.service,
      required this.contacts, required this.currentUserId});

  static Future<void> show(BuildContext context, {
    required BroadcastService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId,
  }) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => BroadcastScreen(service: service,
        contacts: contacts, currentUserId: currentUserId),
  );

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  @override
  Widget build(BuildContext context) {
    final lists = widget.service.lists;
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
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.xPrimary, context.xSurface],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_outlined,
                      color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Mass Messaging', style: TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Send to multiple contacts at once',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, color: Colors.white38, size: 20),
                ),
              ]),
              const SizedBox(height: 16),
              // Action buttons
              Row(children: [
                Expanded(child: _ActionBtn(
                  icon: Icons.send_outlined,
                  label: 'New Broadcast',
                  color: context.xPrimary,
                  onTap: () => _openNewBroadcast(context),
                )),
                const SizedBox(width: 10),
                Expanded(child: _ActionBtn(
                  icon: Icons.list_outlined,
                  label: 'Manage Lists',
                  color: context.xSurface,
                  onTap: () => _openManageLists(context),
                )),
              ]),
              const SizedBox(height: 16),
              if (lists.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Saved Lists (${lists.length})',
                      style: const TextStyle(color: Colors.white38,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          // Lists
          Expanded(
            child: lists.isEmpty
                ? Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(Icons.campaign_outlined,
                        color: Colors.white12, size: 48),
                    const SizedBox(height: 12),
                    Text('No saved lists yet',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _openNewBroadcast(context),
                      child: Text('Create your first broadcast →',
                          style: TextStyle(color: context.xPrimary,
                              fontSize: 13)),
                    ),
                  ])
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: lists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final l = lists[i];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.xCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: context.xPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text('${l.members.length}',
                                  style: TextStyle(
                                      color: context.xPrimary, fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, style: const TextStyle(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                              Text('${l.members.length} recipients',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ],
                          )),
                          GestureDetector(
                            onTap: () => _openNewBroadcast(context,
                                preselected: l.members),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [context.xPrimary,
                                      context.xSurface]),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Send',
                                  style: TextStyle(color: Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
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

  void _openNewBroadcast(BuildContext context, {List<String>? preselected}) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NewBroadcastSheet(
        service: widget.service, contacts: widget.contacts,
        currentUserId: widget.currentUserId, preselected: preselected),
    );
  }

  void _openManageLists(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ManageListsSheet(
        service: widget.service, contacts: widget.contacts,
        currentUserId: widget.currentUserId),
    );
  }
}

// ── New Broadcast Sheet ───────────────────────────────────────────────────────
class _NewBroadcastSheet extends StatefulWidget {
  final BroadcastService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final List<String>? preselected;

  const _NewBroadcastSheet({required this.service, required this.contacts,
      required this.currentUserId, this.preselected});

  @override
  State<_NewBroadcastSheet> createState() => _NewBroadcastSheetState();
}

class _NewBroadcastSheetState extends State<_NewBroadcastSheet> {
  late Set<String> _selected;
  final _textCtrl  = TextEditingController();
  bool _sending    = false;
  String _search   = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.preselected ?? []);
  }

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.contacts
        .where((c) => c['id'] != widget.currentUserId)
        .where((c) => _search.isEmpty ||
            (c['name'] as String? ?? '').toLowerCase()
                .contains(_search.toLowerCase()) ||
            (c['id'] as String).toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
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
                Text('New Broadcast', style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_selected.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.xPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_selected.length} selected',
                        style: TextStyle(color: context.xPrimary,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 12),
              // Search
              Container(
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: Colors.white30),
                    prefixIcon: Icon(Icons.search, color: Colors.white30,
                        size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
          // Contacts list
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: contacts.length,
              itemBuilder: (_, i) {
                final c   = contacts[i];
                final id  = c['id'] as String;
                final name = c['name'] as String? ?? id;
                final sel  = _selected.contains(id);
                return GestureDetector(
                  onTap: () => setState(() =>
                      sel ? _selected.remove(id) : _selected.add(id)),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel
                          ? context.xPrimary.withValues(alpha: 0.08)
                          : context.xCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? context.xPrimary.withValues(alpha: 0.3)
                            : Colors.white10,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: context.xPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(name.isNotEmpty
                              ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                  color: context.xPrimary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(
                              color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w500)),
                          Text(id, style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                        ],
                      )),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: sel ? context.xPrimary : Colors.transparent,
                          border: Border.all(
                            color: sel ? context.xPrimary : Colors.white24,
                            width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: sel
                            ? const Icon(Icons.check, color: Colors.black,
                                size: 14)
                            : null,
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          // Message + send
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            decoration: BoxDecoration(
              color: context.xSurface,
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _textCtrl,
                  maxLines: 3, minLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (_selected.isEmpty) { _snack('Select contacts'); return; }
                      final name = await _promptName(context);
                      if (name == null || name.isEmpty) return;
                      await widget.service.createList(
                          name, _selected.toList());
                      _snack('List saved!');
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.xCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      alignment: Alignment.center,
                      child: const Text('💾 Save List',
                          style: TextStyle(color: Colors.white54,
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _sending ? null : () async {
                      if (_selected.isEmpty) {
                        _snack('Select recipients'); return;
                      }
                      if (_textCtrl.text.trim().isEmpty) {
                        _snack('Type a message'); return;
                      }
                      setState(() => _sending = true);
                      await widget.service.send(
                        recipients: _selected.toList(),
                        text: _textCtrl.text.trim(),
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              '✅ Sent to ${_selected.length} contacts!'),
                          backgroundColor:
                              context.xAccent.withValues(alpha: 0.2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ));
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: _sending ? null : LinearGradient(
                          colors: [context.xPrimary, context.xSurface]),
                        color: _sending ? context.xCard : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: _sending
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: context.xPrimary, strokeWidth: 2))
                          : const Text('📤 Send',
                              style: TextStyle(color: Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: XameColors.darkCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12))));

  Future<String?> _promptName(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: XameColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Name this list', style: TextStyle(color: Colors.white,
                fontSize: 15, fontWeight: FontWeight.w700)),
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
                  hintText: 'e.g. Family, Work, VIPs',
                  hintStyle: TextStyle(color: Colors.white30),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54))),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, ctrl.text),
                child: Container(height: 42,
                  decoration: BoxDecoration(
                    color: XameColors.primary,
                    borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text('Save',
                      style: TextStyle(color: Colors.black,
                          fontWeight: FontWeight.w700))),
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Manage Lists Sheet ────────────────────────────────────────────────────────
class _ManageListsSheet extends StatefulWidget {
  final BroadcastService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;

  const _ManageListsSheet({required this.service, required this.contacts,
      required this.currentUserId});

  @override
  State<_ManageListsSheet> createState() => _ManageListsSheetState();
}

class _ManageListsSheetState extends State<_ManageListsSheet> {
  List<BroadcastList> get _lists => widget.service.lists;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                const Text('Broadcast Lists',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => _NewBroadcastSheet(
                        service: widget.service,
                        contacts: widget.contacts,
                        currentUserId: widget.currentUserId),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [context.xPrimary, context.xSurface]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('+ New List',
                        style: TextStyle(color: Colors.black, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
          Expanded(
            child: _lists.isEmpty
                ? Center(child: Text('No lists yet',
                    style: TextStyle(color: Colors.white38)))
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: _lists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final l = _lists[i];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.xCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: context.xPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text('${l.members.length}',
                                style: TextStyle(
                                    color: context.xPrimary, fontSize: 15,
                                    fontWeight: FontWeight.w700))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, style: const TextStyle(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                              Text('${l.members.length} members',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ],
                          )),
                          GestureDetector(
                            onTap: () async {
                              await widget.service.deleteList(l.listId);
                              setState(() {});
                            },
                            child: Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: context.xDanger
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.delete_outline,
                                  color: context.xDanger, size: 16),
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

// ── Action Button ─────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
