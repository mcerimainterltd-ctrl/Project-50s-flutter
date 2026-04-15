import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, viewerId) {
  return GalleryNotifier(viewerId);
});

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  final String viewerId;
  static List<GalleryItem> _allDatabaseItems = []; // Simulated persistent DB

  GalleryNotifier(this.viewerId) : super(_filterItems(_allDatabaseItems, viewerId));

  static List<GalleryItem> _filterItems(List<GalleryItem> items, String vId) {
    return items.where((item) {
      if (item.ownerId == vId) return true; // Owner sees everything
      if (item.visibility == 'public') return true; // Everyone sees public
      return false; // Filter out private/contacts for now
    }).toList();
  }

  void addItem(GalleryItem item) {
    _allDatabaseItems = [item, ..._allDatabaseItems];
    state = _filterItems(_allDatabaseItems, viewerId);
  }
}
