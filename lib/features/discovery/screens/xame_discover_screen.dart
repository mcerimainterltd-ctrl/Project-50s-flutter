import "../widgets/tv_entry_button.dart";
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../widgets/discovery_cards.dart';
import '../widgets/people_carousel.dart';
import '../widgets/stories_bar.dart';
import '../widgets/region_filter_bar.dart';
import '../widgets/live_pulse.dart';
import '../widgets/story_viewer.dart';
import '../models/discovery_item.dart';

// ── API Service ───────────────────────────────────────────────────────────────
class DiscoveryApiService {
  static final _dio = Dio(BaseOptions(
    baseUrl:        AppConstants.serverUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
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
  const XameDiscoverScreen({Key? key}) : super(key: key);
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
    setState(() {
      _feed    = results[0] as List<DiscoveryItem>;
      _people  = results[1] as List<DiscoveryUser>;
      _stories = results[2] as List<Map<String, dynamic>>;
      _loading = false;
      _page    = 1;
      _hasMore = (_feed.length >= 20);
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
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      floatingActionButton: _PostFAB(
        onPost: () => _showPostDialog(context, user?.xameId ?? ''),
      ),
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtrl,
          physics:    const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor:  const Color(0xFF0A0A0F),
              surfaceTintColor: Colors.transparent,
              floating: true, snap: true, elevation: 0,
              title: Row(children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF7B2FFF)],
                  ).createShader(b),
                  child: const Text('DISCOVERY',
                    style: TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                ),
                const SizedBox(width: 8),
                _LiveCountBadge(count: _feed.where((f) => f.isLive).length),
              ]),
              actions: [
          TVEntryButton(onTap: () => context.push("/tv")),
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _searchOpen ? Icons.close : Icons.search,
                      key: ValueKey(_searchOpen), color: Colors.white70)),
                  onPressed: _searchOpen ? _closeSearch : _openSearch),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                  onPressed: () => _showFilterSheet(context)),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  onPressed: () => _loadData(refresh: true)),
                const SizedBox(width: 4),
              ],
            ),

            // Stories bar — live from API
            SliverToBoxAdapter(
              child: _loading
                ? _StoriesSkeleton()
                : DiscoveryStoriesBar(
                    users: [
                      // Self first
                      {
                        'name':     'You',
                        'avatar':   user?.profilePic ?? '',
                        'hasSeen':  true,
                        'isOnline': true,
                        'isSelf':   true,
                        'onTap':    () => _showPostStoryDialog(context, user?.xameId ?? ''),
                      },
                      // Other users' stories
                      ..._stories.asMap().entries.map((e) {
                        final idx = e.key;
                        final s   = e.value;
                        return {
                          'name':     s['authorName']   as String? ?? '',
                          'avatar':   s['authorAvatar'] as String? ?? '',
                          'hasSeen':  s['hasSeen']      as bool? ?? false,
                          'isOnline': s['isOnline']     as bool? ?? false,
                          'onTap':    () => _openStoryViewer(context, idx),
                        };
                      }),
                    ],
                  ),
            ),

            // Region filter
            SliverToBoxAdapter(
              child: RegionFilterBar(
                onRegionSelected: _onRegionSelected,
                initialCode:      _regionCode),
            ),

            // People carousel — live from API
            if (!_loading && _people.isNotEmpty)
              SliverToBoxAdapter(
                child: PeoplePerspectiveCarousel(
                  users: _people,
                  onAdd: (user) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Request sent to ${user.name}'),
                      backgroundColor: const Color(0xFF1A4A3A),
                      duration: const Duration(seconds: 2)));
                  },
                ),
              ),

            // Section header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(children: [
                  Text(
                    _searchQuery.isNotEmpty
                      ? 'RESULTS FOR "${_searchQuery.toUpperCase()}"'
                      : 'TRENDING IN ${_regionName.toUpperCase()}',
                    style: const TextStyle(color: Colors.white38,
                        fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          color: Color(0xFF2196F3), strokeWidth: 1.5)),
                ]),
              ),
            ),

            // Feed
            if (_loading)
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, __) => const DiscoveryCardSkeleton(), childCount: 3))
            else if (_filtered.isEmpty)
              SliverToBoxAdapter(child: _EmptyState(
                region: _regionName,
                onPost: () => _showPostDialog(context, user?.xameId ?? '')))
            else
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = _filtered[i];
                  return MediaDiscoverCard(
                    mediaUrl:     item.mediaUrl,
                    title:        item.title,
                    category:     item.category,
                    isLive:       item.isLive,
                    authorName:   item.authorName,
                    authorAvatar: item.authorAvatar,
                    viewCount:    item.viewCount,
                    likeCount:    item.likeCount,
                    postId:       item.id,
                    userId:       user?.xameId ?? '',
                    onTap: () {
                      DiscoveryApiService.viewPost(item.id);
                      _openDetail(context, item);
                    },
                  );
                },
                childCount: _filtered.length)),

            // Load more indicator
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(
                      color: Color(0xFF2196F3), strokeWidth: 1.5)))),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // Search overlay
        if (_searchOpen)
          FadeTransition(
            opacity: _searchFade,
            child: _SearchOverlay(
              ctrl:     _searchCtrl,
              onSearch: (q) => setState(() => _searchQuery = q),
              onClose:  _closeSearch,
              feed:     _feed,
            ),
          ),
      ]),
    );
  }

  void _openDetail(BuildContext context, DiscoveryItem item) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim, child: _DetailScreen(item: item)),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FilterSheet(
        currentRegion: _regionCode,
        onApply: (r) { Navigator.pop(context); _onRegionSelected(r); }),
    );
  }

  void _showPostDialog(BuildContext context, String userId) {
    showModalBottomSheet(
      context:          context,
      backgroundColor:  const Color(0xFF161B22),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreatePostSheet(
        userId:   userId,
        region:   _regionName,
        onPosted: () => _loadData(refresh: true),
      ),
    );
  }

  void _openStoryViewer(BuildContext context, int groupIndex) {
    if (_stories.isEmpty) return;
    final groups = _stories.map((s) =>
      StoryGroup.fromMap(s)).toList();
    if (groups.isEmpty) return;
    final safeIndex = groupIndex.clamp(0, groups.length - 1);
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: StoryViewerScreen(
          groups:            groups,
          initialGroupIndex: safeIndex,
          currentUserId:     ref.read(currentUserProvider)?.xameId ?? '',
        ),
      ),
      transitionDuration:        const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    ));
  }

  void _showPostStoryDialog(BuildContext context, String userId) {
    showModalBottomSheet(
      context:          context,
      backgroundColor:  const Color(0xFF161B22),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreateStorySheet(
        userId:   userId,
        onPosted: () => _loadData(refresh: true),
      ),
    );
  }
}

