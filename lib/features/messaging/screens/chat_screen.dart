import 'dart:io' as dart_io;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../gallery/screens/gallery_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/services/translation_service.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../shared/models/message.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import 'chat_wallpaper.dart';
import 'message_schedule_screen.dart';
import '../disappearing.dart';

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
  final FocusNode _composerFocus = FocusNode();
  int   _lastMsgCount = 0;
  XameMessage? _replyTo;
  final Set<String> _selected = {};
  bool _selectMode = false;
  int  _wallpaperVersion = 0;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChatIdProvider.notifier).state = widget.userId;
      ref.read(chatProvider(widget.userId).notifier).markAllSeen();
      ref.read(contactsProvider.notifier).markRead(widget.userId);
      ref.read(socketServiceProvider).emitGetChatHistory(widget.userId);
      Future.delayed(const Duration(milliseconds: 800), _scrollToBottom);
    });
    // Scroll to bottom when composer gains focus (keyboard opens)
    _composerFocus.addListener(() {
      if (_composerFocus.hasFocus) {
        // 450ms — keyboard animation on Android takes ~400ms
        Future.delayed(const Duration(milliseconds: 450), _scrollToBottom);
      }
    });
  }

  @override
  void dispose() {
    ref.read(activeChatIdProvider.notifier).state = null;
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _composerFocus.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    // First pass — scroll to current maxScrollExtent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
    // Second pass — after layout settles, catch any remaining overflow
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (animate) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _onTextChanged(String v) {
    if (v.isNotEmpty) {
      _typingTimer?.cancel();
      ref.read(socketServiceProvider).emitTyping(widget.userId);
      _typingTimer = Timer(const Duration(seconds: 3), () {
        ref.read(socketServiceProvider).emitStopTyping(widget.userId);
      });
    }
  }

  Future<void> _sendVoiceNote(String filePath) async {
    final file = dart_io.File(filePath);
    if (!await file.exists()) return;
    await ref.read(chatProvider(widget.userId).notifier)
        .sendFile(file, 'audio/aac');
  }

  void _openDisappearingTimer() {
    final contactId = widget.userId;
    if (contactId == null) return;
    final socket = ref.read(socketServiceProvider);
    final user   = ref.read(currentUserProvider);
    DisappearingTimerDialog.show(
      context,
      contactId:     contactId,
      socket:        socket,
      currentUserId: user?.xameId ?? "",
    );
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

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: Duration(minutes: 10),
    );
    if (picked == null) return;
    setState(() => _showAttach = false);

    dart_io.File videoFile = dart_io.File(picked.path);
    final originalSize = await videoFile.length();
    const maxBytes = 5 * 1024 * 1024 + 500 * 1024; // 5.5MB safe limit

    if (originalSize > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.xText)),
          SizedBox(width: 12),
          Text('Compressing video...'),
        ]),
        duration: Duration(seconds: 60),
        backgroundColor: context.xCard,
      ));
      try {
        final info = await VideoCompress.compressVideo(
          picked.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        if (info?.file == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Compression failed — try a shorter clip'),
            backgroundColor: Colors.redAccent));
          return;
        }
        final compressedSize = await info!.file!.length();
        if (compressedSize > maxBytes) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Video still too large after compression '
                '(${(compressedSize / 1024 / 1024).toStringAsFixed(1)}MB). '
                'Try a shorter clip.'),
            backgroundColor: Colors.redAccent));
          return;
        }
        videoFile = info.file!;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Compression error: $e'),
          backgroundColor: Colors.redAccent));
        return;
      }
    }

    await ref.read(chatProvider(widget.userId).notifier)
        .sendFile(videoFile, 'video/mp4');
    _scrollToBottom();
  }

  // BUG 1 FIX: Full file picker — any file type from local storage
  Future<void> _pickFile() async {
    setState(() => _showAttach = false);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      if (picked.path == null) return;

      final file = dart_io.File(picked.path!);
      final mime = _mimeFromExtension(picked.extension ?? '');

      await ref.read(chatProvider(widget.userId).notifier)
          .sendFile(file, mime);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not pick file: $e'),
          backgroundColor: context.xCard,
        ));
      }
    }
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':  return 'application/pdf';
      case 'doc':  return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':  return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':  return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':  return 'text/plain';
      case 'zip':  return 'application/zip';
      case 'mp4':  return 'video/mp4';
      case 'mp3':  return 'audio/mpeg';
      case 'aac':  return 'audio/aac';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'gif':  return 'image/gif';
      case 'webp': return 'image/webp';
      default:     return 'application/octet-stream';
    }
  }

  void _enterSelectMode(String msgId) =>
      setState(() { _selectMode = true; _selected.add(msgId); });

  void _exitSelectMode() =>
      setState(() { _selectMode = false; _selected.clear(); });

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Messages copied!'), backgroundColor: context.xCard));
    _exitSelectMode();
  }

  void _showDeleteMenu(List<XameMessage> messages) {
    final hasSent = messages.any(
        (m) => _selected.contains(m.id) && m.direction == MessageDirection.sent);
    showModalBottomSheet(
      context: context, backgroundColor: context.xCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 8),
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
        SizedBox(height: 8),
        ListTile(
            leading: Icon(Icons.copy, color: context.xMuted),
            title: Text('Copy', style: TextStyle(color: context.xText)),
            onTap: () { Navigator.pop(context); _copySelected(messages); }),
        ListTile(
            leading: Icon(Icons.delete_outline, color: context.xMuted),
            title: Text('Delete for me (${_selected.length})',
                style: TextStyle(color: context.xText)),
            onTap: () { Navigator.pop(context); _deleteSelected(); }),
        if (hasSent)
          ListTile(
              leading: Icon(Icons.delete_forever, color: XameColors.danger),
              title: Text('Delete for everyone (${_selected.length})',
                  style: TextStyle(color: XameColors.danger)),
              onTap: () { Navigator.pop(context); _deleteSelected(forEveryone: true); }),
        SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider(widget.userId));
    // Auto-scroll whenever message list grows
    final msgCount = messages.length;
    if (msgCount > _lastMsgCount) {
      _lastMsgCount = msgCount;
      _scrollToBottom();
    }
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact  = contacts.where((c) => c.id == widget.userId).firstOrNull;
    final isTyping = ref.watch(typingProvider).contains(widget.userId);
    final self     = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.xBg,
      // BUG 2 FIX: resizeToAvoidBottomInset ensures the scaffold body
      // shrinks when the keyboard appears, keeping composer always visible
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(contact, isTyping, messages),
      body: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_wallpaperVersion),
        future: WallpaperService.getWallpaper(widget.userId),
        builder: (context, snap) {
          final wallpaper  = snap.data ?? {'type': 'preset', 'id': 'none'};
          final presetId   = wallpaper['type'] == 'preset' ? wallpaper['id'] as String? : null;
          final preset     = (presetId != null && presetId != 'none')
              ? kWallpaperPresets.firstWhere((p) => p.id == presetId,
                  orElse: () => kWallpaperPresets.first)
              : null;
          final customPath = wallpaper['type'] == 'custom'
              ? wallpaper['path'] as String? : null;

          return Stack(children: [
            // Wallpaper background
            if (preset != null)
              Positioned.fill(child: Container(
                  decoration: BoxDecoration(gradient: preset.gradient))),
            if (customPath != null)
              Positioned.fill(child: Image.file(File(customPath), fit: BoxFit.cover)),
            if (preset != null || customPath != null)
              Positioned.fill(child: Container(
                  color: Colors.black.withValues(alpha: 0.3))),

            // Chat UI
            Column(children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              if (_selectMode) _exitSelectMode();
            },
            child: messages.isEmpty
                ? _EmptyChat(name: contact?.name ?? widget.userId)
                : _MessageList(
                    messages:   messages,
                    scrollCtrl: _scrollCtrl,
                    selfId:     self?.xameId ?? '',
                    selected:   _selected,
                    selectMode: _selectMode,
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
        if (_replyTo != null) _ReplyPreview(
          message: _replyTo!,
          onCancel: () => setState(() => _replyTo = null),
        ),
        if (_showAttach) _AttachPanel(
          onImage:  _pickImage,
          onVideo:  _pickVideo,
          onFile:   _pickFile,
          onCamera: () async {
            final file = await _picker.pickImage(
                source: ImageSource.camera, imageQuality: 85);
            if (file == null) return;
            setState(() => _showAttach = false);
            await ref.read(chatProvider(widget.userId).notifier)
                .sendFile(dart_io.File(file.path), 'image/jpeg');
            _scrollToBottom();
          },
          onDismiss: () => setState(() => _showAttach = false),
        ),
        // Recording indicator
        Consumer(builder: (_, ref, __) {
          final voice = ref.watch(voiceProvider);
          if (voice.recordState != VoiceRecordState.recording) {
            return const SizedBox.shrink();
          }
          final secs = voice.recordDuration.inSeconds;
          final m = (secs ~/ 60).toString().padLeft(2, '0');
          final s = (secs % 60).toString().padLeft(2, '0');
          return Container(
            color: Colors.red.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [
              Icon(Icons.circle, color: Colors.red, size: 10),
              SizedBox(width: 8),
              Text('Recording $m:$s',
                  style: TextStyle(color: Colors.red, fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Spacer(),
              Text('Release to send · Slide to cancel',
                  style: TextStyle(color: context.xMuted, fontSize: 11)),
            ]),
          );
        }),
        _Composer(
          controller:   _msgCtrl,
          focusNode:    _composerFocus,
          onChanged:    _onTextChanged,
          onSend:       _send,
          onAttach:     () => setState(() => _showAttach = !_showAttach),
          onVoiceNote:  _sendVoiceNote,
          onDisappearing: _openDisappearingTimer,
        ),
      ]),
          ],
        );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      ContactModel? contact, bool isTyping, List<XameMessage> messages) {
    if (_selectMode) {
      return AppBar(
        backgroundColor: context.xSurface,
        leading: IconButton(
            icon: Icon(Icons.close, color: context.xText),
            onPressed: _exitSelectMode),
        title: Text('${_selected.length} selected',
            style: TextStyle(color: context.xText, fontSize: 16)),
        actions: [
          IconButton(
              icon: Icon(Icons.copy, color: context.xMuted),
              onPressed: () => _copySelected(messages)),
          IconButton(
              icon: Icon(Icons.delete_outline, color: context.xMuted),
              onPressed: () => _showDeleteMenu(messages)),
        ],
      );
    }

    return AppBar(
      backgroundColor: context.xBg,
      elevation: 0,
      leadingWidth: 40,
      leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: context.xText, size: 20),
          onPressed: () => context.go('/contacts')),
      title: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => GalleryScreen(userId: widget.userId, isOwner: false))),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              final pic = contact?.isProfilePicHidden == true ? null : contact?.profilePic;
              if (pic == null || pic.isEmpty) return;
              showDialog(context: context, builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: EdgeInsets.zero,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: SizedBox.expand(
                    child: InteractiveViewer(
                      child: Center(child: CachedNetworkImage(
                          imageUrl: pic, fit: BoxFit.contain))),
                  ),
                ),
              ));
            },
            child: XameAvatar(
              name:       contact?.name ?? widget.userId,
              profilePic: contact?.isProfilePicHidden == true ? null : contact?.profilePic,
              size:       36,
              isOnline:   contact?.isOnline ?? false,
            ),
          ),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact?.name ?? widget.userId,
                style: TextStyle(color: context.xText, fontSize: 15,
                    fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              isTyping ? 'typing...'
                  : contact?.isOnline == true ? 'online' : 'offline',
              style: TextStyle(
                  color: isTyping ? XameColors.accent
                      : (contact?.isOnline == true ? XameColors.accent : context.xMuted),
                  fontSize: 12,
                  fontStyle: isTyping ? FontStyle.italic : FontStyle.normal),
            ),
          ])),
        ]),
      ),
      actions: [
        IconButton(
            icon: Icon(Icons.call_outlined, color: context.xMuted),
            onPressed: () => context.go('/call/${widget.userId}?video=false')),
        IconButton(
            icon: Icon(Icons.videocam_outlined, color: context.xMuted),
            onPressed: () => context.go('/call/${widget.userId}?video=true')),
        IconButton(
            icon: Icon(Icons.more_vert, color: context.xMuted),
            onPressed: _showChatMenu),
      ],
    );
  }

  void _showChatMenu() {
    showModalBottomSheet(
      context: context, backgroundColor: context.xCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 8),
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
        SizedBox(height: 8),
        ListTile(
            leading: Icon(Icons.schedule_send_rounded, color: context.xMuted),
            title: Text('Schedule Message',
                style: TextStyle(color: context.xText)),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => ComposeScheduledSheet(
                  preselectedId:   widget.userId,
                  preselectedName: ref.read(contactsProvider).valueOrNull
                      ?.firstWhere((c) => c.id == widget.userId,
                          orElse: () => ContactModel(id: widget.userId, name: widget.userId))
                      .name,
                ));
            }),
          ListTile(
            leading: Icon(Icons.wallpaper_outlined, color: context.xMuted),
            title: Text('Wallpaper', style: TextStyle(color: context.xText)),
            onTap: () {
              Navigator.pop(context);
              WallpaperPickerSheet.show(context,
                contactId:   widget.userId,
                contactName: 'Chat',
                onChanged:   () => setState(() => _wallpaperVersion++),
              );
            }),
          ListTile(leading: Icon(Icons.search, color: context.xMuted),
            title: Text('Search', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(context)),
        ListTile(leading: Icon(Icons.edit_outlined, color: context.xMuted),
            title: Text('Edit Contact', style: TextStyle(color: context.xText)),
            onTap: () { Navigator.pop(context); _showEditContact(); }),
        ListTile(leading: Icon(Icons.person_remove_outlined, color: Colors.redAccent),
            title: Text('Delete Contact', style: TextStyle(color: Colors.redAccent)),
            onTap: () { Navigator.pop(context); _showDeleteContact(); }),
        ListTile(leading: Icon(Icons.block, color: context.xMuted),
            title: Text('Block Contact', style: TextStyle(color: context.xText)),
            onTap: () => Navigator.pop(context)),
        ListTile(leading: Icon(Icons.delete_outline, color: XameColors.danger),
            title: Text('Clear Chat', style: TextStyle(color: XameColors.danger)),
            onTap: () {
              Navigator.pop(context);
              ref.read(chatProvider(widget.userId).notifier).deleteMessages(
                  ref.read(chatProvider(widget.userId)).map((m) => m.id).toList());
            }),
        SizedBox(height: 8),
      ])),
    );
  }

  void _showEditContact() {
    final contact = ref.read(contactsProvider).valueOrNull
        ?.firstWhere((c) => c.id == widget.userId,
            orElse: () => ContactModel(id: widget.userId, name: widget.userId));
    final ctrl = TextEditingController(text: contact?.name ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.xSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit Contact',
            style: TextStyle(color: context.xText, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: context.xText),
          decoration: InputDecoration(
            hintText: 'Display name',
            hintStyle: TextStyle(color: context.xMuted),
            filled: true, fillColor: context.xSurface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: context.xMuted))),
          TextButton(
              onPressed: () async {
                final newName = ctrl.text.trim();
                if (newName.isEmpty) return;
                final self = ref.read(currentUserProvider);
                if (self == null) return;
                await ref.read(contactsProvider.notifier)
                    .renameContact(self.xameId, widget.userId, newName);
                if (mounted) Navigator.pop(context);
              },
              child: Text('Save',
                  style: TextStyle(color: XameColors.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _showDeleteContact() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.xSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Contact',
            style: TextStyle(color: context.xText, fontWeight: FontWeight.w700)),
        content: Text('Remove this contact? Chat history will remain.',
            style: TextStyle(color: context.xText.withValues(alpha: 0.54))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: context.xMuted))),
          TextButton(
              onPressed: () async {
                final self = ref.read(currentUserProvider);
                if (self == null) return;
                await ref.read(contactsProvider.notifier)
                    .removeContact(self.xameId, widget.userId);
                if (mounted) {
                  Navigator.pop(context);
                  context.go('/contacts');
                }
              },
              child: Text('Delete',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _showBubbleMenu(XameMessage msg, List<XameMessage> messages) {
    showModalBottomSheet(
      context: context, backgroundColor: context.xCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 8),
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
        SizedBox(height: 8),
        if (msg.text.isNotEmpty)
          ListTile(leading: Icon(Icons.reply, color: context.xMuted),
              title: Text('Reply', style: TextStyle(color: context.xText)),
              onTap: () { Navigator.pop(context); setState(() => _replyTo = msg); }),
        if (msg.text.isNotEmpty)
          ListTile(leading: Icon(Icons.copy, color: context.xMuted),
              title: Text('Copy', style: TextStyle(color: context.xText)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg.text));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Copied!'), backgroundColor: context.xCard));
              }),
        if (msg.text.isNotEmpty)
          ListTile(
              leading: Text('🌍', style: TextStyle(fontSize: 18)),
              title: Text('Translate', style: TextStyle(color: context.xText)),
              onTap: () {
                Navigator.pop(context);
                showTranslateSheet(context, ref, msg.text);
              }),
        ListTile(leading: Icon(Icons.select_all, color: context.xMuted),
            title: Text('Select', style: TextStyle(color: context.xText)),
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
  final List<XameMessage>     messages;
  final ScrollController      scrollCtrl;
  final String                selfId;
  final Set<String>           selected;
  final bool                  selectMode;
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
    return ListView.builder(
      controller:  scrollCtrl,
      padding:     const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount:   messages.length,
      itemBuilder: (ctx, i) {
        final msg  = messages[i];
        final prev = i > 0 ? messages[i - 1] : null;
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
  _DaySeparator({required this.ts});

  String get _label {
    final dt   = DateTime.fromMillisecondsSinceEpoch(ts);
    final now  = DateTime.now();
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
          color: context.xCard, borderRadius: BorderRadius.circular(12)),
      child: Text(_label,
          style: TextStyle(color: context.xMuted, fontSize: 11)),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  final String name;
  _EmptyChat({required this.name});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: XameColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.chat_bubble_outline_rounded,
            color: XameColors.primary, size: 40)),
      SizedBox(height: 16),
      Text('Start a conversation with $name',
          style: TextStyle(color: context.xMuted, fontSize: 14),
          textAlign: TextAlign.center),
    ]),
  );
}

