import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/gallery_item.dart';

class AddGalleryItemSheet extends ConsumerStatefulWidget {
  final String userId;
  const AddGalleryItemSheet({Key? key, required this.userId}) : super(key: key);
  @override
  _AddGalleryItemSheetState createState() => _AddGalleryItemSheetState();
}

class _AddGalleryItemSheetState extends ConsumerState<AddGalleryItemSheet> {
  String _mode = 'personal', _vis = 'public';
  File? _file;
  final _cap = TextEditingController(), _pri = TextEditingController(), 
        _con = TextEditingController(), _des = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF1A1B2E), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery);
              if (x != null) setState(() => _file = File(x.path));
            },
            child: Container(
              height: 160, width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))),
              child: _file == null ? const Icon(Icons.add_a_photo, color: Colors.cyanAccent) : ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_file!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 15),
          _in("Caption", _cap),
          const SizedBox(height: 15),
          Row(children: [_b("Personal", _mode == 'personal', () => setState(() => _mode = 'personal')), const SizedBox(width: 10), _b("Business", _mode == 'business', () => setState(() => _mode = 'business'))]),
          if (_mode == 'business') ...[const SizedBox(height: 15), _in("Price (₦)", _pri), const SizedBox(height: 10), _in("Contact", _con), const SizedBox(height: 10), _in("Description", _des, l: 3)],
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_v("Public", _vis == 'public', () => setState(() => _vis = 'public')), _v("Contacts", _vis == 'contacts', () => setState(() => _vis = 'contacts')), _v("Private", _vis == 'private', () => setState(() => _vis = 'private'))]),
          const SizedBox(height: 25),
          ElevatedButton(
            onPressed: () async { // FIXED: Added async
              if (_file == null) return;
              
              // This is the "Discovery" Bridge - Sending data to the Cloud
              await FirebaseFirestore.instance.collection("gallery").add({
                "ownerId": widget.userId,
                "mediaPath": _file!.path,
                "caption": _cap.text,
                "isBusiness": _mode == 'business',
                "visibility": _vis,
                "price": _pri.text,
                "contactInfo": _con.text,
                "description": _des.text,
                "timestamp": FieldValue.serverTimestamp(),
              });
              
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: const Text("UPLOAD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }

  Widget _in(String h, TextEditingController c, {int l = 1}) => TextField(controller: c, maxLines: l, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: h, hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)));
  Widget _b(String l, bool a, VoidCallback t) => Expanded(child: GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Center(child: Text(l, style: TextStyle(color: a ? Colors.cyanAccent : Colors.white38))))));
  Widget _v(String l, bool a, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 90, padding: const EdgeInsets.all(10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: a ? Colors.cyanAccent : Colors.white10)), child: Center(child: Text(l, style: TextStyle(fontSize: 12, color: a ? Colors.cyanAccent : Colors.white38)))));
}
