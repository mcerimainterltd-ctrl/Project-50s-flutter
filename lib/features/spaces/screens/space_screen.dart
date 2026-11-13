import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/config/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/xame_space_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_service.dart';
import '../models/space_model.dart';

class SpaceScreen extends ConsumerStatefulWidget {
  final String spaceSlug;
  const SpaceScreen({super.key, required this.spaceSlug});
  @override
  ConsumerState<SpaceScreen> createState() => _SpaceScreenState();
}

class _SpaceScreenState extends ConsumerState<SpaceScreen> {
  SpaceModel?          _space;
  List<SpaceMessage>   _messages = [];
  bool                 _loading  = true;
  bool                 _sending  = false;
  final _msgCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  SpaceMessage?        _replyTo;
  StreamSubscription?  _msgSub, _typingSub;
  final Set<String>    _typing = {};
  Timer?               _typingTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _listenSocket();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    final socket = ref.read(socketServiceProvider);
    socket.emit('space:leave', {'spaceSlug': widget.spaceSlug,
      'userId': ref.read(currentUserProvider)?.xameId ?? ''});
    super.dispose();
  }

  Future<void> _load() async {
    final user  = ref.read(currentUserProvider);
    final space = await XameSpaceService.fetchSpace(widget.spaceSlug, userId: user?.xameId);
    final msgs  = await XameSpaceService.fetchMessages(widget.spaceSlug);
    if (!mounted) return;
    setState(() { _space = space; _messages = msgs; _loading = false; });
    _scrollToBottom();
    // Join socket room
    ref.read(socketServiceProvider).emit('space:join',
      {'spaceSlug': widget.spaceSlug, 'userId': user?.xameId ?? 'guest'});
  }

  void _listenSocket() {
    final socket = ref.read(socketServiceProvider);
    _msgSub = socket.spaceMessage.listen((data) {
      if (data['spaceSlug'] != widget.spaceSlug) return;
      final msg = SpaceMessage.fromJson(data['message']);
      if (!mounted) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });
    _typingSub = socket.spaceTyping.listen((data) {
      if (data['spaceSlug'] != widget.spaceSlug) return;
      if (!mounted) return;
      final name = data['name'] as String? ?? 'Someone';
      setState(() { data['isTyping'] == true ? _typing.add(name) : _typing.remove(name); });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _onTyping(String val) {
    final user = ref.read(currentUserProvider);
    final socket = ref.read(socketServiceProvider);
    socket.emit('space:typing', {'spaceSlug': widget.spaceSlug,
      'userId': user?.xameId ?? '', 'name': user?.preferredName ?? 'Someone', 'isTyping': true});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      socket.emit('space:typing', {'spaceSlug': widget.spaceSlug,
        'userId': user?.xameId ?? '', 'name': '', 'isTyping': false});
    });
  }

  // SPACES_MEDIA_V1 ─────────────────────────────────────────────────────────
  bool _uploadingMedia = false;
  static const int _spaceMaxBytes = 50 * 1024 * 1024;

  void _spaceSnack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _showSpaceAttachSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: XameColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
            title: const Text('Photo or video', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: Colors.white70),
            title: const Text('Camera', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.white70),
            title: const Text('Document or file', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    await _pickAndSendSpaceMedia(choice);
  }

  Future<void> _pickAndSendSpaceMedia(String kind) async {
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
      if (size > _spaceMaxBytes) {
        _spaceSnack('File too large. Max ${_spaceMaxBytes ~/ (1024 * 1024)} MB in Spaces.');
        return;
      }

      if (mounted) setState(() => _uploadingMedia = true);
      final req = http.MultipartRequest('POST', Uri.parse('${AppConstants.serverUrl}/api/upload-file'));
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: name));
      final streamed = await req.send().timeout(const Duration(minutes: 10));
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body is! Map || body['success'] != true || body['url'] == null) {
        _spaceSnack('Upload failed. Please try again.');
        return;
      }

      final user = ref.read(currentUserProvider);
      final msg = await XameSpaceService.sendMessage(widget.spaceSlug,
        userId: user?.xameId, displayName: user?.preferredName ?? user?.firstName,
        text: '', mediaUrl: body['url'].toString(), mediaType: _spaceMimeFor(name), fileName: name);
      if (!mounted) return;
      if (msg == null) {
        _spaceSnack('Could not send the file to the Space.');
        return;
      }
      setState(() => _messages.add(msg));
      ref.read(socketServiceProvider).emit('space:message',
        {'spaceSlug': widget.spaceSlug, 'message': {'_id': msg.id, 'senderId': msg.senderId,
          'senderName': msg.senderName, 'senderAvatar': msg.senderAvatar,
          'text': msg.text, 'mediaUrl': msg.mediaUrl, 'mediaType': msg.mediaType,
          'fileName': msg.fileName, 'createdAt': msg.createdAt.toIso8601String()}});
      _scrollToBottom();
    } catch (e) {
      _spaceSnack('Could not send file: $e');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  void _showSpaceGallery() {
    final uid = ref.read(currentUserProvider)?.xameId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: XameColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: FutureBuilder<List<SpaceMessage>>(
          future: XameSpaceService.fetchMedia(widget.spaceSlug, userId: uid),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(child: CircularProgressIndicator(color: XameColors.primary));
            }
            final items = snap.data ?? <SpaceMessage>[];
            if (items.isEmpty) {
              return const Center(
                  child: Text('No media shared yet', style: TextStyle(color: Colors.white54)));
            }
            final images = items.where((m) => m.mediaType.startsWith('image')).toList();
            final files = items.where((m) => !m.mediaType.startsWith('image')).toList();
            return ListView(padding: const EdgeInsets.all(12), children: [
              Text('Media Gallery (${items.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (images.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: images.map((m) => GestureDetector(
                    onTap: () => _SpaceMediaView.viewImage(ctx, m.mediaUrl),
                    child: CachedNetworkImage(imageUrl: m.mediaUrl, fit: BoxFit.cover),
                  )).toList(),
                ),
              ...files.map((m) => ListTile(
                    leading: const Icon(Icons.insert_drive_file_rounded, color: Colors.white70),
                    title: Text(m.fileName.isNotEmpty ? m.fileName : 'File',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(m.senderName, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: const Icon(Icons.download_rounded, color: Colors.white54),
                    onTap: () => _SpaceMediaView.open(ctx, m.mediaUrl, m.fileName),
                  )),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() { _sending = true; });
    final user = ref.read(currentUserProvider);
    final msg = await XameSpaceService.sendMessage(widget.spaceSlug,
      userId: user?.xameId, displayName: user?.preferredName ?? user?.firstName,
      text: text, replyToId: _replyTo?.id, replyToText: _replyTo?.text);
    if (!mounted) return;
    setState(() { _sending = false; _replyTo = null; });
    if (msg != null) {
      setState(() => _messages.add(msg));
      // Broadcast via socket
      ref.read(socketServiceProvider).emit('space:message',
        {'spaceSlug': widget.spaceSlug, 'message': {'_id': msg.id, 'senderId': msg.senderId,
          'senderName': msg.senderName, 'senderAvatar': msg.senderAvatar,
          'text': msg.text, 'createdAt': msg.createdAt.toIso8601String()}});
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(backgroundColor: XameColors.darkBg,
      body: const Center(child: CircularProgressIndicator()));
    if (_space == null) return Scaffold(backgroundColor: XameColors.darkBg,
      body: const Center(child: Text('Space not found', style: TextStyle(color: Colors.white))));

    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _buildMessages()),
        if (_typing.isNotEmpty) _buildTypingIndicator(),
        if (_replyTo != null) _buildReplyBar(),
        _buildComposer(),
      ]),
    );
  }

  Widget _buildHeader() => Container(
    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8,
      left: 8, right: 16, bottom: 12),
    decoration: BoxDecoration(
      color: XameColors.darkSurface,
      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
    child: Row(children: [
      IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context)),
      if (_space!.avatar.isNotEmpty)
        CircleAvatar(radius: 18, backgroundImage: CachedNetworkImageProvider(_space!.avatar))
      else
        CircleAvatar(radius: 18, backgroundColor: XameColors.primary,
          child: Text(_space!.name[0].toUpperCase(),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_space!.name, style: const TextStyle(color: Colors.white,
          fontWeight: FontWeight.w700, fontSize: 16)),
        Text('${_space!.memberCount} members · ${_space!.archetype}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
      ])),
      IconButton(icon: const Icon(Icons.people_outline, color: Colors.white70),
        onPressed: () => _showMembers()),
      IconButton(icon: const Icon(Icons.more_vert, color: Colors.white70),
        onPressed: () => _showOptions()),
    ]),
  );

  Widget _buildMessages() => ListView.builder(
    controller: _scrollCtrl,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    itemCount: _messages.length,
    itemBuilder: (_, i) => _SpaceMessageBubble(
      msg: _messages[i],
      currentUserId: ref.read(currentUserProvider)?.xameId ?? '',
      onReply: (m) => setState(() => _replyTo = m),
      onReact: (m, e) async {
        await XameSpaceService.reactToMessage(widget.spaceSlug, m.id, e,
          userId: ref.read(currentUserProvider)?.xameId);
        final updated = await XameSpaceService.fetchMessages(widget.spaceSlug);
        if (mounted) setState(() => _messages = updated);
      },
    ),
  );

  Widget _buildTypingIndicator() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Text('${_typing.join(', ')} ${_typing.length == 1 ? 'is' : 'are'} typing...',
      style: TextStyle(color: XameColors.primary, fontSize: 12, fontStyle: FontStyle.italic)),
  );

  Widget _buildReplyBar() => Container(
    margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: XameColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      Container(width: 3, height: 32, color: XameColors.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(_replyTo!.text, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 13))),
      IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18),
        onPressed: () => setState(() => _replyTo = null)),
    ]),
  );

  Widget _buildComposer() => Container(
    padding: EdgeInsets.only(left: 8, right: 8, top: 8,
      bottom: MediaQuery.of(context).padding.bottom + 8),
    decoration: BoxDecoration(color: XameColors.darkSurface,
      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
    child: Row(children: [
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 42),
        icon: _uploadingMedia
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
            : const Icon(Icons.attach_file_rounded, color: Colors.white54),
        onPressed: _uploadingMedia ? null : _showSpaceAttachSheet,
      ),
      Expanded(child: TextField(
        controller: _msgCtrl,
        onChanged: _onTyping,
        style: const TextStyle(color: Colors.white),
        maxLines: 5, minLines: 1,
        decoration: InputDecoration(
          hintText: 'Message ${_space!.name}...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          filled: true, fillColor: XameColors.darkCard,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _send,
        child: Container(width: 42, height: 42,
          decoration: BoxDecoration(color: XameColors.primary, shape: BoxShape.circle),
          child: _sending
            ? const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)))
            : const Icon(Icons.send_rounded, color: Colors.black, size: 20)),
      ),
    ]),
  );

  void _showMembers() => showModalBottomSheet(context: context,
    backgroundColor: XameColors.darkSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ListView(padding: const EdgeInsets.all(16), children: [
      Text('Members (${_space!.memberCount})', style: const TextStyle(color: Colors.white,
        fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      ..._space!.members.map((m) => ListTile(
        leading: CircleAvatar(
          backgroundImage: m.avatar.isNotEmpty ? CachedNetworkImageProvider(m.avatar) : null,
          backgroundColor: XameColors.primary,
          child: m.avatar.isEmpty ? Text(m.displayName.isNotEmpty ? m.displayName[0] : 'G',
            style: const TextStyle(color: Colors.black)) : null),
        title: Text(m.displayName.isNotEmpty ? m.displayName : m.xameId,
          style: const TextStyle(color: Colors.white)),
        subtitle: Text(m.role, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
        trailing: m.role == 'OWNER' ? const Icon(Icons.star, color: Colors.amber, size: 16) : null)),
    ]));

  void _showOptions() => showModalBottomSheet(context: context,
    backgroundColor: XameColors.darkSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.link, color: Colors.white70),
        title: const Text('Copy Space Link', style: TextStyle(color: Colors.white)),
        onTap: () {
          Clipboard.setData(ClipboardData(text: 'https://app.xamepage.com/space/${widget.spaceSlug}'));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Space link copied!')));
        }),
      ListTile(leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
        title: const Text('Media Gallery', style: TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); _showSpaceGallery(); }),
      SizedBox(height: MediaQuery.of(context).padding.bottom),
    ]));
}

