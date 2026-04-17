import 'package:flutter/material.dart';

class RegionFilterBar extends StatefulWidget {
  final Function(String) onRegionSelected;

  const RegionFilterBar({Key? key, required this.onRegionSelected}) : super(key: key);

  @override
  State<RegionFilterBar> createState() => _RegionFilterBarState();
}

class _RegionFilterBarState extends State<RegionFilterBar> {
  String selectedRegion = "Global";
  final List<String> regions = ["Global", "Atlantic", "Pacific", "Mediterranean", "Arctic", "Indian"];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: regions.length,
        itemBuilder: (context, index) {
          final isSelected = regions[index] == selectedRegion;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(regions[index]),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() => selectedRegion = regions[index]);
                widget.onRegionSelected(regions[index]);
              },
              selectedColor: Colors.blueAccent.withOpacity(0.2),
              backgroundColor: Colors.white.withOpacity(0.05),
              labelStyle: TextStyle(
                color: isSelected ? Colors.blueAccent : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.blueAccent.withOpacity(0.5) : Colors.transparent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
