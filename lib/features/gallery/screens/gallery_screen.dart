import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'my_gallery_engine.dart';
import '../models/gallery_item.dart';

// THE NEW CINEMATIC GALLERY ENTRY
class GalleryScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isOwner;
  const GalleryScreen({super.key, required this.userId, required this.isOwner});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String _activeTab = 'business'; // Default to Business World

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060609),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('MY GALLERY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900, fontSize: 14)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // THE WORLD SWITCHER
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTabButton('BUSINESS', _activeTab == 'business'),
                const SizedBox(width: 20),
                _buildTabButton('PERSONAL', _activeTab == 'personal'),
              ],
            ),
          ),
          
          // THE CINEMATIC GRID (Simplified Entry)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 50),
                  const SizedBox(height: 16),
                  Text('EXPLORE ${_activeTab.toUpperCase()} WORLD', 
                       style: const TextStyle(color: Colors.white, letterSpacing: 2)),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                    onPressed: () {
                      // FORCE LAUNCH ENGINE
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => MyGalleryViewer(items: [], initialIndex: 0) // Engine handles data
                      ));
                    }, 
                    child: const Text('OPEN CINEMATIC VIEW', style: TextStyle(color: Colors.white))
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _activeTab = label.toLowerCase()),
      child: Text(label, style: TextStyle(
        color: active ? Colors.cyanAccent : Colors.white24,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        fontSize: 12
      )),
    );
  }
}