// ── Post FAB ──────────────────────────────────────────────────────────────────
class _PostFAB extends StatelessWidget {
  final VoidCallback onPost;
  const _PostFAB({required this.onPost});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: onPost,
    backgroundColor: const Color(0xFF2196F3),
    foregroundColor: Colors.white,
    elevation: 4,
    icon: const Icon(Icons.add_photo_alternate_outlined),
    label: const Text('Post',
        style: TextStyle(fontWeight: FontWeight.w700)),
  );
}

// ── Create Post Sheet ─────────────────────────────────────────────────────────
class _CreatePostSheet extends StatefulWidget {
  final String   userId, region;
  final VoidCallback onPosted;
  const _CreatePostSheet({
    required this.userId, required this.region,
    required this.onPosted});
  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _titleCtrl   = TextEditingController();
  final _captionCtrl = TextEditingController();
  File?  _mediaFile;
  String _mediaType  = 'image';
  String _category   = 'General';
  bool   _uploading  = false;
  String? _error;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() { _mediaFile = File(picked.path); _mediaType = 'image'; });
    }
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (picked == null) return;

    File videoFile = File(picked.path);
    final size = await videoFile.length();
    const maxBytes = 25 * 1024 * 1024; // 25MB safe limit for discover endpoint

    if (size > maxBytes) {
      setState(() => _error = 'Compressing video...');
      try {
        final info = await VideoCompress.compressVideo(
          picked.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (info?.file != null) {
          final compressedSize = await info!.file!.length();
          if (compressedSize <= maxBytes) {
            videoFile = info.file!;
          } else {
            setState(() => _error =
                'Video too large (${(compressedSize/1024/1024).toStringAsFixed(1)}MB). Try a shorter clip.');
            return;
          }
        }
      } catch (e) {
        setState(() => _error = 'Compression failed: $e');
        return;
      }
    }
    setState(() {
      _mediaFile = videoFile;
      _mediaType = 'video';
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title is required'); return;
    }
    if (_mediaFile == null) {
      setState(() => _error = 'Please select media'); return;
    }
    setState(() { _uploading = true; _error = null; });
    final err = await DiscoveryApiService.createPost(
      authorId:  widget.userId,
      title:     _titleCtrl.text.trim(),
      caption:   _captionCtrl.text.trim(),
      region:    widget.region,
      category:  _category,
      mediaFile: _mediaFile!,
      mediaType: _mediaType,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err == null) {
      Navigator.pop(context);
      widget.onPosted();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Post published!'),
        backgroundColor: Color(0xFF1A4A3A)));
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.white24,
            borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      const Text('Create Post', style: TextStyle(color: Colors.white,
          fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),

      // Media picker
      GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12)),
          child: _mediaFile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(fit: StackFit.expand, children: [
                  _mediaType == 'video'
                    ? Container(
                        color: const Color(0xFF0A0A1A),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_rounded,
                                color: Color(0xFF2196F3), size: 48),
                            const SizedBox(height: 8),
                            Text(
                              _mediaFile!.path.split('/').last,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            FutureBuilder<int>(
                              future: _mediaFile!.length(),
                              builder: (_, snap) => Text(
                                snap.hasData
                                    ? '${(snap.data! / 1024 / 1024).toStringAsFixed(1)}MB'
                                    : '',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                            ),
                          ],
                        ),
                      )
                    : Image.file(_mediaFile!, fit: BoxFit.cover,
                        width: double.infinity),
                  if (_mediaType == 'video')
                    const Center(child: Icon(Icons.play_circle_outline,
                        color: Colors.white54, size: 40)),
                ]))
            : Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                const Icon(Icons.add_photo_alternate_outlined,
                    color: Colors.white38, size: 40),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  GestureDetector(onTap: _pickMedia,
                    child: const Text('Photo',
                      style: TextStyle(color: Color(0xFF2196F3),
                          fontWeight: FontWeight.w600))),
                  const Text('  or  ',
                      style: TextStyle(color: Colors.white38)),
                  GestureDetector(onTap: _pickVideo,
                    child: const Text('Video',
                      style: TextStyle(color: Color(0xFF2196F3),
                          fontWeight: FontWeight.w600))),
                ]),
              ]),
        ),
      ),
      const SizedBox(height: 12),

      // Title
      TextField(
        controller: _titleCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText:  'Title',
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true, fillColor: const Color(0xFF0A0A0F),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF2196F3), width: 1))),
      ),
      const SizedBox(height: 8),

      // Caption
      TextField(
        controller: _captionCtrl,
        style: const TextStyle(color: Colors.white),
        maxLines: 2,
        decoration: InputDecoration(
          hintText:  'Caption (optional)',
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true, fillColor: const Color(0xFF0A0A0F),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF2196F3), width: 1))),
      ),
      const SizedBox(height: 8),

      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: const TextStyle(
              color: Color(0xFFE53935), fontSize: 13))),

      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _uploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: _uploading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Publish',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── Create Story Sheet ────────────────────────────────────────────────────────
