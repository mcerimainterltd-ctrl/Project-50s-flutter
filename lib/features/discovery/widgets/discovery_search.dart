import 'dart:ui';
import 'package:flutter/material.dart';

class DiscoverySearchOverlay extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onClose;

  const DiscoverySearchOverlay({Key? key, required this.isVisible, required this.onClose}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isVisible ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.8),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      autofocus: isVisible,
                      style: TextStyle(color: context.xText, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: "Search people, topics, or channels...",
                        hintStyle: TextStyle(color: context.xText.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.search, color: Colors.blueAccent),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.close, color: context.xText),
                          onPressed: onClose,
                        ),
                        filled: true,
                        fillColor: context.xText.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  // Predictive Pill Clusters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: ["#Maritime", "#History", "Ships", "Live Now", "Nearby"].map((tag) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(tag),
                          backgroundColor: context.xText.withOpacity(0.1),
                          labelStyle: TextStyle(color: context.xText, fontSize: 12),
                          onPressed: () {},
                        ),
                      )).toList(),
                    ),
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
