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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: CustomScrollView(
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
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: List.generate(5, (i) => {"name": "User $i", "mutuals": "3", "avatar": "https://i.pravatar.cc/150?u=$i"}),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => MediaDiscoverCard(
                    mediaUrl: "https://picsum.photos/seed/$index/800/1200",
                    title: "Trending in $_activeRegion",
                    category: _activeRegion,
                  ),
                  childCount: 5,
                ),
              ),
            ],
          ),
        ),
        DiscoverySearchOverlay(
          isVisible: _isSearchOpen,
          onClose: () => setState(() => _isSearchOpen = false),
        ),
      ],
    );
  }
}
