import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class XameSpaceService {
  static const String baseUrl = 'https://app.xamepage.com/api/v3/spaces';

  static Future<Map<String, dynamic>> fetchSpace(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? prefs.getString('guest_token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/$slug'),
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
}