class _CreateStorySheet extends StatefulWidget {
  final String userId;
  final VoidCallback onPosted;
  const _CreateStorySheet({required this.userId, required this.onPosted});
  @override
  State<_CreateStorySheet> createState() => _CreateStorySheetState();
}

class _CreateStorySheetState extends State<_CreateStorySheet> {
  File?  _mediaFile;
  String _mediaType = 'image';
  bool   _uploading = false;
  String? _error;
  final _picker = ImagePicker();

  Future<void> _pickMedia() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null)
      setState(() { _mediaFile = File(picked.path); _mediaType = 'image'; });
  }

  Future<void> _submit() async {
    if (_mediaFile == null) {
      setState(() => _error = 'Please select a photo or video'); return;
    }
    setState(() { _uploading = true; _error = null; });
    final err = await DiscoveryApiService.createStory(
      authorId:  widget.userId,
      mediaFile: _mediaFile!,
      mediaType: _mediaType,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err == null) {
      Navigator.pop(context);
      widget.onPosted();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Story posted! Expires in 24hrs'),
        backgroundColor: Color(0xFF1A4A3A)));
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.white24,
            borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      const Text('Add to Your Story',
        style: TextStyle(color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Stories disappear after 24 hours',
        style: TextStyle(color: Colors.white38, fontSize: 13)),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12)),
          child: _mediaFile != null
            ? ClipRRect(borderRadius: BorderRadius.circular(16),
                child: Image.file(_mediaFile!, fit: BoxFit.cover,
                    width: double.infinity))
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(Icons.camera_alt_outlined,
                    color: Colors.white38, size: 48),
                SizedBox(height: 8),
                Text('Tap to select photo',
                  style: TextStyle(color: Colors.white38)),
              ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: const TextStyle(
              color: Color(0xFFE53935), fontSize: 13))),
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _uploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B2FFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: _uploading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Share Story',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── Live count badge ──────────────────────────────────────────────────────────
class _LiveCountBadge extends StatelessWidget {
  final int count;
  const _LiveCountBadge({this.count = 0});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4444).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFFFF4444).withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0xFFFF4444))),
        const SizedBox(width: 4),
        Text('$count LIVE', style: const TextStyle(
            color: Color(0xFFFF4444), fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
    );
  }
}

