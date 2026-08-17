import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateNotifierProvider.family<GalleryNotifier, List<GalleryItem>, String>((ref, userId) {
  return GalleryNotifier(userId);
});

class GalleryNotifier extends StateNotifier<List<GalleryItem>> {
  final String userId;
  Box? _box;

  GalleryNotifier(this.userId) : super([]) {
    _init();
  }

  Future<void> _init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('xame_gallery_$userId');
    _loadItems();
  }

  void _loadItems() {
    if (_box == null) return;
    final raw = _box!.values.toList();
    state = raw.map((item) {
      final map = Map<String, dynamic>.from(item);
      return GalleryItem(
        id: map['id'],
        ownerId: map['ownerId'],
        mediaPath: map['mediaPath'],
        caption: map['caption'],
        isBusiness: map['isBusiness'] ?? false,
        visibility: map['visibility'] ?? 'public',
        price: map['price'],
        contactInfo: map['contactInfo'],
        description: map['description'],
        timestamp: DateTime.parse(map['timestamp']),
      );
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> addItem(GalleryItem item) async {
    if (_box == null) await _init();
    await _box!.put(item.id, item.toMap());
    _loadItems();
    // Discovery: This is where your SocketService would broadcast the map
  }
}
