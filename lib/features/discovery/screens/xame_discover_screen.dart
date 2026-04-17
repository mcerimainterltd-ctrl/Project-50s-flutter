import 'package:flutter/material.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/kinetic_story_item.dart';
import '../widgets/people_carousel.dart';
import '../widgets/discovery_search.dart';

class XameDiscoverScreen extends StatefulWidget {
  const XameDiscoverScreen({Key? key}) : super(key: key);

  @override
  _XameDiscoverScreenState createState() => _XameDiscoverScreenState();
}

class _XameDiscoverScreenState extends State<XameDiscoverScreen> {
  bool _isSearchOpen = false;

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
                title: const Text(
                  "DISCOVERY",
                  style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900),
                ),
                centerTitle: true,
              ),
              
              // Stories Section
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: 10,
                    itemBuilder: (context, i) => const KineticStoryAvatar(
                      avatarUrl: "https://i.pravatar.cc/150?u=xame",
                      isActive: true,
                    ),
                  ),
                ),
              ),

              // People You May Know
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "PEOPLE YOU MAY KNOW",
                    style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: List.generate(5, (i) => {
                    "name": "User $i",
                    "mutuals": "${i + 2}",
                    "avatar": "https://i.pravatar.cc/150?img=$i"
                  }),
                ),
              ),

              // Hero Feed Section
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "TRENDING MOMENTS",
                    style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const MediaDiscoverCard(
                    mediaUrl: "https://picsum.photos/800/1200",
                    title: "A Glimpse into the Maritime Archive",
                    category: "History",
                  ),
                  childCount: 10,
                ),
              ),
            ],
          ),
        ),
        
        // The Search Overlay
        DiscoverySearchOverlay(
          isVisible: _isSearchOpen,
          onClose: () => setState(() => _isSearchOpen = false),
        ),
      ],
    );
  }
}
