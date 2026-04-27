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
    connectTimeout: const Duration(seconds: 60), // Render cold start can take 50s
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout:    const Duration(minutes: 10), // large video uploads need time
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

    // 50MB limit for video messages
    const maxUploadBytes = 50 * 1024 * 1024;
    if ((fileSize ?? 0) > maxUploadBytes) {
      final mb = ((fileSize ?? 0) / (1024 * 1024)).toStringAsFixed(1);
      state = [...state, XameMessage(
        id: _uuid.v4(),
        senderId:    _ref.read(currentUserProvider)?.xameId ?? '',
        recipientId: _contactId,
        text:        'File too large (\${mb}MB). Max 50MB.',
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
  }) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;
    try {
      // Validate MIME — if not in allowed list, use octet-stream fallback
      // so the server still accepts it rather than rejecting outright
      final effectiveMime = AppConstants.allAllowedTypes.contains(mimeType)
          ? mimeType
          : 'application/octet-stream';

      // Step 1: Get Cloudinary signature from server
      final sigRes  = await _dio.get('/api/cloudinary/sign',
          queryParameters: {'folder': 'xamepage_chat'});
      final sigData = sigRes.data as Map<String, dynamic>;
      final signature  = sigData['signature']  as String;
      final timestamp  = sigData['timestamp']  as int;
      final folder     = sigData['folder']     as String;
      final cloudName  = sigData['cloud_name'] as String;
      final apiKey     = sigData['api_key']    as String;

      // Step 2: Upload directly to Cloudinary
      final isVideo    = effectiveMime.startsWith('video');
      final isAudio    = effectiveMime.startsWith('audio');
      final resourceType = isVideo || isAudio ? 'video' : 'image';
      final cloudUrl   = 'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload';

      final cloudForm  = FormData.fromMap({
        'file':      await MultipartFile.fromFile(file.path,
                         contentType: DioMediaType.parse(effectiveMime)),
        'api_key':   apiKey,
        'timestamp': timestamp.toString(),
        'signature': signature,
        'folder':    folder,
      });

      final cloudDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout:    const Duration(minutes: 15),
        receiveTimeout: const Duration(minutes: 5),
      ));

      int _lastPct = 0;
      final res = await cloudDio.post(
        cloudUrl,
        data: cloudForm,
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
      final fileUrl = data?['secure_url'] as String?;

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
      debugPrint('DioException during upload: ${e.type} — ${e.message}');
      debugPrint('Response: ${e.response?.data}');
      _markFailed(msgId,
          hint: e.response?.data?['message'] as String? ??
                e.message ??
                'Upload failed — check connection');
    } catch (e, st) {
      debugPrint('Upload error: $e');
      debugPrint('Stack: $st');
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
