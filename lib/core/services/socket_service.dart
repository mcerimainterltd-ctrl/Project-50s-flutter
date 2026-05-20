import "webrtc_service.dart";
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/constants.dart';
import 'package:xamepage/core/services/audio_service.dart';

final socketServiceProvider = Provider<SocketService>((ref) => SocketService());

final socketStateProvider = StreamProvider<SocketState>((ref) {
  return ref.watch(socketServiceProvider).connectionState;
});

enum SocketState { disconnected, connecting, connected, reconnecting, failed }

class SocketService {
  String? currentUserId;
  IO.Socket? _socket;
  int    _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  Timer? _stealthTimer;
  Timer? _offlineTimer;

  final _connectionStateCtrl  = StreamController<SocketState>.broadcast();
  final AudioService _audio = AudioService();
  final _receiveMessageCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _typingCtrl           = StreamController<String>.broadcast();
  final _stopTypingCtrl       = StreamController<String>.broadcast();
  final _msgStatusCtrl        = StreamController<MsgStatusUpdate>.broadcast();
  final _msgSeenCtrl          = StreamController<MsgSeenUpdate>.broadcast();
  final _onlineUsersCtrl      = StreamController<List<String>>.broadcast();
  final _contactsListCtrl     = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _chatHistoryCtrl      = StreamController<dynamic>.broadcast();
  final _incomingCallCtrl     = StreamController<IncomingCallData>.broadcast();
  final _callAnswerCtrl       = StreamController<CallAnswerData>.broadcast();
  final _iceCandidateCtrl     = StreamController<IceCandidateData>.broadcast();
  final _callAcceptedCtrl     = StreamController<String>.broadcast();
  final _callRejectedCtrl     = StreamController<CallRejectedData>.broadcast();
  final _callRingingCtrl      = StreamController<void>.broadcast();
  final _callEndedCtrl        = StreamController<String>.broadcast();
  final _callAcknowledgedCtrl = StreamController<String>.broadcast();
  final _messagesDeletedCtrl  = StreamController<MessagesDeletedData>.broadcast();
  final _disappearExpiredCtrl = StreamController<DisappearExpiredData>.broadcast();
  final _walletReceiveCtrl    = StreamController<WalletReceiveData>.broadcast();
  final _walletDebitCtrl      = StreamController<Map<String,dynamic>>.broadcast();
  final _profileUpdatedCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _contactStatusCtrl    = StreamController<ContactStatusData>.broadcast();
  final _forceLogoutCtrl      = StreamController<String>.broadcast();
  final _missedCallCountCtrl  = StreamController<String>.broadcast();
  final _callUnansweredAckCtrl = StreamController<String>.broadcast();
  final _newDiscoveryPostCtrl = StreamController<String>.broadcast();
  final _reactionUpdateCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _walletRequestCtrl     = StreamController<Map<String, dynamic>>.broadcast();
  final _contactRequestCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _contactRequestAcceptedCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<SocketState>               get connectionState  => _connectionStateCtrl.stream;
  Stream<Map<String, dynamic>>      get receiveMessage   => _receiveMessageCtrl.stream;
  Stream<String>                    get typing           => _typingCtrl.stream;
  Stream<String>                    get stopTyping       => _stopTypingCtrl.stream;
  Stream<MsgStatusUpdate>           get messageStatus    => _msgStatusCtrl.stream;
  Stream<MsgSeenUpdate>             get messageSeen      => _msgSeenCtrl.stream;
  Stream<List<String>>              get onlineUsers      => _onlineUsersCtrl.stream;
  Stream<List<Map<String,dynamic>>> get contactsList     => _contactsListCtrl.stream;
  Stream<dynamic>                   get chatHistory      => _chatHistoryCtrl.stream;
  Stream<String>                    get newDiscoveryPost  => _newDiscoveryPostCtrl.stream;
  Stream<Map<String,dynamic>>       get reactionUpdate   => _reactionUpdateCtrl.stream;
  Stream<IncomingCallData>          get incomingCall     => _incomingCallCtrl.stream;
  Stream<CallAnswerData>            get callAnswer       => _callAnswerCtrl.stream;
  Stream<IceCandidateData>          get iceCandidate     => _iceCandidateCtrl.stream;
  Stream<String>                    get callAccepted     => _callAcceptedCtrl.stream;
  Stream<CallRejectedData>          get callRejected     => _callRejectedCtrl.stream;
  Stream<void>                      get callRinging      => _callRingingCtrl.stream;
  Stream<String>                    get callEnded        => _callEndedCtrl.stream;
  Stream<String>                    get callAcknowledged => _callAcknowledgedCtrl.stream;
  Stream<MessagesDeletedData>       get messagesDeleted  => _messagesDeletedCtrl.stream;
  Stream<DisappearExpiredData>      get disappearExpired => _disappearExpiredCtrl.stream;
  Stream<WalletReceiveData>         get walletReceive    => _walletReceiveCtrl.stream;
  Stream<Map<String,dynamic>>       get walletDebit      => _walletDebitCtrl.stream;
  Stream<Map<String, dynamic>>      get profileUpdated   => _profileUpdatedCtrl.stream;
  Stream<ContactStatusData>         get contactStatus    => _contactStatusCtrl.stream;
  Stream<Map<String, dynamic>>      get walletRequest          => _walletRequestCtrl.stream;
  Stream<Map<String, dynamic>>      get contactRequest         => _contactRequestCtrl.stream;
  Stream<Map<String, dynamic>>      get contactRequestAccepted => _contactRequestAcceptedCtrl.stream;
  Stream<String>                    get forceLogout      => _forceLogoutCtrl.stream;
  Stream<String>                    get missedCallCount  => _missedCallCountCtrl.stream;
  Stream<String>                    get callUnansweredAck => _callUnansweredAckCtrl.stream;
  final _confPeerJoinedCtrl    = StreamController<ConferencePeerData>.broadcast();
  final _confPeerLeftCtrl      = StreamController<ConferencePeerData>.broadcast();
  final _confOfferCtrl         = StreamController<ConferenceSignalData>.broadcast();
  final _confAnswerCtrl        = StreamController<ConferenceSignalData>.broadcast();
  final _confIceCtrl           = StreamController<ConferenceSignalData>.broadcast();
  final _confMicToggleCtrl     = StreamController<ConferenceMicData>.broadcast();
  final _confHandCtrl          = StreamController<ConferenceHandData>.broadcast();
  final _confMutedByHostCtrl   = StreamController<void>.broadcast();
  final _confRemovedByHostCtrl = StreamController<void>.broadcast();
  final _confScreenStartCtrl   = StreamController<ConferenceScreenShareData>.broadcast();
  final _confScreenStopCtrl    = StreamController<void>.broadcast();
  final _confRoomClosedCtrl    = StreamController<void>.broadcast();

