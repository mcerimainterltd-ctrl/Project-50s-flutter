// XameTV Premium — isolated catalogue foundation.
// Category -> channels -> full-screen viewer.
// No backend, payment, or Free TV dependencies.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:better_player_enhanced/better_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/premium_tv_catalogue_service.dart';

enum _PremiumLayout { grid, list, large }

class PremiumTvScreen extends StatefulWidget {
  const PremiumTvScreen({Key? key}) : super(key: key);

  @override
  State<PremiumTvScreen> createState() => _PremiumTvScreenState();
}

class _PremiumTvScreenState extends State<PremiumTvScreen> {
  static const _gold = Color(0xFFE6C978);
  static const _goldDeep = Color(0xFFD2B36C);
  static const _background = Color(0xFF08080D);
  static const _surface = Color(0xFF141420);

  final TextEditingController _searchController = TextEditingController();

  _PremiumLayout _layout = _PremiumLayout.grid;
  String _query = '';
  bool _catalogueRefreshStarted = false;

  @override
  void initState() {
    super.initState();
    _refreshPremiumCatalogue();
  }

  Future<void> _refreshPremiumCatalogue() async {
    if (_catalogueRefreshStarted) return;
    _catalogueRefreshStarted = true;
    await _PremiumCatalogue.refresh();
    if (mounted) setState(() {});
  }

  static const List<_PremiumCategory> _categories = [
    _PremiumCategory(
      1,
      'Xame News',
      'Global and African news',
      Icons.newspaper_rounded,
    ),
    _PremiumCategory(
      2,
      'Xame Sports',
      'Sports and live events',
      Icons.sports_soccer_rounded,
    ),
    _PremiumCategory(
      3,
      'Xame Kids',
      'Kids and family entertainment',
      Icons.child_care_rounded,
    ),
    _PremiumCategory(
      4,
      'Xame Cinema',
      'Movies and cinema',
      Icons.local_movies_rounded,
    ),
    _PremiumCategory(
      5,
      'Xame Music',
      'Music and live performances',
      Icons.music_note_rounded,
    ),
    _PremiumCategory(
      6,
      'Xame Nature',
      'Nature and wildlife',
      Icons.park_rounded,
    ),
    _PremiumCategory(
      7,
      'Xame History',
      'History and culture',
      Icons.account_balance_rounded,
    ),
    _PremiumCategory(
      8,
      'Xame Science',
      'Science and discovery',
      Icons.science_rounded,
    ),
    _PremiumCategory(
      9,
      'Xame Lifestyle',
      'Lifestyle and entertainment',
      Icons.auto_awesome_rounded,
    ),
    _PremiumCategory(
      10,
      'Xame Travel',
      'Travel and destinations',
      Icons.flight_takeoff_rounded,
    ),
    _PremiumCategory(
      11,
      'Xame Food',
      'Food and cooking',
      Icons.restaurant_rounded,
    ),
    _PremiumCategory(
      12,
      'Xame World',
      'International television',
      Icons.public_rounded,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_PremiumCategory> get _filteredCategories {
    final available = _PremiumCatalogue.categories.isNotEmpty
        ? _PremiumCatalogue.categories
        : _categories;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return available;

    return available.where((category) {
      return category.number.toString().padLeft(3, '0').contains(query) ||
          category.name.toLowerCase().contains(query) ||
          category.description.toLowerCase().contains(query);
    }).toList();
  }

  void _openCategory(_PremiumCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PremiumCategoryScreen(category: category),
      ),
    );
  }

