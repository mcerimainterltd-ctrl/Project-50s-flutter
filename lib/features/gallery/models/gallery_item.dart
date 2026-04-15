class GalleryItem {
  final String id;
  final String ownerId;
  final String mediaPath;
  final String? caption;
  final bool isBusiness;
  final String visibility; // 'public', 'contacts', 'private'
  final String? price;
  final String? contactInfo;
  final String? description;
  final DateTime timestamp;

  GalleryItem({
    required this.id,
    required this.ownerId,
    required this.mediaPath,
    this.caption,
    required this.isBusiness,
    required this.visibility,
    this.price,
    this.contactInfo,
    this.description,
    required this.timestamp,
  });
}
