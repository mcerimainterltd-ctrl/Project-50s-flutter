
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/cache_service.dart';

final activeContactIdProvider = StateProvider<String?>((ref) => null);

class ContactModel {
  final String id, name;
  final String? profilePic, personalStatusEmoji, personalStatusMessage;
  final bool   isOnline, isProfilePicHidden;
  final int    unreadCount, missedCallsCount, lastInteractionTs;
  final String lastInteractionPreview;

  const ContactModel({
    required this.id, required this.name,
    this.profilePic, this.personalStatusEmoji, this.personalStatusMessage,
    this.isOnline = false, this.isProfilePicHidden = false,
    this.unreadCount = 0, this.missedCallsCount = 0,
    this.lastInteractionTs = 0, this.lastInteractionPreview = '',
  });

  factory ContactModel.fromSocketMap(Map<String, dynamic> m,
      {int? existingUnread, int? existingMissed}) =>
    ContactModel(
      id:                     m['xameId']              as String,
      name:                   m['name']                as String? ?? m['xameId'] as String,
      profilePic:             m['profilePic']          as String?,
      isOnline:               m['isOnline']            as bool? ?? false,
      isProfilePicHidden:     m['isProfilePicHidden']  as bool? ?? false,
      unreadCount:            existingUnread ?? (m['unreadMessagesCount'] as int? ?? 0),
      missedCallsCount:       existingMissed ?? (m['missedCallsCount']    as int? ?? 0),
      lastInteractionTs:      m['lastInteractionTs']      as int? ?? 0,
      lastInteractionPreview: m['lastInteractionPreview'] as String? ?? '',
      personalStatusEmoji:    m['personalStatus']?['emoji']   as String?,
      personalStatusMessage:  m['personalStatus']?['message'] as String?,
    );

  ContactModel copyWith({
    bool? isOnline, int? unreadCount, int? missedCallsCount,
    String? lastInteractionPreview, int? lastInteractionTs,
    String? name, String? profilePic, bool? isProfilePicHidden,
  }) => ContactModel(
    id: id,
    name:                   name                   ?? this.name,
    profilePic:             profilePic             ?? this.profilePic,
    isOnline:               isOnline               ?? this.isOnline,
    isProfilePicHidden:     isProfilePicHidden     ?? this.isProfilePicHidden,
    unreadCount:            unreadCount            ?? this.unreadCount,
    missedCallsCount:       missedCallsCount       ?? this.missedCallsCount,
    lastInteractionTs:      lastInteractionTs      ?? this.lastInteractionTs,
    lastInteractionPreview: lastInteractionPreview ?? this.lastInteractionPreview,
    personalStatusEmoji:    personalStatusEmoji,
    personalStatusMessage:  personalStatusMessage,
  );
}

final typingProvider = StateProvider<Set<String>>((ref) => {});

class ContactsNotifier extends AsyncNotifier<List<ContactModel>> {
  final List<StreamSubscription> _subs = [];
  final _dio = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  @override
  Future<List<ContactModel>> build() async {
    _listenToSocket();
    ref.onDispose(() { for (final s in _subs) s.cancel(); });
    // Load cached contacts instantly — show UI before socket responds
    final cached = CacheService.loadContacts();
    if (cached.isNotEmpty) {
      state = AsyncData(cached.map((m) =>
        ContactModel.fromSocketMap(m)).toList());
    }
    // Request fresh data from socket
    _requestContacts();
    return state.valueOrNull ?? [];
  }

  // Request contacts — called on build and after addContact
  void _requestContacts() {
    final socket = ref.read(socketServiceProvider);
    final user   = ref.read(currentUserProvider);
    if (user == null) return;

    if (socket.isConnected) {
      // Already connected — request immediately
      socket.emitGetContacts(user.xameId);
      socket.emitGetChatHistory(user.xameId);
      socket.emitRequestOnlineUsers();
    } else {
      // Not connected yet — listen for connection then request
      late StreamSubscription sub;
      sub = socket.connectionState.listen((state) {
        if (state == SocketState.connected) {
          Future.delayed(const Duration(milliseconds: 300), () {
            socket.emitGetContacts(user.xameId);
            socket.emitGetChatHistory(user.xameId);
            socket.emitRequestOnlineUsers();
          });
          sub.cancel();
        }
      });
      _subs.add(sub);
    }
  }

