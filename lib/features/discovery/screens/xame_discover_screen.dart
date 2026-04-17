import 'package:flutter/material.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/kinetic_story_item.dart';
import '../widgets/people_carousel.dart';
import '../widgets/discovery_search.dart';
import '../widgets/stories_bar.dart';
import '../widgets/region_filter_bar.dart';

class XameDiscoverScreen extends StatefulWidget {
  const XameDiscoverScreen({Key? key}) : super(key: key);
  @override
  _XameDiscoverScreenState createState() => _XameDiscoverScreenState();
}

class _XameDiscoverScreenState extends State<XameDiscoverScreen> {
  bool _isSearchOpen = false;
  String _activeRegion = "Global";
  String _searchQuery = "";

  // Mock Database for Production Testing
  final List<Map<String, String>> _allContent = [
    {"title": "Pacific Storm Surge", "cat": "Pacific", "img": "https://picsum.photos/seed/p1/800/1200"},
    {"title": "Atlantic Heritage", "cat": "Atlantic", "img": "https://picsum.photos/seed/a1/800/1200"},
    {"title": "Arctic Expedition", "cat": "Arctic", "img": "https://picsum.photos/seed/ar1/800/1200"},
    {"title": "Mediterranean Blue", "cat": "Mediterranean", "img": "https://picsum.photos/seed/m1/800/1200"},
    {"title": "Deep Sea Indian Ocean", "cat": "Indian", "img": "https://picsum.photos/seed/i1/800/1200"},
    {"title": "Global Maritime Trade", "cat": "Global", "img": "https://picsum.photos/seed/g1/800/1200"},
  ];

  List<Map<String, String>> get _filteredContent {
    return _allContent.where((item) {
      final matchesRegion = _activeRegion == "Global" || item['cat'] == _activeRegion;
      final matchesSearch = item['title']!.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesRegion && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                floating: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _isSearchOpen = true),
                  )
                ],
                title: const Text("DISCOVERY", style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900)),
                centerTitle: true,
              ),
              const SliverToBoxAdapter(child: DiscoveryStoriesBar()),
              SliverToBoxAdapter(
                child: RegionFilterBar(onRegionSelected: (r) => setState(() => _activeRegion = r)),
              ),
              // People Carousel remains as a constant discovery element
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: List.generate(5, (i) => {"name": "User $i", "mutuals": "3", "avatar": "https://i.pravatar.cc/150?u=$i"}),
                ),
              ),
              // Dynamic Results Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _searchQuery.isEmpty ? "TRENDING IN $_activeRegion" : "SEARCH RESULTS FOR '$_searchQuery'",
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
              ),
              // Filtered Feed
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _filteredContent[index % _filteredContent.length];
                    return MediaDiscoverCard(
                      mediaUrl: item['img']!,
                      title: item['title']!,
                      category: item['cat']!,
                    );
                  },
                  childCount: _filteredContent.isEmpty ? 0 : _filteredContent.length,
                ),
              ),
              if (_filteredContent.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Text("No content found in this region.", style: TextStyle(color: Colors.white24)),
                  )),
                ),
            ],
          ),
        ),
        // Search Overlay with actual Callback
        DiscoverySearchOverlay(
          isVisible: _isSearchOpen,
          onClose: () => setState(() {
             _isSearchOpen = false;
             _searchQuery = ""; // Reset search on close
          }),
          // In a real app, we'd pass a controller, but for this build we'll let it be handled via overlay interaction
        ),
      ],
    );
  }
}
