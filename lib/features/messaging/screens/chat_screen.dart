import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/message.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String userId;
  const ChatScreen({super.key, required this.userId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl      = TextEditingController();
  final _scrollCtrl   = ScrollController();
  final _picker       = ImagePicker();
  bool  _showAttach   = false;
  Timer? _typingTimer;
  XameMessage? _replyTo;
  final Set<String> _selected = {};
  bool _selectMode = false;

  @override
  void initState() {
    super.initState();
    // Set active ID — mirrors: ACTIVE_ID = id
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChatIdProvider.notifier).state = widget.userId;
      ref.read(chatProvider(widget.userId).notifier).markAllSeen();
      ref.read(contactsProvider.notifier).markRead(widget.userId);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    ref.read(activeChatIdProvider.notifier).state = null;
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // Mirrors: typing indicator logic in chat.js
  void _onTextChanged(String v) {
    if (v.isNotEmpty) {
      _typingTimer?.cancel();
      ref.read(socketServiceProvider).emitTyping(widget.userId);
      _typingTimer = Timer(const Duration(seconds: 3), () {
        ref.read(socketServiceProvider).emitStopTyping(widget.userId);
      });
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    _typingTimer?.cancel();
    ref.read(socketServiceProvider).emitStopTyping(widget.userId);

    await ref.read(chatProvider(widget.userId).notifier).sendMessage(
      text,
      replyToId:   _replyTo?.id,
      replyToText: _replyTo?.text,
    );
    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    setState(() => _showAttach = false);
    await ref.read(chatProvider(widget.userId).notifier)
      .sendFile(dart_io.File(file.path), 'image/jpeg');
    _scrollToBottom();
  }

  Future<void> _pickFile() async {
    // TODO: use file_picker package for documents
    setState(() => _showAttach = false);
  }

  void _enterSelectMode(String msgId) {
    setState(() { _selectMode = true; _selected.add(msgId); });
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selected.clear(); });
  }

  void _toggleSelect(String msgId) {
    setState(() {
      if (_selected.contains(msgId)) {
        _selected.remove(msgId);
        if (_selected.isEmpty) _exitSelectMode();
      } else {
        _selected.add(msgId);
      }
    });
  }

  Future<void> _deleteSelected({bool forEveryone = false}) async {
    await ref.read(chatProvider(widget.userId).notifier)
      .deleteMessages(_selected.toList(), deleteForEveryone: forEveryone);
    _exitSelectMode();
  }

  void _copySelected(List<XameMessage> messages) {
    final texts = messages
      .where((m) => _selected.contains(m.id))
      .map((m) => m.text.isNotEmpty ? m.text : '[Attachment]')
      .join('\n\n');
    Clipboard.setData(ClipboardData(text: texts));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages copied!'), backgroundColor: XameColors.darkCard));
    _exitSelectMode();
  }

  void _showDeleteMenu(List<XameMessage> messages) {
    final hasSent = messages.any((m) =>
      _selected.contains(m.id) && m.direction == MessageDirection.sent);
    showModalBottomSheet(
      context: context, backgroundColor: XameColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        ListTile(leading: const Icon(Icons.copy, color: Colors.white70),
          title: const Text('Copy', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _copySelected(messages); }),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.white70),
          title: Text('Delete for me (${_selected.length})',
            style: const TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _deleteSelected(); }),
        if (hasSent)
          ListTile(leading: const Icon(Icons.delete_forever, color: XameColors.danger),
            title: Text('Delete for everyone (${_selected.length})',
              style: const TextStyle(color: XameColors.danger)),
            onTap: () { Navigator.pop(context); _deleteSelected(forEveryone: true); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages  = ref.watch(chatProvider(widget.userId));
    final contacts  = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact   = contacts.where((c) => c.id == widget.userId).firstOrNull;
    final isTyping  = ref.watch(typingProvider).contains(widget.userId);
    final self      = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: XameColors.darkBg,
      appBar: _buildAppBar(contact, isTyping, messages),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              if (_selectMode) _exitSelectMode();
            },
            child: messages.isEmpty
              ? _EmptyChat(name: contact?.name ?? widget.userId)
              : _MessageList(
                  messages:    messages,
                  scrollCtrl:  _scrollCtrl,
                  selfId:      self?.xameId ?? '',
                  selected:    _selected,
                  selectMode:  _selectMode,
                  onLongPress: (msg) {
                    if (_selectMode) { _toggleSelect(msg.id); return; }
                    _showBubbleMenu(msg, messages);
                  },
                  onTap: (msg) {
                    if (_selectMode) _toggleSelect(msg.id);
                  },
                ),
          ),
        ),
        // Reply preview
        if (_replyTo != null) _ReplyPreview(
          message: _replyTo!,
          onCancel: () => setState(() => _replyTo = null),
        ),
        // Attachment panel
        if (_showAttach) _AttachPanel(
          onImage:    _pickImage,
          onFile:     _pickFile,
          onCamera:   () async {
            final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
            if (file == null) return;
            setState(() => _showAttach = false);
            await ref.read(chatProvider(widget.userId).notifier)
              .sendFile(dart_io.File(file.path), 'image/jpeg');
            _scrollToBottom();
          },
          onDismiss: () => setState(() => _showAttach = false),
        ),
        _Composer(
          controller: _msgCtrl,
          onChanged:  _onTextChanged,
          onSend:     _send,
          onAttach:   () => setState(() => _showAttach = !_showAttach),
        ),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(
    ContactModel? contact, bool isTyping, List<XameMessage> messages) {
    if (_selectMode) {
      return AppBar(
        backgroundColor: XameColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _exitSelectMode),
        title: Text('${_selected.length} selected',
          style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: () => _copySelected(messages)),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: () => _showDeleteMenu(messages)),
        ],
      );
    }

    return AppBar(
      backgroundColor: XameColors.darkBg,
      elevation: 0,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
        onPressed: () => context.go('/contacts')),
      title: GestureDetector(
        onTap: () {/* TODO: contact profile */},
        child: Row(children: [
          XameAvatar(
            name:       contact?.name ?? widget.userId,
            profilePic: contact?.isProfilePicHidden == true ? null : contact?.profilePic,
            size:       36,
            isOnline:   contact?.isOnline ?? false,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact?.name ?? widget.userId,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              isTyping ? 'typing...'
                : contact?.isOnline == true ? 'online' : 'offline',
              style: TextStyle(
                color:     isTyping ? XameColors.accent : (contact?.isOnline == true ? XameColors.accent : Colors.white38),
                fontSize:  12,
                fontStyle: isTyping ? FontStyle.italic : FontStyle.normal),
            ),
          ])),
        ]),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call_outlined, color: Colors.white70),
          onPressed: () => context.go('/call/${widget.userId}?video=false')),
        IconButton(
          icon: const Icon(Icons.videocam_outlined, color: Colors.white70),
          onPressed: () => context.go('/call/${widget.userId}?video=true')),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          onPressed: () => _showChatMenu()),
      ],
    );
  }

  void _showChatMenu() {
    showModalBottomSheet(
      context: context, backgroundColor: XameColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        ListTile(leading: const Icon(Icons.search, color: Colors.white70),
          title: const Text('Search', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(context)),
        ListTile(leading: const Icon(Icons.block, color: Colors.white70),
          title: const Text('Block Contact', style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(context)),
        ListTile(leading: const Icon(Icons.delete_outline, color: XameColors.danger),
          title: const Text('Clear Chat', style: TextStyle(color: XameColors.danger)),
          onTap: () {
            Navigator.pop(context);
            ref.read(chatProvider(widget.userId).notifier).deleteMessages(
              ref.read(chatProvider(widget.userId)).map((m) => m.id).toList());
          }),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showBubbleMenu(XameMessage msg, List<XameMessage> messages) {
    showModalBottomSheet(
      context: context, backgroundColor: XameColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        if (msg.text.isNotEmpty)
          ListTile(leading: const Icon(Icons.reply, color: Colors.white70),
            title: const Text('Reply', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); setState(() => _replyTo = msg); }),
        if (msg.text.isNotEmpty)
          ListTile(leading: const Icon(Icons.copy, color: Colors.white70),
            title: const Text('Copy', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: msg.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied!'), backgroundColor: XameColors.darkCard));
            }),
        ListTile(leading: const Icon(Icons.select_all, color: Colors.white70),
          title: const Text('Select', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _enterSelectMode(msg.id); }),
        ListTile(leading: const Icon(Icons.delete_outline, color: XameColors.danger),
          title: const Text('Delete', style: TextStyle(color: XameColors.danger)),
          onTap: () {
            Navigator.pop(context);
            setState(() { _selected.add(msg.id); _selectMode = true; });
            _showDeleteMenu(messages);
          }),
        const SizedBox(height: 8),
      ])),
    );
  }
}

