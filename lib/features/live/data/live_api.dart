import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/constants.dart';
import '../models/live_session.dart';
import '../models/live_entitlement.dart';

class LiveApiException extends StateError {
  final String? code;
  final int statusCode;

  LiveApiException({
    required this.code,
    required this.statusCode,
    required String message,
  }) : super(message);
}

class LiveApi {
  LiveApi({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<Map<String, String>> _headers() async {
    final token = await _secureStorage.read(
      key: AppConstants.keySessionToken,
    );

    if (token == null || token.isEmpty) {
      throw StateError('XamePage session token is missing.');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path) {
    return Uri.parse('${AppConstants.serverUrl}$path');
  }


  Future<GoLiveEntitlement?> getGoLiveEntitlement() async {
    final response = await http.get(
      _uri('/api/live/entitlement'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to load Go Live entitlement (${response.statusCode}).',
      );
    }

    if (data['hasAccess'] != true) {
      return null;
    }

    final entitlementJson = data['entitlement'];

    if (entitlementJson is! Map) {
      return null;
    }

    return GoLiveEntitlement.fromJson(
      Map<String, dynamic>.from(entitlementJson),
    );
  }

  Future<GoLiveEntitlement> claimGoLiveTrial() async {
    final response = await http.post(
      _uri('/api/live/trial/claim'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: data['message']?.toString() ??
            'Unable to claim the Go Live trial.',
      );
    }

    final entitlementJson = data['entitlement'];

    if (entitlementJson is! Map) {
      throw LiveApiException(
        code: null,
        statusCode: response.statusCode,
        message: 'Go Live trial entitlement was not returned.',
      );
    }

    return GoLiveEntitlement.fromJson(
      Map<String, dynamic>.from(entitlementJson),
    );
  }

  Future<GoLiveEntitlement> verifyGoLivePurchase({
    required String purchaseToken,
  }) async {
    final response = await http.post(
      _uri('/api/live/purchase/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'purchaseToken': purchaseToken,
      }),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: data['message']?.toString() ??
            'Unable to verify the Go Live purchase (${response.statusCode}).',
      );
    }

    final entitlementJson = data['entitlement'];

    if (entitlementJson is! Map) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: 'Go Live purchase verification returned no entitlement.',
      );
    }

    return GoLiveEntitlement.fromJson(
      Map<String, dynamic>.from(entitlementJson),
    );
  }

  Future<List<GoLivePlan>> getGoLivePlans() async {
    final response = await http.get(
      _uri('/api/live/plans'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to load Go Live plans (${response.statusCode}).',
      );
    }

    final plans = data['plans'];

    if (plans is! List) {
      return const [];
    }

    return plans
        .whereType<Map>()
        .map(
          (item) => GoLivePlan.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<LiveStartResult> startLive({
    required String title,
    required String category,
  }) async {
    final response = await http.post(
      _uri('/api/live/start'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'category': category,
      }),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: data['message']?.toString() ??
            'Unable to start XameLive (${response.statusCode}).',
      );
    }

    final sessionJson = data['session'];

    if (sessionJson is! Map) {
      throw StateError('XameLive start response is missing session data.');
    }

    final publishUrl = data['stream'] is Map
        ? data['stream']['publishUrl']?.toString()
        : null;

    if (publishUrl == null || publishUrl.isEmpty) {
      throw StateError('XameLive start response is missing publishUrl.');
    }

    return LiveStartResult(
      session: LiveSession.fromJson(
        Map<String, dynamic>.from(sessionJson),
      ),
      publishUrl: publishUrl,
    );
  }

  Future<LiveSession> endLive(String sessionId) async {
    final response = await http.post(
      _uri('/api/live/$sessionId/end'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to end XameLive (${response.statusCode}).',
      );
    }

    final sessionJson = data['session'];

    if (sessionJson is! Map) {
      throw StateError('XameLive end response is missing session data.');
    }

    return LiveSession.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );
  }

  Future<List<LiveSession>> getActiveLives() async {
    final response = await http.get(
      _uri('/api/live/active'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to load live sessions (${response.statusCode}).',
      );
    }

    final sessions = data['sessions'];

    if (sessions is! List) {
      return const [];
    }

    return sessions
        .whereType<Map>()
        .map(
          (item) => LiveSession.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<LiveSession> getLive(String sessionId) async {
    final response = await http.get(
      _uri('/api/live/$sessionId'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to load XameLive session (${response.statusCode}).',
      );
    }

    final sessionJson = data['session'];

    if (sessionJson is! Map) {
      throw StateError('XameLive response is missing session data.');
    }

    return LiveSession.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );
  }

  Future<LiveSession> joinLive(String sessionId) async {
    final response = await http.post(
      _uri('/api/live/$sessionId/join'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: data['message']?.toString() ??
            'Unable to join XameLive (${response.statusCode}).',
      );
    }

    final sessionJson = data['session'];

    if (sessionJson is! Map) {
      throw StateError('XameLive join response is missing session data.');
    }

    return LiveSession.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );
  }

  Future<LiveSession> watchLive(String sessionId) async {
    final response = await http.get(
      _uri('/api/live/$sessionId/watch'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveApiException(
        code: data['code']?.toString(),
        statusCode: response.statusCode,
        message: data['message']?.toString() ??
            'Unable to watch XameLive (${response.statusCode}).',
      );
    }

    final sessionJson = data['session'];

    if (sessionJson is! Map) {
      throw StateError('XameLive watch response is missing session data.');
    }

    return LiveSession.fromJson(
      Map<String, dynamic>.from(sessionJson),
    );
  }

  Future<void> leaveLive(String sessionId) async {
    final response = await http.post(
      _uri('/api/live/$sessionId/leave'),
      headers: await _headers(),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data['message']?.toString() ??
            'Unable to leave XameLive (${response.statusCode}).',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {};
    } catch (_) {
      throw StateError(
        'XameLive server returned invalid JSON (${response.statusCode}).',
      );
    }
  }

}

class LiveStartResult {
  final LiveSession session;
  final String publishUrl;

  const LiveStartResult({
    required this.session,
    required this.publishUrl,
  });
}
