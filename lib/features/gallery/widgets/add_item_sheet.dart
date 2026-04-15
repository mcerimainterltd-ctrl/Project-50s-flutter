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
  final _formKey = GlobalKey<FormState>();
  String _mode = 'personal';
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  void _handleUpload() {
    if (_formKey.currentState!.validate()) {
      final newItem = GalleryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: 'https://placeholder.com/image.jpg', // Replace with your actual upload URL
        mode: _mode,
        description: _descController.text,
        price: _mode == 'business' ? double.tryParse(_priceController.text) : null,
        contactPhone: _mode == 'business' ? _phoneController.text : null,
        contactEmail: _mode == 'business' ? _emailController.text : null,
        createdAt: DateTime.now(),
      );

      // SAVE TO DATABASE via Riverpod
      ref.read(galleryProvider('user_id').notifier).addItem(newItem);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("ADD TO GALLERY", style: TextStyle(color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Standard Description
              _buildField(_descController, "Description / Caption", Icons.closed_caption),
              
              const SizedBox(height: 15),
              
              // Mode Toggle logic would go here (Personal vs Business)
              
              if (_mode == 'business') ...[
                _buildField(_priceController, "Price (Numerical)", Icons.payments, isNumeric: true),
                _buildField(_phoneController, "Contact Phone", Icons.phone),
                _buildField(_emailController, "Business Email", Icons.email),
              ],
              
              const SizedBox(height: 30),
              
              ElevatedButton(
                onPressed: _handleUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("UPLOAD TO WORLD", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, IconData icon, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.cyanAccent),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
