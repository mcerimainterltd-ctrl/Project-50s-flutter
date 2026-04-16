import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import '../models/discovery_item.dart';

class NebulaCard extends StatelessWidget {
  final int index;
  final double glowIntensity;
  final Color primaryColor;
  final Color accentColor;
  final DiscoveryItem item;

  const NebulaCard({
    super.key,
    required this.index,
    required this.glowIntensity,
    required this.primaryColor,
    required this.accentColor,
    required this.item,
  });

  void _handleExplore(BuildContext context) {
    if (item.title == 'Social Aura') {
      context.push('/people');
      return;
    }
    
    switch (item.type) {
      case DiscoveryType.plan:
        context.push('/bills');
        break;
      case DiscoveryType.wallet:
        context.push('/wallet');
        break;
      case DiscoveryType.creator:
        context.push('/call-history');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _handleExplore(context),
      child: Container(
        width: 310,
        height: 480,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: (item.customColor ?? primaryColor).withOpacity(0.3 * glowIntensity),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.1), Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  Text(item.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: const Center(child: Text('EXPLORE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}