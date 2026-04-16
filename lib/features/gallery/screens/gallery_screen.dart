import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gallery_provider.dart';
import '../widgets/add_item_sheet.dart';

class GalleryScreen extends ConsumerWidget {
  final String userId;
  final bool isOwner;
  const GalleryScreen({Key? key, required this.userId, this.isOwner = false}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(galleryProvider(userId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F101C),
      appBar: AppBar(
        title: const Text("Xame Gallery", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white70)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (isOwner) IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.cyanAccent), 
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => AddGalleryItemSheet(userId: userId))
          )
        ],
      ),
      body: galleryAsync.when(
        data: (items) => items.isEmpty 
            ? const Center(child: Text("No posts found", style: TextStyle(color: Colors.white10)))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: items.length,
                itemBuilder: (c, i) => ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(items[i].mediaPath, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white10))),
              ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        error: (err, stack) => Center(child: Text("Error: $err", style: const TextStyle(color: Colors.red))),
      ),
    );
  }
}
