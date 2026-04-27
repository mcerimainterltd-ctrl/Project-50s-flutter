
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage  = FlutterSecureStorage();
const _kPin     = 'xame:walletlock:pin';
const _kEnabled = 'xame:walletlock:enabled';

class WalletLockState {
  final bool   enabled;
  final String pin;
  const WalletLockState({this.enabled=false, this.pin=''});
  WalletLockState copyWith({bool? enabled, String? pin}) =>
    WalletLockState(enabled: enabled ?? this.enabled, pin: pin ?? this.pin);
}

class WalletLockNotifier extends StateNotifier<WalletLockState> {
  WalletLockNotifier() : super(const WalletLockState()) { _load(); }

  Future<void> _load() async {
    final pin     = await _storage.read(key: _kPin)     ?? '';
    final enabled = await _storage.read(key: _kEnabled) == 'true';
    state = WalletLockState(enabled: enabled, pin: pin);
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

  bool verify(String pin) => pin == state.pin;
}

final walletLockProvider = StateNotifierProvider<WalletLockNotifier, WalletLockState>(
    (_) => WalletLockNotifier());
