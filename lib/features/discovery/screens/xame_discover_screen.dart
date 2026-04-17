import 'package:flutter/material.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/story_ring.dart';
import '../widgets/people_carousel.dart';

class XameDiscoverScreen extends StatelessWidget {
  const XameDiscoverScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // Ultramodern Dark Base
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            backgroundColor: Colors.transparent,
            floating: true,
            title: Text("DISCOVERY", style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900)),
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

          // People You May Know (3D Section)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("PEOPLE YOU MAY KNOW", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5)),
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
              child: Text("TRENDING MOMENTS", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5)),
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
    );
  }
}
