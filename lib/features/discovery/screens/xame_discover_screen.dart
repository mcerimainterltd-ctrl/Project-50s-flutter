import "../widgets/tv_entry_button.dart";
import "package:go_router/go_router.dart";
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:better_player_enhanced/better_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/cache_service.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/people_carousel.dart';
import '../widgets/stories_bar.dart';
import '../widgets/region_filter_bar.dart';
import '../widgets/live_pulse.dart';
import '../widgets/story_viewer.dart';
import '../models/discovery_item.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── API Service ───────────────────────────────────────────────────────────────
class DiscoveryApiService {
  static final _dio = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 30),
    sendTimeout:    const Duration(minutes: 10),
    receiveTimeout: const Duration(minutes: 10),
  ));

  static Future<List<DiscoveryItem>> fetchFeed({
    String region = 'global', int page = 1, int limit = 20,
  }) async {
    try {
      final res = await _dio.get('/api/discover/feed', queryParameters: {
        'region': region, 'page': page, 'limit': limit,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return [];
      return (data['posts'] as List).map((p) {
        final m = Map<String, dynamic>.from(p);
        return DiscoveryItem(
          id:             m['id']           as String? ?? '',
          title:          m['title']        as String? ?? '',
          subtitle:       m['caption']      as String? ?? '',
          mediaUrl:       m['mediaUrl']     as String? ?? '',
          thumbnailUrl:   m['thumbnailUrl'] as String?,
          authorName:     m['authorName']   as String? ?? '',
          authorAvatar:   m['authorAvatar'] as String? ?? '',
          authorId:       m['authorId']     as String? ?? '',
          region:         m['region']       as String? ?? 'Global',
          category:       m['category']     as String? ?? 'General',
          type:           (m['isLive'] as bool? ?? false)
                            ? DiscoveryType.live : DiscoveryType.post,
          mediaType:      (m['mediaType'] as String?) == 'video'
                            ? DiscoveryMediaType.video : DiscoveryMediaType.image,
          isLive:         m['isLive']       as bool? ?? false,
          isAuthorOnline: false,
          viewCount:      (m['viewCount']   as num?)?.toInt() ?? 0,
          likeCount:      (m['likeCount']   as num?)?.toInt() ?? 0,
          commentCount:   (m['commentCount'] as num?)?.toInt() ?? 0,
          ts: m['ts'] != null
            ? DateTime.tryParse(m['ts'].toString()) ?? DateTime.now()
            : DateTime.now(),
        );
      }).toList();
    } catch (_) { return []; }
  }

  static Future<List<DiscoveryUser>> fetchPeople(String userId) async {
    try {
      final res = await _dio.get('/api/discover/people',
          queryParameters: {'userId': userId, 'limit': 20});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return [];
      return (data['people'] as List).map((p) {
        final m = Map<String, dynamic>.from(p);
        return DiscoveryUser(
          id:           m['id']          as String? ?? '',
          name:         m['name']        as String? ?? '',
          avatarUrl:    m['avatarUrl']   as String? ?? '',
          mutualCount:  (m['mutualCount'] as num?)?.toInt() ?? 0,
          isOnline:     m['isOnline']    as bool? ?? false,
          tagline:      m['tagline']     as String?,
        );
      }).toList();
    } catch (_) { return []; }
  }

  static Future<List<Map<String, dynamic>>> fetchStories(
      String userId) async {
    try {
      final res = await _dio.get('/api/discover/stories',
          queryParameters: {'userId': userId});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return [];
      return List<Map<String, dynamic>>.from(
        (data['stories'] as List).map((s) =>
          Map<String, dynamic>.from(s)));
    } catch (_) { return []; }
  }

  static Future<bool> likePost(String userId, String postId) async {
    try {
      final res = await _dio.post('/api/discover/like',
          data: {'userId': userId, 'postId': postId});
      final data = res.data as Map<String, dynamic>;
      return data['success'] == true;
    } catch (_) { return false; }
  }

  static Future<void> viewPost(String postId) async {
    try {
      await _dio.post('/api/discover/view', data: {'postId': postId});
    } catch (_) {}
  }

  static Future<String?> createPost({
    required String authorId,
    required String title,
    required String caption,
    required String region,
    required String category,
    required File   mediaFile,
    required String mediaType,
  }) async {
    try {
      final formData = FormData.fromMap({
        'authorId': authorId,
        'title':    title,
        'caption':  caption,
        'region':   region,
        'category': category,
        'mediaType': mediaType,
        'media': await MultipartFile.fromFile(mediaFile.path),
      });
      final res  = await _dio.post('/api/discover/post', data: formData);
      final data = res.data as Map<String, dynamic>;
      return data['success'] == true ? null : data['message'] as String?;
    } catch (e) { return 'Upload failed: \$e'; }
  }

  static Future<String?> createStory({
    required String authorId,
    required File   mediaFile,
    required String mediaType,
  }) async {
    try {
      final formData = FormData.fromMap({
        'authorId':  authorId,
        'mediaType': mediaType,
        'media': await MultipartFile.fromFile(mediaFile.path),
      });
      final res  = await _dio.post('/api/discover/story', data: formData);
      final data = res.data as Map<String, dynamic>;
      return data['success'] == true ? null : data['message'] as String?;
    } catch (_) { return 'Upload failed'; }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class XameDiscoverScreen extends ConsumerStatefulWidget {
  final String? authorId;
  const XameDiscoverScreen({Key? key, this.authorId}) : super(key: key);
  @override
  ConsumerState<XameDiscoverScreen> createState() => _XameDiscoverScreenState();
}

class _XameDiscoverScreenState extends ConsumerState<XameDiscoverScreen>
    with TickerProviderStateMixin {
  final _scrollCtrl  = ScrollController();
  final _searchCtrl  = TextEditingController();
  bool  _searchOpen  = false;
  bool  _loading     = true;
  bool  _loadingMore = false;
  String _regionCode = 'global';
  String _regionName = 'Global';
  String _searchQuery = '';
  String? _authorFilter;
  int    _page        = 1;
  bool   _hasMore     = true;

  List<DiscoveryItem>           _feed    = [];
  List<DiscoveryUser>           _people  = [];
  List<Map<String, dynamic>>    _stories = [];

  late AnimationController _searchAnim;
  late Animation<double>   _searchFade;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _searchFade = CurvedAnimation(
        parent: _searchAnim, curve: Curves.easeOut);
    _scrollCtrl.addListener(_onScroll);
    if (widget.authorId != null && widget.authorId!.isNotEmpty) {
      _authorFilter = widget.authorId;
    }
    // Show cached data instantly
    _loadCached();
    // Then refresh from network
    _loadData();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchAnim.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _loadCached() {
    final cachedFeed = CacheService.loadDiscoveryFeed(_regionCode);
    final cachedPeople = CacheService.loadDiscoveryPeople();
    if (cachedFeed.isNotEmpty || cachedPeople.isNotEmpty) {
      setState(() {
        if (cachedFeed.isNotEmpty) {
          _feed = cachedFeed.map((m) => DiscoveryItem.fromJson(m)).toList();
          _loading = false;
        }
        if (cachedPeople.isNotEmpty) {
          _people = cachedPeople.map((m) => DiscoveryUser.fromJson(m)).toList();
        }
      });
    }
  }


  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) setState(() { _page = 1; _hasMore = true; _feed = []; });
    setState(() => _loading = true);
    final user = ref.read(currentUserProvider);
    final userId = user?.xameId ?? '';

    final results = await Future.wait([
      DiscoveryApiService.fetchFeed(region: _regionCode, page: 1),
      DiscoveryApiService.fetchPeople(userId),
      DiscoveryApiService.fetchStories(userId),
    ]);

    if (!mounted) return;
    final feed    = results[0] as List<DiscoveryItem>;
    final people  = results[1] as List<DiscoveryUser>;
    final stories = results[2] as List<Map<String, dynamic>>;

    // Cache for instant load next time
    CacheService.saveDiscoveryFeed(_regionCode,
        feed.map((i) => i.toJson()).toList());
    CacheService.saveDiscoveryPeople(
        people.map((p) => p.toJson()).toList());

    setState(() {
      _feed    = _authorFilter != null
          ? feed.where((i) => i.authorId == _authorFilter).toList()
          : feed;
      _people  = people;
      _stories = stories;
      _loading = false;
      _page    = 1;
      _hasMore = (feed.length >= 20);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final more = await DiscoveryApiService.fetchFeed(
      region: _regionCode, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _feed.addAll(more);
      _page++;
      _hasMore    = more.length >= 20;
      _loadingMore = false;
    });
  }

  List<DiscoveryItem> get _filtered {
    if (_searchQuery.isEmpty) return _feed;
    return _feed.where((i) =>
      i.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      i.category.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    _searchAnim.forward();
    HapticFeedback.lightImpact();
  }

  void _closeSearch() {
    _searchAnim.reverse().then((_) {
      if (mounted) setState(() {
        _searchOpen  = false;
        _searchQuery = '';
        _searchCtrl.clear();
      });
    });
  }

  void _onRegionSelected(DiscoveryRegion region) {
    HapticFeedback.selectionClick();
    setState(() { _regionCode = region.code; _regionName = region.name; });
    _loadData(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: context.xBg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Media ─────────────────────────────────────────────
            Stack(children: [
              if (item.mediaType == DiscoveryMediaType.video)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _DetailVideoPlayer(url: item.mediaUrl))
              else
                GestureDetector(
                  onTap: () => _showFullscreenImage(context, item.mediaUrl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 200,
                      maxHeight: MediaQuery.of(context).size.height * 0.75,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item.mediaUrl,
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      errorWidget: (_, __, ___) =>
                          Container(height: 300, color: context.xSurface)))),
              Positioned(
                top: topPad + 8, left: 12,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.55)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16)),
                  onPressed: () => Navigator.pop(context)),
              ),
              if (item.isLive)
                Positioned(
                    top: topPad + 12, right: 20,
                    child: LivePulseIndicator()),
            ]),
            // ── Info ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.xPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: context.xPrimary.withOpacity(0.3))),
                      child: Text(item.category.toUpperCase(),
                        style: TextStyle(color: context.xPrimary,
                            fontSize: 10, fontWeight: FontWeight.w800,
                            letterSpacing: 1))),
                    const Spacer(),
                    Text('${_fmt(item.viewCount)} views',
                      style: TextStyle(color: context.xMuted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 12),
                  Text(item.title,
                    style: TextStyle(color: context.xText,
                        fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 8),
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle,
                      style: TextStyle(
                          color: context.xText.withValues(alpha: 0.54),
                          fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                  Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: item.authorAvatar.isNotEmpty
                          ? NetworkImage(item.authorAvatar) : null,
                      backgroundColor: context.xSurface,
                      child: item.authorAvatar.isEmpty
                          ? Icon(Icons.person, color: context.xMuted) : null),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.authorName,
                          style: TextStyle(
                              color: context.xText,
                              fontWeight: FontWeight.w600)),
                        Text(item.region,
                          style: TextStyle(
                              color: context.xMuted, fontSize: 12)),
                      ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: _toggleFollow,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(colors: _following
                              ? [context.xMuted.withValues(alpha: 0.5),
                                 context.xMuted.withValues(alpha: 0.5)]
                              : [context.xPrimary, context.xSecondary]),
                        ),
                        child: _followLoading
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5))
                            : Text(_following ? 'Following' : 'Follow',
                                style: TextStyle(color: context.xText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail video player ──────────────────────────────────────────────────────
class _DetailVideoPlayer extends StatefulWidget {
  final String url;
  const _DetailVideoPlayer({required this.url});
  @override
  State<_DetailVideoPlayer> createState() => _DetailVideoPlayerState();
}

class _DetailVideoPlayerState extends State<_DetailVideoPlayer> {
  BetterPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        looping: true,
        fit: BoxFit.cover,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enableMute: true,
          enablePlayPause: true,
          enableProgressBar: true,
          enableSkips: false,
          controlBarColor: Colors.black54,
          iconsColor: Colors.white,
        ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network, widget.url),
    );
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) =>
      _ctrl != null ? BetterPlayer(controller: _ctrl!) : const SizedBox.shrink();
}

