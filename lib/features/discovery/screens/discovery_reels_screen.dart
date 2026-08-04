import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../models/discovery_item.dart';
import 'discovery_fullscreen_viewer.dart';
import 'author_gallery_screen.dart';
import 'xame_discover_screen.dart';
import 'discovery_map_screen.dart';
import '../widgets/region_filter_bar.dart';
import '../widgets/people_carousel.dart';
import '../../../core/theme/app_theme.dart';

class DiscoveryReelsScreen extends ConsumerStatefulWidget {
  final String? authorId;
  const DiscoveryReelsScreen({Key? key, this.authorId}) : super(key: key);

  @override
  ConsumerState<DiscoveryReelsScreen> createState() => _DiscoveryReelsScreenState();
}

class _DiscoveryReelsScreenState extends ConsumerState<DiscoveryReelsScreen> {
  List<DiscoveryItem> _feed = [];
  bool _loading = true;
  String _regionCode = 'global';
  String _regionName = 'Global';
  int _currentIndex = 0;
  late PageController _pageCtrl;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadData();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadData({bool refresh = false}) async {
    setState(() => _loading = refresh ? false : true);
    try {
      final user = ref.read(currentUserProvider);
      final items = await DiscoveryApiService.fetchFeed(
        region: _regionCode, userId: user?.xameId);
      if (mounted) setState(() { _feed = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onRegionSelected(DiscoveryRegion region) {
    HapticFeedback.selectionClick();
    setState(() { _regionCode = region.code; _regionName = region.name; _currentIndex = 0; });
    _pageCtrl.jumpToPage(0);
    _loadData(refresh: true);
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  List<Map<String, dynamic>> get _posts => _feed.map((e) => {
    'id':           e.id,
    'authorId':     e.authorId,
    'authorName':   e.authorName,
    'authorAvatar': e.authorAvatar,
    'mediaUrl':     e.mediaUrl,
    'mediaType':    e.mediaType == DiscoveryMediaType.video ? 'video' : 'image',
    'thumbnailUrl': e.thumbnailUrl ?? '',
    'title':        e.title,
    'category':     e.category,
    'likeCount':    e.likeCount,
    'commentCount': e.commentCount,
    'viewCount':    e.viewCount,
    'ts':           e.ts?.toIso8601String(),
    'musicUrl':     e.musicUrl,
    'musicTitle':   e.musicTitle,
    'isCollabOpen':      e.isCollabOpen,
    'collabStatus':      e.collabStatus,
    'collabPartnerId':   e.collabPartnerId,
    'collabPartnerName': e.collabPartnerName,
    'collabPartnerAvatar': e.collabPartnerAvatar,
    'collabMediaUrl':    e.collabMediaUrl,
    'collabMediaType':   e.collabMediaType,
    'collabLayout':      e.collabLayout,
    'originalPostId':    e.originalPostId,
    'isRemix':           e.isRemix,
  }).toList();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetHideTimer,
        child: Stack(children: [

          // ── Main feed ──────────────────────────────────────────────
          _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : _feed.isEmpty
                  ? Center(child: Text('No posts yet',
                      style: TextStyle(color: Colors.white54)))
                  : SizedBox.expand(
                      child: DiscoveryFullscreenViewer(

                        posts: _posts,
                        initialIndex: 0,
                        currentUserId: user?.xameId ?? '',
                        currentUserAvatar: user?.profilePic ?? '',
                        embedded: true,
                      ),
                    ),

          // ── Top overlay: back + region filter ─────────────────────
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    if (widget.authorId != null)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    const Spacer(),
                    // Post button
                    GestureDetector(
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: context.xSurface,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                        builder: (_) => CreatePostSheet(
                          userId: user?.xameId ?? '',
                          region: _regionName,
                          onPosted: () => _loadData(refresh: true),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF7B2FFF)]),
                          borderRadius: BorderRadius.circular(20)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_rounded, color: Colors.black, size: 18),
                          SizedBox(width: 4),
                          Text('Post', style: TextStyle(
                              color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // More menu
                    PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                      ),
                      color: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (val) {
                        switch (val) {
                          case 'people':
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: const Color(0xFF12121E),
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                              builder: (_) => SafeArea(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  const SizedBox(height: 12),
                                  Container(width: 36, height: 4,
                                      decoration: BoxDecoration(color: Colors.white24,
                                          borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(height: 12),
                                  const Text('People You May Know',
                                      style: TextStyle(color: Colors.white,
                                          fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 160,
                                    child: PeoplePerspectiveCarousel(
                                      users: const [],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ]),
                              ),
                            );
                            break;
                          case 'map':
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => DiscoveryMapScreen(
                                posts: _feed,
                                regions: discoveryRegions,
                                currentRegion: _regionCode,
                                onRegionSelected: _onRegionSelected,
                              ),
                            ));
                            break;
                          case 'tv':
                            context.push('/tv');
                            break;
                          case 'people_screen':
                            context.push('/people');
                            break;
                          case 'refresh':
                            _loadData(refresh: true);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'trending',
                          child: Row(children: [
                            Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Text('Trending Now', style: TextStyle(color: Colors.white)),
                          ])),
                        const PopupMenuItem(value: 'people',
                          child: Row(children: [
                            Icon(Icons.people_outline, color: Colors.white70, size: 18),
                            SizedBox(width: 10),
                            Text('People You May Know', style: TextStyle(color: Colors.white)),
                          ])),
                        const PopupMenuItem(value: 'map',
                          child: Row(children: [
                            Icon(Icons.map_outlined, color: Colors.white70, size: 18),
                            SizedBox(width: 10),
                            Text('Discovery Map', style: TextStyle(color: Colors.white)),
                          ])),
                        const PopupMenuItem(value: 'tv',
                          child: Row(children: [
                            Icon(Icons.tv_outlined, color: Colors.white70, size: 18),
                            SizedBox(width: 10),
                            Text('XameTV', style: TextStyle(color: Colors.white)),
                          ])),
                        const PopupMenuItem(value: 'people_screen',
                          child: Row(children: [
                            Icon(Icons.explore_outlined, color: Colors.white70, size: 18),
                            SizedBox(width: 10),
                            Text('Explore People', style: TextStyle(color: Colors.white)),
                          ])),
                        const PopupMenuItem(value: 'refresh',
                          child: Row(children: [
                            Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                            SizedBox(width: 10),
                            Text('Refresh Feed', style: TextStyle(color: Colors.white)),
                          ])),
                      ],
                    ),
                  ]),
                ),
                // Region filter
                RegionFilterBar(
                  onRegionSelected: _onRegionSelected,
                  initialCode: _regionCode,
                ),
              ]),
            ),
          ),

        ]),
      ),
    );
  }
}
