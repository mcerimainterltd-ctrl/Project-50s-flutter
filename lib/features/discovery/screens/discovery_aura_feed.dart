import 'package:flutter/material.dart';
import 'xame_discover_screen.dart';

class DiscoveryAuraFeed extends StatelessWidget {
  final String? authorId;
  const DiscoveryAuraFeed({Key? key, this.authorId}) : super(key: key);
  @override
  Widget build(BuildContext context) => XameDiscoverScreen(authorId: authorId);
}
