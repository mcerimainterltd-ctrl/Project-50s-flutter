import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_item.dart';
import '../providers/gallery_provider.dart';

class AddGalleryItemSheet extends ConsumerStatefulWidget {
  const AddGalleryItemSheet({Key? key}) : super(key: key);

  @override
  _AddGalleryItemSheetState createState() => _AddGalleryItemSheetState();
}

class _AddGalleryItemSheetState extends ConsumerState<AddGalleryItemSheet> {
  String _mode = 'personal';
  String _visibility = 'contacts';
  final TextEditingController _captionController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1B2E), // Deep midnight blue matching screenshot
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text("Add to Gallery", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Media Picker Area
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.cyanAccent),
                  SizedBox(height: 10),
                  Text("Tap to pick photo or video", style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Caption Field
            TextField(
              controller: _captionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.title, color: Colors.white38),
                hintText: "Caption (optional)",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),

            // Mode Selector (Personal / Business)
            Row(
              children: [
                _buildToggleItem("Personal", Icons.person, _mode == 'personal', () => setState(() => _mode = 'personal')),
                const SizedBox(width: 10),
                _buildToggleItem("Business", Icons.storefront, _mode == 'business', () => setState(() => _mode = 'business')),
              ],
            ),
            const SizedBox(height: 25),

            const Text("Visibility", style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 10),

            // Visibility Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildVisibilityButton("Public", Icons.public, _visibility == 'public'),
                _buildVisibilityButton("Contacts", Icons.group, _visibility == 'contacts'),
                _buildVisibilityButton("Private", Icons.lock, _visibility == 'private'),
              ],
            ),
            const SizedBox(height: 30),

            // Final Upload Button
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.transparent : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? Colors.cyanAccent : Colors.white10, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? Colors.cyanAccent : Colors.white38),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: isActive ? Colors.cyanAccent : Colors.white38, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityButton(String label, IconData icon, bool isActive) {
    return Container(
      width: 105,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? Colors.transparent : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? Colors.cyanAccent : Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: isActive ? Colors.cyanAccent : Colors.white38),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.cyanAccent : Colors.white38)),
        ],
      ),
    );
  }
}