  Future<void> _openLibrary(bool favorites) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _PremiumLibraryScreen(favorites: favorites),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _filteredCategories;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        titleSpacing: 0,
        title: const Text(
          'PREMIUM TV',
          style: TextStyle(
            color: _gold,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: _PremiumSearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                hintText: 'Search categories...',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _PremiumLayoutSwitcher(
                value: _layout,
                onChanged: (value) => setState(() => _layout = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openLibrary(true),
                      icon: const Icon(Icons.favorite_rounded),
                      label: const Text('Favourites'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _goldDeep),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openLibrary(false),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Recently Watched'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _goldDeep),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const _EmptySearchState(
                      title: 'No categories found',
                      message: 'Try another category name or number.',
                    )
                  : _PremiumCategoryCatalogue(
                      categories: categories,
                      layout: _layout,
                      onCategoryTap: _openCategory,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumCategory {
  final int number;
  final String name;
  final String description;
  final IconData icon;
  final String? categoryId;

  const _PremiumCategory(
    this.number,
    this.name,
    this.description,
    this.icon, {
    this.categoryId,
  });
}

class _PremiumCategoryScreen extends StatefulWidget {
  final _PremiumCategory category;

  const _PremiumCategoryScreen({
    required this.category,
  });

  @override
  State<_PremiumCategoryScreen> createState() =>
      _PremiumCategoryScreenState();
}

class _PremiumCategoryScreenState extends State<_PremiumCategoryScreen> {
  static const _gold = Color(0xFFE6C978);
  static const _goldDeep = Color(0xFFD2B36C);
  static const _background = Color(0xFF08080D);
  static const _surface = Color(0xFF141420);

  final TextEditingController _searchController = TextEditingController();

  _PremiumLayout _layout = _PremiumLayout.grid;
  String _query = '';

  List<_PremiumChannel> get _channels =>
      _PremiumCatalogue.channelsFor(
        widget.category.name,
        categoryId: widget.category.categoryId,
      );

  List<_PremiumChannel> get _filteredChannels {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _channels;

    return _channels.where((channel) {
      return channel.number.toString().padLeft(3, '0').contains(query) ||
          channel.name.toLowerCase().contains(query) ||
          channel.country.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChannel(_PremiumChannel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PremiumChannelViewer(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _filteredChannels;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        titleSpacing: 0,
        title: Text(
          widget.category.name,
          style: const TextStyle(
            color: _gold,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: _PremiumSearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                hintText: 'Search channels...',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _PremiumLayoutSwitcher(
                value: _layout,
                onChanged: (value) => setState(() => _layout = value),
              ),
            ),
            Expanded(
              child: channels.isEmpty
                  ? const _EmptySearchState(
                      title: 'No channels found',
                      message: 'Try another channel name or number.',
                    )
                  : _PremiumChannelCatalogue(
                      channels: channels,
                      layout: _layout,
                      onChannelTap: _openChannel,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumCatalogue {
  static final PremiumTvCatalogueService _service =
      PremiumTvCatalogueService();

  static List<_PremiumCategory> _remoteCategories = const [];
  static List<_PremiumChannel> _remoteChannels = const [];
  static Map<String, String> _remoteCategoryIds = const {};
  static Future<void>? _refreshInFlight;

  static List<_PremiumCategory> get categories => _remoteCategories;

  static Future<void> refresh() async {
    final pending = _refreshInFlight;
    if (pending != null) {
      await pending;
      return;
    }

    final future = _loadRemoteCatalogue();
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  static Future<void> _loadRemoteCatalogue() async {
    try {
      final data = await _service.fetchCatalogue();
      if (data.categories.isEmpty) return;

      final categories = <_PremiumCategory>[];
      final idsByName = <String, String>{};

      for (var i = 0; i < data.categories.length; i++) {
        final item = data.categories[i];
        final id = item['categoryId'] as String;
        final name = (item['name'] as String).trim();

        final description = item['description'] is String
            ? (item['description'] as String).trim()
            : '';
        final iconKey = item['iconKey'] is String
            ? (item['iconKey'] as String).trim().toLowerCase()
            : 'tv';

        categories.add(
          _PremiumCategory(
            categories.length + 1,
            name,
            description,
            _iconFor(iconKey),
            categoryId: id,
          ),
        );
        idsByName.putIfAbsent(name, () => id);
      }

      final categoryNameById = <String, String>{
        for (final category in categories)
          if (category.categoryId != null)
            category.categoryId!: category.name,
      };
      final channels = <_PremiumChannel>[];

      String? safeHttpUrl(dynamic value) {
        if (value is! String) return null;
        final uri = Uri.tryParse(value.trim());
        if (uri == null ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.host.isEmpty) {
          return null;
        }
        return uri.toString();
      }

      for (final item in data.channels) {
        final categoryId = item['categoryId'] as String;
        final categoryName = categoryNameById[categoryId];
        if (categoryName == null) continue;

        final rawNumber = item['number'] as num;
        final rawCountry = item['country'];
        final rawLegacyIds = item['legacyIds'];
        final tier = item['accessTier'];

        channels.add(
          _PremiumChannel(
            rawNumber.toInt(),
            (item['name'] as String).trim(),
            categoryName,
            rawCountry is String ? rawCountry : 'INT',
            streamUrl: safeHttpUrl(item['streamUrl']),
            artworkUrl: safeHttpUrl(item['artworkUrl']),
            accessTier: tier == 'bonusFree'
                ? _PremiumAccessTier.bonusFree
                : _PremiumAccessTier.subscriptionRequired,
            categoryId: categoryId,
            remoteId: item['channelId'] as String,
            legacyIds: rawLegacyIds is List
                ? rawLegacyIds.whereType<String>().toList(growable: false)
                : const [],
          ),
        );
      }

      // Keep the current/static catalogue unless the remote snapshot is usable.
      if (categories.isEmpty) return;

      _remoteCategoryIds = Map.unmodifiable(idsByName);
      _remoteChannels = List.unmodifiable(channels);
      _remoteCategories = List.unmodifiable(categories);
    } catch (_) {
      // Remote failure leaves the static catalogue available.
    }
  }

  static IconData _iconFor(String key) {
    switch (key) {
      case 'news':
      case 'newspaper':
        return Icons.newspaper_rounded;
      case 'sports':
      case 'sport':
        return Icons.sports_soccer_rounded;
      case 'kids':
      case 'child':
        return Icons.child_care_rounded;
      case 'cinema':
      case 'movies':
        return Icons.local_movies_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'nature':
        return Icons.park_rounded;
      case 'history':
        return Icons.account_balance_rounded;
      case 'science':
        return Icons.science_rounded;
      case 'travel':
        return Icons.flight_takeoff_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'world':
      case 'international':
        return Icons.public_rounded;
      case 'lifestyle':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.live_tv_rounded;
    }
  }

  static List<_PremiumChannel> channelsFor(
    String category, {
    String? categoryId,
  }) {
    final resolvedCategoryId =
        categoryId ?? _remoteCategoryIds[category];

    if (resolvedCategoryId != null) {
      return _remoteChannels
          .where((channel) => channel.categoryId == resolvedCategoryId)
          .toList(growable: false);
    }

    switch (category) {
      case 'Xame News':
        return _news;
      case 'Xame Sports':
        return _sports;
      case 'Xame Kids':
        return _kids;
      case 'Xame Cinema':
        return _cinema;
      case 'Xame Music':
        return _music;
      case 'Xame Nature':
        return _nature;
      case 'Xame History':
        return _history;
      case 'Xame Science':
        return _science;
      case 'Xame Lifestyle':
        return _lifestyle;
      case 'Xame Travel':
        return _travel;
      case 'Xame Food':
        return _food;
      case 'Xame World':
        return _world;
      default:
        return const [];
    }
  }

  static const List<_PremiumChannel> _news = [
    _PremiumChannel(1, 'CNN', 'Xame News', 'US'),
    _PremiumChannel(2, 'BBC News', 'Xame News', 'UK'),
    _PremiumChannel(3, 'Al Jazeera English', 'Xame News', 'QA'),
    _PremiumChannel(4, 'NTA News', 'Xame News', 'NG'),
  ];

  static const List<_PremiumChannel> _sports = [
    _PremiumChannel(1, 'FIFA English', 'Xame Sports', 'INT'),
    _PremiumChannel(2, 'SuperSport', 'Xame Sports', 'ZA'),
    _PremiumChannel(3, 'ESPN', 'Xame Sports', 'US'),
    _PremiumChannel(4, 'Trace Sport Stars', 'Xame Sports', 'FR'),
  ];

  static const List<_PremiumChannel> _kids = [
    _PremiumChannel(1, 'Cartoon Network', 'Xame Kids', 'US'),
    _PremiumChannel(2, 'Nickelodeon', 'Xame Kids', 'US'),
    _PremiumChannel(3, 'Disney Channel', 'Xame Kids', 'US'),
    _PremiumChannel(4, 'Disney Junior', 'Xame Kids', 'US'),
    _PremiumChannel(5, 'Nick Jr.', 'Xame Kids', 'US'),
    _PremiumChannel(6, 'CBeebies', 'Xame Kids', 'UK'),
    _PremiumChannel(7, 'BabyTV', 'Xame Kids', 'INT'),
    _PremiumChannel(8, 'PBS Kids', 'Xame Kids', 'US'),
  ];

  static const List<_PremiumChannel> _cinema = [
    _PremiumChannel(1, 'Hollywood', 'Xame Cinema', 'US'),
    _PremiumChannel(2, 'Nollywood', 'Xame Cinema', 'NG'),
    _PremiumChannel(3, 'Bollywood', 'Xame Cinema', 'IN'),
    _PremiumChannel(4, 'African Cinema', 'Xame Cinema', 'AF'),
    _PremiumChannel(5, 'Action', 'Xame Cinema', 'INT'),
    _PremiumChannel(6, 'Drama', 'Xame Cinema', 'INT'),
    _PremiumChannel(7, 'Comedy', 'Xame Cinema', 'INT'),
    _PremiumChannel(8, 'Romance', 'Xame Cinema', 'INT'),
    _PremiumChannel(9, 'Classic Movies', 'Xame Cinema', 'INT'),
  ];

  static const List<_PremiumChannel> _music = [
    _PremiumChannel(1, 'NOW 70s', 'Xame Music', 'UK'),
    _PremiumChannel(2, 'NOW 80s', 'Xame Music', 'UK'),
    _PremiumChannel(3, 'NOW Rock', 'Xame Music', 'UK'),
    _PremiumChannel(4, 'Qwest TV Jazz & Beyond', 'Xame Music', 'FR'),
    _PremiumChannel(5, 'Trace Urban', 'Xame Music', 'FR'),
    _PremiumChannel(6, 'Vevo 2K', 'Xame Music', 'US'),
    _PremiumChannel(7, 'Vevo 70s', 'Xame Music', 'US'),
    _PremiumChannel(8, 'Vevo 80s', 'Xame Music', 'US'),
    _PremiumChannel(9, 'Vevo 90s', 'Xame Music', 'US'),
    _PremiumChannel(10, 'Vevo Country', 'Xame Music', 'US'),
    _PremiumChannel(11, 'Vevo Pop', 'Xame Music', 'US'),
    _PremiumChannel(12, 'Vevo Retro Rock', 'Xame Music', 'US'),
  ];

  static const List<_PremiumChannel> _nature = [
    _PremiumChannel(1, 'Love Nature', 'Xame Nature', 'CA'),
    _PremiumChannel(2, 'InWild', 'Xame Nature', 'INT'),
    _PremiumChannel(3, 'NatureTime', 'Xame Nature', 'CA'),
    _PremiumChannel(4, 'MagellanTV Nature', 'Xame Nature', 'INT'),
  ];

  static const List<_PremiumChannel> _history = [
    _PremiumChannel(1, 'History', 'Xame History', 'US'),
    _PremiumChannel(2, 'History Hit', 'Xame History', 'UK'),
    _PremiumChannel(3, 'Classic History', 'Xame History', 'INT'),
  ];

  static const List<_PremiumChannel> _science = [
    _PremiumChannel(1, 'Science', 'Xame Science', 'INT'),
    _PremiumChannel(2, 'Discovery Science', 'Xame Science', 'INT'),
    _PremiumChannel(3, 'Science & Discovery', 'Xame Science', 'INT'),
  ];

  static const List<_PremiumChannel> _lifestyle = [
    _PremiumChannel(1, 'Lifestyle', 'Xame Lifestyle', 'INT'),
    _PremiumChannel(2, 'Food Network', 'Xame Lifestyle', 'US'),
    _PremiumChannel(3, 'Travel Channel', 'Xame Lifestyle', 'US'),
  ];

  static const List<_PremiumChannel> _travel = [
    _PremiumChannel(1, 'Travel Channel', 'Xame Travel', 'US'),
    _PremiumChannel(2, 'Travel XP', 'Xame Travel', 'INT'),
    _PremiumChannel(3, 'World Travel', 'Xame Travel', 'INT'),
  ];

  static const List<_PremiumChannel> _food = [
    _PremiumChannel(1, 'Food Network', 'Xame Food', 'US'),
    _PremiumChannel(2, 'Cooking Channel', 'Xame Food', 'US'),
    _PremiumChannel(3, 'Taste', 'Xame Food', 'INT'),
  ];

  static const List<_PremiumChannel> _world = [
    _PremiumChannel(1, 'International News', 'Xame World', 'INT'),
    _PremiumChannel(2, 'African Entertainment', 'Xame World', 'AF'),
    _PremiumChannel(3, 'Global Entertainment', 'Xame World', 'INT'),
  ];
}

class _PremiumLibrary {
  static const _favoritesKey = 'xametv_premium_favorites_v1';
  static const _recentKey = 'xametv_premium_recent_v1';
  static const _recentLimit = 30;

  static Future<List<String>> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(key) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  static Future<bool?> toggleFavorite(_PremiumChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_favoritesKey) ?? <String>[];
      final aliases = <String>{
        channel.libraryId,
        if (channel.remoteId != null && channel.remoteId!.isNotEmpty)
          channel.remoteId!,
        ...channel.legacyIds.where((id) => id.isNotEmpty),
      };
      final nowFavorite = !ids.any(aliases.contains);
      ids.removeWhere(aliases.contains);
      if (nowFavorite) ids.insert(0, channel.libraryId);
      final saved = await prefs.setStringList(_favoritesKey, ids);
      return saved ? nowFavorite : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> removeFavorite(_PremiumChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_favoritesKey) ?? <String>[];
      final aliases = <String>{
        channel.libraryId,
        if (channel.remoteId != null && channel.remoteId!.isNotEmpty)
          channel.remoteId!,
        ...channel.legacyIds.where((id) => id.isNotEmpty),
      };
      ids.removeWhere(aliases.contains);
      return await prefs.setStringList(_favoritesKey, ids);
    } catch (_) {
      return false;
    }
  }

  static Future<void> recordWatched(_PremiumChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_recentKey) ?? <String>[];
      final aliases = <String>{
        channel.libraryId,
        if (channel.remoteId != null && channel.remoteId!.isNotEmpty)
          channel.remoteId!,
        ...channel.legacyIds.where((id) => id.isNotEmpty),
      };
      ids.removeWhere(aliases.contains);
      ids.insert(0, channel.libraryId);
      if (ids.length > _recentLimit) {
        ids.removeRange(_recentLimit, ids.length);
      }
      await prefs.setStringList(_recentKey, ids);
    } catch (_) {
      // History storage must never interrupt playback.
    }
  }

  static Future<List<String>> favorites() => _read(_favoritesKey);
  static Future<List<String>> recent() => _read(_recentKey);

  static List<_PremiumChannel> resolve(List<String> ids) {
    final wanted = ids.toSet();
    final byId = <String, _PremiumChannel>{};
    final categories = <_PremiumCategory>{
      ..._PremiumTvScreenState._categories,
      ..._PremiumCatalogue.categories,
    };
    for (final category in categories) {
      for (final channel in _PremiumCatalogue.channelsFor(
        category.name,
        categoryId: category.categoryId,
      )) {
        byId[channel.libraryId] = channel;
        final remoteId = channel.remoteId;
        if (remoteId != null && remoteId.isNotEmpty) {
          byId[remoteId] = channel;
        }
        for (final legacyId in channel.legacyIds) {
          byId[legacyId] = channel;
        }
      }
    }
    return ids
        .where(wanted.contains)
        .map((id) => byId[id])
        .whereType<_PremiumChannel>()
        .toList();
  }
}

enum _PremiumAccessTier {
  bonusFree,
  subscriptionRequired,
}

class _PremiumChannel {
  final int number;
  final String name;
  final String category;
  final String country;
  final String? categoryId;
  final String? streamUrl;
  final String? artworkUrl;
  final _PremiumAccessTier accessTier;
  final String? remoteId;
  final List<String> legacyIds;

  String get libraryId =>
      '${category.toLowerCase()}|$number|${name.toLowerCase()}';

  const _PremiumChannel(
    this.number,
    this.name,
    this.category,
    this.country, {
    this.streamUrl,
    this.artworkUrl,
    this.categoryId,
    this.accessTier = _PremiumAccessTier.subscriptionRequired,
    this.remoteId,
    this.legacyIds = const [],
  });
}

class _PremiumCategoryCatalogue extends StatelessWidget {
  final List<_PremiumCategory> categories;
  final _PremiumLayout layout;
  final ValueChanged<_PremiumCategory> onCategoryTap;

  const _PremiumCategoryCatalogue({
    required this.categories,
    required this.layout,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case _PremiumLayout.grid:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 9,
            mainAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: categories.length,
          itemBuilder: (_, index) {
            final category = categories[index];
            return _GridCategoryCard(
              category: category,
              onTap: () => onCategoryTap(category),
            );
          },
        );

      case _PremiumLayout.list:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final category = categories[index];
            return _ListCategoryCard(
              category: category,
              onTap: () => onCategoryTap(category),
            );
          },
        );

      case _PremiumLayout.large:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: categories.length,
          itemBuilder: (_, index) {
            final category = categories[index];
            return _LargeCategoryCard(
              category: category,
              onTap: () => onCategoryTap(category),
            );
          },
        );
    }
  }
}

class _PremiumChannelCatalogue extends StatelessWidget {
  final List<_PremiumChannel> channels;
  final _PremiumLayout layout;
  final ValueChanged<_PremiumChannel> onChannelTap;

  const _PremiumChannelCatalogue({
    required this.channels,
    required this.layout,
    required this.onChannelTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case _PremiumLayout.grid:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 9,
            mainAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: channels.length,
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _GridChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );

      case _PremiumLayout.list:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: channels.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _ListChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );

      case _PremiumLayout.large:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: channels.length,
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _LargeChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );
    }
  }
}

class _GridCategoryCard extends StatelessWidget {
  final _PremiumCategory category;
  final VoidCallback onTap;

  const _GridCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CategoryCardShell(
      category: category,
      onTap: onTap,
      child: _PremiumCategoryArtwork(category: category),
    );
  }
}

class _ListCategoryCard extends StatelessWidget {
  final _PremiumCategory category;
  final VoidCallback onTap;

  const _ListCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 52,
                child: _PremiumCategoryArtwork(
                  category: category,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeCategoryCard extends StatelessWidget {
  final _PremiumCategory category;
  final VoidCallback onTap;

  const _LargeCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CategoryCardShell(
      category: category,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _PremiumCategoryArtwork(category: category),
          ),
          const SizedBox(height: 12),
          Text(
            category.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category.description,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCardShell extends StatelessWidget {
  final _PremiumCategory category;
  final VoidCallback onTap;
  final Widget child;

  const _CategoryCardShell({
    required this.category,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A2417),
                      Color(0xFF141420),
                      Color(0xFF0E0E14),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: _ChannelNumber(number: category.number),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumCategoryArtwork extends StatelessWidget {
  static const _logoAsset = 'assets/icons/xamepage_icon.png';

  final _PremiumCategory category;
  final bool compact;

  const _PremiumCategoryArtwork({
    required this.category,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 11 : 14),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.15,
            colors: [
              Color(0xFF292217),
              Color(0xFF141420),
              Color(0xFF08080D),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.icon,
              size: compact ? 28 : 46,
              color: _PremiumTvScreenState._gold,
            ),
            SizedBox(height: compact ? 5 : 10),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 12,
              ),
              child: Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 9 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  category.description,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            if (!compact) ...[
              const SizedBox(height: 12),
              Image.asset(
                _logoAsset,
                height: 20,
                fit: BoxFit.contain,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PremiumAccessBadge extends StatelessWidget {
  final _PremiumAccessTier tier;
  final bool compact;

  const _PremiumAccessBadge({
    required this.tier,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBonus = tier == _PremiumAccessTier.bonusFree;
    final label = isBonus
        ? (compact ? 'BONUS • FREE' : 'BONUS • WATCH FREE')
        : (compact ? 'PREMIUM' : 'PREMIUM • SUBSCRIPTION REQUIRED');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: isBonus
            ? const Color(0xFF183D2A)
            : const Color(0xFF342A16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isBonus
              ? const Color(0xFF64C98A)
              : const Color(0xFFE6C978),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isBonus
              ? const Color(0xFF9CF0B8)
              : const Color(0xFFE6C978),
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _GridChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _GridChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ChannelCardShell(
      channel: channel,
      onTap: onTap,
      child: _PremiumChannelArtwork(channel: channel),
    );
  }
}

class _ListChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _ListChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 52,
                child: _PremiumChannelArtwork(
                  channel: channel,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${channel.country} • ${channel.category}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _PremiumAccessBadge(
                        tier: channel.accessTier,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _LargeChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ChannelCardShell(
      channel: channel,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _PremiumChannelArtwork(channel: channel),
          ),
          const SizedBox(height: 12),
          Text(
            channel.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            channel.country,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCardShell extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;
  final Widget child;

  const _ChannelCardShell({
    required this.channel,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A2417),
                      Color(0xFF141420),
                      Color(0xFF0E0E14),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: _PremiumAccessBadge(
                tier: channel.accessTier,
                compact: true,
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelNumber extends StatelessWidget {
  final int number;

  const _ChannelNumber({
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: _PremiumTvScreenState._goldDeep.withOpacity(0.55),
        ),
      ),
      child: Text(
        number.toString().padLeft(3, '0'),
        style: const TextStyle(
          color: _PremiumTvScreenState._gold,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _PremiumLayoutSwitcher extends StatelessWidget {
  final _PremiumLayout value;
  final ValueChanged<_PremiumLayout> onChanged;

  const _PremiumLayoutSwitcher({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _PremiumTvScreenState._surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _PremiumTvScreenState._goldDeep.withOpacity(0.16),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _item(_PremiumLayout.grid, Icons.grid_view_rounded, 'Grid'),
          _item(_PremiumLayout.list, Icons.view_list_rounded, 'List'),
          _item(_PremiumLayout.large, Icons.view_agenda_rounded, 'Large'),
        ],
      ),
    );
  }

  Widget _item(
    _PremiumLayout layout,
    IconData icon,
    String label,
  ) {
    final selected = value == layout;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(layout),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? _PremiumTvScreenState._goldDeep.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(
                    color: _PremiumTvScreenState._goldDeep.withOpacity(0.32),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? _PremiumTvScreenState._gold
                    : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  const _PremiumSearchField({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.42)),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: _PremiumTvScreenState._gold,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                color: Colors.white54,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: _PremiumTvScreenState._surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String title;
  final String message;

  const _EmptySearchState({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.35),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumLibraryScreen extends StatefulWidget {
  final bool favorites;

  const _PremiumLibraryScreen({required this.favorites});

  @override
  State<_PremiumLibraryScreen> createState() =>
      _PremiumLibraryScreenState();
}

class _PremiumLibraryScreenState extends State<_PremiumLibraryScreen> {
  bool _loading = true;
  List<_PremiumChannel> _channels = <_PremiumChannel>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = widget.favorites
        ? await _PremiumLibrary.favorites()
        : await _PremiumLibrary.recent();
    if (!mounted) return;
    setState(() {
      _channels = _PremiumLibrary.resolve(ids);
      _loading = false;
    });
  }

  Future<void> _removeFavorite(_PremiumChannel channel) async {
    final saved = await _PremiumLibrary.removeFavorite(channel);
    if (!mounted || !saved) return;
    setState(() => _channels.removeWhere(
          (item) => item.libraryId == channel.libraryId,
        ));
  }

  Future<void> _openChannel(_PremiumChannel channel) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _PremiumChannelViewer(channel: channel),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF08080D);
    const gold = Color(0xFFE6C978);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: Text(
          widget.favorites ? 'FAVOURITES' : 'RECENTLY WATCHED',
          style: const TextStyle(
            color: gold,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: gold),
            )
          : _channels.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      widget.favorites
                          ? 'Your favourite channels will appear here.'
                          : 'Channels appear here after playback starts successfully.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _channels.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0x22FFFFFF)),
                  itemBuilder: (context, index) {
                    final channel = _channels[index];
                    return ListTile(
                      onTap: () => _openChannel(channel),
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF342A16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          channel.number.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            color: gold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        channel.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${channel.category} • ${channel.country}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      trailing: widget.favorites
                          ? IconButton(
                              tooltip: 'Remove favourite',
                              onPressed: () => _removeFavorite(channel),
                              icon: const Icon(
                                Icons.favorite_rounded,
                                color: gold,
                              ),
                            )
                          : const Icon(
                              Icons.play_circle_outline_rounded,
                              color: gold,
                            ),
                    );
                  },
                ),
    );
  }
}

class _PremiumChannelViewer extends StatefulWidget {
  final _PremiumChannel channel;

  const _PremiumChannelViewer({
    required this.channel,
  });

  @override
  State<_PremiumChannelViewer> createState() =>
      _PremiumChannelViewerState();
}

class _PremiumChannelViewerState extends State<_PremiumChannelViewer> {
  static const _officialTvcLiveUrl = 'https://www.tvcnews.tv/live-streaming/';
  BetterPlayerController? _controller;
  Timer? _youtubeReadyTimeout;
  YoutubePlayerController? _youtubeController;
  bool _loading = false;
  String? _error;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
    final url = widget.channel.streamUrl?.trim();
    if (url == null || url.isEmpty) {
      _error = 'No stream is configured for this channel yet.';
    } else {
      final videoId = _youtubeVideoIdFromUrl(url);
      if (videoId != null) {
        _initializeYoutubePlayer(videoId);
      } else {
        _initializePlayer(url);
      }
    }
  }

  Future<void> _loadFavorite() async {
    final ids = await _PremiumLibrary.favorites();
    if (!mounted) return;
    setState(() => _isFavorite = ids.contains(widget.channel.libraryId));
  }

  Future<void> _toggleFavorite() async {
    final result = await _PremiumLibrary.toggleFavorite(widget.channel);
    if (!mounted || result == null) return;
    setState(() => _isFavorite = result);
  }

  String? _youtubeVideoIdFromUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    const allowedHosts = {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'youtube-nocookie.com',
      'www.youtube-nocookie.com',
      'youtu.be',
      'www.youtu.be',
    };
    if (!allowedHosts.contains(host)) return null;

    final id = YoutubePlayer.convertUrlToId(value.trim());
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return null;
    }
    return id;
  }

  void _handleYoutubeControllerChange() {
    final player = _youtubeController;
    if (!mounted || player == null) return;

    final errorCode = player.value.errorCode;
    if (errorCode != 0 && _error == null) {
      _youtubeReadyTimeout?.cancel();
      setState(() {
        _loading = false;
        _error = 'YouTube could not play this stream (error $errorCode).';
      });
    }
  }

  Future<void> _openOfficialTvcStream() async {
    try {
      final opened = await launchUrl(
        Uri.parse(_officialTvcLiveUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() {
          _error = 'Could not open the TVC News website. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open the TVC News website. Please try again.';
      });
    }
  }

  Future<void> _initializeYoutubePlayer(String videoId) async {
    _loading = true;

    final player = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: true,
      ),
    );
    _youtubeController = player;
    player.addListener(_handleYoutubeControllerChange);

    _youtubeReadyTimeout?.cancel();
    _youtubeReadyTimeout = Timer(const Duration(seconds: 20), () {
      if (!mounted || _youtubeController != player || !_loading) return;
      setState(() {
        _loading = false;
        _error ??=
            'The embedded stream is taking too long to load. Open TVC News in your browser.';
      });
    });

    try {
      await _PremiumLibrary.recordWatched(widget.channel);
    } catch (_) {
      // Viewing-history failure must not prevent playback.
    }
  }

  Future<void> _initializePlayer(String url) async {
    if (mounted) setState(() => _loading = true);

    final player = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: true,
        looping: false,
        fit: BoxFit.contain,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: true,
        ),
      ),
    );

    try {
      await player.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          url,
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 1500,
            maxBufferMs: 10000,
            bufferForPlaybackMs: 300,
            bufferForPlaybackAfterRebufferMs: 700,
          ),
        ),
      );

      if (player.videoPlayerController?.value.initialized != true) {
        throw StateError('Premium TV player failed to initialize.');
      }

      if (!mounted) {
        player.dispose();
        return;
      }

      await _PremiumLibrary.recordWatched(widget.channel);
      if (!mounted) {
        player.dispose();
        return;
      }

      setState(() {
        _controller = player;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      player.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _loading = false;
        _error = 'Unable to play this stream. Please try again later.';
      });
    }
  }

  @override
  void dispose() {
    _youtubeReadyTimeout?.cancel();
    _controller?.dispose();
    _youtubeController?.removeListener(_handleYoutubeControllerChange);
    _youtubeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_youtubeController != null)
            Center(
              child: YoutubePlayer(
                controller: _youtubeController!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: const Color(0xFFE6C978),
                onReady: () {
                  if (!mounted) return;
                  final errorCode = _youtubeController?.value.errorCode ?? 0;
                  if (errorCode == 0) {
                    _youtubeReadyTimeout?.cancel();
                  }
                  setState(() {
                    _loading = false;
                    if (errorCode == 0) {
                      _error = null;
                    } else {
                      _error ??=
                          'YouTube could not play this stream (error $errorCode).';
                    }
                  });
                },
              ),
            )
          else if (_controller != null)
            Center(child: BetterPlayer(controller: _controller!))
          else
            _PremiumChannelArtwork(channel: channel, viewer: true),

          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFE6C978)),
            ),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xE6141420),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x55E6C978)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.live_tv_rounded,
                        color: Color(0xFFE6C978),
                        size: 38,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      if (_youtubeController != null &&
                          widget.channel.remoteId == 'tvc-news') ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _openOfficialTvcStream,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: const Text('Open official TVC stream'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE6C978),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _ChannelNumber(number: channel.number),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${channel.country} • ${channel.category}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PremiumAccessBadge(tier: channel.accessTier),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: const Color(0xFFE6C978),
                      ),
                      label: Text(
                        _isFavorite ? 'Remove Favourite' : 'Add to Favourites',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0x55E6C978)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumChannelArtwork extends StatelessWidget {
  static const _logoAsset = 'assets/icons/xamepage_icon.png';

  final _PremiumChannel channel;
  final bool compact;
  final bool viewer;

  const _PremiumChannelArtwork({
    required this.channel,
    this.compact = false,
    this.viewer = false,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = channel.artworkUrl == null
        ? _placeholder()
        : Image.network(
            channel.artworkUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _placeholder(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        compact ? 11 : (viewer ? 0 : 14),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2A2417),
                  Color(0xFF141420),
                  Color(0xFF08080D),
                ],
              ),
            ),
          ),
          artwork,
          if (!viewer)
            Positioned(
              top: compact ? 5 : 7,
              left: compact ? 5 : 7,
              child: _ChannelNumber(number: channel.number),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.15,
          colors: [
            Color(0xFF292217),
            Color(0xFF141420),
            Color(0xFF08080D),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(compact ? 7 : 18),
                child: Image.asset(
                  _logoAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 2 : 8,
              0,
              compact ? 2 : 8,
              compact ? 2 : 12,
            ),
            child: Text(
              'Coming Soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: compact ? 7 : (viewer ? 15 : 12),
                fontWeight: FontWeight.w700,
                letterSpacing: compact ? 0.15 : 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
