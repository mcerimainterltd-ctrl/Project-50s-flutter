import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gallery_provider.dart';
import '../widgets/add_item_sheet.dart';
import 'gallery_viewer_screen.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This is the "Ear" — it listens for new items
    final galleryItems = ref.watch(galleryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F101C),
      appBar: AppBar(
        title: const Text("Gallery", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo, color: Colors.cyanAccent),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AddGalleryItemSheet(),
            ),
          ),
        ],
      ),
      body: galleryItems.isEmpty 
        ? const Center(child: Text("No items yet. Tap + to add!", style: TextStyle(color: Colors.white54)))
        : GridView.builder(
            padding: const EdgeInsets.all(15),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: galleryItems.length,
            itemBuilder: (context, index) {
              final item = galleryItems[index];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GalleryViewerScreen(
                      mediaPath: item.mediaPath,
                      caption: item.caption,
                    ),
                  ),
                ),
                child: Hero(
                  tag: item.mediaPath,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(item.mediaPath),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}