  Stream<ConferencePeerData>        get confPeerJoined    => _confPeerJoinedCtrl.stream;
  Stream<ConferencePeerData>        get confPeerLeft      => _confPeerLeftCtrl.stream;
  Stream<ConferenceSignalData>      get confOffer         => _confOfferCtrl.stream;
  Stream<ConferenceSignalData>      get confAnswer        => _confAnswerCtrl.stream;
  Stream<ConferenceSignalData>      get confIce           => _confIceCtrl.stream;
  Stream<ConferenceMicData>         get confMicToggle     => _confMicToggleCtrl.stream;
  Stream<ConferenceHandData>        get confHand          => _confHandCtrl.stream;
  Stream<void>                      get confMutedByHost   => _confMutedByHostCtrl.stream;
  Stream<void>                      get confRemovedByHost => _confRemovedByHostCtrl.stream;
  Stream<ConferenceScreenShareData> get confScreenStart   => _confScreenStartCtrl.stream;
  Stream<void>                      get confScreenStop    => _confScreenStopCtrl.stream;
  Stream<void>                      get confRoomClosed    => _confRoomClosedCtrl.stream;

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get rawSocket => _socket;

  void connect(String xameId, {bool stealth = false}) { currentUserId = xameId;
    if (_socket?.connected == true) {
      debugPrint('✅ Socket already connected for: $xameId');
      return;
    }
    if (_socket != null) {
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket = null;
    }

    debugPrint('🔌 Connecting socket for: $xameId');
    _connectionStateCtrl.add(SocketState.connecting);

    try {
      // Try polling first (more reliable on restricted networks)
      // then upgrade to websocket — mirrors JS: transports: ['polling','websocket']
      _socket = IO.io(
        AppConstants.serverUrl,
        IO.OptionBuilder()
          .setQuery({'userId': xameId})
          .setTransports(['websocket'])
          .setPath('/socket.io/')
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(999999)
          .setTimeout(30000)
          .enableForceNew()
          
          .build(),
      );

      _registerHandlers(_socket!, xameId, stealth: stealth);

    

    } catch (e) {
      debugPrint('❌ Socket error: $e');
      _connectionStateCtrl.add(SocketState.failed);
      _scheduleReconnect(xameId, stealth: stealth);
    }
  }

