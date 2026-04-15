import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, userId) {
  return GalleryNotifier(userId);
});

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  final String userId;
  GalleryNotifier(this.userId) : super([]);

  void addItem(GalleryItem item) {
    state = [item, ...state];
  }
}
