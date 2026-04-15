import 'package:flutter/foundation.dart';

class GalleryItem {
  final String id;
  final String url;
  final String mode; // 'personal' or 'business'
  final String? description;
  final double? price;
  final String? contactPhone;
  final String? contactEmail;
  final DateTime? createdAt;

  GalleryItem({
    required this.id,
    required this.url,
    required this.mode,
    this.description,
    this.price,
    this.contactPhone,
    this.contactEmail,
    this.createdAt,
  });
}
