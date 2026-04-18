// Mirrors: CHAT_HISTORY, getChat(), setChat(), sendMessage(), markAllSeen()
// intelligentMerge(), deleteMessages(), forwardMessages()

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../shared/models/message.dart';

// ── Active chat ID ────────────────────────────────────────────────────────
final activeChatIdProvider = StateProvider<String?>((ref) => null);

// ── Chat messages provider ────────────────────────────────────────────────
final chatProvider = StateNotifierProvider.family<ChatNotifier, List<XameMessage>, String>(
  (ref, contactId) => ChatNotifier(ref, contactId),
);

class ChatNotifier extends StateNotifier<List<XameMessage>> {
  final Ref    _ref;
  final String _contactId;
  final _uuid    = const Uuid();
  final _storage = const FlutterSecureStorage();
  final _dio     = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5), // large files need time
    sendTimeout:    const Duration(minutes: 5),
  ));
  final List<StreamSubscription> _subs = [];

  ChatNotifier(this._ref, this._contactId) : super([]) {
    final cached = CacheService.loadChat(_contactId);
    if (cached.isNotEmpty) state = cached;
    _listenSocket();
  }

  void _listenSocket() {
    final socket = _ref.read(socketServiceProvider);

    _subs.add(socket.receiveMessage.listen((data) {
      final senderId = data['senderId'] as String?;
      if (senderId != _contactId) return;
      final m = data['message'] as Map<String, dynamic>?;
      if (m == null) return;

      final fileObj = m['file'];
      final hasFile = fileObj != null && fileObj is Map && fileObj['url'] != null;
      final mime    = hasFile ? (fileObj['type'] as String? ?? '') : '';

      final msg = XameMessage(
        id:          m['id']  as String? ?? _uuid.v4(),
        senderId:    senderId ?? '',
        recipientId: _ref.read(currentUserProvider)?.xameId ?? '',
        text:        m['text'] as String? ?? '',
        type:        hasFile ? _typeFromMime(mime) : MessageType.text,
        direction:   MessageDirection.received,
        ts:          (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        status:      'delivered',
        expiresAt:   m['expiresAt'] as int?,
        replyToId:   (m['replyTo'] as Map?)?['id']   as String?,
        replyToText: (m['replyTo'] as Map?)?['text'] as String?,
        forwarded:   m['forwarded'] as bool? ?? false,
        viewOnce:    m['viewOnce']  as bool? ?? false,
        fileUrl:     hasFile ? fileObj['url']  as String? : null,
        fileName:    hasFile ? fileObj['name'] as String? : null,
        fileMime:    hasFile ? mime : null,
      );

      // Deduplicate — server echo can arrive before socket ack
      if (state.any((s) => s.id == msg.id)) return;
      state = [...state, msg];

      final activeId = _ref.read(activeChatIdProvider);
      if (activeId == _contactId) {
        socket.emitMessageSeen(_contactId, [msg.id]);
      }
    }));

    _subs.add(socket.messageStatus.listen((update) {
      if (update.recipientId != _contactId) return;
      state = state.map((m) =>
        m.id == update.messageId ? m.copyWith(status: update.status) : m
      ).toList();
    }));

    _subs.add(socket.messageSeen.listen((update) {
      if (update.recipientId != _contactId) return;
      state = state.map((m) =>
        update.messageIds.contains(m.id) ? m.copyWith(status: 'seen') : m
      ).toList();
    }));

    _subs.add(socket.disappearExpired.listen((data) {
      if (data.contactId != _contactId) return;
      state = state.where((m) => m.id != data.messageId).toList();
    }));

    _subs.add(socket.messagesDeleted.listen((data) {
      if (data.contactId != _contactId) return;
      state = state.where((m) => !data.messageIds.contains(m.id)).toList();
    }));

    _subs.add(socket.chatHistory.listen((historyData) {
      if (historyData == null) return;
      try {
        final map        = Map<String, dynamic>.from(historyData);
        final serverMsgs = map[_contactId];
        if (serverMsgs == null || serverMsgs is! List) return;
        _intelligentMerge(List<Map<String, dynamic>>.from(
          serverMsgs.map((m) => Map<String, dynamic>.from(m))));
      } catch (_) {}
    }));
  }

  // ── Send text ─────────────────────────────────────────────────────────
  Future<void> sendMessage(String text,
      {String? replyToId, String? replyToText, int? expiresAt}) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;

    final msgId = _uuid.v4();
    final ts    = DateTime.now().millisecondsSinceEpoch;

    final msg = XameMessage(
      id: msgId, senderId: self.xameId, recipientId: _contactId,
      text: text, type: MessageType.text, direction: MessageDirection.sent,
      ts: ts, status: 'sending',
      replyToId: replyToId, replyToText: replyToText, expiresAt: expiresAt,
    );

    state = [...state, msg];
    CacheService.saveChat(_contactId, state);

    final socketMsg = <String, dynamic>{'id': msgId, 'text': text, 'ts': ts};
    if (expiresAt != null) socketMsg['expiresAt'] = expiresAt;
    if (replyToId != null)
      socketMsg['replyTo'] = {'id': replyToId, 'text': replyToText};

    _ref.read(socketServiceProvider).emit('send-message', {
      'recipientId': _contactId,
      'message':     socketMsg,
    });
  }

  // ── Send file — FIXED: never silently delete, show failed state ────────
  Future<void> sendFile(File file, String mimeType,
      {String? caption, bool viewOnce = false}) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;

    final msgId    = _uuid.v4();
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final fileName = file.path.split('/').last;
    int?  fileSize;
    try { fileSize = await file.length(); } catch (_) {}

    // Resolve correct MessageType immediately from mime — not text
    final msgType  = _typeFromMime(mimeType);

    // Pending bubble: correct type + fileName + fileSize visible right away
    // status 'uploading' drives the upload progress indicator in the bubble
    final pending = XameMessage(
      id: msgId,         senderId:    self.xameId,
      recipientId: _contactId,        text:        caption ?? '',
      type: msgType,     direction:   MessageDirection.sent,
      ts: ts,            status:      'uploading',
      fileName: fileName, fileMime:   mimeType,
      fileSize: fileSize, viewOnce:   viewOnce,
      // fileUrl is null while uploading — bubble handles this gracefully
    );
    state = [...state, pending];

    try {
      // Validate MIME — if not in allowed list, use octet-stream fallback
      // so the server still accepts it rather than rejecting outright
      final effectiveMime = AppConstants.allAllowedTypes.contains(mimeType)
          ? mimeType
          : 'application/octet-stream';

      final formData = FormData.fromMap({
        'file':    await MultipartFile.fromFile(file.path,
                       contentType: DioMediaType.parse(effectiveMime)),
        'userId':  self.xameId,
        'caption': caption ?? '',
      });

      // Server: POST /api/gallery/upload
      // Response: { success: true, item: { url: 'https://res.cloudinary.com/...' } }
      final res        = await _dio.post('/api/gallery/upload', data: formData);
      final data       = res.data as Map<String, dynamic>?;
      final fileUrl    = (data?['item'] as Map?)?['url'] as String?;

      if (data != null && data['success'] == true && fileUrl != null) {
        // SUCCESS — replace pending with final message
        final finalMsg = XameMessage(
          id: msgId,         senderId:    self.xameId,
          recipientId: _contactId,        text:        caption ?? '',
          type: msgType,     direction:   MessageDirection.sent,
          ts: ts,            status:      'sending',
          fileUrl: fileUrl,  fileName:    fileName,
          fileMime: mimeType, fileSize:   fileSize,   viewOnce: viewOnce,
        );
        state = state.map((m) => m.id == msgId ? finalMsg : m).toList();
        CacheService.saveChat(_contactId, state);

        _ref.read(socketServiceProvider).emit('send-message', {
          'recipientId': _contactId,
          'message': {
            'id': msgId, 'text': caption ?? '', 'ts': ts,
            'file': {
              'url':  fileUrl,
              'name': fileName,
              'type': effectiveMime,
              'size': fileSize,
            },
            'viewOnce': viewOnce,
          },
        });
      } else {
        // Server returned success:false — mark failed, keep bubble visible
        _markFailed(msgId);
      }
    } on DioException catch (e) {
      // Network/server error — mark failed with error detail, never delete
      _markFailed(msgId,
          hint: e.response?.data?['message'] as String? ??
                e.message ??
                'Upload failed');
    } catch (e) {
      _markFailed(msgId, hint: e.toString());
    }
  }

  // Mark a message as failed — keeps it in the list so user sees it
  void _markFailed(String msgId, {String? hint}) {
    state = state.map((m) => m.id == msgId
        ? m.copyWith(status: 'failed')
        : m).toList();
  }

  // Retry a failed file upload — called from bubble long-press menu
  Future<void> retryFile(XameMessage msg, File file) async {
    // Reset to uploading
    state = state.map((m) => m.id == msg.id
        ? m.copyWith(status: 'uploading')
        : m).toList();
    await sendFile(file, msg.fileMime ?? 'application/octet-stream',
        caption: msg.text, viewOnce: msg.viewOnce);
  }

  // ── Fetch history ─────────────────────────────────────────────────────
  Future<void> fetchHistory() async {
    try {
      final token = await _storage.read(key: AppConstants.keySessionToken);
      if (token == null) return;
      final res = await _dio.get(
        '/api/messages/$_contactId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) return;
      final msgs = data['messages'];
      if (msgs == null || msgs is! List) return;
      _intelligentMerge(List<Map<String, dynamic>>.from(
        msgs.map((m) => Map<String, dynamic>.from(m))));
    } catch (_) {}
  }

  // ── Mark all seen ─────────────────────────────────────────────────────
  void markAllSeen() {
    final unseen = state
        .where((m) =>
            m.direction == MessageDirection.received && m.status != 'seen')
        .map((m) => m.id)
        .toList();
    if (unseen.isEmpty) return;
    state = state.map((m) =>
        unseen.contains(m.id) ? m.copyWith(status: 'seen') : m).toList();
    _ref.read(socketServiceProvider).emitMessageSeen(_contactId, unseen);
  }

  // ── Delete messages ───────────────────────────────────────────────────
  Future<void> deleteMessages(List<String> ids,
      {bool deleteForEveryone = false}) async {
    state = state.where((m) => !ids.contains(m.id)).toList();
    if (deleteForEveryone) {
      _ref.read(socketServiceProvider).emit('sync-deletions', {
        'chat': {
          'messageIds': ids, 'contactId': _contactId,
          'deleteForEveryone': true,
        },
      });
    }
  }

  // ── Forward messages ──────────────────────────────────────────────────
  void forwardMessages(List<String> ids, List<String> recipientIds) {
    final msgs = state.where((m) => ids.contains(m.id)).toList();
    for (final recipientId in recipientIds) {
      for (final m in msgs) {
        final fwdId = _uuid.v4();
        final ts    = DateTime.now().millisecondsSinceEpoch;
        _ref.read(socketServiceProvider).emit('send-message', {
          'recipientId': recipientId,
          'message': {
            'id': fwdId, 'text': m.text, 'ts': ts,
            'forwarded': true,
            if (m.fileUrl != null)
              'file': {'url': m.fileUrl, 'name': m.fileName, 'type': m.fileMime},
          },
        });
      }
    }
  }

  // ── Intelligent merge ─────────────────────────────────────────────────
  void _intelligentMerge(List<Map<String, dynamic>> serverMessages) {
    final now      = DateTime.now().millisecondsSinceEpoch;
    final localIds = state.map((m) => m.id).toSet();
    final selfId   = _ref.read(currentUserProvider)?.xameId ?? '';

    final newMsgs = serverMessages
        .where((m) =>
            m['id'] != null &&
            !localIds.contains(m['id'] as String) &&
            (m['expiresAt'] == null ||
                (m['expiresAt'] as int) > now))
        .map((m) {
          final dirStr  = m['type'] as String? ?? 'received';
          final isSent  = dirStr == 'sent';
          final fileObj = m['file'];
          final hasFile = fileObj != null &&
              fileObj is Map &&
              fileObj['url'] != null;
          final mime    = hasFile ? (fileObj['type'] as String? ?? '') : '';

          return XameMessage(
            id:          m['id'] as String,
            senderId:    isSent ? selfId : _contactId,
            recipientId: isSent ? _contactId : selfId,
            text:        m['text'] as String? ?? '',
            type:        hasFile ? _typeFromMime(mime) : MessageType.text,
            direction:
                isSent ? MessageDirection.sent : MessageDirection.received,
            ts:          (m['ts'] as num?)?.toInt() ?? 0,
            status:      m['status'] as String? ?? 'delivered',
            expiresAt:   m['expiresAt'] as int?,
            replyToId:   (m['replyTo'] as Map?)?['id']   as String?,
            replyToText: (m['replyTo'] as Map?)?['text'] as String?,
            forwarded:   m['forwarded'] as bool? ?? false,
            viewOnce:    m['viewOnce']  as bool? ?? false,
            fileUrl:     hasFile ? fileObj['url']  as String? : null,
            fileName:    hasFile ? fileObj['name'] as String? : null,
            fileMime:    hasFile ? mime : null,
            reactions: m['reactions'] != null &&
                    (m['reactions'] as Map).isNotEmpty
                ? Map<String, String>.from(m['reactions'] as Map)
                : null,
          );
        })
        .toList();

    if (newMsgs.isEmpty) return;

    final merged = [...state, ...newMsgs]..sort((a, b) => a.ts.compareTo(b.ts));
    state = merged;
    CacheService.saveChat(_contactId, state);
  }

  void loadInitial(List<XameMessage> messages) => state = messages;

  MessageType _typeFromMime(String mime) {
    if (AppConstants.allowedImageTypes.contains(mime)) return MessageType.image;
    if (AppConstants.allowedVideoTypes.contains(mime)) return MessageType.video;
    if (AppConstants.allowedAudioTypes.contains(mime)) return MessageType.audio;
    return MessageType.file;
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }
}
