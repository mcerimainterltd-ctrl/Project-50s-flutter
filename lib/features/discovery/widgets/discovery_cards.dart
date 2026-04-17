import 'dart:ui';
import 'package:flutter/material.dart';

class DiscoverCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? height;

  const DiscoverCard({Key? key, required this.child, this.onTap, this.height}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32.0),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(32.0), child: child),
      ),
    );
  }
}

class MediaDiscoverCard extends StatelessWidget {
  final String mediaUrl;
  final String title;
  final String? category;
  final VoidCallback? onTap;

  const MediaDiscoverCard({Key? key, required this.mediaUrl, required this.title, this.category, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DiscoverCard(
      height: 450,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(mediaUrl, fit: BoxFit.cover, filterQuality: FilterQuality.high),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.7)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text(category!.toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 8),
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 22.0, fontWeight: FontWeight.w800)),
                    ],
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
