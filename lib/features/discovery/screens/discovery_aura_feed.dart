import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../../core/theme/app_theme.dart';
import '../widgets/nebula_card.dart';

class DiscoveryAuraFeed extends ConsumerStatefulWidget {
  const DiscoveryAuraFeed({super.key});
  @override
  ConsumerState<DiscoveryAuraFeed> createState() => _DiscoveryAuraFeedState();
}

class _DiscoveryAuraFeedState extends ConsumerState<DiscoveryAuraFeed> {
  late PageController _pageController;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82)
      ..addListener(() {
        setState(() {
          _currentPage = _pageController.page ?? 0.0;
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          _buildAnimatedBackground(theme),
          Positioned(
            top: 60,
            left: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DISCOVER', style: TextStyle(color: theme.primary.withOpacity(0.5), letterSpacing: 4, fontSize: 12, fontWeight: FontWeight.w900)),
                Text('Aura Feed', style: TextStyle(color: theme.text, fontSize: 32, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          PageView.builder(
            controller: _pageController,
            itemCount: 10,
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
        Positioned(bottom: -100, left: -100, child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.secondary.withOpacity(0.08)), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(color: Colors.transparent)))),
      ],
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}