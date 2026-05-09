// CacheService — Hive-backed persistence for contacts, chats, call history
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../shared/models/message.dart';

class CacheService {
  static const _boxContacts    = 'xame_contacts';
  static const _boxChats       = 'xame_chats';
  static const _boxCallHistory = 'xame_call_history';

  // ── Open all boxes ────────────────────────────────────────────────────
  static Future<void> init() async {
    await Hive.openBox<String>(_boxContacts);
    await Hive.openBox<String>(_boxChats);
    await Hive.openBox<String>(_boxCallHistory);
    await Hive.openBox<bool>('xame_discovery_likes');
    await Hive.openBox<String>(_boxDiscovery);
    await Hive.openBox<String>(_boxPhoneRecents);
    await Hive.openBox<String>(_boxDevContacts);
  }

  // ── Contacts ──────────────────────────────────────────────────────────
  static Box<String> get _contacts => Hive.box<String>(_boxContacts);

  static Future<void> saveContacts(List<Map<String, dynamic>> contacts) async {
    await _contacts.put('list', jsonEncode(contacts));
  }

  static List<Map<String, dynamic>> loadContacts() {
    final raw = _contacts.get('list');
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    } catch (_) { return []; }
  }

  // ── Chat messages ─────────────────────────────────────────────────────
  static Box<String> get _chats => Hive.box<String>(_boxChats);

  static Future<void> saveChat(
      String contactId, List<XameMessage> messages) async {
    final data = messages.map((m) => {
      'id':          m.id,
      'senderId':    m.senderId,
      'recipientId': m.recipientId,
      'text':        m.text,
      'type':        m.type.index,
      'direction':   m.direction.index,
      'ts':          m.ts,
      'status':      m.status,
      'forwarded':   m.forwarded,
      'viewOnce':    m.viewOnce,
      'expiresAt':   m.expiresAt,
      'replyToId':   m.replyToId,
      'replyToText': m.replyToText,
      'fileUrl':     m.fileUrl,
      'fileName':    m.fileName,
      'fileMime':    m.fileMime,
      'reactions':   m.reactions,
    }).toList();
    // Keep last 100 messages per contact
    final trimmed = data.length > 100 ? data.sublist(data.length - 100) : data;
    await _chats.put(contactId, jsonEncode(trimmed));
  }

  static List<XameMessage> loadChat(String contactId) {
    final raw = _chats.get(contactId);
    if (raw == null) return [];
    try {
      final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
      final now = DateTime.now().millisecondsSinceEpoch;
      return list
        .where((m) =>
          m['expiresAt'] == null || (m['expiresAt'] as int) > now)
        .map((m) => XameMessage(
          id:          m['id']          as String,
          senderId:    m['senderId']    as String,
          recipientId: m['recipientId'] as String,
          text:        m['text']        as String,
          type:        MessageType.values[m['type'] as int],
          direction:   MessageDirection.values[m['direction'] as int],
          ts:          m['ts']          as int,
          status:      m['status']      as String,
          forwarded:   m['forwarded']   as bool? ?? false,
          viewOnce:    m['viewOnce']    as bool? ?? false,
          expiresAt:   m['expiresAt']   as int?,
          replyToId:   m['replyToId']   as String?,
          replyToText: m['replyToText'] as String?,
          fileUrl:     m['fileUrl']     as String?,
          fileName:    m['fileName']    as String?,
          fileMime:    m['fileMime']    as String?,
          reactions:   m['reactions'] != null
            ? Map<String,String>.from(m['reactions'] as Map) : null,
        ))
        .toList();
    } catch (_) { return []; }
  }

  // ── Call history ──────────────────────────────────────────────────────
  static Box<String> get _calls => Hive.box<String>(_boxCallHistory);

  static Future<void> saveCallHistory(
      List<Map<String, dynamic>> calls) async {
    await _calls.put('list', jsonEncode(calls));
  }

  static List<Map<String, dynamic>> loadCallHistory() {
    final raw = _calls.get('list');
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    } catch (_) { return []; }
  }

  static Future<void> addCallRecord(Map<String, dynamic> record) async {
    final existing = loadCallHistory();
    existing.insert(0, record);
    // Keep last 200 call records
    final trimmed = existing.length > 200
      ? existing.sublist(0, 200) : existing;
    await _calls.put('list', jsonEncode(trimmed));
  }

  static Future<void> clearCallHistory() async {
    await _calls.put('list', jsonEncode([]));
  }

  // ── Full wipe on logout ───────────────────────────────────────────────
  static Future<void> clearAll() async {
    await _contacts.clear();
    await _chats.clear();
    await _calls.clear();
    if (Hive.isBoxOpen('xame_discovery_likes'))
      await Hive.box<bool>('xame_discovery_likes').clear();
    if (Hive.isBoxOpen(_boxDiscovery))
      await Hive.box<String>(_boxDiscovery).clear();
    if (Hive.isBoxOpen(_boxPhoneRecents))
      await Hive.box<String>(_boxPhoneRecents).clear();
    if (Hive.isBoxOpen(_boxDevContacts))
      await Hive.box<String>(_boxDevContacts).clear();
  }

  // ── Discovery feed cache ──────────────────────────────────────────────
  static const _boxDiscovery = 'xame_discovery_cache';

  static Future<void> initDiscovery() async {
    if (!Hive.isBoxOpen(_boxDiscovery))
      await Hive.openBox<String>(_boxDiscovery);
  }

  static Future<void> saveDiscoveryFeed(
      String region, List<Map<String,dynamic>> items) async {
    await initDiscovery();
    final box = Hive.box<String>(_boxDiscovery);
    final trimmed = items.length > 50 ? items.sublist(0, 50) : items;
    await box.put('feed_$region', jsonEncode(trimmed));
  }

  static List<Map<String,dynamic>> loadDiscoveryFeed(String region) {
    if (!Hive.isBoxOpen(_boxDiscovery)) return [];
    final box = Hive.box<String>(_boxDiscovery);
    final raw = box.get('feed_$region');
    if (raw == null) return [];
    try {
      return List<Map<String,dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)));
    } catch (_) { return []; }
  }

  static Future<void> saveDiscoveryPeople(
      List<Map<String,dynamic>> people) async {
    await initDiscovery();
    final box = Hive.box<String>(_boxDiscovery);
    await box.put('people', jsonEncode(people));
  }

  static List<Map<String,dynamic>> loadDiscoveryPeople() {
    if (!Hive.isBoxOpen(_boxDiscovery)) return [];
    final box = Hive.box<String>(_boxDiscovery);
    final raw = box.get('people');
    if (raw == null) return [];
    try {
      return List<Map<String,dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)));
    } catch (_) { return []; }
  }

  // ── Phone recents ─────────────────────────────────────────────────────
  static const _boxPhoneRecents = 'xame_phone_recents';
  static Box<String> get _phoneRecents => Hive.box<String>(_boxPhoneRecents);

  static Future<void> initPhoneRecents() async {
    if (!Hive.isBoxOpen(_boxPhoneRecents)) {
      await Hive.openBox<String>(_boxPhoneRecents);
    }
  }

  static Future<void> savePhoneRecents(List<Map<String,dynamic>> recents) async {
    await initPhoneRecents();
    final trimmed = recents.length > 100 ? recents.sublist(0, 100) : recents;
    await _phoneRecents.put('list', jsonEncode(trimmed));
  }


  // ── Device contacts cache ─────────────────────────────────────────────────
  static const _boxDevContacts = 'xame_device_contacts';

  static Future<void> saveDevContacts(List<Map<String,dynamic>> contacts) async {
    final box = Hive.box<String>(_boxDevContacts);
    await box.put('list', jsonEncode(contacts));
  }

  static List<Map<String,dynamic>> loadDevContacts() {
    if (!Hive.isBoxOpen(_boxDevContacts)) return [];
    final box = Hive.box<String>(_boxDevContacts);
    final raw = box.get('list');
    if (raw == null) return [];
    try {
      return List<Map<String,dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)));
    } catch (_) { return []; }
  }

  static List<Map<String,dynamic>> loadPhoneRecents() {
    if (!Hive.isBoxOpen(_boxPhoneRecents)) return [];
    final raw = _phoneRecents.get('list');
    if (raw == null) return [];
    try {
      return List<Map<String,dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)));
    } catch (_) { return []; }
  }
}
