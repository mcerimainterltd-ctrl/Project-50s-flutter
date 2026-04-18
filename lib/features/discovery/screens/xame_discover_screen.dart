import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/people_carousel.dart';
import '../widgets/stories_bar.dart';
import '../widgets/region_filter_bar.dart';
import '../widgets/live_pulse.dart';
import '../models/discovery_item.dart';

final _rng = Random(42);

List<DiscoveryItem> _mockFeed(String regionCode) {
  final seeds = [
    ('Pacific Storm Surge',   'Pacific',       'https://picsum.photos/seed/p1/800/1200',   false, 12400, 3200),
    ('Atlantic Heritage',     'Atlantic',      'https://picsum.photos/seed/a1/800/1200',   false,  8900, 2100),
    ('Arctic Expedition',     'Arctic',        'https://picsum.photos/seed/ar1/800/1200',  false,  5600, 1400),
    ('Mediterranean Blue',    'Mediterranean', 'https://picsum.photos/seed/m1/800/1200',   false, 19200, 4800),
    ('Deep Sea Indian Ocean', 'Indian',        'https://picsum.photos/seed/i1/800/1200',   false,  7300, 1900),
    ('Global Maritime Trade', 'Global',        'https://picsum.photos/seed/g1/800/1200',   false, 22100, 5500),
    ('Live from Lagos',       'Nigeria',       'https://picsum.photos/seed/ng1/800/1200',  true,  41000, 9800),
    ('Accra Street Art',      'Ghana',         'https://picsum.photos/seed/gh1/800/1200',  false,  6200, 1500),
    ('Nairobi Tech Week',     'Kenya',         'https://picsum.photos/seed/ke1/800/1200',  false, 11300, 2700),
    ('Cape Town Sunsets',     'South Africa',  'https://picsum.photos/seed/za1/800/1200',  false,  8800, 2200),
    ('Tokyo Neon Nights',     'Japan',         'https://picsum.photos/seed/jp1/800/1200',  false, 31200, 7600),
    ('London Street Style',   'UK',            'https://picsum.photos/seed/uk1/800/1200',  false, 14500, 3600),
    ('New York Energy',       'USA',           'https://picsum.photos/seed/us1/800/1200',  true,  52000, 12100),
    ('Mumbai Monsoon',        'India',         'https://picsum.photos/seed/in1/800/1200',  false, 18700, 4500),
    ('Dubai Skyline',         'UAE',           'https://picsum.photos/seed/ae1/800/1200',  false, 23400, 5800),
  ];
  return seeds.map((s) => DiscoveryItem(
    id:             s.$1.toLowerCase().replaceAll(' ', '_'),
    title:          s.$1,
    subtitle:       s.$2,
    mediaUrl:       s.$3,
    authorName:     'XameCreator ${_rng.nextInt(99)}',
    authorAvatar:   'https://i.pravatar.cc/150?img=${_rng.nextInt(70)}',
    authorId:       'creator_${_rng.nextInt(999)}',
    region:         s.$2,
    category:       s.$2,
    type:           s.$4 ? DiscoveryType.live : DiscoveryType.post,
    isLive:         s.$4,
    isAuthorOnline: _rng.nextBool(),
    viewCount:      s.$5,
    likeCount:      s.$6,
    commentCount:   _rng.nextInt(500),
    ts: DateTime.now().subtract(Duration(hours: _rng.nextInt(48))),
  )).toList();
}

List<DiscoveryUser> _mockUsers() => List.generate(8, (i) => DiscoveryUser(
  id:           'user_$i',
  name:         ['Alex Morgan','Chioma Obi','Kwame Asante','Sofia Reyes',
                  'Yuki Tanaka','James Okafor','Amara Diallo','Lena Kovacs'][i],
  avatarUrl:    'https://i.pravatar.cc/150?img=${i + 20}',
  mutualCount:  _rng.nextInt(8) + 1,
  isOnline:     i % 2 == 0,
  tagline:      ['Creative director','Tech founder','Artist','Engineer',
                  'Photographer','Musician','Designer','Traveler'][i],
));

class XameDiscoverScreen extends ConsumerStatefulWidget {
  const XameDiscoverScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<XameDiscoverScreen> createState() => _XameDiscoverScreenState();
}