  void _scheduleReconnect(String xameId, {bool stealth = false}) {
    // Never give up reconnecting — cap delay at 30s
    final delay = min(
      AppConstants.reconnectBaseDelayMs * pow(1.5, _reconnectAttempts),
      30000).toInt();
    _reconnectAttempts++;
    debugPrint('🔄 Reconnecting in ${delay}ms (attempt $_reconnectAttempts)');
    Future.delayed(Duration(milliseconds: delay),
      () => connect(xameId, stealth: stealth));
  }

  void _registerHandlers(IO.Socket socket, String xameId,
      {bool stealth = false}) {

    socket.onConnect((_) {
      debugPrint('✅ Socket connected for: $xameId');
      _reconnectAttempts = 0;
      _connectionStateCtrl.add(SocketState.connected);

      if (stealth) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (socket.connected) emit('user-offline', {'userId': xameId});
        });
      } else {
        emit('user-online', {
          'userId': xameId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Request data after brief delay — mirrors JS setTimeout 100ms
      Future.delayed(const Duration(milliseconds: 200), () {
        if (socket.connected) {
          debugPrint('📡 Requesting contacts and history for: $xameId');
          emit('request_online_users', null);
          emit('get_contacts',         xameId);
          emit('get_chat_history',     {'userId': xameId});
        }
      });
    });

    socket.onConnectError((err) {
      debugPrint('❌ Socket connect error: $err');
      _connectionStateCtrl.add(SocketState.reconnecting);
    });

    socket.onDisconnect((_) {
      debugPrint('🔌 Socket disconnected');
      _offlineTimer?.cancel();
      _offlineTimer = Timer(
        Duration(milliseconds: AppConstants.offlineGracePeriodMs),
        () {
          if (!isConnected) {
            _connectionStateCtrl.add(SocketState.disconnected);
          }
        });
    });

    socket.on('connect_error',     (_) => _connectionStateCtrl.add(SocketState.reconnecting));
    socket.on('reconnect_attempt', (_) => _connectionStateCtrl.add(SocketState.reconnecting));
    socket.on('reconnect_failed',  (_) => _connectionStateCtrl.add(SocketState.failed));

    socket.on('reconnect', (_) {
      _reconnectAttempts = 0;
      _offlineTimer?.cancel();
      _connectionStateCtrl.add(SocketState.connected);
      debugPrint('🔄 Reconnected for: $xameId');
      if (!stealth) {
        emit('user-online', {
          'userId': xameId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      emit('request_online_users', null);
      emit('get_contacts',         xameId);
      emit('get_chat_history',     {'userId': xameId});
    });

    // ── Messaging ─────────────────────────────────────────────────────────
    socket.on('receive-message', (d) {
      if (d != null) {
        _receiveMessageCtrl.add(Map<String,dynamic>.from(d));
        _audio.playMessage();
      }
    });
    socket.on('typing', (d) {
      final s = d?['senderId'] as String?;
      if (s != null) _typingCtrl.add(s);
    });
    socket.on('stop-typing', (d) {
      final s = d?['senderId'] as String?;
      if (s != null) _stopTypingCtrl.add(s);
    });
    socket.on('message-status-update', (d) {
      if (d != null) _msgStatusCtrl.add(MsgStatusUpdate(
        recipientId: d['recipientId'],
        messageId:   d['messageId'],
        status:      d['status']));
    });
    socket.on('message-seen-update', (d) {
      if (d != null) _msgSeenCtrl.add(MsgSeenUpdate(
        recipientId: d['recipientId'],
        messageIds:  List<String>.from(d['messageIds'] ?? [])));
    });

    // ── Contacts / presence ───────────────────────────────────────────────
    socket.on('online_users', (d) {
      debugPrint('📡 online_users received: $d');
      _onlineUsersCtrl.add(List<String>.from(d ?? []));
    });
    socket.on('contacts_list', (d) {
      debugPrint('📡 contacts_list received: ${d?.length ?? 0} contacts');
      if (d == null || d is! List) return;
      _contactsListCtrl.add(List<Map<String,dynamic>>.from(
        (d as List).map((c) => Map<String,dynamic>.from(c))));
    });
    socket.on('chat_history', (d) {
      debugPrint('📡 chat_history received');
      _chatHistoryCtrl.add(d);
    });
    socket.on('contact-status-update', (d) {
      if (d != null) _contactStatusCtrl.add(ContactStatusData(
        userId: d['userId'],
        status: '${d['status']?['emoji'] ?? ''} ${d['status']?['message'] ?? ''}'.trim()));
    });
    socket.on('wallet_request', (d) {
      if (d != null) _walletRequestCtrl.add(Map<String, dynamic>.from(d));
    });
    socket.on('contact_request', (d) {
      if (d != null) _contactRequestCtrl.add(Map<String, dynamic>.from(d));
    });
    socket.on('contact_request_accepted', (d) {
      if (d != null) _contactRequestAcceptedCtrl.add(Map<String, dynamic>.from(d));
    });
    socket.on('profile-updated', (d) {
      if (d != null) _profileUpdatedCtrl.add(Map<String,dynamic>.from(d));
    });
    socket.on('new_missed_call_count', (d) {
      final s = d?['senderId'] as String?;
      if (s != null) _missedCallCountCtrl.add(s);
    });
    socket.on('messages-deleted', (d) {
      if (d != null) _messagesDeletedCtrl.add(MessagesDeletedData(
        deleterId:   d['deleterId'],
        contactId:   d['contactId'],
        messageIds:  List<String>.from(d['messageIds'] ?? []),
        permanently: d['permanently'] ?? false));
    });
    socket.on('disappearing:expired', (d) {
      if (d != null) _disappearExpiredCtrl.add(DisappearExpiredData(
        messageId: d['messageId'], contactId: d['contactId']));
    });

    // ── Calls ─────────────────────────────────────────────────────────────
    socket.on('call-user', (d) {
      if (d != null) _incomingCallCtrl.add(IncomingCallData(
        offer:    d['offer'],
        callerId: d['callerId'],
        caller:   Map<String,dynamic>.from(d['caller'] ?? {}),
        callType: d['callType'] ?? 'voice',
        callId:   d['callId']));
    });
    socket.on('make-answer', (d) {
      if (d != null) _callAnswerCtrl.add(
        CallAnswerData(answer: d['answer'], senderId: d['senderId']));
    });
    socket.on('ice-candidate', (d) {
      if (d != null) _iceCandidateCtrl.add(
        IceCandidateData(candidate: d['candidate'], senderId: d['senderId']));
    });
    socket.on('call-accepted', (d) {
      if (d?['recipientId'] != null) _callAcceptedCtrl.add(d['recipientId']);
    });
    socket.on('call-ringing', (d) => _callRingingCtrl.add(null));
    socket.on('call-rejected', (d) => _callRejectedCtrl.add(
      CallRejectedData(senderId: d?['senderId'],
        reason: d?['reason'] ?? 'user-rejected')));
    socket.on('call-acknowledged', (d) {
      if (d?['senderId'] != null) _callAcknowledgedCtrl.add(d['senderId']);
    });
    socket.on('call-ended', (d) => _callEndedCtrl.add(d?['senderId'] ?? ''));
    socket.on('call-unanswered-ack', (d) => _callUnansweredAckCtrl.add(d?['recipientId'] ?? ''));

    // ── Wallet ────────────────────────────────────────────────────────────
    socket.on('wallet:debit', (d) {
      if (d != null) _walletDebitCtrl.add(Map<String,dynamic>.from(d));
    });
    socket.on('wallet:receive', (d) {
      if (d != null) _walletReceiveCtrl.add(WalletReceiveData(
        senderId:   d['senderId'],
        senderName: d['senderName'],
        amount:     (d['amount'] as num).toDouble(),
        currency:   d['currency'] ?? 'USD'));
    });

    // ── Force logout ──────────────────────────────────────────────────────
    socket.on('reaction:update', (d) {
      if (d != null) _reactionUpdateCtrl.add(Map<String,dynamic>.from(d as Map));
    });

    socket.on('new_discovery_post', (d) {
      final authorId = d?['authorId'] as String? ?? '';
      if (authorId.isNotEmpty) _newDiscoveryPostCtrl.add(authorId);
    });

    socket.on('force-logout', (d) =>
      _forceLogoutCtrl.add(d?['reason'] ?? 'Logged out remotely.'));

    // ── Conference ────────────────────────────────────────────────────────
    socket.on("conference:peer-joined", (d) {
      if (d != null) _confPeerJoinedCtrl.add(ConferencePeerData(
        peerId: d["peerId"] ?? "", displayName: d["displayName"] ?? ""));
    });
    socket.on("conference:peer-left", (d) {
      if (d != null) _confPeerLeftCtrl.add(ConferencePeerData(
        peerId: d["peerId"] ?? "", displayName: d["displayName"] ?? ""));
    });
    socket.on("conference:offer", (d) {
      if (d != null) _confOfferCtrl.add(ConferenceSignalData(
        from: d["from"] ?? "", payload: Map<String,dynamic>.from(d)));
    });
    socket.on("conference:answer", (d) {
      if (d != null) _confAnswerCtrl.add(ConferenceSignalData(
        from: d["from"] ?? "", payload: Map<String,dynamic>.from(d)));
    });
    socket.on("conference:ice", (d) {
      if (d != null) _confIceCtrl.add(ConferenceSignalData(
        from: d["from"] ?? "", payload: Map<String,dynamic>.from(d)));
    });
    socket.on("conference:mic-toggle", (d) {
      if (d != null) _confMicToggleCtrl.add(ConferenceMicData(
        userId: d["userId"] ?? "", muted: d["muted"] ?? false));
    });
    socket.on("conference:raise-hand", (d) {
      if (d != null) _confHandCtrl.add(ConferenceHandData(
        userId: d["userId"] ?? "", raised: d["raised"] ?? false));
    });
    socket.on("conference:muted-by-host",    (_) => _confMutedByHostCtrl.add(null));
    socket.on("conference:removed-by-host",  (_) => _confRemovedByHostCtrl.add(null));
    socket.on("conference:screen-share-started", (d) => _confScreenStartCtrl.add(
      ConferenceScreenShareData(userId: d?["userId"])));
    socket.on("conference:screen-share-stopped", (_) => _confScreenStopCtrl.add(null));
    socket.on("conference:room-closed",      (_) => _confRoomClosedCtrl.add(null));
  }

  void emit(String event, dynamic data) {
    if (data != null) _socket?.emit(event, data);
    else _socket?.emit(event);
  }

  // ── Emit helpers ──────────────────────────────────────────────────────────
  void emitTyping(String r)                        => emit('typing',             {'recipientId': r});
  void emitStopTyping(String r)                    => emit('stop-typing',        {'recipientId': r});
  void emitMessageSeen(String r, List<String> ids) => emit('message-seen',       {'recipientId': r, 'messageIds': ids});
  void emitGetContacts(String id)                  => emit('get_contacts',        id);
  void emitGetChatHistory(String id)               => emit('get_chat_history',   {'userId': id});
  void emitRequestOnlineUsers()                    => emit('request_online_users', null);
  void emitUserOnline(String id)                   => emit('user-online',        {'userId': id, 'timestamp': DateTime.now().millisecondsSinceEpoch});
  void emitUserOffline(String id)                  => emit('user-offline',       {'userId': id});
  void emitHeartbeat(String id)                    => emit('heartbeat',          {'userId': id, 'timestamp': DateTime.now().millisecondsSinceEpoch});
  void emitCallRingingAck(String callerId)         => emit('call-ringing-ack',   {'callerId': callerId});
  void emitCallUser(String r, dynamic o, String t) => emit('call-user',          {'recipientId': r, 'offer': o, 'callType': t});

  // Listen for callId assigned by server after emitting call-user
  void onCallInitiated(void Function(String callId) cb) {
    _socket?.off('call-initiated');
    _socket?.on('call-initiated', (d) => cb(d['callId'] ?? ''));
  }
  void emitMakeAnswer(String r, dynamic a)         => emit('make-answer',        {'recipientId': r, 'answer': a});
  void emitIceCandidate(String r, dynamic c)       => emit('ice-candidate',      {'recipientId': r, 'candidate': c});
  void emitCallAccepted(String r, {String? callId})=> emit('call-accepted',      {'recipientId': r, if (callId != null) 'callId': callId});
  void emitCallRejected(String r, String reason)   => emit('call-rejected',      {'recipientId': r, 'reason': reason});
  void emitCallEnded(String r)                     => emit('call-ended',         {'recipientId': r});
  void emitGroupTyping(String g, String u, String n)=> emit('group:typing',      {'groupId': g, 'userId': u, 'name': n});
  void emitReactionToggle(String messageId, String emoji, String userId) => emit('reaction:toggle', {'messageId': messageId, 'emoji': emoji, 'userId': userId});
  void emitMarkDiscoverySeen(String authorId) => emit('mark_discovery_seen', {'authorId': authorId});
  void emitDisappearingTimer(String contactId, String userId, String value) => emit("disappearing:timer-set", {"contactId": contactId, "userId": userId, "value": value});

  void startHeartbeat(String xameId, {bool stealth = false}) {
    stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.heartbeatIntervalMs),
      (_) { if (isConnected && !stealth) emitHeartbeat(xameId); });
    if (isConnected && !stealth) emitHeartbeat(xameId);
  }

  void stopHeartbeat() { _heartbeatTimer?.cancel(); _heartbeatTimer = null; }

  void startStealthMode(String xameId) {
    stopStealthMode();
    if (isConnected) emitUserOffline(xameId);
    _stealthTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.stealthHeartbeatMs),
      (_) { if (isConnected) emitUserOffline(xameId); });
  }

  void stopStealthMode() { _stealthTimer?.cancel(); _stealthTimer = null; }

  void disconnect() {
    stopHeartbeat(); stopStealthMode(); _offlineTimer?.cancel();
    _socket?.clearListeners(); _socket?.disconnect(); _socket = null;
    _connectionStateCtrl.add(SocketState.disconnected);
  }
}