class _SpaceMessageBubble extends StatelessWidget {
  final SpaceMessage msg;
  final String currentUserId;
  final Function(SpaceMessage) onReply;
  final Function(SpaceMessage, String) onReact;
  const _SpaceMessageBubble({required this.msg, required this.currentUserId,
    required this.onReply, required this.onReact});

  bool get isMine => msg.senderId == currentUserId;

  @override
  Widget build(BuildContext context) {
    if (msg.deleted) return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('  🚫 Message deleted',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12,
          fontStyle: FontStyle.italic)));

    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              CircleAvatar(radius: 14,
                backgroundImage: msg.senderAvatar.isNotEmpty
                  ? CachedNetworkImageProvider(msg.senderAvatar) : null,
                backgroundColor: XameColors.primary,
                child: msg.senderAvatar.isEmpty
                  ? Text(msg.senderName.isNotEmpty ? msg.senderName[0] : 'G',
                      style: const TextStyle(color: Colors.black, fontSize: 11)) : null),
              const SizedBox(width: 6),
            ],
            Flexible(child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine ? XameColors.primary.withValues(alpha: 0.85) : XameColors.darkCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!isMine) Text(msg.senderName,
                  style: TextStyle(color: XameColors.primary, fontSize: 11,
                    fontWeight: FontWeight.w700)),
                if (msg.replyToText != null) Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(msg.replyToText!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 11))),
                if (msg.mediaUrl.isNotEmpty) _SpaceMediaView(msg: msg, isMine: isMine),
                if (msg.text.isNotEmpty) Text(msg.text,
                  style: TextStyle(color: isMine ? Colors.black87 : Colors.white, fontSize: 14)),
                const SizedBox(height: 2),
                Text(_fmtTime(msg.createdAt),
                  style: TextStyle(color: isMine
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.35), fontSize: 10)),
                if (msg.reactions.isNotEmpty) _buildReactions(context),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    final grouped = <String, int>{};
    for (final r in msg.reactions) grouped[r['emoji']] = (grouped[r['emoji']] ?? 0) + 1;
    return Wrap(spacing: 4, children: grouped.entries.map((e) => GestureDetector(
      onTap: () => onReact(msg, e.key),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 11))))).toList());
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showActions(BuildContext context) => showModalBottomSheet(context: context,
    backgroundColor: const Color(0xFF1A2A2A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ['👍','❤️','😂','😮','😢','🔥'].map((e) => GestureDetector(
          onTap: () { Navigator.pop(context); onReact(msg, e); },
          child: Text(e, style: const TextStyle(fontSize: 28)))).toList()),
      const Divider(color: Colors.white12),
      ListTile(leading: const Icon(Icons.reply, color: Colors.white70),
        title: const Text('Reply', style: TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); onReply(msg); }),
      SizedBox(height: MediaQuery.of(context).padding.bottom),
    ]));
}

