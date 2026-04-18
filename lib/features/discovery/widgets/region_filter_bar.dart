import 'package:flutter/material.dart';
import '../models/discovery_item.dart';

class RegionFilterBar extends StatefulWidget {
  final Function(DiscoveryRegion) onRegionSelected;
  final String initialCode;
  const RegionFilterBar({
    Key? key,
    required this.onRegionSelected,
    this.initialCode = 'global',
  }) : super(key: key);
  @override
  State<RegionFilterBar> createState() => _RegionFilterBarState();
}

class _RegionFilterBarState extends State<RegionFilterBar> {
  late String _selected;
  @override
  void initState() { super.initState(); _selected = widget.initialCode; }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: discoveryRegions.length,
        itemBuilder: (_, i) {
          final r          = discoveryRegions[i];
          final isSelected = r.code == _selected;
          return GestureDetector(
            onTap: () {
              setState(() => _selected = r.code);
              widget.onRegionSelected(r);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isSelected
                  ? const Color(0xFF2196F3).withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
                border: Border.all(
                  color: isSelected
                    ? const Color(0xFF2196F3).withOpacity(0.6)
                    : Colors.transparent,
                  width: 1.2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isSelected) ...[
                  const Icon(Icons.check_rounded,
                      color: Color(0xFF2196F3), size: 12),
                  const SizedBox(width: 4),
                ],
                Text('${r.flag} ${r.name}',
                  style: TextStyle(
                    color: isSelected
                      ? const Color(0xFF2196F3) : Colors.white54,
                    fontSize:   12,
                    fontWeight: isSelected
                      ? FontWeight.w700 : FontWeight.normal)),
              ]),
            ),
          );
        },
      ),
    ),
    _CurrencyHint(region: discoveryRegions.firstWhere(
      (r) => r.code == _selected,
      orElse: () => discoveryRegions[0])),
  ]);
}

class _CurrencyHint extends StatelessWidget {
  final DiscoveryRegion region;
  const _CurrencyHint({required this.region});

  @override
  Widget build(BuildContext context) {
    if (region.code == 'global') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(region.flag,
                style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 5),
            Text('${region.currencySymbol} ${region.currency}',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11,
                  fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(child: SizedBox(height: 28,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: region.categories.length,
            itemBuilder: (_, i) => Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(6)),
              child: Text(region.categories[i],
                style: const TextStyle(
                    color: Colors.white24, fontSize: 10)),
            ),
          ),
        )),
      ]),
    );
  }
}
