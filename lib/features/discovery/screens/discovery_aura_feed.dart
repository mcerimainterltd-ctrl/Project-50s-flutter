import 'package:flutter/material.dart';
import 'xame_discover_screen.dart';

class DiscoveryAuraFeed extends StatelessWidget {
  final String? authorId;
  final bool isTabActive;
  const DiscoveryAuraFeed({Key? key, this.authorId, this.isTabActive = true}) : super(key: key);
  @override
  Widget build(BuildContext context) => XameDiscoverScreen(authorId: authorId, isTabActive: isTabActive);
}
