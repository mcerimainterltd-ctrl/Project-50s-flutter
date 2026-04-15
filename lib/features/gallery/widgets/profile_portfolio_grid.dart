import 'package:flutter/material.dart';

class ProfilePortfolioGrid extends StatelessWidget {
  final List<dynamic> items;
  final Function(int) onShowLightbox;

  const ProfilePortfolioGrid({
    super.key, 
    required this.items, 
    required this.onShowLightbox
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return GestureDetector(
            onTap: () => onShowLightbox(index),
            child: Container(
              color: Colors.grey[900],
              child: Image.network(
                item.url,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white24),
              ),
            ),
          );
        },
        childCount: items.length,
      ),
    );
  }
}
