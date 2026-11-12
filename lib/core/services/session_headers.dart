import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

/// Authorization header for API calls that must be tied to the logged-in session.
/// Returns an empty map when there is no stored session, so callers never send a "Bearer null" header.
Future<Map<String, String>> sessionAuthHeaders() async {
  try {
    final token = await const FlutterSecureStorage()
        .read(key: AppConstants.keySessionToken);
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
  } catch (_) {}
  return const <String, String>{};
}
