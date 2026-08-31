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
  final String? addedBy;
  const GroupMember({required this.userId, required this.name,
      required this.role, this.addedBy});
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    userId:  j['userId']  as String,
    name:    j['name']    as String? ?? '',
    role:    j['role']    as String? ?? 'member',
    addedBy: j['addedBy'] as String?,
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

  Future<bool> leaveGroup(String groupId) async {
    try {
      final res = await http.post(
        Uri.parse('\${AppConstants.serverUrl}/api/groups/\$groupId/leave'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _groups.removeWhere((g) => g.groupId == groupId);
        return true;
      }
    } catch (e) { debugPrint('[Groups] Leave error: \$e'); }
    return false;
  }

  Future<bool> deleteGroup(String groupId) async {
    try {
      final res = await http.post(
        Uri.parse('\${AppConstants.serverUrl}/api/groups/\$groupId/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _groups.removeWhere((g) => g.groupId == groupId);
        return true;
      }
    } catch (e) { debugPrint('[Groups] Delete error: \$e'); }
    return false;
  }

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
                    : Text('Create Group',
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
      color: context.xCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
    ),
    child: TextField(
      controller: ctrl,
      style: TextStyle(color: context.xText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
        prefixIcon: Icon(icon, color: context.xMuted.withValues(alpha: 0.3), size: 18),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
          decoration: BoxDecoration(
            color: XameColors.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: XameColors.darkSurface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2)),
            )),
            Text('Add Member', style: TextStyle(color: XameColors.darkBg,
                fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 300),
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
                              : XameColors.darkSurface),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(name, style: TextStyle(
                            color: XameColors.darkBg, fontSize: 14))),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 150),
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: sel ? XameColors.primary : Colors.transparent,
                            border: Border.all(
                              color: sel ? XameColors.primary : XameColors.darkSurface.withValues(alpha: 0.5),
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

// ── Group Chat Screen ─────────────────────────────────────────────────────────
class GroupChatScreen extends StatefulWidget {
  final XameGroup group;
  final String currentUserId;
  final GroupsService service;
  const GroupChatScreen({super.key, required this.group,
      required this.currentUserId, required this.service});
  @override State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _ctrl     = TextEditingController();
  final _scroll   = ScrollController();
  bool _loading   = true;
  bool _typing    = false;
  String? _typer;
  List<GroupMessage> _msgs = [];
  late XameGroup _group;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _load();
    widget.service.onMessage = (msg, groupId) {
      if (groupId == _group.groupId && mounted) {
        setState(() => _msgs.add(msg));
        _scrollDown();
      }
    };
    widget.service.onTyping = (groupId, name) {
      if (groupId == _group.groupId && mounted) {
        setState(() { _typing = true; _typer = name; });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() { _typing = false; _typer = null; });
        });
      }
    };
  }

  @override
  void dispose() {
    _ctrl.dispose(); _scroll.dispose();
    widget.service.onMessage = null;
    widget.service.onTyping  = null;
    super.dispose();
  }

  Future<void> _load() async {
    await widget.service.loadMessages(_group.groupId);
    if (mounted) setState(() {
      _msgs    = List.from(widget.service.activeMessages);
      _loading = false;
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.service.sendMessage(_group.groupId, text);
    _ctrl.clear();
  }

  bool get _isAdmin =>
      _group.createdBy == widget.currentUserId ||
      _group.members.any((m) =>
          m.userId == widget.currentUserId && m.role == 'admin');

  String _fmt(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.xBg,
    appBar: AppBar(
      backgroundColor: context.xCard,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: context.xText),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: () => _showGroupInfo(),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: context.xPrimary.withValues(alpha: 0.2),
            backgroundImage: _group.avatar != null
                ? NetworkImage(_group.avatar!) : null,
            child: _group.avatar == null
                ? Text(_group.name.isNotEmpty ? _group.name[0].toUpperCase() : 'G',
                    style: TextStyle(color: context.xPrimary,
                        fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_group.name, style: TextStyle(color: context.xText,
                  fontSize: 15, fontWeight: FontWeight.w700)),
              Text('${_group.members.length} members',
                  style: TextStyle(color: context.xMuted, fontSize: 12)),
            ],
          )),
        ]),
      ),
      actions: [
        if (_isAdmin)
          IconButton(
            icon: Icon(Icons.admin_panel_settings_outlined,
                color: context.xPrimary),
            onPressed: _showGroupInfo,
          ),
      ],
    ),
    body: Column(children: [
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: context.xPrimary))
            : _msgs.isEmpty
                ? Center(child: Text('No messages yet. Say hello! 👋',
                    style: TextStyle(color: context.xMuted)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final msg   = _msgs[i];
                      final isMe  = msg.senderId == widget.currentUserId;
                      final showName = !isMe && (i == 0 ||
                          _msgs[i - 1].senderId != msg.senderId);
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (showName)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, bottom: 2),
                                  child: Text(msg.senderName,
                                      style: TextStyle(
                                          color: context.xPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? context.xPrimary
                                      : context.xCard,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14),
                                    topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(isMe ? 14 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(child: Text(msg.text ?? '',
                                        style: TextStyle(
                                            color: isMe
                                                ? Colors.white
                                                : context.xText,
                                            fontSize: 14))),
                                    const SizedBox(width: 6),
                                    Text(_fmt(msg.ts),
                                        style: TextStyle(
                                            color: isMe
                                                ? Colors.white70
                                                : context.xMuted,
                                            fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
      ),
      if (_typing && _typer != null)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('$_typer is typing...',
                style: TextStyle(color: context.xMuted, fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ),
        ),
      Container(
        padding: EdgeInsets.only(
            left: 12, right: 8, top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 8),
        decoration: BoxDecoration(
          color: context.xCard,
          border: Border(top: BorderSide(
              color: context.xMuted.withValues(alpha: 0.1))),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: TextStyle(color: context.xText, fontSize: 14),
              onChanged: (_) => widget.service.emitTyping(
                  _group.groupId, widget.currentUserId),
              decoration: InputDecoration(
                hintText: 'Message ${_group.name}...',
                hintStyle: TextStyle(color: context.xMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: context.xPrimary),
            onPressed: _send,
          ),
        ]),
      ),
    ]),
  );

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.xCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _GroupInfoPanel(
        group: _group,
        currentUserId: widget.currentUserId,
        service: widget.service,
        isAdmin: _isAdmin,
        onUpdated: (g) => setState(() => _group = g),
      ),
    );
  }
}

