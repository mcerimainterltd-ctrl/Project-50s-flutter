import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StateProvider.family<List<GalleryItem>, String>((ref, userId) {
  return [
    GalleryItem(
      id: '1',
      url: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe',
      mode: 'business',
      description: 'Ultramodern Architecture Concept',
      price: 2500.00,
      contactEmail: 'sales@xame.com',
      contactPhone: '+123456789',
      createdAt: DateTime.now(),
    ),
    GalleryItem(
      id: '2',
      url: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb',
      mode: 'personal',
      description: 'Sunset at the Valley',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ]; 
});
