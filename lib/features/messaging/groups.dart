import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Models ────────────────────────────────────────────────────────────────────
class GroupMember {
  final String userId, name, role;
  const GroupMember({required this.userId, required this.name,
      required this.role});
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    userId: j['userId'] as String,
    name:   j['name']   as String? ?? '',
    role:   j['role']   as String? ?? 'member',
  );
}

class XameGroup {
  final String groupId, name, createdBy;
  final String? description, avatar;
  List<GroupMember> members;
  String? lastMessagePreview;
  int? lastMessageTs;

  XameGroup({required this.groupId, required this.name,
      required this.createdBy, this.description, this.avatar,
      required this.members, this.lastMessagePreview, this.lastMessageTs});

  factory XameGroup.fromJson(Map<String, dynamic> j) => XameGroup(
    groupId:     j['groupId']     as String,
    name:        j['name']        as String,
    description: j['description'] as String?,
    avatar:      j['avatar']      as String?,
    createdBy:   j['createdBy']   as String? ?? '',
    members:     (j['members'] as List? ?? [])
        .map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    lastMessagePreview: j['lastMessagePreview'] as String?,
    lastMessageTs:      j['lastMessageTs']      as int?,
  );
}

class GroupMessage {
  final String id, senderId, senderName;
  final String? text;
  final int ts;
  const GroupMessage({required this.id, required this.senderId,
      required this.senderName, this.text, required this.ts});
  factory GroupMessage.fromJson(Map<String, dynamic> j) => GroupMessage(
    id:         j['id']         as String,
    senderId:   j['senderId']   as String,
    senderName: j['senderName'] as String? ?? '',
    text:       j['text']       as String?,
    ts:         j['ts']         as int,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class GroupsService {
  final SocketService _socket;
  final String _userId;
  List<XameGroup> _groups = [];
  List<GroupMessage> _activeMessages = [];
  XameGroup? activeGroup;
  void Function(GroupMessage msg, String groupId)? onMessage;
  void Function(String groupId, String name)? onTyping;

  GroupsService(this._socket, this._userId) {
    _socket.emit('groups:subscribe', {'userId': _userId});
  }

  List<XameGroup>    get groups         => List.unmodifiable(_groups);
  List<GroupMessage> get activeMessages => List.unmodifiable(_activeMessages);

  void handleGroupMessage(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final msgData = data['message'] as Map<String, dynamic>?;
    if (groupId == null || msgData == null) return;
    final msg = GroupMessage.fromJson(msgData);
    if (activeGroup?.groupId == groupId) _activeMessages.add(msg);
    final g = _groups.firstWhere((g) => g.groupId == groupId,
        orElse: () => XameGroup(groupId: '', name: '', createdBy: '',
            members: []));
    if (g.groupId.isNotEmpty) {
      g.lastMessagePreview = msg.text ?? 'Attachment';
      g.lastMessageTs      = msg.ts;
    }
    onMessage?.call(msg, groupId);
  }

  void handleGroupTyping(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final name    = data['name']    as String?;
    if (groupId != null && name != null) onTyping?.call(groupId, name);
  }

  Future<void> loadGroups() async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/groups/$_userId'));
      final d = jsonDecode(res.body);
      _groups = (d['groups'] as List? ?? [])
          .map((g) => XameGroup.fromJson(Map<String, dynamic>.from(g)))
          .toList();
    } catch (e) { debugPrint('[Groups] Load error: $e'); _groups = []; }
  }

