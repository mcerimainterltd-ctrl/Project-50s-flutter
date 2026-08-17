import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class MyGalleryViewer extends StatefulWidget {
  final List<dynamic> items;
  final int initialIndex;

  const MyGalleryViewer({super.key, required this.items, required this.initialIndex});

  @override
  State<MyGalleryViewer> createState() => _MyGalleryViewerState();
}

class _MyGalleryViewerState extends State<MyGalleryViewer> {
  late PageController _pageController;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060609),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final bool isBusiness = item.mode.toString().toLowerCase() == 'business';
          
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. DYNAMIC AMBIENT BACKDROP
              _buildBackdrop(item.url),
              
              // 2. THE CONTENT
              GestureDetector(
                onTap: () => setState(() => _showUI = !_showUI),
                child: InteractiveViewer(
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: item.url,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),

              // 3. INTELLIGENT UI LAYER
              if (_showUI) ...[
                _buildTopHeader(context, item),
                _buildBottomDictionary(item, isBusiness),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackdrop(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      imageBuilder: (context, provider) => Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: provider, fit: BoxFit.cover, opacity: 0.25),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 35, sigmaY: 35),
          child: Container(color: Colors.black.withOpacity(0.4)),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, dynamic item) {
    final dateStr = item.createdAt != null ? DateFormat('MMM dd, yyyy').format(item.createdAt!) : '';
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(item.mode.toString().toUpperCase(), 
                       style: TextStyle(color: item.mode.toString() == 'business' ? Colors.cyanAccent : Colors.pinkAccent, 
                       fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
                  Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDictionary(dynamic item, bool isBusiness) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBusiness && item.price != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text("\$${item.price}", style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                Text(item.description ?? (isBusiness ? 'Business Portfolio' : 'Personal Memory'),
                     style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300)),
                
                if (isBusiness) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.mail_outline, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.contactEmail ?? 'N/A', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                      const Icon(Icons.phone_android, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 8),
                      Text(item.contactPhone ?? 'N/A', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
