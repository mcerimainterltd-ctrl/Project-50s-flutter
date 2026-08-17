import 'package:flutter/material.dart';
import '../models/gallery_item.dart';

class MyGalleryViewer extends StatelessWidget {
  final List<GalleryItem> items;
  final int initialIndex;
  const MyGalleryViewer({Key? key, required this.items, required this.initialIndex}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: items.length,
        itemBuilder: (context, index) => Center(child: Image.network(items[index].url)),
      ),
    );
  }
}
