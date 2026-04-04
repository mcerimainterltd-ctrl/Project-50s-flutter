import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';
import '../../shared/models/xame_user.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final currentUserProvider = StateProvider<XameUser?>((ref) => null);

class AuthService {
  final _storage = const FlutterSecureStorage();
  final _dio     = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<XameUser?> init() async {
    try {
      final raw = await _storage.read(key: AppConstants.keyUser);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['xameId'] == null) return null;
      return XameUser.fromMap(map);
    } catch (_) { return null; }
  }

  // Server only needs: firstName, lastName, dob, password
  // xameId is generated server-side and returned in response
  Future<XameUser> register({
    required String firstName,
    required String lastName,
    required String dob,
    required String password,
  }) async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob))
      throw Exception('Invalid date of birth format');
    final res  = await _dio.post('/api/register', data: {
      'firstName': firstName.trim(),
      'lastName':  lastName.trim(),
      'dob':       dob,
      'password':  password,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['success'] != true)
      throw Exception(data['message'] ?? data['errors']?.toString() ?? 'Registration failed');
    return XameUser.fromMap(data['user'] as Map<String, dynamic>);
  }

  Future<LoginResult> login(String xameId, String password, {String? otp}) async {
    final body = <String, dynamic>{'xameId': xameId.trim(), 'password': password};
    if (otp != null) body['otp'] = otp;
    final res  = await _dio.post('/api/login', data: body);
    final data = res.data as Map<String, dynamic>;
    if (data['requiresPasswordSetup'] == true)
      return LoginResult.needsPasswordSetup(XameUser.fromMap(data['user'] as Map<String, dynamic>));
    if (data['requiresOTP'] == true)
      return LoginResult.needsOTP(data['message'] ?? 'OTP sent.');
    if (data['success'] != true)
      throw Exception(data['message'] ?? 'Login failed');
    final user = XameUser.fromMap(data['user'] as Map<String, dynamic>);
    await _storage.write(key: AppConstants.keyUser,         value: jsonEncode(data['user']));
    await _storage.write(key: AppConstants.keySessionToken, value: data['sessionToken']?.toString());
    return LoginResult.success(user);
  }

  Future<void> setPassword(String xameId, String newPassword) async {
    final v = validatePassword(newPassword);
    if (!v.isValid) throw Exception(v.errors.join('\n'));
    final res  = await _dio.post('/api/set-password',
      data: {'xameId': xameId, 'newPassword': newPassword});
    final data = res.data as Map<String, dynamic>;
    if (data['success'] != true) throw Exception(data['message'] ?? 'Failed to set password');
  }

  Future<void> logout(String xameId) async {
    try {
      final token = await _storage.read(key: AppConstants.keySessionToken);
      if (token != null)
        await _dio.post('/api/sessions/kill', data: {'userId': xameId, 'sessionId': token});
    } catch (_) {}
    await _storage.delete(key: AppConstants.keySessionToken);
    await _storage.delete(key: AppConstants.keyUser);
  }

  Future<void> forceLogout() => _storage.deleteAll();

  Future<XameUser?> getSavedUser() async {
    final raw = await _storage.read(key: AppConstants.keyUser);
    if (raw == null) return null;
    try { return XameUser.fromMap(jsonDecode(raw) as Map<String, dynamic>); }
    catch (_) { return null; }
  }

  Future<bool> isStealthMode() async =>
    await _storage.read(key: AppConstants.keyStealth) == 'true';

  Future<void> setStealthMode(bool v) =>
    _storage.write(key: AppConstants.keyStealth, value: v.toString());

  PasswordValidation validatePassword(String p) {
    final e = <String>[];
    if (p.length < 8)                                     e.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(p))                    e.add('One uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(p))                    e.add('One lowercase letter');
    if (!RegExp(r'[0-9]').hasMatch(p))                    e.add('One number');
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(p)) e.add('One special character');
    return PasswordValidation(isValid: e.isEmpty, errors: e);
  }

  String? validateDob(int day, int month, int year) {
    final now = DateTime.now().year;
    if (day   < 1 || day   > 31)    return 'Invalid day';
    if (month < 1 || month > 12)    return 'Invalid month';
    if (year  < 1900 || year > now) return 'Invalid year';
    return null;
  }
}

class LoginResult {
  final LoginResultType type;
  final XameUser?       user;
  final String?         message;
  const LoginResult._({required this.type, this.user, this.message});
  factory LoginResult.success(XameUser u)         => LoginResult._(type: LoginResultType.success,           user: u);
  factory LoginResult.needsPasswordSetup(XameUser u) => LoginResult._(type: LoginResultType.needsPasswordSetup, user: u);
  factory LoginResult.needsOTP(String msg)         => LoginResult._(type: LoginResultType.needsOTP,          message: msg);
}

enum LoginResultType { success, needsPasswordSetup, needsOTP }

class PasswordValidation {
  final bool isValid; final List<String> errors;
  const PasswordValidation({required this.isValid, required this.errors});
}