// ── Group Info Panel ──────────────────────────────────────────────────────────
class _GroupInfoPanel extends StatefulWidget {
  final XameGroup group;
  final String currentUserId;
  final GroupsService service;
  final bool isAdmin;
  final void Function(XameGroup) onUpdated;
  const _GroupInfoPanel({required this.group, required this.currentUserId,
      required this.service, required this.isAdmin, required this.onUpdated});
  @override State<_GroupInfoPanel> createState() => _GroupInfoPanelState();
}

class _GroupInfoPanelState extends State<_GroupInfoPanel> {
  late XameGroup _group;

  @override
  void initState() { super.initState(); _group = widget.group; }

  Future<void> _removeMember(String userId) async {
    final ok = await widget.service.removeMember(_group.groupId, userId);
    if (ok && mounted) {
      setState(() => _group.members.removeWhere((m) => m.userId == userId));
      widget.onUpdated(_group);
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false, initialChildSize: 0.6,
    builder: (_, sc) => ListView(
      controller: sc,
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        // Group avatar
        Center(child: CircleAvatar(
          radius: 40,
          backgroundColor: context.xPrimary.withValues(alpha: 0.2),
          backgroundImage: _group.avatar != null
              ? NetworkImage(_group.avatar!) : null,
          child: _group.avatar == null
              ? Text(_group.name.isNotEmpty ? _group.name[0].toUpperCase() : 'G',
                  style: TextStyle(color: context.xPrimary, fontSize: 28,
                      fontWeight: FontWeight.w700))
              : null,
        )),
        const SizedBox(height: 12),
        Center(child: Text(_group.name, style: TextStyle(color: context.xText,
            fontSize: 20, fontWeight: FontWeight.w700))),
        if (_group.description != null && _group.description!.isNotEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_group.description!,
                style: TextStyle(color: context.xMuted, fontSize: 13),
                textAlign: TextAlign.center),
          )),
        const SizedBox(height: 20),
        Text('${_group.members.length} Members',
            style: TextStyle(color: context.xMuted, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 8),
        ..._group.members.map((m) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: context.xPrimary.withValues(alpha: 0.15),
            child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                style: TextStyle(color: context.xPrimary,
                    fontWeight: FontWeight.w700)),
          ),
          title: Text(m.name, style: TextStyle(color: context.xText,
              fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.role == 'admin' ? '👑 Admin' : 'Member',
                  style: TextStyle(color: m.role == 'admin'
                      ? context.xPrimary : context.xMuted, fontSize: 12)),
              if (m.addedBy != null && m.addedBy!.isNotEmpty &&
                  m.userId != _group.createdBy)
                Text('Added by ${_group.members.firstWhere(
                    (x) => x.userId == m.addedBy,
                    orElse: () => GroupMember(userId: '', name: m.addedBy!, role: 'member')).name}',
                    style: TextStyle(color: context.xMuted.withValues(alpha: 0.6),
                        fontSize: 11)),
            ],
          ),
          trailing: widget.isAdmin && m.userId != widget.currentUserId
              ? IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      color: Colors.redAccent, size: 20),
                  onPressed: () => _removeMember(m.userId),
                )
              : null,
        )),
        const SizedBox(height: 20),
        // Leave / Delete group
        if (_group.createdBy != widget.currentUserId)
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.exit_to_app, color: Colors.orangeAccent),
              label: const Text('Leave Group',
                  style: TextStyle(color: Colors.orangeAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orangeAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: context.xCard,
                    title: Text('Leave Group?',
                        style: TextStyle(color: context.xText)),
                    content: Text('You will no longer receive messages from this group.',
                        style: TextStyle(color: context.xMuted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: Text('Cancel', style: TextStyle(color: context.xMuted))),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Leave', style: TextStyle(color: Colors.orangeAccent))),
                    ],
                  ),
                );
                if (confirm == true) {
                  final ok = await widget.service.leaveGroup(_group.groupId);
                  if (ok && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
          ),
        if (widget.isAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text('Delete Group',
                    style: TextStyle(color: Colors.redAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: context.xCard,
                      title: Text('Delete Group?',
                          style: TextStyle(color: context.xText)),
                      content: Text('This will permanently delete the group and all messages.',
                          style: TextStyle(color: context.xMuted)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false),
                            child: Text('Cancel', style: TextStyle(color: context.xMuted))),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final ok = await widget.service.deleteGroup(_group.groupId);
                    if (ok && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
              ),
            ),
          ),
      ],
    ),
  );
}
