import 'package:flutter/material.dart';
import 'dart:ui';
import '../widgets/nebula_card.dart';

class DiscoveryAuraFeed extends StatefulWidget {
  const DiscoveryAuraFeed({super.key});

  @override
  State<DiscoveryAuraFeed> createState() => _DiscoveryAuraFeedState();
}

class _DiscoveryAuraFeedState extends State<DiscoveryAuraFeed> {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Aura (Matches Card Glow)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.blue.withOpacity(0.12), Colors.black],
                  center: const Alignment(0, -0.4),
                  radius: 1.4,
                ),
              ),
            ),
          ),
          PageView.builder(
            controller: _pageController,
            itemCount: 10,
            itemBuilder: (context, index) {
              // The Spatial Math: Depth, Tilt, and Focus
              double diff = index - _currentPage;
              
              Matrix4 matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // Perspective Strength
                ..translate(diff * 30, 0, diff.abs() * -150) // Z-Space Depth
                ..rotateY(diff * 0.35); // Horizontal Tilt

              double glow = (1 - diff.abs()).clamp(0.0, 1.0);

              return Center(
                child: Transform(
                  transform: matrix,
                  alignment: Alignment.center,
                  child: NebulaCard(
                    index: index,
                    glowIntensity: glow,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
