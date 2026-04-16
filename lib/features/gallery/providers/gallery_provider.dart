import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, viewerId) {
  return GalleryNotifier(viewerId);
});

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  final String viewerId;
  static List<GalleryItem> _globalDatabase = []; 

  GalleryNotifier(this.viewerId) : super(_runDiscovery(_globalDatabase, viewerId));

  static List<GalleryItem> _runDiscovery(List<GalleryItem> items, String vId) {
    return items.where((item) {
      if (item.ownerId == vId) return true; // I see my own
      if (item.visibility == 'public') return true; // I see everyone's public posts
      return false;
    }).toList();
  }

  void addItem(GalleryItem item) {
    _globalDatabase = [item, ..._globalDatabase];
    state = _runDiscovery(_globalDatabase, viewerId);
  }
}
