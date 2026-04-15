import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, viewerId) {
  return GalleryNotifier(viewerId);
});

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  final String viewerId;
  // This would normally be a database call; we use a static list to simulate cross-user discovery
  static List<GalleryItem> _sharedDatabase = []; 

  GalleryNotifier(this.viewerId) : super(_filterItems(_sharedDatabase, viewerId));

  static List<GalleryItem> _filterItems(List<GalleryItem> items, String vId) {
    return items.where((item) {
      if (item.ownerId == vId) return true; // Owner sees everything
      if (item.visibility == 'public') return true; // Discovery: Others see public posts
      return false;
    }).toList();
  }

  void addItem(GalleryItem item) {
    _sharedDatabase = [item, ..._sharedDatabase];
    state = _filterItems(_sharedDatabase, viewerId);
  }
}
