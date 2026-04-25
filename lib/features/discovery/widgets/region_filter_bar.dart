import 'package:flutter/material.dart';
import '../models/discovery_item.dart';
import 'package:xamepage/core/theme/app_theme.dart';

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
              duration: Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isSelected
                  ? context.xPrimary.withOpacity(0.15)
                  : context.xSurface,
                border: Border.all(
                  color: isSelected
                    ? context.xPrimary.withOpacity(0.6)
                    : context.xMuted.withValues(alpha: 0.2),
                  width: 1.2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isSelected) ...[
                  Icon(Icons.check_rounded,
                      color: context.xPrimary, size: 12),
                  SizedBox(width: 4),
                ],
                Text('${r.flag} ${r.name}',
                  style: TextStyle(
                    color: isSelected
                      ? context.xPrimary : context.xMuted,
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
  _CurrencyHint({required this.region});

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
            color: context.xText.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.xMuted.withValues(alpha: 0.1))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(region.flag,
                style: TextStyle(fontSize: 11)),
            SizedBox(width: 5),
            Text('${region.currencySymbol} ${region.currency}',
              style: TextStyle(
                  color: context.xMuted, fontSize: 11,
                  fontWeight: FontWeight.w500)),
          ]),
        ),
        SizedBox(width: 8),
        Expanded(child: SizedBox(height: 28,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: region.categories.length,
            itemBuilder: (_, i) => Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.xText.withOpacity(0.03),
                borderRadius: BorderRadius.circular(6)),
              child: Text(region.categories[i],
                style: TextStyle(
                    color: context.xMuted.withValues(alpha: 0.5), fontSize: 10)),
            ),
          ),
        )),
      ]),
    );
  }
}