// SPACES_MEDIA_V1
String _spaceMimeFor(String name) {
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

class _SpaceMediaView extends StatelessWidget {
  final SpaceMessage msg;
  final bool isMine;
  const _SpaceMediaView({required this.msg, required this.isMine});

  static void viewImage(BuildContext context, String url) {
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

  static Future<void> open(BuildContext context, String url, String name) async {
    void snack(String t) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }

    try {
      final dir = await getTemporaryDirectory();
      final fileName = name.isNotEmpty ? name : 'file';
      final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final out = File('${dir.path}/spc_${url.hashCode.toRadixString(16)}_$safe');
      if (!await out.exists()) {
        snack('Downloading $fileName...');
        final client = http.Client();
        try {
          final resp = await client.send(http.Request('GET', Uri.parse(url)));
          if (resp.statusCode != 200) {
            snack('Download failed (${resp.statusCode}).');
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
        snack('No app found to open this file.');
      }
    } catch (e) {
      snack('Could not open file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = msg.mediaUrl;
    final type = msg.mediaType;
    final fg = isMine ? Colors.black87 : Colors.white;
    final sub = isMine ? Colors.black54 : Colors.white54;
    if (type.startsWith('image')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: GestureDetector(
          onTap: () => viewImage(context, url),
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
        ),
      );
    }
    final IconData icon = type.startsWith('video')
        ? Icons.videocam_rounded
        : type.startsWith('audio')
            ? Icons.audiotrack_rounded
            : type == 'application/pdf'
                ? Icons.picture_as_pdf_rounded
                : Icons.insert_drive_file_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => open(context, url, msg.fileName),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Text(msg.fileName.isNotEmpty ? msg.fileName : 'File',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Icon(Icons.download_rounded, color: sub, size: 20),
        ]),
      ),
    );
  }
}