  Future<XameGroup?> loadMessages(String groupId) async {
    try {
      final res = await http.get(Uri.parse(
          '${AppConstants.serverUrl}/api/groups/$groupId/messages'));
      final d = jsonDecode(res.body);
      _activeMessages = (d['messages'] as List? ?? [])
          .map((m) => GroupMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      activeGroup = _groups.firstWhere((g) => g.groupId == groupId,
          orElse: () => XameGroup(groupId: '', name: '', createdBy: '',
              members: []));
      return activeGroup?.groupId.isNotEmpty == true ? activeGroup : null;
    } catch (e) { debugPrint('[Groups] Messages error: $e'); return null; }
  }

  Future<XameGroup?> createGroup({required String name,
      required String description, required List<String> memberIds}) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId, 'name': name,
            'description': description, 'memberIds': memberIds}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final group = XameGroup.fromJson(Map<String, dynamic>.from(d['group']));
        _groups.insert(0, group); return group;
      }
    } catch (e) { debugPrint('[Groups] Create error: $e'); }
    return null;
  }

  void sendMessage(String groupId, String text) {
    final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _socket.emit('group:message', {'groupId': groupId, 'userId': _userId,
        'message': {'id': msgId, 'text': text,
            'ts': DateTime.now().millisecondsSinceEpoch}});
  }

  void emitTyping(String groupId, String name) =>
      _socket.emitGroupTyping(groupId, _userId, name);

  Future<bool> addMember(String groupId, String userId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/add-member'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'groupId': groupId, 'requesterId': _userId,
            'userId': userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final g = _groups.firstWhere((g) => g.groupId == groupId,
            orElse: () => XameGroup(groupId: '', name: '', createdBy: '',
                members: []));
        if (g.groupId.isNotEmpty) {
          g.members = (d['group']['members'] as List)
              .map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
        return true;
      }
    } catch (e) { debugPrint('[Groups] Add member error: $e'); }
    return false;
  }

  Future<bool> removeMember(String groupId, String userId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/remove-member'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'groupId': groupId, 'requesterId': _userId,
            'userId': userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final g = _groups.firstWhere((g) => g.groupId == groupId,
            orElse: () => XameGroup(groupId: '', name: '', createdBy: '',
                members: []));
        if (g.groupId.isNotEmpty) {
          g.members.removeWhere((m) => m.userId == userId);
        }
        return true;
      }
    } catch (e) { debugPrint('[Groups] Remove member error: $e'); }
    return false;
  }

  Future<String?> uploadAvatar(String groupId, File file) async {
    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('${AppConstants.serverUrl}/api/groups/upload-avatar'));
      req.fields['groupId'] = groupId;
      req.fields['userId']  = _userId;
      req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
      final res  = await req.send();
      final body = jsonDecode(await res.stream.bytesToString());
      if (body['success'] == true) return body['avatarUrl'] as String?;
    } catch (e) { debugPrint('[Groups] Avatar error: $e'); }
    return null;
  }
}

// ── Groups List Screen ────────────────────────────────────────────────────────
class GroupsListScreen extends StatefulWidget {
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final void Function(XameGroup group) onOpenChat;

  const GroupsListScreen({super.key, required this.service,
      required this.contacts, required this.currentUserId,
      required this.onOpenChat});

  static Future<void> show(BuildContext context, {
    required GroupsService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId,
    required void Function(XameGroup) onOpenChat,
  }) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => GroupsListScreen(service: service, contacts: contacts,
        currentUserId: currentUserId, onOpenChat: onOpenChat)));

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    widget.service.loadGroups().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.service.groups
        .where((g) => _search.isEmpty ||
            g.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: context.xBg,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.arrow_back_ios_new,
                    color: context.xText.withValues(alpha: 0.7), size: 16),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text('Xame Groups',
                  style: TextStyle(color: context.xText, fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            GestureDetector(
              onTap: () => _showCreateDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [context.xPrimary, context.xSurface]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('+ New',
                    style: TextStyle(color: Colors.black, fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: context.xCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(color: context.xText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search groups...',
                hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
                prefixIcon: Icon(Icons.search, color: context.xMuted.withValues(alpha: 0.3), size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
            ),
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(
                  color: context.xPrimary, strokeWidth: 2))
              : groups.isEmpty
                  ? Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.group_outlined,
                          color: context.xMuted.withValues(alpha: 0.25), size: 56),
                      SizedBox(height: 12),
                      Text('No groups yet',
                          style: TextStyle(color: context.xMuted,
                              fontSize: 15)),
                      SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showCreateDialog(context),
                        child: Text('Create your first group →',
                            style: TextStyle(color: context.xPrimary,
                                fontSize: 13)),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount: groups.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final g = groups[i];
                        return GestureDetector(
                          onTap: () => widget.onOpenChat(g),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.xCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                            ),
                            child: Row(children: [
                              // Avatar
                              g.avatar != null
                                  ? ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      child: Image.network(g.avatar!,
                                          width: 50, height: 50,
                                          fit: BoxFit.cover))
                                  : Container(
                                      width: 50, height: 50,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [context.xPrimary,
                                              context.xSurface],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      child: Center(
                                        child: Text(
                                          g.name.substring(0, 2)
                                              .toUpperCase(),
                                          style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 16,
                                              fontWeight:
                                                  FontWeight.w800)),
                                      ),
                                    ),
                              SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(g.name, style: TextStyle(
                                      color: context.xText, fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                                  SizedBox(height: 2),
                                  Text(
                                    g.lastMessagePreview ??
                                        '${g.members.length} members',
                                    style: TextStyle(
                                        color: context.xMuted,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                ],
                              )),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: context.xPrimary
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${g.members.length}',
                                      style: TextStyle(
                                          color: context.xPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: context.xMuted.withValues(alpha: 0.5), size: 16),
                                ],
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ])),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CreateGroupSheet(
        service: widget.service,
        contacts: widget.contacts,
        currentUserId: widget.currentUserId,
        onCreated: (g) {
          setState(() {});
          widget.onOpenChat(g);
        },
      ),
    );
  }
}

