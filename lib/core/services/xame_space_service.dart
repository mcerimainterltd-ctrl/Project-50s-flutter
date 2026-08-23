import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../../features/spaces/models/space_model.dart';

class XameSpaceService {
  static final _dio = Dio(BaseOptions(
    baseUrl: '${AppConstants.serverUrl}/api/v3/spaces',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Stable anonymous guest identity, generated once and persisted locally.
  static Future<String> _guestId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('space_guest_id');
    if (id == null) {
      id = const Uuid().v4();
      await p.setString('space_guest_id', id);
    }
    return id;
  }

  static Future<Map<String, dynamic>> _identity(String? userId, String? displayName) async {
    if (userId != null && userId.isNotEmpty) return {'userId': userId};
    final guestId = await _guestId();
    return {'guestId': guestId, if (displayName != null) 'displayName': displayName};
  }

  // ── Fetch Space ──────────────────────────────────────────────────────────
  static Future<SpaceModel?> fetchSpace(String slug, {String? userId}) async {
    try {
      final r = await _dio.get('/$slug',
        queryParameters: userId != null ? {'userId': userId} : null);
      if (r.data['success'] == true) return SpaceModel.fromJson(r.data['space']);
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
        data: {'userId': userId, 'name': name, 'spaceSlug': spaceSlug, 'archetype': archetype,
          'description': description, 'visibility': visibility, 'allowGuestPosting': allowGuestPosting});
      if (r.data['success'] == true) return SpaceModel.fromJson(r.data['space']);
    } catch (_) {}
    return null;
  }

  // ── Join Space ───────────────────────────────────────────────────────────
  static Future<bool> joinSpace(String slug, {String? userId, String? displayName}) async {
    try {
      final identity = await _identity(userId, displayName);
      final r = await _dio.post('/$slug/join', data: identity);
      return r.data['success'] == true;
    } catch (_) { return false; }
  }

  // ── Get Messages ─────────────────────────────────────────────────────────
  static Future<List<SpaceMessage>> fetchMessages(String slug, {String? before, int limit = 30}) async {
    try {
      final r = await _dio.get('/$slug/messages',
        queryParameters: {'limit': limit, if (before != null) 'before': before});
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
      final identity = await _identity(userId, displayName);
      final r = await _dio.post('/$slug/messages',
        data: {...identity, 'text': text ?? '', 'mediaUrl': mediaUrl ?? '', 'mediaType': mediaType ?? '',
          'fileName': fileName ?? '', 'replyToId': replyToId, 'replyToText': replyToText});
      if (r.data['success'] == true) return SpaceMessage.fromJson(r.data['message']);
    } catch (_) {}
    return null;
  }

  // ── React ────────────────────────────────────────────────────────────────
  static Future<void> reactToMessage(String slug, String msgId, String emoji, {String? userId}) async {
    try {
      final identity = await _identity(userId, null);
      await _dio.post('/$slug/messages/$msgId/react', data: {...identity, 'emoji': emoji});
    } catch (_) {}
  }

  // ── Delete Message ───────────────────────────────────────────────────────
  static Future<void> deleteMessage(String slug, String msgId, {String? userId}) async {
    try {
      await _dio.delete('/$slug/messages/$msgId',
        queryParameters: userId != null ? {'userId': userId} : null);
    } catch (_) {}
  }

  // ── Get Media ────────────────────────────────────────────────────────────
  static Future<List<SpaceMessage>> fetchMedia(String slug) async {
    try {
      final r = await _dio.get('/$slug/media');
      if (r.data['success'] == true) {
        return (r.data['media'] as List).map((m) => SpaceMessage.fromJson(m)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── My Spaces ────────────────────────────────────────────────────────────
  static Future<List<SpaceModel>> fetchMySpaces(String userId) async {
    try {
      final r = await _dio.get('/', queryParameters: {'userId': userId});
      if (r.data['success'] == true) {
        return (r.data['spaces'] as List).map((s) => SpaceModel.fromJson(s)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Claim Guest Messages ─────────────────────────────────────────────────
  static Future<void> claimGuestMessages(String slug, String userId) async {
    try {
      final guestId = await _guestId();
      await _dio.post('/$slug/claim', data: {'guestId': guestId, 'userId': userId});
    } catch (_) {}
  }
}
