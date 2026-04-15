import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/gallery_item.dart';
import '../providers/gallery_provider.dart';

class AddGalleryItemSheet extends ConsumerStatefulWidget {
  final String userId;
  const AddGalleryItemSheet({Key? key, required this.userId}) : super(key: key);
  @override
  _AddGalleryItemSheetState createState() => _AddGalleryItemSheetState();
}

class _AddGalleryItemSheetState extends ConsumerState<AddGalleryItemSheet> {
  String _mode = 'personal'; 
  String _visibility = 'contacts';
  File? _selectedMedia;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  Future<void> _pickMedia() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo != null) setState(() => _selectedMedia = File(photo.path));
  }

  void _handleUpload() {
    if (_selectedMedia == null) return;
    final newItem = GalleryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      mediaPath: _selectedMedia!.path,
      caption: _captionController.text,
      visibility: _visibility,
      isBusiness: _mode == 'business',
      price: _mode == 'business' ? _priceController.text : null,
      timestamp: DateTime.now(),
    );
    ref.read(galleryProvider(widget.userId).notifier).addItem(newItem);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1B2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text("Add to Gallery", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // The "Cinematic" Media Picker Box
            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 180, width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _selectedMedia != null ? Colors.cyanAccent : Colors.white10),
                ),
                child: _selectedMedia == null 
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                      Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.cyanAccent),
                      SizedBox(height: 12),
                      Text("Tap to pick photo or video", style: TextStyle(color: Colors.white38))
                    ])
                  : ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.file(_selectedMedia!, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 20),

            _styledInput("Caption (optional)", _captionController, Icons.text_fields),
            const SizedBox(height: 16),

            // Mode Selection (Personal vs Business)
            Row(children: [
              _modeButton("Personal", Icons.person, _mode == 'personal', () => setState(() => _mode = 'personal')),
              const SizedBox(width: 12),
              _modeButton("Business", Icons.storefront, _mode == 'business', () => setState(() => _mode = 'business')),
            ]),

            if (_mode == 'business') ...[
              const SizedBox(height: 16),
              _styledInput("Price in ₦ (leave empty if free)", _priceController, Icons.attach_money, isNum: true),
            ],

            const SizedBox(height: 20),
            const Text("Visibility", style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 12),

            // Visibility Toggles
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _visOption("Public", Icons.public, _visibility == 'public', () => setState(() => _visibility = 'public')),
              _visOption("Contacts", Icons.group, _visibility == 'contacts', () => setState(() => _visibility = 'contacts')),
              _visOption("Private", Icons.lock, _visibility == 'private', () => setState(() => _visibility = 'private')),
            ]),
            
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _handleUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styledInput(String hint, TextEditingController controller, IconData icon, {bool isNum = false}) => TextField(
    controller: controller,
    keyboardType: isNum ? TextInputType.number : TextInputType.text,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
  );

  Widget _modeButton(String label, IconData icon, bool active, VoidCallback tap) => Expanded(
    child: GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.cyanAccent : Colors.white10, width: 2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: active ? Colors.cyanAccent : Colors.white38),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: active ? Colors.cyanAccent : Colors.white38, fontWeight: FontWeight.bold)),
        ]),
      ),
    ),
  );

  Widget _visOption(String label, IconData icon, bool active, VoidCallback tap) => GestureDetector(
    onTap: tap,
    child: Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Colors.cyanAccent : Colors.white10),
      ),
      child: Column(children: [
        Icon(icon, size: 16, color: active ? Colors.cyanAccent : Colors.white38),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.cyanAccent : Colors.white38)),
      ]),
    ),
  );
}
