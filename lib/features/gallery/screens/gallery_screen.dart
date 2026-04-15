import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/add_item_sheet.dart';
import '../providers/gallery_provider.dart';
import '../widgets/gallery_viewer.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  final String userId;
  const GalleryScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String _activeTab = 'business';

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(galleryProvider(widget.userId));

    return Scaffold(
      backgroundColor: const Color(0xFF060609),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('XAME GALLERY', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white70)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _activeTab = 'business'),
                child: Text('BUSINESS', style: TextStyle(color: _activeTab == 'business' ? Colors.cyanAccent : Colors.white24, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 20),
              TextButton(
                onPressed: () => setState(() => _activeTab = 'personal'),
                child: Text('PERSONAL', style: TextStyle(color: _activeTab == 'personal' ? Colors.cyanAccent : Colors.white24, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 64),
          const SizedBox(height: 20),
          Text('EXPLORE ${_activeTab.toUpperCase()} WORLD', style: const TextStyle(color: Colors.white, letterSpacing: 1.5)),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () {
              final filteredItems = allItems.where((item) => item.mode == _activeTab).toList();
              if (filteredItems.isNotEmpty) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => MyGalleryViewer(items: filteredItems, initialIndex: 0),
                ));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("No items in $_activeTab world yet"), backgroundColor: Colors.black87),
                );
              }
            },
            child: const Text('OPEN CINEMATIC VIEW', style: TextStyle(color: Colors.white)),
          ),
          const Spacer(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.cyanAccent,
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const AddGalleryItemSheet(),
        ),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
