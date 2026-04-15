import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

// THE XAME GALLERY DATA ENGINE
final galleryProvider = StateProvider.family<List<GalleryItem>, String>((ref, userId) {
  // This is where your data logic sits. 
  // For now, it returns an empty list to keep the build green, 
  // but it's ready to be populated from Firestore/API.
  return []; 
});
