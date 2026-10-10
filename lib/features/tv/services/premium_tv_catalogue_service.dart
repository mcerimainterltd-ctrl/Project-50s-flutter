import 'package:dio/dio.dart';

import '../../../core/config/constants.dart';

/// Isolated read-only API client for the XameTV Premium catalogue.
///
/// This service does not modify Free TV, billing, entitlements, or playback.
class PremiumTvCatalogueService {
  PremiumTvCatalogueService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<PremiumTvCatalogueData> fetchCatalogue() async {
    final response = await _dio.get<dynamic>(
      '${AppConstants.serverUrl}/api/xametv/premium/catalogue',
      options: Options(
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {'Accept': 'application/json'},
      ),
    );

    final body = response.data;
    if (body is! Map) {
      throw const FormatException('Invalid Premium TV catalogue response.');
    }

    if (body['success'] != true ||
        body['categories'] is! List ||
        body['channels'] is! List) {
      throw const FormatException('Incomplete Premium TV catalogue response.');
    }

    final categories = <Map<String, dynamic>>[];
    for (final item in body['categories'] as List) {
      if (item is! Map) continue;

      final id = item['categoryId'];
      final name = item['name'];
      if (id is! String ||
          id.trim().isEmpty ||
          name is! String ||
          name.trim().isEmpty) {
        continue;
      }

      categories.add(Map<String, dynamic>.from(item));
    }

    final validCategoryIds =
        categories.map((item) => item['categoryId'] as String).toSet();

    final channels = <Map<String, dynamic>>[];
    for (final item in body['channels'] as List) {
      if (item is! Map) continue;

      final id = item['channelId'];
      final categoryId = item['categoryId'];
      final name = item['name'];
      final number = item['number'];
      final tier = item['accessTier'];

      if (id is! String ||
          id.trim().isEmpty ||
          categoryId is! String ||
          !validCategoryIds.contains(categoryId) ||
          name is! String ||
          name.trim().isEmpty ||
          number is! num ||
          number < 1 ||
          number % 1 != 0 ||
          (tier != 'bonusFree' && tier != 'subscriptionRequired')) {
        continue;
      }

      channels.add(Map<String, dynamic>.from(item));
    }

    return PremiumTvCatalogueData(
      categories: List.unmodifiable(categories),
      channels: List.unmodifiable(channels),
    );
  }
}

class PremiumTvCatalogueData {
  const PremiumTvCatalogueData({
    required this.categories,
    required this.channels,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> channels;
}
