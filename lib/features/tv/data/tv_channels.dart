// lib/features/tv/data/tv_channels.dart
// XameTV — Dynamic channel system powered by iptv-org/iptv

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TvChannel {
  final String name, category, streamUrl, logo, country, language;
  const TvChannel({
    required this.name,      required this.category,
    required this.streamUrl, required this.logo,
    required this.country,   required this.language,
  });
  Map<String, dynamic> toJson() => {
    'name': name, 'category': category, 'streamUrl': streamUrl,
    'logo': logo,  'country': country,  'language': language,
  };
  factory TvChannel.fromJson(Map<String, dynamic> j) => TvChannel(
    name:      j['name']      ?? '',
    category:  j['category']  ?? 'General',
    streamUrl: j['streamUrl'] ?? '',
    logo:      j['logo']      ?? '',
    country:   j['country']   ?? '',
    language:  j['language']  ?? '',
  );
}

const kTvCategories = [
  'All','Africa','News','Sports','Movies','Entertainment',
  'Music','Kids','Series','Documentary','General',
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
  'General':       Color(0xFF263238),
};

const kAfricanCountries = {
  'NG','GH','ZA','KE','ET','TZ','UG','CM','SN','CI','EG','MA','TN',
  'DZ','LY','SD','AO','MZ','ZM','ZW','RW','BJ','BF','ML','NE','TD',
  'SO','ER','MR','GA','GN','SL','LR','GW','GQ','ST','CV','SC','MU',
  'MG','KM','BI','DJ','SS','CF','CG','CD','NA','BW','LS','SZ','GM',
};

List<TvChannel> parseM3u(String content) {
  final channels = <TvChannel>[];
  final lines    = content.split('\n');
  for (int i = 0; i < lines.length - 1; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXTINF')) continue;
    String _attr(String key) {
      final m = RegExp('$key="([^"]*)"').firstMatch(line);
      return m?.group(1) ?? '';
    }
    final nameM = RegExp(r',(.+)$').firstMatch(line);
    final name    = nameM?.group(1)?.trim() ?? '';
    final logo    = _attr('tvg-logo');
    final group   = _attr('group-title').isEmpty ? 'General' : _attr('group-title');
    final lang    = _attr('tvg-language');
    final country = _attr('tvg-country').toUpperCase();
    final url     = lines[i + 1].trim();
    if (url.isEmpty || url.startsWith('#') || !url.startsWith('http')) continue;
    final primary = group.split(';').first.trim();
    final category = const {
      'News':'News','Sports':'Sports','Movies':'Movies',
      'Entertainment':'Entertainment','Music':'Music',
      'Kids':'Kids','Animation':'Kids','Series':'Series',
      'Documentary':'Documentary',
    }[primary] ?? 'General';
    channels.add(TvChannel(name:name,category:category,streamUrl:url,
        logo:logo,country:country,language:lang));
  }
  return channels;
}

class TvChannelService {
  static const _key     = 'xametv_v4';
  static const _timeKey = 'xametv_time_v4';
  static const _ttl     = Duration(hours: 24);
  static const _url     = 'https://iptv-org.github.io/iptv/index.m3u';
  static List<TvChannel>? _mem;

  static Future<List<TvChannel>> fetchChannels({bool force=false}) async {
    if (_mem != null && !force) return _mem!;
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final age = DateTime.now().millisecondsSinceEpoch-(prefs.getInt(_timeKey)??0);
      if (age < _ttl.inMilliseconds) {
        final raw = prefs.getString(_key);
        if (raw != null) {
          try {
            _mem = (jsonDecode(raw) as List)
                .map((j) => TvChannel.fromJson(j as Map<String,dynamic>)).toList();
            return _mem!;
          } catch (_) {}
        }
      }
    }
    try {
      final res = await http.get(Uri.parse(_url),
          headers: {'User-Agent':'XamePage/2.1'}).timeout(const Duration(seconds:30));
      if (res.statusCode == 200) {
        _mem = parseM3u(res.body);
        await prefs.setString(_key, jsonEncode(_mem!.map((c)=>c.toJson()).toList()));
        await prefs.setInt(_timeKey, DateTime.now().millisecondsSinceEpoch);
        return _mem!;
      }
    } catch (_) {}
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _mem = (jsonDecode(raw) as List)
            .map((j) => TvChannel.fromJson(j as Map<String,dynamic>)).toList();
        return _mem!;
      } catch (_) {}
    }
    return [];
  }

  static List<TvChannel> filterByCategory(List<TvChannel> all, String cat) {
    if (cat == 'All') return all;
    if (cat == 'Africa')
      return all.where((c) => kAfricanCountries.contains(c.country)).toList();
    return all.where((c) => c.category == cat).toList();
  }

  static List<TvChannel> search(List<TvChannel> all, String q) {
    if (q.isEmpty) return all;
    final s = q.toLowerCase();
    return all.where((c) =>
        c.name.toLowerCase().contains(s) ||
        c.country.toLowerCase().contains(s) ||
        c.language.toLowerCase().contains(s)).toList();
  }

  static void clearCache() {
    _mem = null;
    SharedPreferences.getInstance()
        .then((p) => p..remove(_key)..remove(_timeKey));
  }
}