// ── Detail screen ─────────────────────────────────────────────────────────────
class _DetailScreen extends ConsumerStatefulWidget {
  final DiscoveryItem item;
  const _DetailScreen({required this.item});
  @override
  ConsumerState<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<_DetailScreen> {
  bool _following = false;
  bool _followLoading = false;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _showFullscreenImage(BuildContext context, String url) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.95),
      pageBuilder: (_, __, ___) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _toggleFollow() async {
    if (_followLoading || widget.item.authorId.isEmpty) return;
    final self = ref.read(currentUserProvider);
    if (self == null) return;
    setState(() => _followLoading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      if (_following) {
        await dio.post('/api/remove-contact', data: {
          'userId':    self.xameId,
          'contactId': widget.item.authorId,
        });
        if (mounted) setState(() => _following = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unfollowed \${widget.item.authorName}'),
          backgroundColor: context.xSurface));
      } else {
        await dio.post('/api/add-contact', data: {
          'userId':    self.xameId,
          'contactId': widget.item.authorId,
        });
        if (mounted) setState(() => _following = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Now following \${widget.item.authorName}'),
          backgroundColor: context.xSurface));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_following ? 'Could not unfollow' : 'Could not follow'),
        backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: context.xBg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Media ─────────────────────────────────────────────
            Stack(children: [
              if (item.mediaType == DiscoveryMediaType.video)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _DetailVideoPlayer(url: item.mediaUrl))
              else
                GestureDetector(
                  onTap: () => _showFullscreenImage(context, item.mediaUrl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 200,
                      maxHeight: MediaQuery.of(context).size.height * 0.75,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item.mediaUrl,
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      errorWidget: (_, __, ___) =>
                          Container(height: 300, color: context.xSurface)))),
              Positioned(
                top: topPad + 8, left: 12,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.55)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16)),
                  onPressed: () => Navigator.pop(context)),
              ),
              if (item.isLive)
                Positioned(top: topPad + 12, right: 20,
                    child: LivePulseIndicator()),
            ]),
            // ── Info ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.xPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: context.xPrimary.withOpacity(0.3))),
                      child: Text(item.category.toUpperCase(),
                        style: TextStyle(color: context.xPrimary,
                            fontSize: 10, fontWeight: FontWeight.w800,
                            letterSpacing: 1))),
                    const Spacer(),
                    Text('\${_fmt(item.viewCount)} views',
                      style: TextStyle(color: context.xMuted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 12),
                  Text(item.title,
                    style: TextStyle(color: context.xText,
                        fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 8),
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle,
                      style: TextStyle(
                          color: context.xText.withValues(alpha: 0.54),
                          fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                  Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: item.authorAvatar.isNotEmpty
                          ? NetworkImage(item.authorAvatar) : null,
                      backgroundColor: context.xSurface,
                      child: item.authorAvatar.isEmpty
                          ? Icon(Icons.person, color: context.xMuted) : null),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.authorName,
                          style: TextStyle(color: context.xText,
                              fontWeight: FontWeight.w600)),
                        Text(item.region,
                          style: TextStyle(color: context.xMuted, fontSize: 12)),
                      ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: _toggleFollow,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(colors: _following
                              ? [context.xMuted.withValues(alpha: 0.5),
                                 context.xMuted.withValues(alpha: 0.5)]
                              : [context.xPrimary, context.xSecondary]),
                        ),
                        child: _followLoading
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5))
                            : Text(_following ? 'Following' : 'Follow',
                                style: TextStyle(color: context.xText,
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String region;
  final VoidCallback onPost;
  _EmptyState({required this.region, required this.onPost});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: context.xBg.withOpacity(0.04)),
          child: Icon(Icons.explore_outlined,
              color: context.xMuted.withValues(alpha: 0.5), size: 36)),
        SizedBox(height: 20),
        Text('Nothing in $region yet', style: TextStyle(
            color: context.xText, fontSize: 16,
            fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Be the first to share a moment\nfrom this region',
          style: TextStyle(color: context.xMuted.withValues(alpha: 0.5), fontSize: 13,
              height: 1.5), textAlign: TextAlign.center),
        SizedBox(height: 20),
        GestureDetector(
          onTap: onPost,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: [
                XameColors.primary, XameColors.secondary,
              ])),
            child: Text('Post First',
              style: TextStyle(color: context.xText, fontSize: 14,
                  fontWeight: FontWeight.w700))),
        ),
      ]),
    ),
  );
}
