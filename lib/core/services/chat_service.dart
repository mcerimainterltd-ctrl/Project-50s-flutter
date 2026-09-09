import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import 'socket_service.dart';
import '../../shared/models/message.dart';

final chatServiceProvider      = Provider<ChatService>((ref) => ChatService(ref.read(socketServiceProvider)));
final activeContactIdProvider  = StateProvider<String?>((ref) => null);

class ChatService {
  final SocketService _socket;
  final _dio     = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final _mediaDio = Dio(BaseOptions(baseUrl: AppConstants.mediaWorkerUrl));
  final _storage = const FlutterSecureStorage();
  final _uuid    = const Uuid();
  Timer? _typingTimer;
  final Map<String, String>          _drafts    = {};
  final Map<String, List<XameMessage>> _cache   = {};

  ChatService(this._socket);

  Future<XameMessage> sendMessage({
    required String recipientId,
    required String text,
    String? replyToId,
    String? replyToText,
    bool    isDisappearing = false,
    int?    expiresAt,
  }) async {
    final msg = XameMessage(
      id: _uuid.v4(), senderId: await _selfId(),
      recipientId: recipientId, text: text,
      type: MessageType.text, direction: MessageDirection.sent,
      ts: DateTime.now().millisecondsSinceEpoch, status: 'sending',
      replyToId: replyToId, replyToText: replyToText,
      isDisappearing: isDisappearing, expiresAt: expiresAt,
    );
    _addToCache(recipientId, msg);
    _socket.emit('send-message', {
      'recipientId': recipientId,
      'message': {
        'id': msg.id, 'text': text, 'ts': msg.ts,
        'replyTo': replyToId != null ? {'id': replyToId, 'text': replyToText} : null,
        'expiresAt': expiresAt,
      },
    });
    _drafts.remove(recipientId);
    await _saveDrafts();
    return msg;
  }

  Future<XameMessage> sendFile({
    required String  recipientId,
    required File    file,
    required String  mimeType,
    String?  caption,
    bool     viewOnce = false,
  }) async {
    // Validate file first — mirrors: const validation = validateFile(file)
    final validation = validateFile(file, mimeType);
    if (!validation.isValid) throw Exception(validation.error);

    final fileName = file.path.split('/').last;
    final fileSize = await file.length();
    final sessionToken = await _storage.read(
      key: AppConstants.keySessionToken,
    );

    if (sessionToken == null || sessionToken.isEmpty) {
      throw Exception('No active session.');
    }

    final initResponse = await _dio.post(
      '/api/media/upload-init',
      data: {
        'fileName': fileName,
        'contentType': mimeType,
        'size': fileSize,
        'folder': 'chat',
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $sessionToken',
          'Content-Type': 'application/json',
        },
      ),
    );

    final initData = initResponse.data as Map<String, dynamic>;

    if (initData['success'] != true ||
        initData['key'] == null ||
        initData['uploadId'] == null ||
        initData['capability'] == null) {
      throw Exception('Media upload initialization failed.');
    }

    final key = initData['key'] as String;
    final uploadId = initData['uploadId'] as String;
    final capability = initData['capability'] as String;

    const chunkSize = 8 * 1024 * 1024;
    final totalParts = (fileSize + chunkSize - 1) ~/ chunkSize;
    final completedParts = <Map<String, dynamic>>[];

    late final String fileUrl;

    try {
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        final start = (partNumber - 1) * chunkSize;
        final end = (start + chunkSize < fileSize)
            ? start + chunkSize
            : fileSize;
        final partLength = end - start;

        Map<String, dynamic>? partResult;
        Object? lastError;

        for (var attempt = 1; attempt <= 3; attempt++) {
          try {
            final response = await _mediaDio.put(
              '/multipart/part',
              queryParameters: {
                'key': key,
                'uploadId': uploadId,
                'partNumber': partNumber,
              },
              data: file.openRead(start, end),
              options: Options(
                headers: {
                  'Authorization': 'Bearer $capability',
                  'Content-Type': 'application/octet-stream',
                  'Content-Length': partLength,
                },
              ),
              onSendProgress: (sent, total) {
                if (kDebugMode && total > 0) {
                  final overallSent =
                      start + (sent > total ? total : sent);
                  final progress = overallSent / fileSize;
                  debugPrint(
                    'Media upload ${(progress * 100).toStringAsFixed(1)}%',
                  );
                }
              },
            );

            final data = response.data as Map<String, dynamic>;

            if (data['success'] != true || data['etag'] == null) {
              throw Exception('Multipart part upload failed.');
            }

            partResult = {
              'partNumber': partNumber,
              'etag': data['etag'],
            };
            break;
          } catch (e) {
            lastError = e;
            if (attempt < 3) {
              await Future<void>.delayed(
                Duration(seconds: attempt),
              );
            }
          }
        }

        if (partResult == null) {
          throw Exception(
            'Multipart part $partNumber failed after 3 attempts: $lastError',
          );
        }

        completedParts.add(partResult);
      }

