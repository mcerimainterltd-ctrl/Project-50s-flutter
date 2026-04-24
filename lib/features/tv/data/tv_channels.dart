// lib/features/tv/data/tv_channels.dart
// XameTV — Dynamic channel system powered by iptv-org/iptv
// Fetches 11,000+ channels live, cached 24h, all categories

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ─────────────────────────────────────────────────────────────────
class TvChannel {
  final String name, category, streamUrl, logo, country, language, description;
  final bool isHD;
  const TvChannel({
    required this.name, required this.category, required this.streamUrl,
    required this.logo,  required this.country,  required this.language,
    this.description = '', this.isHD = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'category': category, 'streamUrl': streamUrl,
    'logo': logo,  'country': country,  'language': language,
    'description': description, 'isHD': isHD,
  };

  factory TvChannel.fromJson(Map<String, dynamic> j) => TvChannel(
    name:      j['name']      ?? '',
    category:  j['category']  ?? 'General',
    streamUrl: j['streamUrl'] ?? '',
    logo:      j['logo']      ?? '',
    country:   j['country']   ?? '',
    language:  j['language']  ?? '',
    description: j['description'] ?? '',
    isHD:      j['isHD']      ?? false,
  );
}

// ── Categories ────────────────────────────────────────────────────────────
const kTvCategories = [
  'All', 'Africa', 'News', 'Sports', 'Movies', 'Entertainment',
  'Music', 'Kids', 'Series', 'Documentary', 'General',
];

const kCategoryColors = {
  'All':           Color(0xFF455A64),
  'Africa':        Color(0xFF2E7D32),
  'News':          Color(0xFF1565C0),
  'Sports':        Color(0xFF00838F),
  'Movies':        Color(0xFF6A1B9A),
  'Entertainment': Color(0xFF4527A0),
  'Music':         Color(0xFFAD1457),
  'Kids':          Color(0xFFE65100),
  'Series':        Color(0xFF37474F),
  'Documentary':   Color(0xFF558B2F),
  'General':       Color(0xFF37474F),
};

const kCategoryEmoji = {
  'All':           '📺',
  'Africa':        '🌍',
  'News':          '📰',
  'Sports':        '⚽',
  'Movies':        '🎬',
  'Entertainment': '🎭',
  'Music':         '🎵',
  'Kids':          '🧸',
  'Series':        '📺',
  'Documentary':   '🔭',
  'General':       '📡',
};

// African country codes
const kAfricanCountries = {
  'NG','GH','ZA','KE','ET','TZ','UG','CM','SN','CI','EG','MA','TN',
  'DZ','LY','SD','AO','MZ','ZM','ZW','RW','BJ','BF','ML','NE','TD',
  'SO','ER','MR','GA','GN','SL','LR','GW','GQ','ST','CV','SC','MU',
  'MG','KM','BI','DJ','SS','CF','CG','CD','NA','BW','LS','SZ','GM',
};

// ── M3U Parser ────────────────────────────────────────────────────────────
List<TvChannel> parseM3u(String content) {
  final channels = <TvChannel>[];
  final lines    = content.split('\n');

  for (int i = 0; i < lines.length - 1; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXTINF')) continue;

    // Extract attributes
    final nameMatch    = RegExp(r',(.+)$').firstMatch(line);
    final logoMatch    = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
    final groupMatch   = RegExp(r'group-title="([^"]*)"').firstMatch(line);
    final langMatch    = RegExp(r'tvg-language="([^"]*)"').firstMatch(line);
    final countryMatch = RegExp(r'tvg-country="([^"]*)"').firstMatch(line);

    final name     = nameMatch?.group(1)?.trim()   ?? '';
    final logo     = logoMatch?.group(1)            ?? '';
    final group    = groupMatch?.group(1)           ?? 'General';
    final lang     = langMatch?.group(1)            ?? '';
    final country  = countryMatch?.group(1)?.toUpperCase() ?? '';

    // Get stream URL
    final url = lines[i + 1].trim();
    if (url.isEmpty || url.startsWith('#')) continue;
    if (!url.startsWith('http')) continue;

    // Map iptv-org group to XameTV category
    final primary = group.split(';').first.trim();
    String category;
    switch (primary) {
      case 'News':          category = 'News';          break;
      case 'Sports':        category = 'Sports';        break;
      case 'Movies':        category = 'Movies';        break;
      case 'Entertainment': category = 'Entertainment'; break;
      case 'Music':         category = 'Music';         break;
      case 'Kids':
      case 'Animation':     category = 'Kids';          break;
      case 'Series':        category = 'Series';        break;
      case 'Documentary':   category = 'Documentary';   break;
      default:              category = 'General';
    }

    channels.add(TvChannel(
      name: name, category: category, streamUrl: url,
      logo: logo, country: country,   language: lang,
    ));
  }
  return channels;
}

// ── Channel Service ───────────────────────────────────────────────────────
class TvChannelService {
  static const _cacheKey     = 'xametv_channels_v2';
  static const _cacheTimeKey = 'xametv_channels_time_v2';
  static const _cacheTtl     = Duration(hours: 24);
  static const _m3uUrl       =
      'https://iptv-org.github.io/iptv/index.m3u';

  static List<TvChannel>? _cache;

  static Future<List<TvChannel>> fetchChannels({bool force = false}) async {
    // Return in-memory cache
    if (_cache != null && !force) return _cache!;

    final prefs = await SharedPreferences.getInstance();

    // Check disk cache
    if (!force) {
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;
      final age       = DateTime.now().millisecondsSinceEpoch - cacheTime;
      if (age < _cacheTtl.inMilliseconds) {
        final raw = prefs.getString(_cacheKey);
        if (raw != null) {
          try {
            final list = (jsonDecode(raw) as List)
                .map((j) => TvChannel.fromJson(j as Map<String, dynamic>))
                .toList();
            _cache = list;
            return list;
          } catch (_) {}
        }
      }
    }

    // Fetch fresh
    try {
      final res = await http.get(
        Uri.parse(_m3uUrl),
        headers: {'User-Agent': 'XamePage/2.1 IPTV'},
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final channels = parseM3u(res.body);
        _cache = channels;

        // Save to disk cache
        await prefs.setString(
            _cacheKey,
            jsonEncode(channels.map((c) => c.toJson()).toList()));
        await prefs.setInt(
            _cacheTimeKey,
            DateTime.now().millisecondsSinceEpoch);

        return channels;
      }
    } catch (_) {}

    // Return stale cache on error
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .map((j) => TvChannel.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  // Filter channels by category
  static List<TvChannel> filterByCategory(
      List<TvChannel> all, String category) {
    if (category == 'All') return all;
    if (category == 'Africa') {
      return all
          .where((c) => kAfricanCountries.contains(c.country.toUpperCase()))
          .toList();
    }
    return all.where((c) => c.category == category).toList();
  }

  // Search channels
  static List<TvChannel> search(List<TvChannel> all, String query) {
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.country.toLowerCase().contains(q) ||
            c.language.toLowerCase().contains(q))
        .toList();
  }

  static void clearCache() {
    _cache = null;
    SharedPreferences.getInstance()
        .then((p) => p..remove(_cacheKey)..remove(_cacheTimeKey));
  }
}
