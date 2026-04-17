import 'package:flutter/material.dart';
import 'kinetic_story_item.dart';

class DiscoveryStoriesBar extends StatelessWidget {
  const DiscoveryStoriesBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 10,
        itemBuilder: (context, index) {
          return KineticStoryItem(
            username: index == 0 ? "You" : "User $index",
            avatarUrl: "https://i.pravatar.cc/150?img=$index",
            hasUnseen: index != 0,
          );
        },
      ),
    );
  }
}
