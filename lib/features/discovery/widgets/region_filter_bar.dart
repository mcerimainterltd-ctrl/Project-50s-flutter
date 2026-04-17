import 'package:flutter/material.dart';

class RegionFilterBar extends StatefulWidget {
  final Function(String) onRegionSelected;
  const RegionFilterBar({Key? key, required this.onRegionSelected}) : super(key: key);
  @override
  State<RegionFilterBar> createState() => _RegionFilterBarState();
}

class _RegionFilterBarState extends State<RegionFilterBar> {
  String selected = "Global";
  final regions = ["Global", "Atlantic", "Pacific", "Arctic"];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: regions.map((r) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(r),
            selected: selected == r,
            onSelected: (_) {
              setState(() => selected = r);
              widget.onRegionSelected(r);
            },
          ),
        )).toList(),
      ),
    );
  }
}