// ── Stories skeleton ──────────────────────────────────────────────────────────
class _StoriesSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 106,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        width: 72, margin: const EdgeInsets.only(right: 12),
        child: Column(children: [
          const ShimmerBox(width: 66, height: 66, radius: 33),
          const SizedBox(height: 6),
          const ShimmerBox(width: 48, height: 10, radius: 5),
        ]),
      ),
    ),
  );
}

// ── Search overlay ────────────────────────────────────────────────────────────
class _SearchOverlay extends StatefulWidget {
  final TextEditingController ctrl;
  final Function(String)      onSearch;
  final VoidCallback          onClose;
  final List<DiscoveryItem>   feed;
  const _SearchOverlay({required this.ctrl, required this.onSearch,
      required this.onClose, required this.feed});
  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  List<DiscoveryItem> _results = [];

  void _search(String q) {
    widget.onSearch(q);
    setState(() {
      _results = q.isEmpty ? [] : widget.feed.where((i) =>
        i.title.toLowerCase().contains(q.toLowerCase()) ||
        i.category.toLowerCase().contains(q.toLowerCase())
      ).take(6).toList();
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xF00A0A0F),
    child: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: widget.ctrl,
              autofocus:  true,
              onChanged:  _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:  'Search people, topics, moments...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38, size: 20),
                filled: true, fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF2196F3), width: 1)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(onTap: widget.onClose,
            child: const Text('Cancel', style: TextStyle(
                color: Color(0xFF2196F3), fontSize: 14,
                fontWeight: FontWeight.w600))),
        ]),
      ),
      Expanded(
        child: _results.isEmpty && widget.ctrl.text.isEmpty
          ? _SearchSuggestions(ctrl: widget.ctrl, onSearch: widget.onSearch)
          : _results.isEmpty
            ? const Center(child: Text('No results found',
                style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: item.mediaUrl,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 52, height: 52,
                          color: const Color(0xFF1A1A2E)))),
                    title: Text(item.title, style: const TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                    subtitle: Text(item.category, style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
                    trailing: item.isLive
                      ? const LivePulseIndicator(compact: true) : null,
                  );
                }),
      ),
    ])),
  );
}

class _SearchSuggestions extends StatelessWidget {
  final TextEditingController ctrl;
  final Function(String) onSearch;
  const _SearchSuggestions({required this.ctrl, required this.onSearch});
  final _trending = const [
    '🔥 Afrobeats','⚡ Tech Africa','🌍 Global Culture',
    '🎬 Nollywood','🏆 Sport','🎨 Street Art',
    '💡 Startups','🌊 Ocean Life',
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TRENDING SEARCHES', style: TextStyle(
          color: Colors.white38, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8,
        children: _trending.map((t) => GestureDetector(
          onTap: () {
            // Strip emoji prefix — e.g. '🔥 Afrobeats' → 'Afrobeats'
            final query = t.contains(' ') ? t.split(' ').skip(1).join(' ') : t;
            ctrl.text = query;
            onSearch(query);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10)),
            child: Text(t, style: const TextStyle(
                color: Colors.white60, fontSize: 13)),
          ),
        )).toList()),
    ]),
  );
}

