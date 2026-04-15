import 'dart:io';
import 'package:flutter/material.dart';

class GalleryViewerScreen extends StatelessWidget {
  final String mediaPath;
  final String? caption;
  const GalleryViewerScreen({Key? key, required this.mediaPath, this.caption}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(child: InteractiveViewer(child: Hero(tag: mediaPath, child: Image.file(File(mediaPath), fit: BoxFit.contain)))),
        Positioned(top: 50, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
      ]),
    );
  }
}
