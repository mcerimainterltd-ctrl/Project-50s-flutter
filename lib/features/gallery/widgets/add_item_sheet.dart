import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AddGalleryItemSheet extends StatefulWidget {
  const AddGalleryItemSheet({Key? key}) : super(key: key);
  @override
  _AddGalleryItemSheetState createState() => _AddGalleryItemSheetState();
}

class _AddGalleryItemSheetState extends State<AddGalleryItemSheet> {
  String _mode = 'personal'; 
  String _visibility = 'contacts';
  File? _selectedMedia;
  final ImagePicker _picker = ImagePicker();
  
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  Future<void> _pickMedia() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo != null) setState(() => _selectedMedia = File(photo.path));
  }

  void _handleUpload() {
    if (_selectedMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select an image first!")),
      );
      return;
    }

    // THIS IS THE WIRING: Collecting all the data from your buttons
    final Map<String, dynamic> uploadData = {
      'media': _selectedMedia!.path,
      'caption': _captionController.text,
      'mode': _mode,
      'visibility': _visibility, // Truly captured here
      if (_mode == 'business') ...{
        'price': _priceController.text,
        'contact': _contactController.text,
        'description': _descController.text,
      }
    };

    print("Sending to Database: $uploadData");
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1B2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft, child: Text("Add to Gallery", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(height: 20),
            
            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 160, width: double.infinity,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: _selectedMedia != null ? Colors.cyanAccent : Colors.white10)),
                child: _selectedMedia == null 
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.cyanAccent), SizedBox(height: 10), Text("Tap to pick photo", style: TextStyle(color: Colors.white54))])
                  : ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_selectedMedia!, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 20),

            _input(Icons.title, "Caption", _captionController),
            const SizedBox(height: 15),

            Row(children: [
              _toggle("Personal", Icons.person, _mode == 'personal', () => setState(() => _mode = 'personal')),
              const SizedBox(width: 10),
              _toggle("Business", Icons.storefront, _mode == 'business', () => setState(() => _mode = 'business')),
            ]),

            if (_mode == 'business') ...[
              const SizedBox(height: 15),
              _input(Icons.payments, "Price", _priceController, isNum: true),
              const SizedBox(height: 10),
              _input(Icons.contact_mail, "Phone/Email", _contactController),
              const SizedBox(height: 10),
              _input(Icons.description, "Description", _descController, lines: 3),
            ],

            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft, child: Text("Visibility", style: TextStyle(color: Colors.white54))),
            const SizedBox(height: 10),

            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _vis("Public", Icons.public, _visibility == 'public', () => setState(() => _visibility = 'public')),
              _vis("Contacts", Icons.group, _visibility == 'contacts', () => setState(() => _visibility = 'contacts')),
              _vis("Private", Icons.lock, _visibility == 'private', () => setState(() => _visibility = 'private')),
            ]),
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _handleUpload,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _input(IconData i, String h, TextEditingController c, {bool isNum = false, int lines = 1}) => TextField(
    controller: c, keyboardType: isNum ? TextInputType.number : TextInputType.text, maxLines: lines,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(prefixIcon: Icon(i, color: Colors.white38, size: 20), hintText: h, hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
  );

  Widget _toggle(String l, IconData i, bool a, VoidCallback t) => Expanded(child: GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10, width: 2)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 18, color: a ? Colors.cyanAccent : Colors.white38), const SizedBox(width: 8), Text(l, style: TextStyle(color: a ? Colors.cyanAccent : Colors.white38))]))));
  
  Widget _vis(String l, IconData i, bool a, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 100, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Column(children: [Icon(i, size: 16, color: a ? Colors.cyanAccent : Colors.white38), Text(l, style: TextStyle(fontSize: 12, color: a ? Colors.cyanAccent : Colors.white38))])));
}