// ── Message list ──────────────────────────────────────────────────────────
class _MessageList extends StatelessWidget {
  final List<XameMessage>    messages;
  final ScrollController     scrollCtrl;
  final String               selfId;
  final Set<String>          selected;
  final bool                 selectMode;
  final Function(XameMessage) onLongPress;
  final Function(XameMessage) onTap;

  const _MessageList({
    required this.messages,   required this.scrollCtrl,
    required this.selfId,     required this.selected,
    required this.selectMode, required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Group by day — mirrors dayLabel() logic
    return ListView.builder(
      controller:  scrollCtrl,
      padding:     const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount:   messages.length,
      itemBuilder: (ctx, i) {
        final msg   = messages[i];
        final prev  = i > 0 ? messages[i - 1] : null;

        // Day separator
        final showDay = prev == null ||
          !_sameDay(DateTime.fromMillisecondsSinceEpoch(msg.ts),
                    DateTime.fromMillisecondsSinceEpoch(prev.ts));

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showDay) _DaySeparator(ts: msg.ts),
          MessageBubble(
            message:    msg,
            isSelf:     msg.direction == MessageDirection.sent,
            isSelected: selected.contains(msg.id),
            onLongPress: () => onLongPress(msg),
            onTap:       () => onTap(msg),
          ),
        ]);
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DaySeparator extends StatelessWidget {
  final int ts;
  const _DaySeparator({required this.ts});

  String get _label {
    final dt  = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(dt).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: XameColors.darkCard, borderRadius: BorderRadius.circular(12)),
      child: Text(_label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  final String name;
  const _EmptyChat({required this.name});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: XameColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.chat_bubble_outline_rounded, color: XameColors.primary, size: 40)),
      const SizedBox(height: 16),
      Text('Start a conversation with $name',
        style: const TextStyle(color: Colors.white38, fontSize: 14),
        textAlign: TextAlign.center),
    ]),
  );
}

