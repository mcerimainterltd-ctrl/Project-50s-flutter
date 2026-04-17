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
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.black.withOpacity(0.5),
                floating: true,
                pinned: false,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () => setState(() => _isSearchOpen = true),
                  )
                ],
                title: const Text(
                  "DISCOVERY",
                  style: TextStyle(
                    letterSpacing: 2, 
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                centerTitle: true,
              ),
              
              const SliverToBoxAdapter(child: DiscoveryStoriesBar()),

              SliverToBoxAdapter(
                child: RegionFilterBar(
                  onRegionSelected: (region) => setState(() => _activeRegion = region),
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    "PEOPLE YOU MAY KNOW",
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
              ),
              
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: List.generate(5, (i) => {
                    "name": "User $i",
                    "mutuals": "${i + 2}",
                    "avatar": "https://i.pravatar.cc/150?img=${i + 20}"
                  }),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                  child: Text(
                    "TRENDING IN $_activeRegion",
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => MediaDiscoverCard(
                    mediaUrl: "https://picsum.photos/seed/${index + 50}/800/1200",
                    title: "Exclusive Perspective: $_activeRegion Channel",
                    category: _activeRegion,
                  ),
                  childCount: 8,
                ),
              ),
              
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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