      final completeResponse = await _mediaDio.post(
        '/multipart/complete',
        data: {
          'key': key,
          'uploadId': uploadId,
          'parts': completedParts,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $capability',
            'Content-Type': 'application/json',
          },
        ),
      );

      final completeData =
          completeResponse.data as Map<String, dynamic>;

      if (completeData['success'] != true ||
          completeData['url'] == null) {
        throw Exception('Media upload completion failed.');
      }

      fileUrl = completeData['url'] as String;

    } catch (e) {
      try {
        await _mediaDio.post(
          '/multipart/abort',
          data: {
            'key': key,
            'uploadId': uploadId,
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $capability',
              'Content-Type': 'application/json',
            },
          ),
        );
      } catch (_) {
        // Best-effort multipart cleanup.
      }
      rethrow;
    }

    final msg = XameMessage(
      id:          _uuid.v4(),
      senderId:    await _getSelfId(),
      recipientId: recipientId,
      text:        caption ?? '',
      type:        _typeFromMime(mimeType),
      direction:   MessageDirection.sent,
      ts:          DateTime.now().millisecondsSinceEpoch,
      status:      'sending',
      fileUrl:     fileUrl,
      fileName:    file.path.split('/').last,
      fileSize:    fileSize,
      viewOnce:    viewOnce,
    );

    _addToCache(recipientId, msg);

    _socket.emit('send-message', {
      'recipientId': recipientId,
      'message': {
        'id':      msg.id,
        'text':    caption ?? '',
        'ts':      msg.ts,
        'file':    {'url': fileUrl, 'name': msg.fileName, 'type': mimeType, 'size': msg.fileSize},
        'viewOnce': viewOnce,
      },
    });

    return msg;
  }

  // ── handleIncomingMessage() — mirrors socket.on('receive-message') ─────────
  // Called by the UI layer after receiving from SocketService.receiveMessage stream
  XameMessage incomingFromSocket(Map<String, dynamic> data) {
    final senderId = data['senderId'] as String;
    final m        = data['message']  as Map<String, dynamic>;
    final msg = XameMessage(
      id:          m['id']        ?? _uuid.v4(),
      senderId:    senderId,
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
      fileSize:    m['file']?['size'],
    );
    _addToCache(senderId, msg);
    return msg;
  }

  void emitTyping(String recipientId, {bool enabled = true}) {
    if (!enabled) return;
    _socket.emitTyping(recipientId);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () => _socket.emitStopTyping(recipientId));
  }

  void emitMessageSeen(String senderId, List<String> ids) => _socket.emitMessageSeen(senderId, ids);

  Future<void> saveDraft(String contactId, String text) async {
    text.isEmpty ? _drafts.remove(contactId) : _drafts[contactId] = text;
    await _saveDrafts();
  }

  String? getDraft(String contactId) => _drafts[contactId];

  Future<Map<String, dynamic>?> searchUser(String xameId) async {
    final res  = await _dio.post('/api/search-user', data: {'xameId': xameId.trim()});
    final data = res.data as Map<String, dynamic>;
    return data['success'] == true ? data['user'] as Map<String, dynamic> : null;
  }

  Future<bool> addContact(String selfId, String contactId) async {
    final res  = await _dio.post('/api/add-contact', data: {'userId': selfId, 'contactId': contactId});
    final data = res.data as Map<String, dynamic>;
    if (data['success'] == true) { _socket.emitGetContacts(selfId); return true; }
    return false;
  }

  FileValidation validateFile(File file, String mimeType) {
    final all = [...AppConstants.allowedImageTypes, ...AppConstants.allowedVideoTypes,
                  ...AppConstants.allowedAudioTypes, ...AppConstants.allowedDocumentTypes];
    if (!all.contains(mimeType)) return const FileValidation(isValid: false, error: 'File type not allowed');
    if (file.lengthSync() > AppConstants.maxFileSizeBytes) return const FileValidation(isValid: false, error: 'File exceeds 500MB');
    return const FileValidation(isValid: true, error: null);
  }

  List<XameMessage> getChat(String contactId) => List.unmodifiable(_cache[contactId] ?? []);

  void updateStatus(String contactId, String messageId, String status) {
    final chat = _cache[contactId]; if (chat == null) return;
    final idx  = chat.indexWhere((m) => m.id == messageId);
    if (idx != -1) chat[idx] = chat[idx].copyWith(status: status);
  }

  void deleteMessages(String contactId, List<String> ids) =>
      _cache[contactId]?.removeWhere((m) => ids.contains(m.id));

  void _addToCache(String contactId, XameMessage msg) =>
      _cache.putIfAbsent(contactId, () => []).add(msg);

  Future<void> _saveDrafts() async =>
      await _storage.write(key: AppConstants.keyDrafts, value: jsonEncode(_drafts));

  Future<void> loadDrafts() async {
    final raw = await _storage.read(key: AppConstants.keyDrafts);
    if (raw != null) { try { _drafts.addAll((jsonDecode(raw) as Map).cast<String,String>()); } catch (_) {} }
  }

  Future<String> _selfId() async {
    final raw = await _storage.read(key: AppConstants.keyUser);
    if (raw == null) return '';
    try { return (jsonDecode(raw) as Map<String,dynamic>)['xameId'] as String? ?? ''; } catch (_) { return ''; }
  }

  MessageType _typeFromMime(String m) {
    if (AppConstants.allowedImageTypes.contains(m)) return MessageType.image;
    if (AppConstants.allowedVideoTypes.contains(m)) return MessageType.video;
    if (AppConstants.allowedAudioTypes.contains(m)) return MessageType.audio;
    return MessageType.file;
  }

  MessageType _typeFromFile(Map<String,dynamic> f) => _typeFromMime(f['type'] as String? ?? '');
  void dispose() => _typingTimer?.cancel();
}

class FileValidation {
  final bool    isValid;
  final String? error;
  const FileValidation({required this.isValid, required this.error});
}