// ── Reply preview bar ─────────────────────────────────────────────────────
class _ReplyPreview extends StatelessWidget {
  final XameMessage message;
  final VoidCallback onCancel;
  const _ReplyPreview({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(
      color: XameColors.darkCard,
      border: Border(left: BorderSide(color: XameColors.primary, width: 3))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Replying to', style: TextStyle(color: XameColors.primary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(message.text.isNotEmpty ? message.text : '📎 Attachment',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      IconButton(icon: const Icon(Icons.close, color: Colors.white38, size: 18), onPressed: onCancel),
    ]),
  );
}

// ── Attachment panel ──────────────────────────────────────────────────────
class _AttachPanel extends StatelessWidget {
  final VoidCallback onImage, onFile, onCamera, onDismiss;
  const _AttachPanel({required this.onImage, required this.onFile,
    required this.onCamera, required this.onDismiss});

  @override
  Widget build(BuildContext context) => Container(
    color: XameColors.darkSurface,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _AttachBtn(icon: Icons.photo_library_outlined, label: 'Gallery', onTap: onImage, color: XameColors.primary),
      _AttachBtn(icon: Icons.camera_alt_outlined,    label: 'Camera',  onTap: onCamera, color: XameColors.secondary),
      _AttachBtn(icon: Icons.insert_drive_file_outlined, label: 'File', onTap: onFile, color: XameColors.accent),
    ]),
  );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final Color color;
  const _AttachBtn({required this.icon, required this.label, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: color, size: 24)),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ]),
  );
}

// ── Composer ──────────────────────────────────────────────────────────────
class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final VoidCallback onSend, onAttach;
  const _Composer({required this.controller, required this.onChanged,
    required this.onSend, required this.onAttach});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final has = widget.controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: BoxDecoration(
      color: XameColors.darkSurface,
      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
    ),
    child: SafeArea(top: false, child: Row(children: [
      IconButton(
        icon: const Icon(Icons.attach_file_rounded, color: Colors.white54),
        onPressed: widget.onAttach),
      Expanded(
        child: TextField(
          controller:   widget.controller,
          onChanged:    widget.onChanged,
          onSubmitted:  (_) => widget.onSend(),
          maxLines:     5,
          minLines:     1,
          style:        const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText:    'Message...',
            hintStyle:   const TextStyle(color: Colors.white30),
            filled:      true,
            fillColor:   XameColors.darkCard,
            border:      OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: widget.onSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _hasText ? XameColors.primary : XameColors.darkCard,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.send_rounded,
            color: _hasText ? Colors.black : Colors.white38, size: 20),
        ),
      ),
    ])),
  );
}

// dart:io import alias to avoid conflict with File widget
import 'dart:io' as dart_io;