class _XameDiscoverScreenState extends ConsumerState<XameDiscoverScreen>
    with TickerProviderStateMixin {
  final _scrollCtrl  = ScrollController();
  final _searchCtrl  = TextEditingController();
  bool  _searchOpen  = false;
  bool  _loading     = true;
  String _regionCode = 'global';
  String _regionName = 'Global';
  String _searchQuery = '';
  late List<DiscoveryItem> _feed;
  late List<DiscoveryUser> _people;
  late AnimationController _searchAnim;
  late Animation<double>   _searchFade;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _searchFade = CurvedAnimation(
        parent: _searchAnim, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchAnim.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _feed    = _mockFeed(_regionCode);
      _people  = _mockUsers();
      _loading = false;
    });
  }

  List<DiscoveryItem> get _filtered {
    var list = _feed;
    if (_regionCode != 'global') {
      final region = discoveryRegions.firstWhere(
        (r) => r.code == _regionCode,
        orElse: () => discoveryRegions[0]);
      list = list.where((i) =>
        i.region == region.name || i.isLive).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((i) =>
        i.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        i.category.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    return list;
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    _searchAnim.forward();
    HapticFeedback.lightImpact();
  }

  void _closeSearch() {
    _searchAnim.reverse().then((_) {
      if (mounted) setState(() {
        _searchOpen  = false;
        _searchQuery = '';
        _searchCtrl.clear();
      });
    });
  }

  void _onRegionSelected(DiscoveryRegion region) {
    HapticFeedback.selectionClick();
    setState(() { _regionCode = region.code; _regionName = region.name; });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtrl,
          physics:    const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor:  const Color(0xFF0A0A0F),
              surfaceTintColor: Colors.transparent,
              floating: true, snap: true, elevation: 0,
              title: Row(children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF7B2FFF)],
                  ).createShader(b),
                  child: const Text('DISCOVERY',
                    style: TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                ),
                const SizedBox(width: 8),
                _LiveCountBadge(),
              ]),
              actions: [
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _searchOpen ? Icons.close : Icons.search,
                      key: ValueKey(_searchOpen), color: Colors.white70)),
                  onPressed: _searchOpen ? _closeSearch : _openSearch),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                  onPressed: () => _showFilterSheet(context)),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: DiscoveryStoriesBar(
                users: List.generate(8, (i) => {
                  'name':     i == 0 ? 'You' : _loading ? 'User $i'
                    : _people[i % _people.length].name.split(' ')[0],
                  'avatar':   _loading
                    ? 'https://i.pravatar.cc/150?img=$i'
                    : _people[i % _people.length].avatarUrl,
                  'hasSeen':  i == 0,
                  'isOnline': i % 2 == 0,
                }),
              ),
            ),
            SliverToBoxAdapter(
              child: RegionFilterBar(
                onRegionSelected: _onRegionSelected,
                initialCode:      _regionCode),
            ),
            if (!_loading && _people.isNotEmpty)
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: _people,
                  onAdd: (user) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Request sent to ${user.name}'),
                      backgroundColor: const Color(0xFF1A4A3A),
                      duration: const Duration(seconds: 2)));
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(children: [
                  Text(
                    _searchQuery.isNotEmpty
                      ? 'RESULTS FOR "${_searchQuery.toUpperCase()}"'
                      : 'TRENDING IN ${_regionName.toUpperCase()}',
                    style: const TextStyle(color: Colors.white38,
                        fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          color: Color(0xFF2196F3), strokeWidth: 1.5)),
                ]),
              ),
            ),
            if (_loading)
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, __) => const DiscoveryCardSkeleton(),
                childCount: 3))
            else if (_filtered.isEmpty)
              SliverToBoxAdapter(child: _EmptyState(region: _regionName))
            else
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = _filtered[i];
                  return MediaDiscoverCard(
                    mediaUrl:     item.mediaUrl,
                    title:        item.title,
                    category:     item.category,
                    isLive:       item.isLive,
                    authorName:   item.authorName,
                    authorAvatar: item.authorAvatar,
                    viewCount:    item.viewCount,
                    likeCount:    item.likeCount,
                    onTap: () => _openDetail(context, item),
                  );
                },
                childCount: _filtered.length)),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
        if (_searchOpen)
          FadeTransition(
            opacity: _searchFade,
            child: _SearchOverlay(
              ctrl:     _searchCtrl,
              onSearch: (q) => setState(() => _searchQuery = q),
              onClose:  _closeSearch,
              feed:     _loading ? [] : _feed,
            ),
          ),
      ]),
    );
  }

  void _openDetail(BuildContext context, DiscoveryItem item) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim, child: _DetailScreen(item: item)),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FilterSheet(
        currentRegion: _regionCode,
        onApply: (r) { Navigator.pop(context); _onRegionSelected(r); }),
    );
  }
}

class _LiveCountBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFF4444).withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5,
        decoration: const BoxDecoration(
          shape: BoxShape.circle, color: Color(0xFFFF4444))),
      const SizedBox(width: 4),
      const Text('3 LIVE', style: TextStyle(color: Color(0xFFFF4444),
          fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    ]),
  );
}

class _SearchOverlay extends StatefulWidget {
  final TextEditingController ctrl;
  final Function(String)      onSearch;
  final VoidCallback          onClose;
  final List<DiscoveryItem>   feed;
  const _SearchOverlay({required this.ctrl, required this.onSearch,
      required this.onClose, required this.feed});
  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  List<DiscoveryItem> _results = [];

