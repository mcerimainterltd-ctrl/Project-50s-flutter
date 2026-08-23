import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_constants.dart';
import '../features/spaces/models/space_model.dart';

class XameSpaceService {
  static final _dio = Dio(BaseOptions(
    baseUrl: '${AppConstants.serverUrl}/api/v3/spaces',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Fetch (and cache) a real session token for a logged-in user.
  static Future<String?> _sessionToken(String? xameId) async {
    if (xameId == null || xameId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final cached = p.getString('space_session_token_$xameId');
    if (cached != null) return cached;
    try {
      final r = await _dio.post('/session-token', data: {'xameId': xameId});
      if (r.data['success'] == true) {
        final token = r.data['token'] as String;
        await p.setString('space_session_token_$xameId', token);
        return token;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _guestToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('space_guest_token');
  }

  static Future<void> _saveGuestToken(String? token) async {
    if (token == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('space_guest_token', token);
  }

  static Future<Map<String, String>> _headers({String? userId}) async {
    final token = userId != null ? await _sessionToken(userId) : await _guestToken();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  // ── Fetch Space ──────────────────────────────────────────────────────────
  static Future<SpaceModel?> fetchSpace(String slug, {String? userId}) async {
    try {
      final r = await _dio.get('/$slug', options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) {
        if (r.data['guestToken'] != null) await _saveGuestToken(r.data['guestToken']);
        return SpaceModel.fromJson(r.data['space']);
      }
    } catch (_) {}
    return null;
  }

  // ── Create Space ─────────────────────────────────────────────────────────
  static Future<SpaceModel?> createSpace({
    required String userId, required String name, required String spaceSlug, required String archetype,
    String description = '', String visibility = 'public_link', bool allowGuestPosting = true,
  }) async {
    try {
      final r = await _dio.post('/create',
        data: {'name': name, 'spaceSlug': spaceSlug, 'archetype': archetype,
          'description': description, 'visibility': visibility, 'allowGuestPosting': allowGuestPosting},
        options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) return SpaceModel.fromJson(r.data['space']);
    } catch (_) {}
    return null;
  }

  // ── Join Space ───────────────────────────────────────────────────────────
  static Future<bool> joinSpace(String slug, {String? userId, String? displayName}) async {
    try {
      final r = await _dio.post('/$slug/join',
        data: displayName != null ? {'displayName': displayName} : <String, dynamic>{},
        options: Options(headers: await _headers(userId: userId)));
      if (r.data['guestToken'] != null) await _saveGuestToken(r.data['guestToken']);
      return r.data['success'] == true;
    } catch (_) { return false; }
  }

  // ── Get Messages ─────────────────────────────────────────────────────────
  static Future<List<SpaceMessage>> fetchMessages(String slug, {String? userId, String? before, int limit = 30}) async {
    try {
      final r = await _dio.get('/$slug/messages',
        queryParameters: {'limit': limit, if (before != null) 'before': before},
        options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) {
        return (r.data['messages'] as List).map((m) => SpaceMessage.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Send Message ─────────────────────────────────────────────────────────
  static Future<SpaceMessage?> sendMessage(String slug, {
    String? userId, String? displayName,
    String? text, String? mediaUrl, String? mediaType, String? fileName,
    String? replyToId, String? replyToText,
  }) async {
    try {
      final r = await _dio.post('/$slug/messages',
        data: {'text': text ?? '', 'mediaUrl': mediaUrl ?? '', 'mediaType': mediaType ?? '',
          'fileName': fileName ?? '', 'replyToId': replyToId, 'replyToText': replyToText,
          if (displayName != null) 'displayName': displayName},
        options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) return SpaceMessage.fromJson(r.data['message']);
    } catch (_) {}
    return null;
  }

  // ── React ────────────────────────────────────────────────────────────────
  static Future<void> reactToMessage(String slug, String msgId, String emoji, {String? userId}) async {
    try {
      await _dio.post('/$slug/messages/$msgId/react',
        data: {'emoji': emoji}, options: Options(headers: await _headers(userId: userId)));
    } catch (_) {}
  }

  // ── Delete Message ───────────────────────────────────────────────────────
  static Future<void> deleteMessage(String slug, String msgId, {String? userId}) async {
    try {
      await _dio.delete('/$slug/messages/$msgId', options: Options(headers: await _headers(userId: userId)));
    } catch (_) {}
  }

  // ── Get Media ────────────────────────────────────────────────────────────
  static Future<List<SpaceMessage>> fetchMedia(String slug, {String? userId}) async {
    try {
      final r = await _dio.get('/$slug/media', options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) {
        return (r.data['media'] as List).map((m) => SpaceMessage.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── My Spaces ────────────────────────────────────────────────────────────
  static Future<List<SpaceModel>> fetchMySpaces(String userId) async {
    try {
      final r = await _dio.get('/', options: Options(headers: await _headers(userId: userId)));
      if (r.data['success'] == true) {
        return (r.data['spaces'] as List).map((s) => SpaceModel.fromJson(s)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Claim Guest Messages ─────────────────────────────────────────────────
  static Future<void> claimGuestMessages(String slug, String userId, String guestId) async {
    try {
      await _dio.post('/$slug/claim',
        data: {'guestId': guestId}, options: Options(headers: await _headers(userId: userId)));
    } catch (_) {}
  }
}
