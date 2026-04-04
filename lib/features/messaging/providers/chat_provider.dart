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
import '../../../shared/models/message.dart';

// ── Active chat ID — mirrors ACTIVE_ID ───────────────────────────────────
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
  final _dio     = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final List<StreamSubscription> _subs = [];

  ChatNotifier(this._ref, this._contactId) : super([]) {
    _listenSocket();
  }

  void _listenSocket() {
    final socket = _ref.read(socketServiceProvider);

    // receive-message — mirrors socket.on('receive-message')
    _subs.add(socket.receiveMessage.listen((data) {
      final senderId = data['senderId'] as String?;
      if (senderId != _contactId) return;
      final m = data['message'] as Map<String, dynamic>?;
      if (m == null) return;

      final msg = XameMessage(
        id:          m['id']        ?? _uuid.v4(),
        senderId:    senderId ?? '',
        recipientId: '',
        text:        m['text']      ?? '',
        type:        m['file'] != null ? _typeFromFile(m['file']) : MessageType.text,
        direction:   MessageDirection.received,
        ts:          m['ts']        ?? DateTime.now().millisecondsSinceEpoch,
        status:      'delivered',
        expiresAt:   m['expiresAt'],
        replyToId:   m['replyTo']?['id'],
        replyToText: m['replyTo']?['text'],
        forwarded:   m['forwarded'] ?? false,
        viewOnce:    m['viewOnce']  ?? false,
        fileUrl:     m['file']?['url'],
        fileName:    m['file']?['name'],
        fileMime:    m['file']?['type'],
      );

      state = [...state, msg];

      // Emit seen if this chat is active
      final activeId = _ref.read(activeChatIdProvider);
      if (activeId == _contactId) {
        socket.emitMessageSeen(_contactId, [msg.id]);
      }
    }));

    // message-status-update — mirrors socket.on('message-status-update')
    _subs.add(socket.messageStatus.listen((update) {
      if (update.recipientId != _contactId) return;
      state = state.map((m) =>
        m.id == update.messageId ? m.copyWith(status: update.status) : m
      ).toList();
    }));

    // message-seen-update — mirrors socket.on('message-seen-update')
    _subs.add(socket.messageSeen.listen((update) {
      if (update.recipientId != _contactId) return;
      state = state.map((m) =>
        update.messageIds.contains(m.id) ? m.copyWith(status: 'seen') : m
      ).toList();
    }));

    // disappearing:expired — mirrors socket.on('disappearing:expired')
    _subs.add(socket.disappearExpired.listen((data) {
      if (data.contactId != _contactId) return;
      state = state.where((m) => m.id != data.messageId).toList();
    }));

    // messages-deleted — mirrors socket.on('messages-deleted')
    _subs.add(socket.messagesDeleted.listen((data) {
      if (data.contactId != _contactId) return;
      state = state.where((m) => !data.messageIds.contains(m.id)).toList();
    }));

    // chat_history — mirrors intelligentMerge() called after 'chat_history' socket event
    _subs.add(socket.chatHistory.listen((historyData) {
      if (historyData == null) return;
      try {
        final map = Map<String, dynamic>.from(historyData);
        final serverMsgs = map[_contactId];
        if (serverMsgs == null || serverMsgs is! List) return;
        _intelligentMerge(List<Map<String, dynamic>>.from(
          serverMsgs.map((m) => Map<String, dynamic>.from(m))));
      } catch (_) {}
    }));
  }

  // mirrors sendMessage() in messaging.js
  Future<void> sendMessage(String text, {String? replyToId, String? replyToText, int? expiresAt}) async {
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

    // Optimistic add — mirrors: chat.push(newMsg); setChat(); renderMessages()
    state = [...state, msg];

    final socketMsg = <String, dynamic>{'id': msgId, 'text': text, 'ts': ts};
    if (expiresAt != null) socketMsg['expiresAt'] = expiresAt;
    if (replyToId != null) socketMsg['replyTo'] = {'id': replyToId, 'text': replyToText};

    // Mirrors: socket.emit('send-message', { recipientId, message }, callback)
    _ref.read(socketServiceProvider).emit('send-message', {
      'recipientId': _contactId,
      'message':     socketMsg,
    });
  }

  // mirrors sendFile() in messaging.js — POST /api/upload-file
  Future<void> sendFile(File file, String mimeType, {String? caption, bool viewOnce = false}) async {
    final self = _ref.read(currentUserProvider);
    if (self == null) return;

    final msgId = _uuid.v4();
    final ts    = DateTime.now().millisecondsSinceEpoch;

    // Pending message while uploading
    final pending = XameMessage(
      id: msgId, senderId: self.xameId, recipientId: _contactId,
      text: 'Uploading ${file.path.split('/').last}...',
      type: MessageType.text, direction: MessageDirection.sent,
      ts: ts, status: 'sending',
    );
    state = [...state, pending];

    try {
      final formData = FormData.fromMap({
        'file':        await MultipartFile.fromFile(file.path),
        'senderId':    self.xameId,
        'recipientId': _contactId,
        'messageId':   msgId,
      });

      final res  = await _dio.post('/api/upload-file', data: formData);
      final data = res.data as Map<String, dynamic>;

      if (data['success'] == true && data['url'] != null) {
        final finalMsg = XameMessage(
          id: msgId, senderId: self.xameId, recipientId: _contactId,
          text: caption ?? '', type: _typeFromMime(mimeType),
          direction: MessageDirection.sent, ts: ts, status: 'sending',
          fileUrl: data['url'], fileName: file.path.split('/').last,
          fileMime: mimeType, viewOnce: viewOnce,
        );
        state = state.map((m) => m.id == msgId ? finalMsg : m).toList();

        _ref.read(socketServiceProvider).emit('send-message', {
          'recipientId': _contactId,
          'message': {
            'id': msgId, 'text': caption ?? '', 'ts': ts,
            'file': {'url': data['url'], 'name': finalMsg.fileName, 'type': mimeType},
            'viewOnce': viewOnce,
          },
        });
      }
    } catch (e) {
      // Remove pending on error
      state = state.where((m) => m.id != msgId).toList();
    }
  }

  // mirrors markAllSeen() in messaging.js
  void markAllSeen() {
    final unseen = state
      .where((m) => m.direction == MessageDirection.received && m.status != 'seen')
      .map((m) => m.id)
      .toList();

    if (unseen.isEmpty) return;

    state = state.map((m) =>
      unseen.contains(m.id) ? m.copyWith(status: 'seen') : m
    ).toList();

    _ref.read(socketServiceProvider).emitMessageSeen(_contactId, unseen);
  }

  // mirrors deleteMessages() in messaging.js
  Future<void> deleteMessages(List<String> ids, {bool deleteForEveryone = false}) async {
    state = state.where((m) => !ids.contains(m.id)).toList();
    if (deleteForEveryone) {
      _ref.read(socketServiceProvider).emit('sync-deletions', {
        'chat': {'messageIds': ids, 'contactId': _contactId, 'deleteForEveryone': true},
      });
    }
  }

  // mirrors forwardMessages() — sends same message to other contacts
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
            if (m.fileUrl != null) 'file': {'url': m.fileUrl, 'name': m.fileName, 'type': m.fileMime},
          },
        });
      }
    }
  }

  // mirrors intelligentMerge() — deduplicates server + local messages
  void _intelligentMerge(List<Map<String, dynamic>> serverMessages) {
    final now       = DateTime.now().millisecondsSinceEpoch;
    final localIds  = state.map((m) => m.id).toSet();

    final newMsgs = serverMessages
      .where((m) =>
        m['id'] != null &&
        !localIds.contains(m['id']) &&
        (m['expiresAt'] == null || (m['expiresAt'] as int) > now))
      .map((m) => XameMessage(
        id:          m['messageId'] ?? m['id'] ?? _uuid.v4(),
        senderId:    m['senderId']  ?? '',
        recipientId: m['recipientId'] ?? _contactId,
        text:        m['text']     ?? '',
        type:        m['file'] != null ? _typeFromFile(Map<String,dynamic>.from(m['file'])) : MessageType.text,
        direction:   (m['senderId'] == _ref.read(currentUserProvider)?.xameId)
                       ? MessageDirection.sent : MessageDirection.received,
        ts:          m['ts']       ?? 0,
        status:      m['status']   ?? 'delivered',
        expiresAt:   m['expiresAt'],
        replyToId:   m['replyTo']?['id'],
        replyToText: m['replyTo']?['text'],
        forwarded:   m['forwarded'] ?? false,
        viewOnce:    m['viewOnce']  ?? false,
        fileUrl:     m['file']?['url'],
        fileName:    m['file']?['name'],
        fileMime:    m['file']?['type'],
        reactions:   m['reactions'] != null
          ? Map<String,String>.from(m['reactions']) : null,
      ))
      .toList();

    if (newMsgs.isEmpty) return;

    final merged = [...state, ...newMsgs];
    merged.sort((a, b) => a.ts.compareTo(b.ts));
    state = merged;
  }

  void loadInitial(List<XameMessage> messages) {
    state = messages;
  }

  MessageType _typeFromMime(String mime) {
    if (AppConstants.allowedImageTypes.contains(mime)) return MessageType.image;
    if (AppConstants.allowedVideoTypes.contains(mime)) return MessageType.video;
    if (AppConstants.allowedAudioTypes.contains(mime)) return MessageType.audio;
    return MessageType.file;
  }

  MessageType _typeFromFile(Map<String, dynamic> f) =>
    _typeFromMime(f['type'] as String? ?? '');

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }
}