  void _listenToSocket() {
    final socket = ref.read(socketServiceProvider);

    // contacts_list — server sends after get_contacts
    _subs.add(socket.contactsList.listen((list) {
      if (list.isEmpty) {
        // Empty list — keep existing or stay empty
        if (state.valueOrNull?.isEmpty ?? true) state = const AsyncData([]);
        return;
      }
      final current = state.valueOrNull ?? [];
      final updated = list.map((m) {
        final existing = current.where((c) => c.id == m['xameId']).firstOrNull;
        return ContactModel.fromSocketMap(m,
          existingUnread: existing?.unreadCount,
          existingMissed: existing?.missedCallsCount);
      }).toList();

      // Add self contact if missing
      final self = ref.read(currentUserProvider);
      if (self != null && !updated.any((c) => c.id == self.xameId)) {
        updated.insert(0, ContactModel(
          id: self.xameId,
          name: '${self.firstName} ${self.lastName} (You)',
          profilePic: self.profilePic, isOnline: true,
          lastInteractionTs: DateTime.now().millisecondsSinceEpoch,
          lastInteractionPreview: 'Message yourself',
        ));
      }
      state = AsyncData(updated);
      // Persist to Hive for instant load next time
      CacheService.saveContacts(list.map((m) =>
        Map<String,dynamic>.from(m)).toList());
    }));

    // online_users
    _subs.add(socket.onlineUsers.listen((ids) {
      final current = state.valueOrNull; if (current == null) return;
      final self = ref.read(currentUserProvider);
      state = AsyncData(current.map((c) =>
        c.copyWith(isOnline: ids.contains(c.id) || c.id == self?.xameId)
      ).toList());
    }));

    // receive-message — update preview + unread
    _subs.add(socket.receiveMessage.listen((data) {
      final senderId = data['senderId'] as String?;
      final message  = data['message']  as Map<String, dynamic>?;
      if (senderId == null || message == null) return;
      final current  = state.valueOrNull ?? [];
      final activeId = ref.read(activeContactIdProvider);
      state = AsyncData(current.map((c) {
        if (c.id != senderId) return c;
        return c.copyWith(
          lastInteractionTs:      message['ts'] as int? ??
            DateTime.now().millisecondsSinceEpoch,
          lastInteractionPreview: message['text'] as String? ?? 'Attachment',
          unreadCount: activeId == senderId ? 0 : c.unreadCount + 1,
        );
      }).toList());
    }));

    // typing / stop-typing
    _subs.add(socket.typing.listen((id) {
      final t = Set<String>.from(ref.read(typingProvider))..add(id);
      ref.read(typingProvider.notifier).state = t;
    }));
    _subs.add(socket.stopTyping.listen((id) {
      final t = Set<String>.from(ref.read(typingProvider))..remove(id);
      ref.read(typingProvider.notifier).state = t;
    }));

    // profile-updated
    _subs.add(socket.profileUpdated.listen((data) {
      final userId = data['userId'] as String?; if (userId == null) return;
      final current = state.valueOrNull ?? [];
      state = AsyncData(current.map((c) {
        if (c.id != userId) return c;
        return c.copyWith(
          profilePic: data['profilePic'] as String? ?? c.profilePic,
          name: (data['preferredName'] != null && data['preferredName'] != '')
            ? data['preferredName'] as String : c.name,
          isProfilePicHidden:
            data['hideProfilePicture'] as bool? ?? c.isProfilePicHidden,
        );
      }).toList());
    }));

    // missed call count
    _subs.add(socket.missedCallCount.listen((senderId) {
      final current = state.valueOrNull ?? [];
      state = AsyncData(current.map((c) =>
        c.id == senderId
          ? c.copyWith(missedCallsCount: c.missedCallsCount + 1) : c
      ).toList());
    }));
  }

  void markRead(String contactId) {
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((c) =>
      c.id == contactId ? c.copyWith(unreadCount: 0) : c
    ).toList());
  }

  void clearAllMissedCalls() {
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((c) =>
      c.missedCallsCount > 0 ? c.copyWith(missedCallsCount: 0) : c
    ).toList());
  }

  Future<Map<String, dynamic>?> searchUser(String xameId) async {
    try {
      final res  = await _dio.post('/api/search-user',
        data: {'xameId': xameId.trim()});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return null;
      return data['user'] as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  Future<void> addContact(String selfId, String contactId) async {
    try {
      final res  = await _dio.post('/api/add-contact',
        data: {'userId': selfId, 'contactId': contactId});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        // Add contact directly from API response — no need to wait for socket
        final c = data['contact'] as Map<String, dynamic>?;
        if (c != null) {
          final current = state.valueOrNull ?? [];
          if (!current.any((x) => x.id == c['xameId'])) {
            state = AsyncData([
              ...current,
              ContactModel(
                id:        c['xameId'] as String,
                name:      c['name']   as String? ?? c['xameId'] as String,
                profilePic: c['profilePic'] as String?,
                isOnline:  c['isOnline'] as bool? ?? false,
              ),
            ]);
          }
        }
        // Also refresh via socket
        ref.read(socketServiceProvider).emitGetContacts(selfId);
      }
    } catch (_) {}
  }

  Future<void> deleteContact(String selfId, String contactId) async {
    try {
      await _dio.post('/api/delete-chat-and-contact',
        data: {'userId': selfId, 'contactId': contactId});
      final current = state.valueOrNull ?? [];
      state = AsyncData(current.where((c) => c.id != contactId).toList());
    } catch (_) {}
  }

  Future<void> updateContactName(
      String selfId, String contactId, String newName) async {
    try {
      final res  = await _dio.post('/api/update-contact',
        data: {'userId': selfId, 'contactId': contactId, 'newName': newName});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final current = state.valueOrNull ?? [];
        state = AsyncData(current.map((c) =>
          c.id == contactId
            ? c.copyWith(name: data['updatedName'] as String? ?? newName)
            : c
        ).toList());
      }
    } catch (_) {}
  }
}

final contactsProvider =
  AsyncNotifierProvider<ContactsNotifier, List<ContactModel>>(
    ContactsNotifier.new);
