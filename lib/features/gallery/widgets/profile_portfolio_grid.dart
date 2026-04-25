import 'package:flutter/material.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class ProfilePortfolioGrid extends StatelessWidget {
  final List<dynamic> items;
  final Function(int) onShowLightbox;

  ProfilePortfolioGrid({
    super.key, 
    required this.items, 
    required this.onShowLightbox
  });

  @override
  Widget build(BuildContext context) {
    // If items are empty, show a placeholder so the space isn't empty
    if (items.isEmpty) {
      return Container(
        height: 200,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.xText.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.xMuted.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Text("Gallery Content Coming Soon", 
            style: TextStyle(color: context.xMuted.withValues(alpha: 0.5))),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: context.xText.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.image, color: context.xMuted.withValues(alpha: 0.5)),
        );
      },
    );
  }
}
