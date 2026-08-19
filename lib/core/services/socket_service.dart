import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  Timer? _heartbeatTimer;

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get rawSocket => _socket;

  void init(String serverUrl, String xameId, {bool stealth = false}) {
    if (_socket != null) {
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket = null;
    }

    _socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setExtraHeaders({'x-user-id': xameId})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected');
      if (!stealth) {
        emitUserOnline(xameId);
      }
      emitRequestOnlineUsers();
      startHeartbeat(xameId, stealth: stealth);
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
      _heartbeatTimer?.cancel();
    });
  }

  void emit(String event, [dynamic data]) {
    if (_socket != null && _socket!.connected) {
      if (data != null) {
        _socket!.emit(event, data);
      } else {
        _socket!.emit(event);
      }
    }
  }

  void emitUserOnline(String id)                   => emit('user-online',          {'userId': id});
  void emitRequestOnlineUsers()                    => emit('request_online_users', null);
  void emitStealthUpdate(String userId, bool enabled) => emit('stealth-update', {'userId': userId, 'enabled': enabled});
  void emitStatusUpdate(String userId, String emoji, String message) => emit('status-update', {'userId': userId, 'status': {'emoji': emoji, 'message': message}});
  void emitTyping(String r)                        => emit('typing',             {'recipientId': r});
  void emitStopTyping(String r)                    => emit('stop-typing',        {'recipientId': r});
  void emitMessageSeen(String r, List<String> ids) => emit('message-seen',       {'recipientId': r, 'messageIds': ids});
  void emitGetContacts(String id)                  => emit('get_contacts',        id);
  void emitGetChatHistory(String id)               => emit('get_chat_history',   {'userId': id});
  void emitUserOffline(String id)                  => emit('user-offline',       {'userId': id});
  void emitHeartbeat(String id)                    => emit('heartbeat',          {'userId': id, 'timestamp': DateTime.now().millisecondsSinceEpoch});
  void emitCallRingingAck(String callerId)         => emit('call-ringing-ack',   {'callerId': callerId});
  void emitCallUser(String r, dynamic o, String t) => emit('call-user',          {'recipientId': r, 'offer': o, 'callType': t});
  void emitMakeAnswer(String r, dynamic a)         => emit('make-answer',        {'recipientId': r, 'answer': a});
  void emitIceCandidate(String r, dynamic c)       => emit('ice-candidate',      {'recipientId': r, 'candidate': c});
  void emitCallAccepted(String r, {String? callId})=> emit('call-accepted',      {'recipientId': r, if (callId != null) 'callId': callId});
  void emitCallRejected(String r, String reason)   => emit('call-rejected',      {'recipientId': r, 'reason': reason});
  void emitCallEnded(String r, {String? callId})   => emit('call-ended',         {'recipientId': r, if (callId != null) 'callId': callId});
  void emitCallHold(String r)                      => emit('call-hold',          {'recipientId': r});
  void emitCallResume(String r)                    => emit('call-resume',        {'recipientId': r});
  void emitGroupTyping(String g, String u, String n)=> emit('group:typing',      {'groupId': g, 'userId': u, 'name': n});
  void emitReactionToggle(String messageId, String emoji, String userId) => emit('reaction:toggle', {'messageId': messageId, 'emoji': emoji, 'userId': userId});
  void emitMarkDiscoverySeen(String id)            => emit('discovery-seen',     {'id': id});

  void startHeartbeat(String xameId, {bool stealth = false}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (isConnected && !stealth) {
        emitHeartbeat(xameId);
      }
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