// ── Create Group Sheet ────────────────────────────────────────────────────────
class _CreateGroupSheet extends StatefulWidget {
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final void Function(XameGroup) onCreated;

  const _CreateGroupSheet({required this.service, required this.contacts,
      required this.currentUserId, required this.onCreated});

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool _loading = false;
  String _search = '';

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.contacts
        .where((c) => c['id'] != widget.currentUserId)
        .where((c) => _search.isEmpty ||
            (c['name'] as String? ?? '').toLowerCase()
                .contains(_search.toLowerCase()))
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
                decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.xPrimary, context.xSurface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.group_add_outlined,
                      color: Colors.black, size: 20),
                ),
                SizedBox(width: 12),
                Text('Create Group', style: TextStyle(
                    color: context.xText, fontSize: 16,
                    fontWeight: FontWeight.w700)),
                Spacer(),
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
              SizedBox(height: 14),
              _inputField(_nameCtrl, 'Group name', Icons.group_outlined),
              SizedBox(height: 8),
              _inputField(_descCtrl, 'Description (optional)',
                  Icons.info_outline),
              SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: context.xCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: context.xText, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
                    prefixIcon: Icon(Icons.search, color: context.xMuted.withValues(alpha: 0.3),
                        size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                  ),
                ),
              ),
              SizedBox(height: 8),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: contacts.length,
              itemBuilder: (_, i) {
                final c    = contacts[i];
                final id   = c['id']   as String;
                final name = c['name'] as String? ?? id;
                final sel  = _selected.contains(id);
                return GestureDetector(
                  onTap: () => setState(() =>
                      sel ? _selected.remove(id) : _selected.add(id)),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: sel
                          ? context.xPrimary.withValues(alpha: 0.08)
                          : context.xCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? context.xPrimary.withValues(alpha: 0.3)
                            : context.xMuted.withValues(alpha: 0.1)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: context.xPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                                color: context.xPrimary,
                                fontWeight: FontWeight.w700))),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(
                              color: context.xText, fontSize: 14,
                              fontWeight: FontWeight.w500)),
                          Text(id, style: TextStyle(
                              color: context.xMuted, fontSize: 12)),
                        ],
                      )),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 150),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: sel ? context.xPrimary : Colors.transparent,
                          border: Border.all(
                            color: sel ? context.xPrimary : context.xMuted.withValues(alpha: 0.5),
                            width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: sel ? Icon(Icons.check,
                            color: Colors.black, size: 14) : null,
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20,
                MediaQuery.of(context).viewInsets.bottom + 20),
            decoration: BoxDecoration(
              color: context.xSurface,
              border: Border(top: BorderSide(color: context.xMuted.withValues(alpha: 0.1))),
            ),
            child: GestureDetector(
              onTap: _loading ? null : () async {
                if (_nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Enter a group name'),
                    backgroundColor: context.xCard,
                    behavior: SnackBarBehavior.floating));
                  return;
                }
                setState(() => _loading = true);
                final group = await widget.service.createGroup(
                  name:        _nameCtrl.text.trim(),
                  description: _descCtrl.text.trim(),
                  memberIds:   _selected.toList(),
                );
                if (mounted) {
                  Navigator.pop(context);
                  if (group != null) widget.onCreated(group);
                  else ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create group'),
                        backgroundColor: context.xCard,
                        behavior: SnackBarBehavior.floating));
                }
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 150),
                width: double.infinity, height: 52,
                decoration: BoxDecoration(
                  gradient: _loading ? null : LinearGradient(
                    colors: [context.xPrimary, context.xSurface]),
                  color: _loading ? context.xCard : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: _loading
                    ? SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: context.xPrimary, strokeWidth: 2))
                    : const Text('Create Group',
                        style: TextStyle(color: Colors.black, fontSize: 15,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint,
      IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      color: XameColors.darkCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: Icon(icon, color: Colors.white30, size: 18),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
    ),
  );
}

