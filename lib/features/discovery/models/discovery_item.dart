import 'package:flutter/material.dart';

enum DiscoveryType { plan, creator, wallet }

class DiscoveryItem {
  final String id;
  final String title;
  final String subtitle;
  final DiscoveryType type;
  final Color? customColor;

  DiscoveryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.customColor,
  });
}