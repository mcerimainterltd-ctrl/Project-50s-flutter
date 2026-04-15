import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/gallery_item.dart';

class LightboxView extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;

  const LightboxView({super.key, required this.items, required this.initialIndex});

  @override
  State<LightboxView> createState() => _LightboxViewState();
}

class _LightboxViewState extends State<LightboxView> {
  late PageController _page;
  late int _current;
  bool _showInfo = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060609), // Deepest Black
      body: Stack(
        children: [
          // 1. THE IMAGE (No filters, high contrast)
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.items[i].url,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Colors.white24)),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. THE CINEMATIC OVERLAY (Glassmorphism)
          if (_showInfo) ...[
            // Header Blur
            Positioned(
              top: 0, left: 0, right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 100,
                    color: Colors.black.withOpacity(0.3),
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
