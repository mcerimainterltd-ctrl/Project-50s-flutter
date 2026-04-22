import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:xamepage/core/services/socket_service.dart';

// ── Models ────────────────────────────────────────────────────────────────────
class GroupMember {
  final String userId;
  final String name;
  final String role;

  const GroupMember({
    required this.userId,
    required this.name,
    required this.role,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    userId: j['userId'] as String,
    name:   j['name']   as String? ?? '',
    role:   j['role']   as String? ?? 'member',
  );
}

class XameGroup {
  final String groupId;
  final String name;
  final String? description;
  final String? avatar;
  final String createdBy;
  List<GroupMember> members;
  String? lastMessagePreview;
  int? lastMessageTs;

  XameGroup({
    required this.groupId,
    required this.name,
    this.description,
    this.avatar,
    required this.createdBy,
    required this.members,
    this.lastMessagePreview,
    this.lastMessageTs,
  });

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
  final String id;
  final String senderId;
  final String senderName;
  final String? text;
  final int ts;

  const GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.text,
    required this.ts,
  });

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
    _bindSocketEvents();
  }

  List<XameGroup> get groups => List.unmodifiable(_groups);
  List<GroupMessage> get activeMessages => List.unmodifiable(_activeMessages);

  void _bindSocketEvents() {
    _socket.emit('groups:subscribe', {'userId': _userId});
  }

  // Call this from your socket listener when group events fire
  void handleGroupMessage(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final msgData = data['message'] as Map<String, dynamic>?;
    if (groupId == null || msgData == null) return;
    final msg = GroupMessage.fromJson(msgData);
    if (activeGroup?.groupId == groupId) {
      _activeMessages.add(msg);
    }
    final g = _groups.firstWhere((g) => g.groupId == groupId,
        orElse: () => XameGroup(groupId: '', name: '', createdBy: '', members: []));
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
    } catch (e) {
      debugPrint('[Groups] Load error: $e');
      _groups = [];
    }
  }

  Future<XameGroup?> loadMessages(String groupId) async {
    try {
      final res = await http.get(
          Uri.parse('${AppConstants.serverUrl}/api/groups/$groupId/messages'));
      final d = jsonDecode(res.body);
      _activeMessages = (d['messages'] as List? ?? [])
          .map((m) => GroupMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      activeGroup = _groups.firstWhere((g) => g.groupId == groupId,
          orElse: () => XameGroup(groupId: '', name: '', createdBy: '', members: []));
      return activeGroup?.groupId.isNotEmpty == true ? activeGroup : null;
    } catch (e) {
      debugPrint('[Groups] Load messages error: $e');
      return null;
    }
  }

  Future<XameGroup?> createGroup({
    required String name,
    required String description,
    required List<String> memberIds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'name': name,
          'description': description,
          'memberIds': memberIds,
        }),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final group = XameGroup.fromJson(Map<String, dynamic>.from(d['group']));
        _groups.insert(0, group);
        return group;
      }
    } catch (e) { debugPrint('[Groups] Create error: $e'); }
    return null;
  }

  void sendMessage(String groupId, String text) {
    final msgId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _socket.emit('group:message', {
      'groupId': groupId,
      'userId':  _userId,
      'message': {'id': msgId, 'text': text, 'ts': DateTime.now().millisecondsSinceEpoch},
    });
  }

  void emitTyping(String groupId, String name) {
    _socket.emitGroupTyping(groupId, _userId, name);
  }

  Future<bool> addMember(String groupId, String userId) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/groups/add-member'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'groupId': groupId, 'requesterId': _userId, 'userId': userId}),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final g = _groups.firstWhere((g) => g.groupId == groupId,
            orElse: () => XameGroup(groupId: '', name: '', createdBy: '', members: []));
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
        body: jsonEncode({
          'groupId': groupId,
          'requesterId': _userId,
          'userId': userId,
        }),
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        final g = _groups.firstWhere((g) => g.groupId == groupId,
            orElse: () => XameGroup(groupId: '', name: '', createdBy: '', members: []));
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
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.serverUrl}/api/groups/upload-avatar'),
      );
      req.fields['groupId'] = groupId;
      req.fields['userId']  = _userId;
      req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
      final res = await req.send();
      final body = jsonDecode(await res.stream.bytesToString());
      if (body['success'] == true) return body['avatarUrl'] as String?;
    } catch (e) { debugPrint('[Groups] Avatar upload error: $e'); }
    return null;
  }
}

// ── Groups List Screen ────────────────────────────────────────────────────────
class GroupsListScreen extends StatefulWidget {
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final void Function(XameGroup group) onOpenChat;

  const GroupsListScreen({
    super.key,
    required this.service,
    required this.contacts,
    required this.currentUserId,
    required this.onOpenChat,
  });

