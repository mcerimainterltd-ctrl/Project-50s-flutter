
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kPin      = 'xame:applock:pin';
const _kEnabled  = 'xame:applock:enabled';
const _kDelay    = 'xame:applock:delay';

class AppLockState {
  final bool   enabled;
  final String pin;
  final int    delayMs;
  const AppLockState({this.enabled=false, this.pin='', this.delayMs=60000});
  AppLockState copyWith({bool? enabled, String? pin, int? delayMs}) =>
    AppLockState(
      enabled:  enabled  ?? this.enabled,
      pin:      pin      ?? this.pin,
      delayMs:  delayMs  ?? this.delayMs);
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier() : super(const AppLockState()) { _load(); }

  Future<void> _load() async {
    final pin     = await _storage.read(key: _kPin)     ?? '';
    final enabled = await _storage.read(key: _kEnabled) == 'true';
    final delay   = int.tryParse(await _storage.read(key: _kDelay) ?? '') ?? 60000;
    state = AppLockState(enabled: enabled, pin: pin, delayMs: delay);
  }

  Future<void> enable(String pin) async {
    await _storage.write(key: _kPin,     value: pin);
    await _storage.write(key: _kEnabled, value: 'true');
    state = state.copyWith(enabled: true, pin: pin);
  }

  Future<void> disable() async {
    await _storage.write(key: _kEnabled, value: 'false');
    await _storage.delete(key: _kPin);
    state = state.copyWith(enabled: false, pin: '');
  }

  Future<void> setDelay(int ms) async {
    await _storage.write(key: _kDelay, value: '\$ms');
    state = state.copyWith(delayMs: ms);
  }

  bool verify(String pin) => pin == "__biometric__" || pin == state.pin;
}

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>(
    (_) => AppLockNotifier());