  void _search(String q) {
    widget.onSearch(q);
    setState(() {
      _results = q.isEmpty ? [] : widget.feed.where((i) =>
        i.title.toLowerCase().contains(q.toLowerCase()) ||
        i.category.toLowerCase().contains(q.toLowerCase())
      ).take(6).toList();
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xF00A0A0F),
    child: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: widget.ctrl,
              autofocus:  true,
              onChanged:  _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:  'Search people, topics, moments...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38, size: 20),
                filled:    true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF2196F3), width: 1)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF2196F3),
                  fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
      ),
      Expanded(
        child: _results.isEmpty && widget.ctrl.text.isEmpty
          ? _SearchSuggestions()
          : _results.isEmpty
            ? const Center(child: Text('No results found',
                style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(item.mediaUrl,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 52, height: 52,
                          color: const Color(0xFF1A1A2E)))),
                    title: Text(item.title, style: const TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                    subtitle: Text(item.category,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                    trailing: item.isLive
                      ? const LivePulseIndicator(compact: true) : null,
                  );
                },
              ),
      ),
    ])),
  );
}

class _SearchSuggestions extends StatelessWidget {
  final _trending = const [
    '🔥 Afrobeats','⚡ Tech Africa','🌍 Global Culture',
    '🎬 Nollywood','🏆 Sport','🎨 Street Art',
    '💡 Startups','🌊 Ocean Life',
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TRENDING SEARCHES', style: TextStyle(
          color: Colors.white38, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8,
        children: _trending.map((t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10)),
          child: Text(t, style: const TextStyle(
              color: Colors.white60, fontSize: 13)),
        )).toList()),
    ]),
  );
}

class _FilterSheet extends StatefulWidget {
  final String currentRegion;
  final Function(DiscoveryRegion) onApply;
  const _FilterSheet({required this.currentRegion, required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _selected;
  @override
  void initState() { super.initState(); _selected = widget.currentRegion; }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('Filter by Region', style: TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SizedBox(height: 320,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, childAspectRatio: 2.2,
              crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: discoveryRegions.length,
            itemBuilder: (_, i) {
              final r          = discoveryRegions[i];
              final isSelected = r.code == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = r.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                      ? const Color(0xFF2196F3).withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                    border: Border.all(
                      color: isSelected
                        ? const Color(0xFF2196F3).withOpacity(0.5)
                        : Colors.white10)),
                  child: Center(child: Text('${r.flag} ${r.name}',
                    style: TextStyle(
                      color: isSelected
                        ? const Color(0xFF2196F3) : Colors.white54,
                      fontSize: 12,
                      fontWeight: isSelected
                        ? FontWeight.w700 : FontWeight.normal),
                    textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () {
              final r = discoveryRegions.firstWhere(
                  (r) => r.code == _selected);
              widget.onApply(r);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0),
            child: const Text('Apply Filter',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    ),
  );
}

class _DetailScreen extends StatelessWidget {
  final DiscoveryItem item;
  const _DetailScreen({required this.item});

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    body: CustomScrollView(slivers: [
      SliverAppBar(
        expandedHeight: 360, pinned: true,
        backgroundColor: const Color(0xFF0A0A0F),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5)),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 16)),
          onPressed: () => Navigator.pop(context)),
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(fit: StackFit.expand, children: [
            Image.network(item.mediaUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF1A1A2E))),
            Container(decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)]))),
            if (item.isLive)
              const Positioned(top: 60, right: 20,
                child: LivePulseIndicator()),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF2196F3).withOpacity(0.3))),
                child: Text(item.category.toUpperCase(),
                  style: const TextStyle(color: Color(0xFF2196F3),
                      fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 1))),
              const Spacer(),
              Text('${_fmt(item.viewCount)} views · ${_fmt(item.likeCount)} likes',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            Text(item.title, style: const TextStyle(color: Colors.white,
                fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 16),
            Row(children: [
              CircleAvatar(radius: 20,
                backgroundImage: NetworkImage(item.authorAvatar),
                backgroundColor: const Color(0xFF1A1A2E)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(item.authorName, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
                Text(item.region, style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
              ]),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [
                    Color(0xFF2196F3), Color(0xFF7B2FFF),
                  ])),
                child: const Text('Follow', style: TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 24),
            const Text('About this moment', style: TextStyle(
                color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'A captivating moment from ${item.region} — '
              'shared by the XamePage community. '
              'Explore more from this creator and discover '
              'trending content from around the world.',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.6)),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final String region;
  const _EmptyState({required this.region});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.04)),
          child: const Icon(Icons.explore_outlined,
              color: Colors.white24, size: 36)),
        const SizedBox(height: 20),
        Text('Nothing in $region yet', style: const TextStyle(
            color: Colors.white38, fontSize: 16,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Be the first to share a moment\nfrom this region',
          style: TextStyle(color: Colors.white24, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center),
      ]),
    ),
  );
}