// ── Reply preview bar ─────────────────────────────────────────────────────
class _ReplyPreview extends StatelessWidget {
  final XameMessage  message;
  final VoidCallback onCancel;
  _ReplyPreview({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(
      color: context.xCard,
      border: Border(left: BorderSide(color: XameColors.primary, width: 3))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Replying to',
            style: TextStyle(color: XameColors.primary, fontSize: 11)),
        SizedBox(height: 2),
        Text(message.text.isNotEmpty ? message.text : '📎 Attachment',
            style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 13),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      IconButton(
          icon: Icon(Icons.close, color: context.xMuted, size: 18),
          onPressed: onCancel),
    ]),
  );
}

// ── Attachment panel ──────────────────────────────────────────────────────
class _AttachPanel extends StatelessWidget {
  final VoidCallback onImage, onFile, onCamera, onDismiss, onVideo;
  _AttachPanel({
    required this.onImage,  required this.onFile,
    required this.onCamera, required this.onDismiss,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: context.xSurface,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _AttachBtn(icon: Icons.photo_library_outlined,     label: 'Gallery',
          onTap: onImage,  color: XameColors.primary),
      _AttachBtn(icon: Icons.videocam_outlined,           label: 'Video',
          onTap: onVideo,  color: XameColors.secondary),
      _AttachBtn(icon: Icons.camera_alt_outlined,         label: 'Camera',
          onTap: onCamera, color: context.xMuted),
      _AttachBtn(icon: Icons.insert_drive_file_outlined,  label: 'File',
          onTap: onFile,   color: XameColors.accent),
    ]),
  );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final Color color;
  _AttachBtn({
    required this.icon,  required this.label,
    required this.onTap, required this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: color, size: 24)),
      SizedBox(height: 6),
      Text(label, style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 11)),
    ]),
  );
}

