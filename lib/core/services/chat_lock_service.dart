
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage  = FlutterSecureStorage();
const _kLocks   = 'xame:chat-locks';

class ChatLockNotifier extends StateNotifier<Map<String, String>> {
  ChatLockNotifier() : super({}) { _load(); }

  Future<void> _load() async {
    final raw = await _storage.read(key: _kLocks);
    if (raw != null) state = Map<String, String>.from(jsonDecode(raw));
  }

  Future<void> _save() async =>
    await _storage.write(key: _kLocks, value: jsonEncode(state));

  bool isLocked(String chatId) => state.containsKey(chatId);
  bool verify(String chatId, String pin) => state[chatId] == pin;

  Future<void> setPin(String chatId, String pin) async {
    state = {...state, chatId: pin};
    await _save();
  }

  Future<void> removePin(String chatId) async {
    final next = Map<String, String>.from(state);
    next.remove(chatId);
    state = next;
    await _save();
  }
}

final chatLockProvider = StateNotifierProvider<ChatLockNotifier, Map<String, String>>(
    (_) => ChatLockNotifier());
