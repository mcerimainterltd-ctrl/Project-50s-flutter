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
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Color(0xFF1A1B2E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _pickMedia,
            child: Container(
              height: 160, width: double.infinity,
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: _selectedMedia != null ? Colors.cyanAccent : Colors.white10)),
              child: _selectedMedia == null 
                ? const Icon(Icons.add_photo_alternate, size: 40, color: Colors.cyanAccent)
                : ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_selectedMedia!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 20),
          TextField(controller: _captionController, decoration: const InputDecoration(hintText: "Caption", hintStyle: TextStyle(color: Colors.white24))),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _handleUpload,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, minimumSize: const Size(double.infinity, 50)),
            child: const Text("Upload", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