// ── Filter sheet ──────────────────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final String currentRegion;
  final Function(DiscoveryRegion) onApply;
  const _FilterSheet({required this.currentRegion, required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _selected;
  @override
  void initState() { super.initState(); _selected = widget.currentRegion; }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('Filter by Region', style: TextStyle(
            color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SizedBox(height: 320,
          child: GridView.builder(
            gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 2.2,
                crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: discoveryRegions.length,
            itemBuilder: (_, i) {
              final r          = discoveryRegions[i];
              final isSelected = r.code == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = r.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                      ? const Color(0xFF2196F3).withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                    border: Border.all(
                      color: isSelected
                        ? const Color(0xFF2196F3).withOpacity(0.5)
                        : Colors.white10)),
                  child: Center(child: Text('${r.flag} ${r.name}',
                    style: TextStyle(
                      color: isSelected
                        ? const Color(0xFF2196F3) : Colors.white54,
                      fontSize: 12,
                      fontWeight: isSelected
                        ? FontWeight.w700 : FontWeight.normal),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () {
              final r = discoveryRegions.firstWhere(
                  (r) => r.code == _selected);
              widget.onApply(r);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0),
            child: const Text('Apply Filter',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    ),
  );
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

  Future<void> _toggleFollow() async {
    if (_followLoading || widget.item.authorId.isEmpty) return;
    final self = ref.read(currentUserProvider);
    if (self == null) return;
    setState(() => _followLoading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      if (_following) {
        // Unfollow
        await dio.post('/api/remove-contact', data: {
          'userId':    self.xameId,
          'contactId': widget.item.authorId,
        });
        if (mounted) setState(() => _following = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Unfollowed \${widget.item.authorName}'),
            backgroundColor: const Color(0xFF1A2332),
          ));
        }
      } else {
        // Follow
        await dio.post('/api/add-contact', data: {
          'userId':    self.xameId,
          'contactId': widget.item.authorId,
        });
        if (mounted) setState(() => _following = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Now following \${widget.item.authorName}'),
            backgroundColor: const Color(0xFF1A4A3A),
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_following
              ? 'Could not unfollow — try again'
              : 'Could not follow — try again'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    body: CustomScrollView(slivers: [
      SliverAppBar(
        expandedHeight: 360, pinned: true,
        backgroundColor: const Color(0xFF0A0A0F),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5)),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 16)),
          onPressed: () => Navigator.pop(context)),
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(imageUrl: item.mediaUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                Container(color: const Color(0xFF1A1A2E))),
            Container(decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)]))),
            if (item.isLive)
              const Positioned(top: 60, right: 20,
                child: LivePulseIndicator()),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF2196F3).withOpacity(0.3))),
                child: Text(item.category.toUpperCase(),
                  style: const TextStyle(color: Color(0xFF2196F3),
                      fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 1))),
              const Spacer(),
              Text('${_fmt(item.viewCount)} views',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            Text(item.title, style: const TextStyle(color: Colors.white,
                fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 8),
            if (item.subtitle.isNotEmpty)
              Text(item.subtitle, style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.5)),
            const SizedBox(height: 16),
            Row(children: [
              CircleAvatar(radius: 20,
                backgroundImage: item.authorAvatar.isNotEmpty
                  ? NetworkImage(item.authorAvatar) : null,
                backgroundColor: const Color(0xFF1A1A2E),
                child: item.authorAvatar.isEmpty
                  ? const Icon(Icons.person, color: Colors.white38) : null),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(item.authorName, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
                Text(item.region, style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
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
                        ? [Colors.white24, Colors.white24]
                        : [const Color(0xFF2196F3), const Color(0xFF7B2FFF)]),
                  ),
                  child: _followLoading
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white))
                      : Text(_following ? 'Following' : 'Follow',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    ]),
  );
}
}
// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String region;
  final VoidCallback onPost;
  const _EmptyState({required this.region, required this.onPost});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.04)),
          child: const Icon(Icons.explore_outlined,
              color: Colors.white24, size: 36)),
        const SizedBox(height: 20),
        Text('Nothing in $region yet', style: const TextStyle(
            color: Colors.white38, fontSize: 16,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Be the first to share a moment\nfrom this region',
          style: TextStyle(color: Colors.white24, fontSize: 13,
              height: 1.5), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onPost,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [
                Color(0xFF2196F3), Color(0xFF7B2FFF),
              ])),
            child: const Text('Post First',
              style: TextStyle(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w700))),
        ),
      ]),
    ),
  );
}
