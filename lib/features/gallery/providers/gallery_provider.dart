import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  GalleryNotifier() : super([]);
  void addItem(GalleryItem item) => state = [...state, item];
}

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, id) {
  return GalleryNotifier();
});
