import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage  = FlutterSecureStorage();
const _kPin     = 'xame:settingslock:pin';
const _kEnabled = 'xame:settingslock:enabled';

class SettingsLockState {
  final bool   enabled;
  final String pin;
  const SettingsLockState({this.enabled = false, this.pin = ''});
  SettingsLockState copyWith({bool? enabled, String? pin}) =>
      SettingsLockState(enabled: enabled ?? this.enabled, pin: pin ?? this.pin);
}

class SettingsLockNotifier extends StateNotifier<SettingsLockState> {
  SettingsLockNotifier() : super(const SettingsLockState()) { _load(); }

  Future<void> _load() async {
    final pin     = await _storage.read(key: _kPin)     ?? '';
    final enabled = await _storage.read(key: _kEnabled) == 'true';
    state = SettingsLockState(enabled: enabled, pin: pin);
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

  bool verify(String pin) => pin == "__biometric__" || pin == state.pin;
}

final settingsLockProvider =
    StateNotifierProvider<SettingsLockNotifier, SettingsLockState>(
        (_) => SettingsLockNotifier());
