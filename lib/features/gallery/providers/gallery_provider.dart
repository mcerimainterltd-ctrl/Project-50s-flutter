import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';

final galleryProvider = StreamProvider.family<List<GalleryItem>, String>((ref, viewerId) {
  final firestore = FirebaseFirestore.instance;
  
  // DISCOVERY LOGIC: Get all public posts OR posts owned by the viewer
  return firestore
      .collection('gallery')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return GalleryItem(
            id: doc.id,
            ownerId: data['ownerId'] ?? '',
            mediaPath: data['mediaPath'] ?? '',
            caption: data['caption'],
            isBusiness: data['isBusiness'] ?? false,
            visibility: data['visibility'] ?? 'public',
            price: data['price'],
            contactInfo: data['contactInfo'],
            description: data['description'],
            timestamp: (data['timestamp'] as Timestamp).toDate(),
          );
        }).where((item) {
          return item.ownerId == viewerId || item.visibility == 'public';
        }).toList();
      });
});
