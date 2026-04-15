import 'package:flutter/material.dart';

class AddGalleryItemSheet extends StatefulWidget {
  const AddGalleryItemSheet({Key? key}) : super(key: key);
  @override
  _AddGalleryItemSheetState createState() => _AddGalleryItemSheetState();
}

class _AddGalleryItemSheetState extends State<AddGalleryItemSheet> {
  String _mode = 'personal'; // personal or business
  String _visibility = 'contacts';
  
  // Controllers for the required data
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1B2E), // Matching your high-end navy theme
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
            
            // Media Picker Box
            Container(
              height: 160, width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.cyanAccent),
                SizedBox(height: 10),
                Text("Tap to pick photo or video", style: TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 20),

            // Caption Field (Always visible)
            _buildInput(Icons.title, "Caption (optional)", _captionController),
            const SizedBox(height: 15),

            // Mode Selector
            Row(children: [
              _toggle("Personal", Icons.person, _mode == 'personal', () => setState(() => _mode = 'personal')),
              const SizedBox(width: 10),
              _toggle("Business", Icons.storefront, _mode == 'business', () => setState(() => _mode = 'business')),
            ]),

            // Dynamic Business Fields
            if (_mode == 'business') ...[
              const SizedBox(height: 15),
              _buildInput(Icons.payments, "Price in ₦ (leave empty if free)", _priceController, isNum: true),
              const SizedBox(height: 10),
              _buildInput(Icons.contact_mail, "Phone / Email", _contactController),
              const SizedBox(height: 10),
              _buildInput(Icons.description, "Description", _descController, maxLines: 3),
            ],

            const SizedBox(height: 25),
            const Text("Visibility", style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 10),

            // Visibility Selector
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _vis("Public", Icons.public, _visibility == 'public', () => setState(() => _visibility = 'public')),
              _vis("Contacts", Icons.group, _visibility == 'contacts', () => setState(() => _visibility = 'contacts')),
              _vis("Private", Icons.lock, _visibility == 'private', () => setState(() => _visibility = 'private')),
            ]),
            const SizedBox(height: 30),

            // Upload Button
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent, 
                foregroundColor: Colors.black, 
                minimumSize: const Size(double.infinity, 55), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
              ),
              child: const Text("Upload", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(IconData icon, String hint, TextEditingController ctrl, {bool isNum = false, int maxLines = 1}) => TextField(
    controller: ctrl,
    keyboardType: isNum ? TextInputType.number : TextInputType.text,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      hintText: hint, hintStyle: const TextStyle(color: Colors.white24),
      filled: true, fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    ),
  );

  Widget _toggle(String l, IconData i, bool a, VoidCallback t) => Expanded(child: GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10, width: 2)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 18, color: a ? Colors.cyanAccent : Colors.white38), const SizedBox(width: 8), Text(l, style: TextStyle(color: a ? Colors.cyanAccent : Colors.white38, fontWeight: a ? FontWeight.bold : FontWeight.normal))]))));
  
  Widget _vis(String l, IconData i, bool a, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 100, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Column(children: [Icon(i, size: 16, color: a ? Colors.cyanAccent : Colors.white38), const SizedBox(height: 4), Text(l, style: TextStyle(fontSize: 12, color: a ? Colors.cyanAccent : Colors.white38))])));
}