// ── Composer ──────────────────────────────────────────────────────────────
class _Composer extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final Function(String) onChanged;
  final VoidCallback onSend, onAttach;
  final VoidCallback? onDisappearing;
  final Function(String)? onVoiceNote;
  _Composer({
    required this.controller, required this.focusNode,
    required this.onChanged,  required this.onSend,
    required this.onAttach,   this.onVoiceNote, this.onDisappearing,
  });

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
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
      color: context.xSurface,
      border: Border(top: BorderSide(color: context.xMuted.withValues(alpha: 0.2))),
    ),
    child: SafeArea(top: false, child: Row(children: [
      IconButton(
          icon: Icon(Icons.attach_file_rounded, color: context.xText.withValues(alpha: 0.54)),
          onPressed: widget.onAttach),
      IconButton(
          icon: Icon(Icons.timer_outlined, color: context.xText.withValues(alpha: 0.54)),
          onPressed: widget.onDisappearing),
      Expanded(
        child: TextField(
          controller:  widget.controller,
          focusNode:   widget.focusNode,
          onChanged:   widget.onChanged,
          textInputAction: ref.read(settingsProvider).enterToSend ? TextInputAction.send : TextInputAction.newline,
          onSubmitted: (_) { if (ref.read(settingsProvider).enterToSend) widget.onSend(); },
          maxLines:    5,
          minLines:    1,
          style: TextStyle(color: context.xText, fontSize: 15),
          decoration: InputDecoration(
            hintText:  'Message...',
            hintStyle: TextStyle(color: context.xMuted),
            filled:    true,
            fillColor: context.xCard,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
      SizedBox(width: 6),

      // STT mic button
      Consumer(builder: (_, ref, __) {
        final voice    = ref.watch(voiceProvider);
        final notifier = ref.read(voiceProvider.notifier);
        return GestureDetector(
          onTap: () async {
            if (voice.isSpeechListening) {
              await notifier.stopListening();
            } else {
              await notifier.startListening((text) {
                widget.controller.text = text;
                widget.onChanged(text);
              });
            }
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: voice.isSpeechListening
                  ? Colors.red.withValues(alpha: 0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              voice.isSpeechListening ? Icons.mic : Icons.mic_none_rounded,
              color: voice.isSpeechListening ? Colors.red : context.xMuted,
              size: 22),
          ),
        );
      }),

      const SizedBox(width: 4),

      // Send / voice-note button
      Consumer(builder: (_, ref, __) {
        final voice    = ref.watch(voiceProvider);
        final notifier = ref.read(voiceProvider.notifier);

        if (_hasText) {
          return GestureDetector(
            onTap: widget.onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42, height: 42,
              decoration: const BoxDecoration(
                  color: XameColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
            ),
          );
        }

        return GestureDetector(
          onLongPressStart: (_) async => await notifier.startRecording(),
          onLongPressEnd:   (_) async {
            final path = await notifier.stopRecording();
            if (path != null) {
              widget.onVoiceNote?.call(path);
              notifier.reset();
            }
          },
          onLongPressCancel: () => notifier.cancelRecording(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: voice.recordState == VoiceRecordState.recording
                  ? Colors.red : XameColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              voice.recordState == VoiceRecordState.recording
                  ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.black, size: 22),
          ),
        );
      }),
    ])),
  );
}