// ── Data classes ───────────────────────────────────────────────────────────
class MsgStatusUpdate {
  final String recipientId, messageId, status;
  const MsgStatusUpdate({required this.recipientId, required this.messageId, required this.status});
}
class MsgSeenUpdate {
  final String recipientId; final List<String> messageIds;
  const MsgSeenUpdate({required this.recipientId, required this.messageIds});
}
class IncomingCallData {
  final dynamic offer; final String callerId, callType;
  final String? callId; final Map<String,dynamic> caller;
  const IncomingCallData({required this.offer, required this.callerId,
    required this.caller, required this.callType, this.callId});
}
class CallAnswerData {
  final dynamic answer; final String senderId;
  const CallAnswerData({required this.answer, required this.senderId});
}
class IceCandidateData {
  final dynamic candidate; final String senderId;
  const IceCandidateData({required this.candidate, required this.senderId});
}
class CallRejectedData {
  final String? senderId; final String reason;
  const CallRejectedData({this.senderId, required this.reason});
}
class MessagesDeletedData {
  final String deleterId, contactId;
  final List<String> messageIds; final bool permanently;
  const MessagesDeletedData({required this.deleterId, required this.contactId,
    required this.messageIds, required this.permanently});
}
class DisappearExpiredData {
  final String messageId; final String? contactId;
  const DisappearExpiredData({required this.messageId, this.contactId});
}
class WalletReceiveData {
  final String senderId, currency; final String? senderName; final double amount;
  const WalletReceiveData({required this.senderId, this.senderName,
    required this.amount, required this.currency});
  static const _sym = {'NGN':'₦','GHS':'GH₵','KES':'KSh','ZAR':'R','USD':'\$','EUR':'€','GBP':'£'};
  String get symbol => _sym[currency] ?? '$currency ';
}
class ContactStatusData {
  final String userId, status;
  const ContactStatusData({required this.userId, required this.status});
}

// ── Conference data classes ───────────────────────────────────────────────────
class ConferencePeerData {
  final String peerId, displayName;
  const ConferencePeerData({required this.peerId, required this.displayName});
}
class ConferenceSignalData {
  final String from; final Map<String, dynamic> payload;
  const ConferenceSignalData({required this.from, required this.payload});
}
class ConferenceMicData {
  final String userId; final bool muted;
  const ConferenceMicData({required this.userId, required this.muted});
}
class ConferenceHandData {
  final String userId; final bool raised;
  const ConferenceHandData({required this.userId, required this.raised});
}
class ConferenceScreenShareData {
  final String? userId;
  const ConferenceScreenShareData({this.userId});
}
