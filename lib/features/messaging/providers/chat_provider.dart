import 'package:flutter/foundation.dart';
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
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout:    const Duration(minutes: 10), // large video uploads need time
  ));
  final List<StreamSubscription> _subs = [];

  ChatNotifier(this._ref, this._contactId) : super([]) {
    final cached = CacheService.loadChat(_contactId);
    if (cached.isNotEmpty) state = cached;
    _listenSocket();
    // Fetch fresh history on init so chat is always up to date after reboot
    Future.microtask(() => fetchHistory());
  }

  void appendIncoming(XameMessage msg) {
    if (state.any((m) => m.id == msg.id)) return; // deduplicate
    state = [...state, msg];
    CacheService.saveChat(_contactId, state);
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
      final isCall  = m['type'] == 'call' || data['type'] == 'call';
      final dir     = m['direction'] as String? ?? data['direction'] as String? ?? 'received';
      final isSent  = dir == 'sent';
      final selfId  = _ref.read(currentUserProvider)?.xameId ?? '';

      final msg = XameMessage(
        id:          m['id']  as String? ?? _uuid.v4(),
        senderId:    isSent ? selfId : (senderId ?? ''),
        recipientId: isSent ? (senderId ?? '') : selfId,
        text:        m['text'] as String? ?? '',
        type:        isCall ? MessageType.call : (hasFile ? _typeFromMime(mime) : MessageType.text),
        direction:   isSent ? MessageDirection.sent : MessageDirection.received,
        ts:          (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        status:      'delivered',
        expiresAt:   m['expiresAt'] as int?,
        replyToId:      (m['replyTo'] as Map?)?['id']      as String?,
        replyToText:    (m['replyTo'] as Map?)?['text']    as String?,
        replyToFileUrl: (m['replyTo'] as Map?)?['fileUrl']  as String?,
        replyToFileMime:(m['replyTo'] as Map?)?['fileMime'] as String?,
        forwarded:   m['forwarded'] as bool? ?? false,
        viewOnce:    m['viewOnce']  as bool? ?? false,
        fileUrl:     hasFile ? fileObj['url']  as String? : null,
        fileName:    hasFile ? fileObj['name'] as String? : null,
        fileMime:    hasFile ? mime : null,
        callType:    m['callType']    as String? ?? data['callType']    as String?,
        callStatus:  m['callStatus']  as String? ?? data['callStatus']  as String?,
        callDuration:((((m['callDuration'] as num?)?.toInt() ?? (data['callDuration'] as num?)?.toInt()) ?? 0) > 86400 ? (((m['callDuration'] as num?)?.toInt() ?? (data['callDuration'] as num?)?.toInt())! ~/ 1000) : ((m['callDuration'] as num?)?.toInt() ?? (data['callDuration'] as num?)?.toInt())),
        albumId:     m['albumId']    as String?,
        albumIndex:  (m['albumIndex'] as num?)?.toInt(),
        albumTotal:  (m['albumTotal'] as num?)?.toInt(),
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
      state = state.map((m) => data.messageIds.contains(m.id) ? m.copyWith(isDeleted: true) : m).toList();
      CacheService.saveChat(_contactId, state);
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

    _subs.add(socket.callMessage.listen((data) {
      final selfId      = _ref.read(currentUserProvider)?.xameId ?? '';
      final senderId    = data['senderId']    as String? ?? '';
      final recipientId = data['recipientId'] as String? ?? '';
      final isSent      = data['direction']   == 'sent';
      final contactId   = isSent ? recipientId : senderId;
      if (contactId != _contactId) return;
      final msg = XameMessage(
        id:           data['id']           as String? ?? _uuid.v4(),
        senderId:     isSent ? selfId : senderId,
        recipientId:  isSent ? recipientId : selfId,
        text:         '',
        type:         MessageType.call,
        direction:    isSent ? MessageDirection.sent : MessageDirection.received,
        ts:           (data['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        status:       data['status'] as String? ?? 'sent',
        callType:     data['callType']     as String?,
        callStatus:   data['callStatus']   as String?,
        callDuration: ((data['callDuration'] as num?)?.toInt() ?? 0) > 86400 ? ((data['callDuration'] as num?)!.toInt() ~/ 1000) : (data['callDuration'] as num?)?.toInt(),
      );
      if (state.any((s) => s.id == msg.id)) return;
      state = [...state, msg];
    }));
  }

  // ── Send text ─────────────────────────────────────────────────────────
  Future<void> sendMessage(String text,
      {String? replyToId, String? replyToText, String? replyToFileUrl, String? replyToFileMime, int? expiresAt}) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;

    final msgId = _uuid.v4();
    final ts    = DateTime.now().millisecondsSinceEpoch;

    final msg = XameMessage(
      id: msgId, senderId: self.xameId, recipientId: _contactId,
      text: text, type: MessageType.text, direction: MessageDirection.sent,
      ts: ts, status: 'sending',
      replyToId: replyToId, replyToText: replyToText,
      replyToFileUrl: replyToFileUrl, replyToFileMime: replyToFileMime,
      expiresAt: expiresAt,
    );

    state = [...state, msg];
    CacheService.saveChat(_contactId, state);

    final socketMsg = <String, dynamic>{'id': msgId, 'text': text, 'ts': ts};
    if (expiresAt != null) socketMsg['expiresAt'] = expiresAt;
    if (replyToId != null)
      socketMsg['replyTo'] = {'id': replyToId, 'text': replyToText, 'fileUrl': replyToFileUrl, 'fileMime': replyToFileMime};

    _ref.read(socketServiceProvider).emit('send-message', {
      'recipientId': _contactId,
      'message':     socketMsg,
    });
  }

  // ── Send file — FIXED: never silently delete, show failed state ────────
  Future<void> sendFile(File file, String mimeType,
      {String? caption, bool viewOnce = false,
       String? albumId, int? albumIndex, int? albumTotal}) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;

    final msgId    = _uuid.v4();
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final fileName = file.path.split('/').last;
    int?  fileSize;
    try { fileSize = await file.length(); } catch (_) {}

    if ((fileSize ?? 0) > AppConstants.maxFileSizeBytes) {
      final mb    = ((fileSize ?? 0) / (1024 * 1024)).toStringAsFixed(1);
      final maxMb = (AppConstants.maxFileSizeBytes / (1024 * 1024)).toStringAsFixed(0);
      state = [...state, XameMessage(
        id: _uuid.v4(),
        senderId:    _ref.read(currentUserProvider)?.xameId ?? '',
        recipientId: _contactId,
        text:        'File too large (${mb}MB). Max ${maxMb}MB.',
        type:        MessageType.text,
        direction:   MessageDirection.sent,
        ts:          DateTime.now().millisecondsSinceEpoch,
        status:      'failed',
      )];
      return;
    }

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
      localPath: file.path,  // keep local path for instant open without download
      // fileUrl is null while uploading — bubble handles this gracefully
      albumId: albumId, albumIndex: albumIndex, albumTotal: albumTotal,
    );
    state = [...state, pending];

    // Scale timeout with file size: 2min base + 1min per 5MB, max 10min
    final sizeMb       = (fileSize ?? 0) / (1024 * 1024);
    final timeoutMins  = (2 + (sizeMb / 5)).ceil().clamp(2, 10);
    final uploadFuture = _doUpload(
      msgId: msgId, file: file, mimeType: mimeType,
      caption: caption, viewOnce: viewOnce,
      fileName: fileName, fileSize: fileSize, ts: ts,
      msgType: msgType,
      albumId: albumId, albumIndex: albumIndex, albumTotal: albumTotal,
    );
    try {
      await uploadFuture.timeout(
        Duration(minutes: timeoutMins),
        onTimeout: () => _markFailed(msgId,
            hint: 'Upload timed out after \${timeoutMins}min — try on a faster connection'),
      );
    } catch (e) {
      _markFailed(msgId, hint: e.toString());
    }
  }

  // Internal upload worker — called by sendFile()
  Future<void> _doUpload({
    required String msgId,      required File   file,
    required String mimeType,   required String? caption,
    required bool   viewOnce,   required String fileName,
    required int?   fileSize,   required int    ts,
    required MessageType msgType,
    String? albumId, int? albumIndex, int? albumTotal,
  }) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;
    try {
      // Validate MIME — if not in allowed list, use octet-stream fallback
      // so the server still accepts it rather than rejecting outright
      final effectiveMime = AppConstants.allAllowedTypes.contains(mimeType)
          ? mimeType
          : 'application/octet-stream';

      // Upload via server's ImageKit endpoint
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path,
            contentType: DioMediaType.parse(effectiveMime)),
      });

      int _lastPct = 0;
      final res = await _dio.post(
        '/api/upload-file',
        data: form,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final pct = (sent / total * 100).round();
          if (pct != _lastPct && pct % 10 == 0) {
            _lastPct = pct;
            state = state.map((m) => m.id == msgId
                ? m.copyWith(status: 'uploading')
                : m).toList();
          }
        },
      );

      final data    = res.data as Map<String, dynamic>?;
      final fileUrl = (data?['success'] == true) ? (data?['url'] as String?) : null;

      if (data != null && fileUrl != null) {
        // SUCCESS — replace pending with final message
        final finalMsg = XameMessage(
          id: msgId,         senderId:    self.xameId,
          recipientId: _contactId,        text:        caption ?? '',
          type: msgType,     direction:   MessageDirection.sent,
          ts: ts,            status:      'sending',
          fileUrl: fileUrl,  fileName:    fileName,
          fileMime: mimeType, fileSize:   fileSize,   viewOnce: viewOnce,
          localPath: file.path,
          albumId: albumId, albumIndex: albumIndex, albumTotal: albumTotal,
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
            if (albumId != null) 'albumId': albumId,
            if (albumIndex != null) 'albumIndex': albumIndex,
            if (albumTotal != null) 'albumTotal': albumTotal,
          },
        });
      } else {
        // Server returned success:false — mark failed, keep bubble visible
        _markFailed(msgId);
      }
    } on DioException catch (e) {
      debugPrint('DioException during upload: ${e.type} — ${e.message}');
      debugPrint('Response: ${e.response?.data}');
      _markFailed(msgId,
          hint: e.response?.data?['message'] as String? ??
                e.message ??
                'Upload failed — check connection');
    } catch (e, st) {
      debugPrint('Upload error: $e');
      debugPrint('Stack: $st');
      _markFailed(msgId, hint: 'Error: ${e.toString().substring(0, e.toString().length.clamp(0, 100))}');
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
      final selfId = _ref.read(currentUserProvider)?.xameId;
      if (selfId == null || selfId.isEmpty) return;
      final res = await _dio.get('/api/chat/$selfId/$_contactId');
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
    if (deleteForEveryone) {
      state = state.map((m) => ids.contains(m.id) ? m.copyWith(isDeleted: true) : m).toList();
    } else {
      state = state.where((m) => !ids.contains(m.id)).toList();
    }
    CacheService.saveChat(_contactId, state);
    _ref.read(socketServiceProvider).emit('sync-deletions', {
      'chat': {
        'messageIds': ids, 'contactId': _contactId,
        'deleteForEveryone': deleteForEveryone,
      },
    });
  }

  // ── Forward messages ──────────────────────────────────────────────────
  void toggleReaction(String messageId, String emoji) {
    final selfId = _ref.read(currentUserProvider)?.xameId ?? '';
    if (selfId.isEmpty) return;
    state = state.map((m) {
      if (m.id != messageId) return m;
      final reactions = Map<String, String>.from(m.reactions ?? {});
      if (reactions[selfId] == emoji) {
        reactions.remove(selfId);
      } else {
        reactions[selfId] = emoji;
      }
      return m.copyWith(reactions: reactions);
    }).toList();
    _ref.read(socketServiceProvider).emitReactionToggle(messageId, emoji, selfId);
  }

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
          final dirStr  = m['direction'] as String? ?? m['type'] as String? ?? 'received';
          final isSent  = dirStr == 'sent';
          final fileObj = m['file'];
          final hasFile = fileObj != null &&
              fileObj is Map &&
              fileObj['url'] != null;
          final mime    = hasFile ? (fileObj['type'] as String? ?? '') : '';
          final isCall  = m['type'] == 'call';

          return XameMessage(
            id:          m['id'] as String,
            senderId:    isSent ? selfId : _contactId,
            recipientId: isSent ? _contactId : selfId,
            text:        m['text'] as String? ?? '',
            type:        isCall ? MessageType.call : (hasFile ? _typeFromMime(mime) : MessageType.text),
            direction:
                isSent ? MessageDirection.sent : MessageDirection.received,
            ts:          (m['ts'] as num?)?.toInt() ?? 0,
            status:      m['status'] as String? ?? 'delivered',
            expiresAt:   m['expiresAt'] as int?,
            replyToId:      (m['replyTo'] as Map?)?['id']      as String?,
            replyToText:    (m['replyTo'] as Map?)?['text']    as String?,
            replyToFileUrl: (m['replyTo'] as Map?)?['fileUrl']  as String?,
            replyToFileMime:(m['replyTo'] as Map?)?['fileMime'] as String?,
            forwarded:   m['forwarded'] as bool? ?? false,
            viewOnce:    m['viewOnce']  as bool? ?? false,
            fileUrl:     hasFile ? fileObj['url']  as String? : null,
            fileName:    hasFile ? fileObj['name'] as String? : null,
            fileMime:    hasFile ? mime : null,
            callType:    m['callType']     as String?,
            callStatus:  m['callStatus']   as String?,
            callDuration:((((m['callDuration'] as num?)?.toInt()) ?? 0) > 86400 ? (((m['callDuration'] as num?)?.toInt())! ~/ 1000) : ((m['callDuration'] as num?)?.toInt())),
            reactions: m['reactions'] != null &&
                    (m['reactions'] as Map).isNotEmpty
                ? Map<String, String>.from(m['reactions'] as Map)
                : null,
            albumId:     m['albumId']    as String?,
            albumIndex:  (m['albumIndex'] as num?)?.toInt(),
            albumTotal:  (m['albumTotal'] as num?)?.toInt(),
            actionButton: m['actionButton'] != null
                ? Map<String, dynamic>.from(m['actionButton'] as Map)
                : null,
          );
        })
        .toList();

    // Silently drop locally cached messages that the server no longer has
    // (e.g. removed server-side), without any visible "deleted" indicator.
    // Only reconcile within the timestamp range actually covered by this
    // fetch (the server returns a limited page, not full history), and
    // never touch messages still pending send.
    final serverIds = serverMessages
        .map((m) => m['id'] as String?)
        .whereType<String>()
        .toSet();
    final fetchedTimestamps = serverMessages
        .map((m) => (m['ts'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    int? rangeStart, rangeEnd;
    if (fetchedTimestamps.isNotEmpty) {
      rangeStart = fetchedTimestamps.reduce((a, b) => a < b ? a : b);
      rangeEnd   = fetchedTimestamps.reduce((a, b) => a > b ? a : b);
    }
    final reconciledState = state.where((m) {
      final isPending = m.status == 'sending' || m.status == 'uploading';
      if (isPending) return true;
      if (rangeStart == null || rangeEnd == null) return true;
      final withinFetchedRange = m.ts >= rangeStart! && m.ts <= rangeEnd!;
      if (!withinFetchedRange) return true; // outside this page, leave untouched
      return serverIds.contains(m.id); // inside range but missing → was deleted
    }).toList();

    if (newMsgs.isEmpty) {
      if (reconciledState.length != state.length) {
        state = reconciledState;
        CacheService.saveChat(_contactId, state);
      }
      return;
    }

    final merged = [...reconciledState, ...newMsgs]..sort((a, b) => a.ts.compareTo(b.ts));
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
