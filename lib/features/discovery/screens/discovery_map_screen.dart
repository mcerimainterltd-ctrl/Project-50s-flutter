// lib/features/discovery/screens/discovery_map_screen.dart
// XameTV Discovery Map — real-time post locations on an interactive world map

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/discovery_item.dart';

// Region coordinates map
const _regionCoords = <String, LatLng>{
  'global': LatLng(20, 0),
  'ng':     LatLng(9.082, 8.6753),
  'gh':     LatLng(7.9465, -1.0232),
  'ke':     LatLng(-0.0236, 37.9062),
  'za':     LatLng(-30.5595, 22.9375),
  'us':     LatLng(37.0902, -95.7129),
  'gb':     LatLng(55.3781, -3.4360),
  'eu':     LatLng(54.5260, 15.2551),
  'in':     LatLng(20.5937, 78.9629),
  'ae':     LatLng(23.4241, 53.8478),
  'sg':     LatLng(1.3521, 103.8198),
  'jp':     LatLng(36.2048, 138.2529),
  'br':     LatLng(-14.2350, -51.9253),
  'ca':     LatLng(56.1304, -106.3468),
  'au':     LatLng(-25.2744, 133.7751),
};

class DiscoveryMapScreen extends StatefulWidget {
  final List<DiscoveryItem> posts;
  final List<DiscoveryRegion> regions;
  final String currentRegion;
  final void Function(DiscoveryRegion) onRegionSelected;

  const DiscoveryMapScreen({
    Key? key,
    required this.posts,
    required this.regions,
    required this.currentRegion,
    required this.onRegionSelected,
  }) : super(key: key);

  @override
  State<DiscoveryMapScreen> createState() => _DiscoveryMapScreenState();
}

class _DiscoveryMapScreenState extends State<DiscoveryMapScreen> {
  final _mapCtrl = MapController();
  String? _selectedRegion;
  DiscoveryItem? _selectedPost;

  // Count posts per region
  Map<String, int> get _regionPostCounts {
    final counts = <String, int>{};
    for (final post in widget.posts) {
      final code = post.region.toLowerCase();
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final counts = _regionPostCounts;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [

        // ── Map ──────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: const LatLng(20, 10),
            initialZoom: 2.2,
            minZoom: 1.5,
            maxZoom: 8,
            backgroundColor: const Color(0xFF0A0A0F),
            onTap: (_, __) => setState(() {
              _selectedRegion = null;
              _selectedPost   = null;
            }),
          ),
          children: [
            // Dark map tiles
            TileLayer(
              urlTemplate:
                  'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.xamepage.app',
              tileBuilder: (ctx, tile, info) => ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.8, 0, 0, 0, 0,
                  0, 0.8, 0, 0, 0,
                  0, 0, 0.8, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: tile,
              ),
            ),

            // Region markers
            MarkerLayer(
              markers: widget.regions
                  .where((r) => r.code != 'global')
                  .map((region) {
                final coord   = _regionCoords[region.code];
                if (coord == null) return null;
                final count   = counts[region.code] ?? 0;
                final isActive = region.code == widget.currentRegion;
                final isSelected = region.code == _selectedRegion;
                final size = count > 0
                    ? (36.0 + (count * 4).clamp(0, 24)).toDouble()
                    : 32.0;

                return Marker(
                  point: coord,
                  width: size + 20,
                  height: size + 20,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedRegion = region.code);
                      _mapCtrl.move(coord, 4.0);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glow ring for active region
                          if (isActive || isSelected)
                            Container(
                              width: size + 16,
                              height: size + 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF2196F3).withOpacity(0.2),
                                border: Border.all(
                                    color: const Color(0xFF2196F3)
                                        .withOpacity(0.5),
                                    width: 1.5),
                              ),
                            ),
                          // Post count pulse ring
                          if (count > 0)
                            Container(
                              width: size + 8,
                              height: size + 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                                border: Border.all(
                                    color: const Color(0xFFFF5722)
                                        .withOpacity(0.4),
                                    width: 1),
                              ),
                            ),
                          // Flag marker
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive
                                  ? const Color(0xFF1565C0)
                                  : const Color(0xFF1A1A2E),
                              border: Border.all(
                                  color: isActive
                                      ? const Color(0xFF2196F3)
                                      : Colors.white24,
                                  width: isActive ? 2 : 1),
                              boxShadow: [BoxShadow(
                                  color: isActive
                                      ? const Color(0xFF2196F3).withOpacity(0.4)
                                      : Colors.black45,
                                  blurRadius: 8)],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(region.flag,
                                    style: TextStyle(
                                        fontSize: size * 0.38)),
                                if (count > 0)
                                  Text('$count',
                                    style: TextStyle(
                                      color: const Color(0xFFFF5722),
                                      fontSize: size * 0.2,
                                      fontWeight: FontWeight.w900,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).whereType<Marker>().toList(),
            ),
          ],
        ),

        // ── Top bar ───────────────────────────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('🌍', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                const Text('Discovery Map',
                    style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Spacer(),
            // Total post count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text('${widget.posts.length} posts',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11)),
            ),
          ]),
        )),

        // ── Region info panel ─────────────────────────────────────────────
        if (_selectedRegion != null)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildRegionPanel(_selectedRegion!, counts),
          ),
      ]),
    );
  }

  Widget _buildRegionPanel(String regionCode, Map<String, int> counts) {
    final region = widget.regions.firstWhere(
        (r) => r.code == regionCode,
        orElse: () => widget.regions.first);
    final count = counts[regionCode] ?? 0;
    final regionPosts = widget.posts
        .where((p) => p.region.toLowerCase() == regionCode)
        .take(5)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),

        // Region header
        Row(children: [
          Text(region.flag, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(region.name, style: const TextStyle(
                color: Colors.white, fontSize: 20,
                fontWeight: FontWeight.w800)),
            Text('$count active ${count == 1 ? 'post' : 'posts'}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12)),
          ])),
          // View region button
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onRegionSelected(region);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('View Feed',
                style: TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ]),

        if (regionPosts.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          // Preview posts
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: regionPosts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final post = regionPosts[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onRegionSelected(region);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: post.thumbnailUrl?.isNotEmpty == true
                              ? post.thumbnailUrl!
                              : post.mediaUrl,
                          width: 56, height: 56,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 56, height: 56,
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.image_outlined,
                                  color: Colors.white24, size: 20)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(width: 56,
                        child: Text(post.title,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 8),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center)),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Text('No posts in this region yet.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Be the first to post here!',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],

        // Categories chips
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6,
          children: region.categories.map((cat) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF2196F3).withOpacity(0.3)),
            ),
            child: Text(cat, style: const TextStyle(
                color: Color(0xFF90CAF9), fontSize: 10,
                fontWeight: FontWeight.w600)),
          )).toList()),
      ]),
    );
  }
}