// ── Group Info Sheet ──────────────────────────────────────────────────────────
class GroupInfoDialog extends StatefulWidget {
  final XameGroup group;
  final bool isAdmin;
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final VoidCallback onLeft;

  const GroupInfoDialog({super.key, required this.group, required this.isAdmin,
      required this.service, required this.contacts,
      required this.currentUserId, required this.onLeft});

  static Future<void> show(BuildContext context, {
    required XameGroup group, required bool isAdmin,
    required GroupsService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId, required VoidCallback onLeft,
  }) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => GroupInfoDialog(group: group, isAdmin: isAdmin,
        service: service, contacts: contacts,
        currentUserId: currentUserId, onLeft: onLeft));

  @override
  State<GroupInfoDialog> createState() => _GroupInfoDialogState();
}

class _GroupInfoDialogState extends State<GroupInfoDialog> {
  late XameGroup _group;

  @override
  void initState() { super.initState(); _group = widget.group; }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2)),
          )),
          // Group avatar + name
          GestureDetector(
            onTap: widget.isAdmin ? _changeAvatar : null,
            child: Stack(alignment: Alignment.bottomRight, children: [
              _group.avatar != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.network(_group.avatar!,
                          width: 80, height: 80, fit: BoxFit.cover))
                  : Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [context.xPrimary, context.xSurface],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(child: Text(
                          _group.name.substring(0, 2).toUpperCase(),
                          style: TextStyle(color: Colors.black,
                              fontSize: 24, fontWeight: FontWeight.w800))),
                    ),
              if (widget.isAdmin)
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: context.xPrimary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.xSurface,
                        width: 2),
                  ),
                  child: Icon(Icons.camera_alt,
                      color: Colors.black, size: 13),
                ),
            ]),
          ),
          SizedBox(height: 10),
          Text(_group.name, style: TextStyle(color: context.xText,
              fontSize: 18, fontWeight: FontWeight.w700)),
          if (_group.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_group.description!, style: TextStyle(
                  color: context.xMuted, fontSize: 13)),
            ),
          SizedBox(height: 16),
          // Members section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('Members (${_group.members.length})',
                  style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Spacer(),
              if (widget.isAdmin)
                GestureDetector(
                  onTap: () => _showAddMember(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: context.xPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('+ Add',
                        style: TextStyle(color: context.xPrimary,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
          SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _group.members.length,
              separatorBuilder: (_, __) => SizedBox(height: 6),
              itemBuilder: (_, i) {
                final m = _group.members[i];
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.xCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: context.xPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text(
                          (m.name.isNotEmpty ? m.name : m.userId)[0]
                              .toUpperCase(),
                          style: TextStyle(color: context.xPrimary,
                              fontWeight: FontWeight.w700))),
                    ),
                    SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name.isNotEmpty ? m.name : m.userId,
                            style: TextStyle(color: context.xText,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(m.role, style: TextStyle(
                            color: context.xMuted, fontSize: 11)),
                      ],
                    )),
                    if (widget.isAdmin &&
                        m.userId != widget.currentUserId)
                      GestureDetector(
                        onTap: () async {
                          final ok = await widget.service
                              .removeMember(_group.groupId, m.userId);
                          if (ok) setState(() =>
                              _group.members.removeAt(i));
                        },
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: context.xDanger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.person_remove_outlined,
                              color: context.xDanger, size: 15),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
          // Leave button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: GestureDetector(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: context.xCard,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Leave Group?',
                            style: TextStyle(color: context.xText,
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 8),
                        Text(
                            'You will no longer receive messages from this group.',
                            style: TextStyle(color: context.xMuted,
                                fontSize: 13),
                            textAlign: TextAlign.center),
                        SizedBox(height: 16),
                        Row(children: [
                          Expanded(child: GestureDetector(
                            onTap: () => Navigator.pop(context, false),
                            child: Container(height: 42,
                              decoration: BoxDecoration(
                                color: context.xText.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12)),
                              alignment: Alignment.center,
                              child: Text('Cancel',
                                  style: TextStyle(color: context.xText.withValues(alpha: 0.54)))),
                          )),
                          SizedBox(width: 10),
                          Expanded(child: GestureDetector(
                            onTap: () => Navigator.pop(context, true),
                            child: Container(height: 42,
                              decoration: BoxDecoration(
                                color: context.xDanger,
                                borderRadius: BorderRadius.circular(12)),
                              alignment: Alignment.center,
                              child: Text('Leave',
                                  style: TextStyle(color: context.xText,
                                      fontWeight: FontWeight.w700))),
                          )),
                        ]),
                      ]),
                    ),
                  ),
                );
                if (confirm == true && mounted) {
                  await widget.service.removeMember(
                      _group.groupId, widget.currentUserId);
                  Navigator.pop(context);
                  widget.onLeft();
                }
              },
              child: Container(
                width: double.infinity, height: 48,
                decoration: BoxDecoration(
                  color: context.xDanger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: context.xDanger.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text('Leave Group',
                    style: TextStyle(color: context.xDanger, fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final url = await widget.service.uploadAvatar(
        _group.groupId, File(file.path));
    if (url != null && mounted) setState(() => _group = XameGroup(
      groupId: _group.groupId, name: _group.name,
      description: _group.description, avatar: url,
      createdBy: _group.createdBy, members: _group.members));
  }

  void _showAddMember(BuildContext context) {
    final existing  = _group.members.map((m) => m.userId).toSet();
    final available = widget.contacts
        .where((c) => c['id'] != widget.currentUserId &&
            !existing.contains(c['id']))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All contacts are already members'),
        backgroundColor: XameColors.darkCard,
        behavior: SnackBarBehavior.floating));
      return;
    }
    final Set<String> selected = {};
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: const BoxDecoration(
            color: XameColors.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            )),
            const Text('Add Member', style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(shrinkWrap: true,
                children: available.map((c) {
                  final id   = c['id']   as String;
                  final name = c['name'] as String? ?? id;
                  final sel  = selected.contains(id);
                  return GestureDetector(
                    onTap: () => setSt(() =>
                        sel ? selected.remove(id) : selected.add(id)),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: sel
                            ? XameColors.primary.withValues(alpha: 0.08)
                            : XameColors.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? XameColors.primary.withValues(alpha: 0.3)
                              : Colors.white10),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(name, style: const TextStyle(
                            color: Colors.white, fontSize: 14))),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: sel ? XameColors.primary : Colors.transparent,
                            border: Border.all(
                              color: sel ? XameColors.primary : Colors.white24,
                              width: 1.5),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: sel ? const Icon(Icons.check,
                              color: Colors.black, size: 13) : null,
                        ),
                      ]),
                    ),
                  );
                }).toList()),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                if (selected.isEmpty) return;
                for (final uid in selected) {
                  await widget.service.addMember(_group.groupId, uid);
                }
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Member(s) added'),
                    backgroundColor: XameColors.darkCard,
                    behavior: SnackBarBehavior.floating));
                }
              },
              child: Container(
                width: double.infinity, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [XameColors.primary, XameColors.darkSurface]),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Add Selected',
                    style: TextStyle(color: Colors.black, fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
