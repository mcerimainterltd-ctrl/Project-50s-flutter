import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LightboxView extends StatelessWidget {
  final List<dynamic> items;
  final int initialIndex;

  const LightboxView({super.key, required this.items, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    final PageController controller = PageController(initialPage: initialIndex);
    
    return Scaffold(
      backgroundColor: const Color(0xFF060609), // Absolute Black
      body: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: items.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: items[index].url,
                    fit: BoxFit.contain,
                    // Force zero filters
                    color: null,
                    colorBlendMode: null,
                    placeholder: (c, u) => const CircularProgressIndicator(color: Colors.white24),
                  ),
                ),
              );
            },
          ),
          // Cinematic Blur Header
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  height: 90,
                  color: Colors.black.withOpacity(0.4),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
