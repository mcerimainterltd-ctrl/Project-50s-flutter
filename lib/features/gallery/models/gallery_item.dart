import 'dart:io';

class GalleryItem {
  final String id;
  final String mediaPath; // Standardizing this
  final String? caption;   // Standardizing this
  final bool isBusiness;
  final String visibility;
  final String? price;
  final String? contactInfo;
  final String? description;
  final DateTime timestamp;

  GalleryItem({
    required this.id,
    required this.mediaPath,
    this.caption,
    this.isBusiness = false,
    required this.visibility,
    this.price,
    this.contactInfo,
    this.description,
    required this.timestamp,
  });
}