  static Future<void> show(BuildContext context, {
    required GroupsService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId,
    required void Function(XameGroup) onOpenChat,
  }) {
    return Navigator.push(context, MaterialPageRoute(
      builder: (_) => GroupsListScreen(
        service: service,
        contacts: contacts,
        currentUserId: currentUserId,
        onOpenChat: onOpenChat,
      ),
    ));
  }

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.service.loadGroups().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.service.groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xame Groups'),
        actions: [
          TextButton(
            onPressed: () => _showCreateDialog(context),
            child: const Text('+ New'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? const Center(
                  child: Text('No groups yet. Create one!',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final g = groups[i];
                    return ListTile(
                      leading: g.avatar != null
                          ? CircleAvatar(backgroundImage: NetworkImage(g.avatar!))
                          : CircleAvatar(
                              child: Text(g.name.substring(0, 2).toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w700))),
                      title: Text(g.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(g.lastMessagePreview ?? 'No messages yet',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text('${g.members.length} members',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      onTap: () => widget.onOpenChat(g),
                    );
                  },
                ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateGroupDialog(
        service:      widget.service,
        contacts:     widget.contacts,
        currentUserId: widget.currentUserId,
        onCreated: (g) {
          setState(() {});
          widget.onOpenChat(g);
        },
      ),
    );
  }
}

// ── Create Group Dialog ───────────────────────────────────────────────────────
class _CreateGroupDialog extends StatefulWidget {
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final void Function(XameGroup) onCreated;

  const _CreateGroupDialog({
    required this.service,
    required this.contacts,
    required this.currentUserId,
    required this.onCreated,
  });

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.contacts
        .where((c) => c['id'] != widget.currentUserId)
        .toList();

    return AlertDialog(
      title: const Text('Create Group'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(hintText: 'Group name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration:
                  const InputDecoration(hintText: 'Description (optional)'),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select members:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: contacts.map((c) {
                  final id   = c['id']   as String;
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : () async {
            if (_nameCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a group name')));
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
              if (group != null) {
                widget.onCreated(group);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create group')));
              }
            }
          },
          child: const Text('Create Group'),
        ),
      ],
    );
  }
}

// ── Group Info Dialog ─────────────────────────────────────────────────────────
class GroupInfoDialog extends StatefulWidget {
  final XameGroup group;
  final bool isAdmin;
  final GroupsService service;
  final List<Map<String, dynamic>> contacts;
  final String currentUserId;
  final VoidCallback onLeft;

  const GroupInfoDialog({
    super.key,
    required this.group,
    required this.isAdmin,
    required this.service,
    required this.contacts,
    required this.currentUserId,
    required this.onLeft,
  });

  static Future<void> show(BuildContext context, {
    required XameGroup group,
    required bool isAdmin,
    required GroupsService service,
    required List<Map<String, dynamic>> contacts,
    required String currentUserId,
    required VoidCallback onLeft,
  }) {
    return showDialog(
      context: context,
      builder: (_) => GroupInfoDialog(
        group: group,
        isAdmin: isAdmin,
        service: service,
        contacts: contacts,
        currentUserId: currentUserId,
        onLeft: onLeft,
      ),
    );
  }

  @override
  State<GroupInfoDialog> createState() => _GroupInfoDialogState();
}

class _GroupInfoDialogState extends State<GroupInfoDialog> {
  late XameGroup _group;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        children: [
          GestureDetector(
            onTap: widget.isAdmin ? _changeAvatar : null,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                _group.avatar != null
                    ? CircleAvatar(radius: 40,
                        backgroundImage: NetworkImage(_group.avatar!))
                    : CircleAvatar(radius: 40,
                        child: Text(_group.name.substring(0, 2).toUpperCase(),
                            style: const TextStyle(fontSize: 24,
                                fontWeight: FontWeight.w700))),
                if (widget.isAdmin)
                  const CircleAvatar(radius: 12,
                      child: Icon(Icons.camera_alt, size: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(_group.name, textAlign: TextAlign.center),
          if (_group.description != null)
            Text(_group.description!,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Members (${_group.members.length})',
                style: const TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 13)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _group.members.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = _group.members[i];
                  return ListTile(
                    dense: true,
                    title: Text(m.name.isNotEmpty ? m.name : m.userId,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(m.role),
                    trailing: widget.isAdmin && m.userId != widget.currentUserId
                        ? TextButton(
                            onPressed: () async {
                              final ok = await widget.service
                                  .removeMember(_group.groupId, m.userId);
                              if (ok) setState(() {
                                _group.members.removeAt(i);
                              });
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text('Remove'),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.isAdmin)
          TextButton(
            onPressed: () => _showAddMember(context),
            child: const Text('+ Add Member'),
          ),
        TextButton(
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                content: const Text('Leave this group?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('Leave')),
                ],
              ),
            );
            if (confirm == true && mounted) {
              await widget.service.removeMember(
                  _group.groupId, widget.currentUserId);
              Navigator.pop(context);
              widget.onLeft();
            }
          },
          child: const Text('Leave Group',
              style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final url = await widget.service.uploadAvatar(
        _group.groupId, File(file.path));
    if (url != null && mounted) {
      setState(() => _group = XameGroup(
        groupId:     _group.groupId,
        name:        _group.name,
        description: _group.description,
        avatar:      url,
        createdBy:   _group.createdBy,
        members:     _group.members,
      ));
    }
  }

  void _showAddMember(BuildContext context) {
    final existing  = _group.members.map((m) => m.userId).toSet();
    final available = widget.contacts
        .where((c) =>
            c['id'] != widget.currentUserId &&
            !existing.contains(c['id']))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All contacts are already members')));
      return;
    }
    final Set<String> selected = {};
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add Member'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView(
                shrinkWrap: true,
                children: available.map((c) {
                  final id   = c['id']   as String;
                  final name = c['name'] as String? ?? id;
                  return CheckboxListTile(
                    dense: true,
                    title: Text(name),
                    value: selected.contains(id),
                    onChanged: (v) => setSt(() =>
                        v! ? selected.add(id) : selected.remove(id)),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (selected.isEmpty) return;
                for (final uid in selected) {
                  await widget.service.addMember(_group.groupId, uid);
                }
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Member(s) added')));
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
