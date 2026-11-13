import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/services/session_headers.dart';
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
  final Map<String, dynamic>? file; // GROUPS_MEDIA_V1
  final bool deleted; // GROUP_DELETE_V1
  const GroupMessage({required this.id, required this.senderId,
      required this.senderName, this.text, required this.ts, this.file, this.deleted = false});
  // GROUP_DELETE_V1: tombstone copy of this message
  GroupMessage asDeleted() => GroupMessage(id: id, senderId: senderId, senderName: senderName,
      text: '', ts: ts, file: null, deleted: true);
  factory GroupMessage.fromJson(Map<String, dynamic> j) => GroupMessage(
    id:         (j['id'] ?? j['_id'] ?? '').toString(),
    senderId:   j['senderId']   as String,
    senderName: j['senderName'] as String? ?? '',
    text:       j['text']       as String?,
    ts:         j['ts']         as int,
    file:       j['file'] is Map ? Map<String, dynamic>.from(j['file'] as Map) : null,
    deleted:    j['deleted'] == true,
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

  void Function(String groupId, String messageId)? onMessageDeleted; // GROUP_DELETE_V1
  final List<StreamSubscription<Map<String, dynamic>>> _subs = [];
  VoidCallback? onGroupsChanged; // GROUPS_APP_V1

  GroupsService(this._socket, this._userId) {
    _socket.emit('groups:subscribe', {'userId': _userId});
    // GROUPS_APP_V1: connect the server's group events to this service
    _subs.add(_socket.groupMessage.listen(handleGroupMessage));
    _subs.add(_socket.groupTyping.listen(handleGroupTyping));
    _subs.add(_socket.groupAdded.listen(_handleGroupAdded));
    _subs.add(_socket.groupMessageDeleted.listen(_handleMessageDeleted));
  }

  List<XameGroup>    get groups         => List.unmodifiable(_groups);
  List<GroupMessage> get activeMessages => List.unmodifiable(_activeMessages);

  // GROUPS_APP_V1: someone created a group with me in it, or added me to one
  void _handleGroupAdded(Map<String, dynamic> data) {
    try {
      final raw = data['group'];
      if (raw is! Map) return;
      final g = XameGroup.fromJson(Map<String, dynamic>.from(raw));
      _groups.removeWhere((x) => x.groupId == g.groupId);
      _groups.insert(0, g);
      onGroupsChanged?.call();
    } catch (e) {
      debugPrint('[Groups] added handler error: $e');
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    onGroupsChanged = null;
  }

  void handleGroupMessage(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final msgData = data['message'] as Map<String, dynamic>?;
    if (groupId == null || msgData == null) return;
    final msg = GroupMessage.fromJson(msgData);
    if (activeGroup?.groupId == groupId && !_activeMessages.any((x) => x.id == msg.id)) _activeMessages.add(msg); // GROUPS_FIX2_V1
    final g = _groups.firstWhere((g) => g.groupId == groupId,
        orElse: () => XameGroup(groupId: '', name: '', createdBy: '',
            members: []));
    if (g.groupId.isNotEmpty) {
      g.lastMessagePreview = (msg.text != null && msg.text!.isNotEmpty) ? msg.text! : '📎 Attachment';
      g.lastMessageTs      = msg.ts;
    }
    onMessage?.call(msg, groupId);
    onGroupsChanged?.call();
  }

  void handleGroupTyping(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final name    = data['name']    as String?;
    if (groupId != null && name != null) onTyping?.call(groupId, name);
  }

  Future<void> loadGroups() async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/groups/$_userId'),
          headers: await sessionAuthHeaders());
      final d = jsonDecode(res.body);
      _groups = (d['groups'] as List? ?? [])
          .map((g) => XameGroup.fromJson(Map<String, dynamic>.from(g)))
          .toList();
    } catch (e) { debugPrint('[Groups] Load error: $e'); _groups = []; }
  }

  Future<XameGroup?> loadMessages(String groupId) async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/groups/$groupId/messages'),
          headers: await sessionAuthHeaders());
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
        _groups.insert(0, group); onGroupsChanged?.call(); return group;
      }
    } catch (e) { debugPrint('[Groups] Create error: $e'); }
    return null;
  }

  // GROUP_DELETE_V1: delete a message for everyone (sender, or a group admin)
  void deleteMessage(String groupId, String messageId) {
    final payload = <String, dynamic>{'groupId': groupId, 'messageId': messageId};
    if (messageId.startsWith('local-')) {
      final ts = int.tryParse(messageId.substring(6));
      if (ts != null) payload['ts'] = ts;
    }
    _socket.emit('group:delete-message', payload);
    _markDeleted(groupId, messageId);
  }

  void _markDeleted(String groupId, String messageId) {
    if (activeGroup?.groupId == groupId) {
      final i = _activeMessages.indexWhere((x) => x.id == messageId);
      if (i >= 0) _activeMessages[i] = _activeMessages[i].asDeleted();
    }
    onMessageDeleted?.call(groupId, messageId);
    onGroupsChanged?.call();
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final messageId = data['messageId'] as String?;
    if (groupId == null || messageId == null) return;
    _markDeleted(groupId, messageId);
  }

  // GROUPS_MEDIA_V1: send an already-uploaded file (url/name/type/size) to the group
  GroupMessage sendFileMessage(String groupId, Map<String, dynamic> file) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _socket.emit('group:send-message', {
      'groupId': groupId,
      'message': {'senderId': _userId, 'text': '', 'file': file, 'ts': ts},
    });
    for (final g in _groups) {
      if (g.groupId == groupId) {
        g.lastMessagePreview = '\u{1F4CE} Attachment';
        g.lastMessageTs = ts;
      }
    }
    onGroupsChanged?.call();
    return GroupMessage(id: 'local-$ts', senderId: _userId, senderName: '', text: '', ts: ts, file: file);
  }

  // GROUPS_APP_V1: sends in the server's contract (group:send-message). The server forwards only to the
  // other members, so the local copy is returned for the sender's own screen.
  GroupMessage sendMessage(String groupId, String text) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _socket.emit('group:send-message', {
      'groupId': groupId,
      'message': {'senderId': _userId, 'text': text, 'ts': ts},
    });
    for (final g in _groups) {
      if (g.groupId == groupId) {
        g.lastMessagePreview = text;
        g.lastMessageTs = ts;
      }
    }
    onGroupsChanged?.call();
    return GroupMessage(id: 'local-$ts', senderId: _userId, senderName: '', text: text, ts: ts);
  }

  void emitTyping(String groupId, String name) =>
      _socket.emitGroupTyping(groupId, _userId, name);

  Future<bool> leaveGroup(String groupId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/$groupId/leave'),
        body: jsonEncode({'userId': _userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _groups.removeWhere((g) => g.groupId == groupId);
        return true;
      }
    } catch (e) {
      debugPrint('[Groups] Leave error: $e');
    }
    return false;
  }

  Future<bool> deleteGroup(String groupId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/$groupId/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        _groups.removeWhere((g) => g.groupId == groupId);
        return true;
      }
    } catch (e) {
      debugPrint('[Groups] Delete error: $e');
    }
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
    widget.service.onMessageDeleted = (groupId, messageId) { // GROUP_DELETE_V1
      if (!mounted || groupId != _group.groupId) return;
      final i = _msgs.indexWhere((x) => x.id == messageId);
      if (i >= 0) setState(() => _msgs[i] = _msgs[i].asDeleted());
    };
    widget.service.onMessage = (msg, groupId) {
      if (groupId == _group.groupId && mounted) {
        if (!_msgs.any((x) => x.id == msg.id)) setState(() => _msgs.add(msg));
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
    widget.service.onMessageDeleted = null;
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

  // GROUPS_MEDIA_V1 ─────────────────────────────────────────────────────────
  bool _uploadingFile = false;
  static const int _groupMaxFileBytes = 50 * 1024 * 1024;

  void _groupSnack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _groupMimeFor(String name) {
    final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const m = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
      'webp': 'image/webp', 'heic': 'image/heic',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', '3gp': 'video/3gpp', 'mkv': 'video/x-matroska',
      'mp3': 'audio/mpeg', 'm4a': 'audio/x-m4a', 'aac': 'audio/aac', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
      'pdf': 'application/pdf', 'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain', 'csv': 'text/csv', 'zip': 'application/zip',
    };
    return m[e] ?? 'application/octet-stream';
  }

  String _groupSizeLabel(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _showAttachSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.xCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: context.xPrimary),
            title: Text('Photo or video', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: context.xPrimary),
            title: Text('Camera', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file_outlined, color: context.xPrimary),
            title: Text('Document or file', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    await _pickAndSendFile(choice);
  }

  Future<void> _pickAndSendFile(String kind) async {
    try {
      String? path;
      String name = 'file';
      if (kind == 'file') {
        final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: false);
        if (r == null || r.files.isEmpty) return;
        path = r.files.single.path;
        name = r.files.single.name;
      } else {
        final picker = ImagePicker();
        final XFile? x = kind == 'camera'
            ? await picker.pickImage(source: ImageSource.camera, imageQuality: 85)
            : await picker.pickMedia();
        if (x == null) return;
        path = x.path;
        name = x.name;
      }
      if (path == null || path.isEmpty) return;

      final size = await File(path).length();
      if (size > _groupMaxFileBytes) {
        _groupSnack('File too large (${_groupSizeLabel(size)}). Max ${_groupSizeLabel(_groupMaxFileBytes)} in groups.');
        return;
      }

      if (mounted) setState(() => _uploadingFile = true);
      final req = http.MultipartRequest('POST', Uri.parse('${AppConstants.serverUrl}/api/upload-file'));
      req.headers.addAll(await sessionAuthHeaders());
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: name));
      final streamed = await req.send().timeout(const Duration(minutes: 10));
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body is! Map || body['success'] != true || body['url'] == null) {
        _groupSnack('Upload failed. Please try again.');
        return;
      }
      final file = <String, dynamic>{
        'url': body['url'].toString(),
        'name': name,
        'type': _groupMimeFor(name),
        'size': size,
      };
      final sent = widget.service.sendFileMessage(_group.groupId, file);
      if (!mounted) return;
      setState(() => _msgs.add(sent));
      _scrollDown();
    } catch (e) {
      _groupSnack('Could not send file: $e');
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  void _viewGroupImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, __) => const CircularProgressIndicator(),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _openGroupFile(String url, String name) async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final out = File('${dir.path}/grp_${url.hashCode.toRadixString(16)}_$safe');
      if (!await out.exists()) {
        _groupSnack('Downloading $name...');
        final client = http.Client();
        try {
          final resp = await client.send(http.Request('GET', Uri.parse(url)));
          if (resp.statusCode != 200) {
            _groupSnack('Download failed (${resp.statusCode}).');
            return;
          }
          final sink = out.openWrite();
          await resp.stream.pipe(sink);
        } finally {
          client.close();
        }
      }
      final result = await OpenFilex.open(out.path);
      if (result.type != ResultType.done) {
        _groupSnack('No app found to open this file.');
      }
    } catch (e) {
      _groupSnack('Could not open file: $e');
    }
  }

  Widget _groupFileBody(GroupMessage msg, bool isMe) {
    final f = msg.file!;
    final url = (f['url'] ?? '').toString();
    final name = (f['name'] ?? 'File').toString();
    final type = (f['type'] ?? '').toString();
    final size = f['size'] is num ? (f['size'] as num).toInt() : 0;
    final fg = isMe ? Colors.white : context.xText;
    final sub = isMe ? Colors.white70 : context.xMuted;
    if (type.startsWith('image/') && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => _viewGroupImage(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => const SizedBox(
                width: 220, height: 140,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorWidget: (_, __, ___) => const SizedBox(
                width: 220, height: 100,
                child: Center(child: Icon(Icons.broken_image, size: 32))),
          ),
        ),
      );
    }
    final IconData icon = type.startsWith('video/')
        ? Icons.videocam_rounded
        : type.startsWith('audio/')
            ? Icons.audiotrack_rounded
            : type == 'application/pdf'
                ? Icons.picture_as_pdf_rounded
                : Icons.insert_drive_file_rounded;
    return InkWell(
      onTap: url.isEmpty ? null : () => _openGroupFile(url, name),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: fg, size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
              if (size > 0)
                Text(_groupSizeLabel(size), style: TextStyle(color: sub, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.download_rounded, color: sub, size: 20),
      ]),
    );
  }

  // GROUP_DELETE_V1 ─────────────────────────────────────────────────────────
  void _onGroupMessageLongPress(GroupMessage msg, bool isMe) {
    if (msg.deleted) return;
    if (!(isMe || _isAdmin)) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.xCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: Text(isMe ? 'Delete for everyone' : 'Delete message (admin)',
                style: TextStyle(color: context.xText)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmGroupDelete(msg);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmGroupDelete(GroupMessage msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.xCard,
        title: Text('Delete message?', style: TextStyle(color: context.xText)),
        content: Text('This removes it for everyone in the group.',
            style: TextStyle(color: context.xMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) widget.service.deleteMessage(_group.groupId, msg.id);
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final sent = widget.service.sendMessage(_group.groupId, text);
    setState(() => _msgs.add(sent));
    _scrollDown();
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
                        child: GestureDetector(
  onLongPress: () => _onGroupMessageLongPress(msg, isMe),
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
                                    Flexible(child: msg.deleted
    ? Text('🚫 This message was deleted',
        style: TextStyle(color: isMe ? Colors.white70 : context.xMuted, fontSize: 13, fontStyle: FontStyle.italic))
    : msg.file != null ? _groupFileBody(msg, isMe) : Text(msg.text ?? '',
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
                        )),
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
            bottom: 8),
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
            icon: _uploadingFile
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.xPrimary))
                : Icon(Icons.attach_file_rounded, color: context.xMuted),
            onPressed: _uploadingFile ? null : _showAttachSheet,
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
