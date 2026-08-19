import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class XameSpaceService {
  static const String baseUrl = 'https://app.xamepage.com/api/v3';

  /// Resolve space slug & update guest session if returned
  static Future<Map<String, dynamic>> fetchSpace(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? prefs.getString('guest_token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/spaces/$slug'),
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(response.body);
    if (data['success'] == true && data['guestToken'] != null) {
      await prefs.setString('guest_token', data['guestToken']);
    }
    return data;
  }

  /// Resolve space object by slug
  static Future<Map<String, dynamic>?> resolveSpace(String slug) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/objects/space/$slug'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Error resolving space: $e');
    }
    return null;
  }

  /// Fetch space messages
  static Future<List<dynamic>> fetchMessages(String slug, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/objects/space/$slug/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['messages'] ?? [];
      }
    } catch (e) {
      print('Error fetching messages: $e');
    }
    return [];
  }

  /// Claim guest activity after sign-in
  static Future<bool> claimGuestActivity(String userToken, String guestToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/claim-guest'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $userToken',
        },
        body: jsonEncode({'guestToken': guestToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      print('Error claiming guest activity: $e');
    }
    return false;
  }
}
