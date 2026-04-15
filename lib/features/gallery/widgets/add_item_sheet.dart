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
  String _visibility = 'public';
  File? _selectedMedia;
  final TextEditingController _capC = TextEditingController();
  final TextEditingController _priC = TextEditingController();
  final TextEditingController _conC = TextEditingController();
  final TextEditingController _desC = TextEditingController();

  void _handleUpload() {
    if (_selectedMedia == null) return;
    final newItem = GalleryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      ownerId: widget.userId,
      mediaPath: _selectedMedia!.path,
      caption: _capC.text,
      isBusiness: _mode == 'business',
      visibility: _visibility,
      price: _mode == 'business' ? _priC.text : null,
      contactInfo: _mode == 'business' ? _conC.text : null,
      description: _mode == 'business' ? _desC.text : null,
      timestamp: DateTime.now(),
    );
    ref.read(galleryProvider(widget.userId).notifier).addItem(newItem);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF1A1B2E), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (file != null) setState(() => _selectedMedia = File(file.path));
              },
              child: Container(
                height: 150, width: double.infinity,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent.withOpacity(0.2))),
                child: _selectedMedia == null ? const Icon(Icons.add_photo_alternate, color: Colors.cyanAccent) : ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_selectedMedia!, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 15),
            _input("Caption", _capC),
            const SizedBox(height: 15),
            Row(children: [
              _btn("Personal", _mode == 'personal', () => setState(() => _mode = 'personal')),
              const SizedBox(width: 10),
              _btn("Business", _mode == 'business', () => setState(() => _mode = 'business')),
            ]),
            if (_mode == 'business') ...[
              const SizedBox(height: 15),
              _input("Price (₦)", _priC),
              const SizedBox(height: 10),
              _input("Phone / Email", _conC),
              const SizedBox(height: 10),
              _input("Description", _desC, lines: 3),
            ],
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _vis("Public", _visibility == 'public', () => setState(() => _visibility = 'public')),
              _vis("Contacts", _visibility == 'contacts', () => setState(() => _visibility = 'contacts')),
              _vis("Private", _visibility == 'private', () => setState(() => _visibility = 'private')),
            ]),
            const SizedBox(height: 25),
            ElevatedButton(onPressed: _handleUpload, style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text("UPLOAD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
          ],
        ),
      ),
    );
  }

  Widget _input(String h, TextEditingController c, {int lines = 1}) => TextField(controller: c, maxLines: lines, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: h, hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)));
  Widget _btn(String l, bool a, VoidCallback t) => Expanded(child: GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Center(child: Text(l, style: TextStyle(color: a ? Colors.cyanAccent : Colors.white38))))));
  Widget _vis(String l, bool a, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 90, padding: const EdgeInsets.all(10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Center(child: Text(l, style: TextStyle(fontSize: 12, color: a ? Colors.cyanAccent : Colors.white38)))));
}
