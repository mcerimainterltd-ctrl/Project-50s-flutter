import 'package:flutter/material.dart';

enum DiscoveryType { post, story, live, creator, trending, channel }
enum DiscoveryMediaType { image, video, text }

class DiscoveryItem {
  final String            id;
  final String            title;
  final String            subtitle;
  final String            mediaUrl;
  final String?           thumbnailUrl;
  final String            authorName;
  final String            authorAvatar;
  final String            authorId;
  final String            region;
  final String            category;
  final DiscoveryType     type;
  final DiscoveryMediaType mediaType;
  final bool              isLive;
  final bool              isAuthorOnline;
  final int               viewCount;
  final int               likeCount;
  final int               commentCount;
  final DateTime          ts;
  final Color?            accentColor;

  const DiscoveryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.authorName,
    required this.authorAvatar,
    required this.authorId,
    required this.region,
    required this.category,
    required this.type,
    this.mediaType    = DiscoveryMediaType.image,
    this.isLive       = false,
    this.isAuthorOnline = false,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.ts,
    this.accentColor,
  });

  factory DiscoveryItem.fromJson(Map<String, dynamic> json) {
    return DiscoveryItem(
      id:             json['id'] as String,
      title:          json['title'] as String,
      subtitle:       json['subtitle'] as String,
      mediaUrl:       json['mediaUrl'] as String,
      thumbnailUrl:   json['thumbnailUrl'] as String?,
      authorName:     json['authorName'] as String,
      authorAvatar:   json['authorAvatar'] as String,
      authorId:       json['authorId'] as String,
      region:         json['region'] as String,
      category:       json['category'] as String,
      type:           DiscoveryType.values.byName(json['type'] as String),
      mediaType:      DiscoveryMediaType.values.byName(json['mediaType'] as String),
      isLive:         json['isLive'] as bool,
      isAuthorOnline: json['isAuthorOnline'] as bool,
      viewCount:      json['viewCount'] as int,
      likeCount:      json['likeCount'] as int,
      commentCount:   json['commentCount'] as int,
      ts:             DateTime.parse(json['ts'] as String),
      accentColor:    json['accentColor'] != null ? Color(json['accentColor'] as int) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':             id,
    'title':          title,
    'subtitle':       subtitle,
    'mediaUrl':       mediaUrl,
    'thumbnailUrl':   thumbnailUrl,
    'authorName':     authorName,
    'authorAvatar':   authorAvatar,
    'authorId':       authorId,
    'region':         region,
    'category':       category,
    'type':           type.name,
    'mediaType':      mediaType.name,
    'isLive':         isLive,
    'isAuthorOnline': isAuthorOnline,
    'viewCount':      viewCount,
    'likeCount':      likeCount,
    'commentCount':   commentCount,
    'ts':             ts.toIso8601String(),
    'accentColor':    accentColor?.value,
  };
}

class DiscoveryUser {
  final String  id;
  final String  name;
  final String  avatarUrl;
  final int     mutualCount;
  final bool    isOnline;
  final String? statusEmoji;
  final String? tagline;
  bool          isAdded;

  DiscoveryUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.mutualCount,
    this.isOnline    = false,
    this.statusEmoji,
    this.tagline,
    this.isAdded     = false,
  });

  factory DiscoveryUser.fromJson(Map<String, dynamic> json) {
    return DiscoveryUser(
      id:          json['id'] as String,
      name:        json['name'] as String,
      avatarUrl:   json['avatarUrl'] as String,
      mutualCount: json['mutualCount'] as int,
      isOnline:    json['isOnline'] as bool? ?? false,
      statusEmoji: json['statusEmoji'] as String?,
      tagline:     json['tagline'] as String?,
      isAdded:     json['isAdded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    'avatarUrl':   avatarUrl,
    'mutualCount': mutualCount,
    'isOnline':    isOnline,
    'statusEmoji': statusEmoji,
    'tagline':     tagline,
    'isAdded':     isAdded,
  };
}

class DiscoveryRegion {
  final String   code;
  final String   name;
  final String   flag;
  final String   currency;
  final String   currencySymbol;
  final List<String> categories;

  const DiscoveryRegion({
    required this.code,
    required this.name,
    required this.flag,
    required this.currency,
    required this.currencySymbol,
    required this.categories,
  });
}

// ── Region data — mirrors wallet GD regions ───────────────────────────────
const discoveryRegions = [
  DiscoveryRegion(code:'global',  name:'Global',        flag:'🌍', currency:'USD', currencySymbol:'\$',  categories:['Trending','Culture','Tech','Sport','Art']),
  DiscoveryRegion(code:'ng',      name:'Nigeria',       flag:'🇳🇬', currency:'NGN', currencySymbol:'₦',  categories:['Afrobeats','Nollywood','Tech','Business','Sport']),
  DiscoveryRegion(code:'gh',      name:'Ghana',         flag:'🇬🇭', currency:'GHS', currencySymbol:'GH₵',categories:['Music','Culture','Business','Sport','Art']),
  DiscoveryRegion(code:'ke',      name:'Kenya',         flag:'🇰🇪', currency:'KES', currencySymbol:'KSh',categories:['Safari','Tech','Music','Business','Sport']),
  DiscoveryRegion(code:'za',      name:'South Africa',  flag:'🇿🇦', currency:'ZAR', currencySymbol:'R',  categories:['Music','Sport','Culture','Business','Tech']),
  DiscoveryRegion(code:'us',      name:'USA',           flag:'🇺🇸', currency:'USD', currencySymbol:'\$',  categories:['Pop','Tech','Sport','Politics','Art']),
  DiscoveryRegion(code:'gb',      name:'UK',            flag:'🇬🇧', currency:'GBP', currencySymbol:'£',  categories:['Music','Football','Tech','Culture','Art']),
  DiscoveryRegion(code:'eu',      name:'Europe',        flag:'🇪🇺', currency:'EUR', currencySymbol:'€',  categories:['Football','Art','Tech','Fashion','Music']),
  DiscoveryRegion(code:'in',      name:'India',         flag:'🇮🇳', currency:'INR', currencySymbol:'₹',  categories:['Bollywood','Cricket','Tech','Culture','Business']),
  DiscoveryRegion(code:'ae',      name:'UAE',           flag:'🇦🇪', currency:'AED', currencySymbol:'AED',categories:['Luxury','Business','Sport','Travel','Tech']),
  DiscoveryRegion(code:'sg',      name:'Singapore',     flag:'🇸🇬', currency:'SGD', currencySymbol:'S\$',categories:['Tech','Business','Food','Culture','Travel']),
  DiscoveryRegion(code:'jp',      name:'Japan',         flag:'🇯🇵', currency:'JPY', currencySymbol:'¥',  categories:['Anime','Tech','Culture','Sport','Food']),
  DiscoveryRegion(code:'br',      name:'Brazil',        flag:'🇧🇷', currency:'BRL', currencySymbol:'R\$',categories:['Samba','Football','Culture','Business','Art']),
  DiscoveryRegion(code:'ca',      name:'Canada',        flag:'🇨🇦', currency:'CAD', currencySymbol:'CA\$',categories:['Hockey','Tech','Culture','Music','Nature']),
  DiscoveryRegion(code:'au',      name:'Australia',     flag:'🇦🇺', currency:'AUD', currencySymbol:'A\$',categories:['Sport','Nature','Music','Tech','Culture']),
];
