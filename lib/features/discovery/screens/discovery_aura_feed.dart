import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
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

  // Mock data for the Universe discovery
  final List<DiscoveryItem> _items = [
    DiscoveryItem(id: '1', title: 'Global Data', subtitle: '35 Regions Live', type: DiscoveryType.plan),
    DiscoveryItem(id: '2', title: 'Xame Wallet', subtitle: 'Secure Assets', type: DiscoveryType.wallet),
    DiscoveryItem(id: '3', title: 'Aura Nodes', subtitle: 'Connect Now', type: DiscoveryType.creator),
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
      body: Stack(
        children: [
          _buildAnimatedBackground(theme),
          PageView.builder(
            controller: _pageController,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              double diff = index - _currentPage;
              Matrix4 matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..translate(diff * 40, 0, diff.abs() * -160)
                ..rotateY(diff * 0.4);
              return Center(
                child: Transform(
                  transform: matrix,
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
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground(XameTheme theme) {
    return Stack(
      children: [
        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: RadialGradient(colors: [theme.primary.withOpacity(0.15), theme.bg], center: const Alignment(0.7, -0.5), radius: 1.5)))),
      ],
    );
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }
}