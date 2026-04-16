import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/nebula_card.dart';
import '../models/discovery_item.dart';

class DiscoveryAuraFeed extends ConsumerStatefulWidget {
  const DiscoveryAuraFeed({super.key});
  @override
  ConsumerState<DiscoveryAuraFeed> createState() => _DiscoveryAuraFeedState();
}

class _DiscoveryAuraFeedState extends ConsumerState<DiscoveryAuraFeed> {
  late PageController _pageController;
  double _currentPage = 0.0;

  final List<DiscoveryItem> _items = [
    DiscoveryItem(id: '1', title: 'Utility Bills', subtitle: 'Pay subtitle: 'Global Bundles' Manage Utilities', type: DiscoveryType.plan),
    DiscoveryItem(id: '2', title: 'Xame Wallet', subtitle: 'Manage Assets', type: DiscoveryType.wallet),
    DiscoveryItem(id: '3', title: 'Call Logs', subtitle: 'Recent Activity', type: DiscoveryType.creator),
    DiscoveryItem(id: '4', title: 'Social Aura', subtitle: 'Find Friends', type: DiscoveryType.creator, customColor: Colors.purple),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82)
      ..addListener(() { setState(() { _currentPage = _pageController.page ?? 0.0; }); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: theme.bg,
      body: PageView.builder(
        controller: _pageController,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          double diff = index - _currentPage;
          return Center(
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translate(diff * 30, 0, diff.abs() * -100)
                ..rotateY(diff * 0.3),
              alignment: Alignment.center,
              child: NebulaCard(
                index: index,
                glowIntensity: (1 - diff.abs()).clamp(0.0, 1.0),
                primaryColor: theme.primary,
                accentColor: theme.accent,
                item: _items[index],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }
}