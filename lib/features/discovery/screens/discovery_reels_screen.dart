import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../models/discovery_item.dart';
import 'discovery_fullscreen_viewer.dart';
import 'author_gallery_screen.dart';
import 'xame_discover_screen.dart';
import '../widgets/region_filter_bar.dart';
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
                        builder: (_) => _CreatePostSheet(
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
