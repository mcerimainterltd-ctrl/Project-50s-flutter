import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gallery_provider.dart';
import '../widgets/add_item_sheet.dart';
import 'gallery_viewer_screen.dart';

class GalleryScreen extends ConsumerWidget {
  final String userId;
  final bool isOwner;
  
  const GalleryScreen({Key? key, required this.userId, this.isOwner = false}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Passing userId into the family provider so it compiles
    final galleryItems = ref.watch(galleryProvider(userId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F101C),
      appBar: AppBar(
        title: const Text("Gallery"),
        actions: [
          if (isOwner)
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
        ? const Center(child: Text("Empty Gallery", style: TextStyle(color: Colors.white24)))
        : GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: galleryItems.length,
            itemBuilder: (context, index) {
              final item = galleryItems[index];
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryViewerScreen(mediaPath: item.mediaPath, caption: item.caption))),
                child: Hero(tag: item.mediaPath, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(item.mediaPath), fit: BoxFit.cover))),
              );
            },
          ),
    );
  }
}
