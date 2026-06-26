import "../widgets/tv_entry_button.dart";
import "discovery_map_screen.dart";
import "package:go_router/go_router.dart";
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../../features/settings/screens/settings_screen.dart';
import 'discovery_fullscreen_viewer.dart';
import 'followers_following_screen.dart';
import 'author_gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:better_player_enhanced/better_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../features/contacts/providers/contacts_provider.dart';
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
    String region = 'global', int page = 1, int limit = 20, String? userId,
  }) async {
    try {
      final res = await _dio.get('/api/discover/feed', queryParameters: {
        'region': region, 'page': page, 'limit': limit,
        if (userId != null) 'userId': userId,
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
          musicUrl:       m['musicUrl']    as String? ?? '',
          musicTitle:     m['musicTitle']  as String? ?? '',
          mediaUrls: m['mediaUrls'] != null
              ? (m['mediaUrls'] as List).map((e) => (e as Map)['url'] as String).toList()
              : const [],
        );
      }).toList();
    } catch (_) { return []; }
  }

  static Future<List<DiscoveryUser>> fetchPeople(String userId, {Set<String> contactIds = const {}, int page = 1}) async {
    try {
      final res = await _dio.get('/api/discover/people',
          queryParameters: {'userId': userId, 'limit': 30, 'page': page});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) return [];
      return (data['people'] as List).map((p) {
        final m = Map<String, dynamic>.from(p);
        final id = m['id'] as String? ?? '';
        return DiscoveryUser(
          id:           id,
          name:         m['name']        as String? ?? '',
          avatarUrl:    m['avatarUrl']   as String? ?? '',
          mutualCount:  (m['mutualCount'] as num?)?.toInt() ?? 0,
          isOnline:     m['isOnline']    as bool? ?? false,
          tagline:      m['tagline']     as String?,
          isAdded:      contactIds.contains(id),
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

  static Future<void> viewPost(String postId, {String? userId}) async {
    try {
      await _dio.post('/api/discover/view', data: {'postId': postId, if (userId != null) 'userId': userId});
    } catch (_) {}
  }

  static Future<bool> deletePost(String postId, String userId) async {
    try {
      final res = await _dio.delete('/api/discover/post/$postId',
          queryParameters: {'userId': userId},
          data: {'userId': userId});
      return res.data['success'] == true;
    } catch (_) { return false; }
  }

  static Future<String?> createPost({
    required String authorId,
    required String title,
    required String caption,
    required String region,
    required String category,
    required File   mediaFile,
    required String mediaType,
    bool isWhisper = false,
    bool isCollabOpen = false,
    String musicUrl = '',
    String musicTitle = '',
    void Function(int, int)? onProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'authorId':     authorId,
        'title':        title,
        'caption':      caption,
        'region':       region,
        'category':     category,
        'mediaType':    mediaType,
        'isWhisper':    isWhisper.toString(),
        'isCollabOpen': isCollabOpen.toString(),
        'musicTitle':   musicTitle,
        if (musicUrl.isNotEmpty) 'musicUrl': musicUrl,
        'media': await MultipartFile.fromFile(mediaFile.path),
      });
      final res = await _dio.post(
        '/api/discover/post',
        data: formData,
        onSendProgress: onProgress,
      );
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
  final bool isTabActive;
  const XameDiscoverScreen({Key? key, this.authorId, this.isTabActive = true}) : super(key: key);
  @override
  ConsumerState<XameDiscoverScreen> createState() => _XameDiscoverScreenState();
}

class _XameDiscoverScreenState extends ConsumerState<XameDiscoverScreen>
    with TickerProviderStateMixin {
  final _scrollCtrl  = ScrollController();
  final _searchCtrl  = TextEditingController();
  StreamSubscription? _collabRequestSub;
  StreamSubscription? _collabAcceptedSub;
  bool  _searchOpen  = false;
  bool  _loading     = true;
  bool  _loadingMore = false;
  String _regionCode = 'global';
  String _regionName = 'Global';
  String _searchQuery = '';
  String _moodFilter  = '';
  String? _authorFilter;
  int    _page        = 1;
  bool   _hasMore     = true;

  List<DiscoveryItem>           _feed    = [];
  final Map<String, GlobalKey<MediaDiscoverCardState>> _videoKeys = {};
  List<DiscoveryUser>           _people      = [];
  int                           _peoplePage  = 1;
  bool                          _hasMorePeople = true;
  bool                          _loadingMorePeople = false;
  List<_OfficialPost>           _officialPosts = [];
  List<Map<String,dynamic>>      _leaderboard   = [];
  List<Map<String, dynamic>>    _stories = [];
  int                            _currentFeedIndex = 0;

  late AnimationController _searchAnim;
  late Animation<double>   _searchFade;
  StreamSubscription?      _discoverySub;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _searchFade = CurvedAnimation(
        parent: _searchAnim, curve: Curves.easeOut);
    _scrollCtrl.addListener(_onScroll);
    // Auto-refresh feed when a followed contact posts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _discoverySub = ref.read(socketServiceProvider)
          .newDiscoveryPost
          .listen((authorId) {
        if (!mounted) return;
        final contacts = ref.read(contactsProvider).valueOrNull ?? [];
        final isContact = contacts.any((c) => c.id == authorId);
        if (isContact) _loadData(refresh: true);
      });

      // Collab request — show accept/decline sheet to post author
      _collabRequestSub = ref.read(socketServiceProvider)
          .collabRequest
          .listen((data) {
        if (!mounted) return;
        _showCollabRequestSheet(data);
      });

      // Collab accepted — notify requester
      _collabAcceptedSub = ref.read(socketServiceProvider)
          .collabAccepted
          .listen((data) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🤝 Your collab on "${data['postTitle']}" was accepted!'),
          backgroundColor: const Color(0xFF1A3A3A),
          duration: const Duration(seconds: 4),
        ));
        _loadData(refresh: true);
      });
    });
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
    _discoverySub?.cancel();
    _collabRequestSub?.cancel();
    _collabAcceptedSub?.cancel();
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
    final cachedFeed = CacheService.loadDiscoveryFeed(_regionName);
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


  Future<void> _fetchOfficialPosts() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get('/api/xamepage/announcements');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final allPosts = (data['announcements'] as List? ?? [])
          .map((p) => _OfficialPost.fromJson(p as Map<String, dynamic>))
          .toList();
        // Filter by platform
        final posts = allPosts.where((p) =>
          p.platform == 'both' ||
          (Platform.isIOS && p.platform == 'ios') ||
          (!Platform.isIOS && p.platform == 'android')
        ).toList();
        if (mounted) setState(() => _officialPosts = posts);
      }
    } catch (_) {}
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res  = await dio.get('/api/rewards/leaderboard');
      if (res.data['success'] == true && mounted) {
        setState(() => _leaderboard = List<Map<String,dynamic>>.from(res.data['leaderboard'] ?? []));
      }
    } catch (_) {}
  }


  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) setState(() { _page = 1; _hasMore = true; _feed = []; });
    setState(() => _loading = true);
    if (refresh || _officialPosts.isEmpty) _fetchOfficialPosts();
    if (refresh || _leaderboard.isEmpty) _fetchLeaderboard();
    final user = ref.read(currentUserProvider);
    final userId = user?.xameId ?? '';

    final results = await Future.wait([
      DiscoveryApiService.fetchFeed(region: _regionName, page: 1, userId: userId),
      DiscoveryApiService.fetchPeople(userId, contactIds: ref.read(contactsProvider).valueOrNull?.map((c) => c.id).toSet() ?? {}, page: 1),
      DiscoveryApiService.fetchStories(userId),
    ]);

    if (!mounted) return;
    final feed    = results[0] as List<DiscoveryItem>;
    final people  = results[1] as List<DiscoveryUser>;
    final stories = results[2] as List<Map<String, dynamic>>;

    // Cache for instant load next time
    CacheService.saveDiscoveryFeed(_regionName,
        feed.map((i) => i.toJson()).toList());
    CacheService.saveDiscoveryPeople(
        people.map((p) => p.toJson()).toList());

    setState(() {
      _feed    = _authorFilter != null
          ? feed.where((i) => i.authorId == _authorFilter).toList()
          : feed;
      _people     = people;
      _peoplePage = 1;
      _hasMorePeople = people.length >= 30;
      _stories = stories;
      _loading = false;
      _page    = 1;
      _hasMore = (feed.length >= 20);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final user2 = ref.read(currentUserProvider);
    final more = await DiscoveryApiService.fetchFeed(
      region: _regionName, page: _page + 1, userId: user2?.xameId);
    if (!mounted) return;
    setState(() {
      _feed.addAll(more);
      _page++;
      _hasMore    = more.length >= 20;
      _loadingMore = false;
    });
  }

  List<DiscoveryItem> get _filtered {
    var list = _feed;
    if (_searchQuery.isNotEmpty) {
      list = list.where((i) =>
        i.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        i.category.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    if (_moodFilter.isNotEmpty) {
      list = list.where((i) =>
        i.category.toLowerCase().contains(_moodFilter.toLowerCase()) ||
        i.title.toLowerCase().contains(_moodFilter.toLowerCase())
      ).toList();
    }
    return list;
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

  Future<void> _loadMorePeople() async {
    if (_loadingMorePeople || !_hasMorePeople) return;
    final userId = ref.read(currentUserProvider)?.xameId;
    if (userId == null) return;
    setState(() => _loadingMorePeople = true);
    try {
      final nextPage = _peoplePage + 1;
      final more = await DiscoveryApiService.fetchPeople(userId, page: nextPage);
      setState(() {
        _people = [..._people, ...more];
        _peoplePage = nextPage;
        _hasMorePeople = more.length >= 30;
        _loadingMorePeople = false;
      });
    } catch (_) {
      setState(() => _loadingMorePeople = false);
    }
  }

  void _showCollabRequestSheet(Map<String, dynamic> data) {
    final postId        = data['postId']         as String? ?? '';
    final postTitle     = data['postTitle']       as String? ?? 'your post';
    final requesterId   = data['requesterId']     as String? ?? '';
    final requesterName = data['requesterName']   as String? ?? 'Someone';
    final requesterAvatar = data['requesterAvatar'] as String? ?? '';
    final mediaUrl      = data['mediaUrl']        as String? ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('🤝 Collab Request',
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          // Requester info
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5)),
              child: ClipOval(child: requesterAvatar.isNotEmpty
                  ? CachedNetworkImage(imageUrl: requesterAvatar, fit: BoxFit.cover)
                  : Container(color: const Color(0xFF1A2E2E),
                      child: const Icon(Icons.person, color: Colors.white54)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(requesterName, style: const TextStyle(color: Colors.white,
                  fontSize: 15, fontWeight: FontWeight.w700)),
              Text('wants to collab on "$postTitle"',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
          ]),
          // Preview of their media
          if (mediaUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(imageUrl: mediaUrl,
                  height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(height: 160,
                      color: const Color(0xFF1A1A2E),
                      child: const Icon(Icons.image_outlined,
                          color: Colors.white24, size: 40)))),
          ],
          const SizedBox(height: 20),
          Row(children: [
            // Decline
            Expanded(child: OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                // No server action needed — just dismiss, post stays open
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white12),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Decline'),
            )),
            const SizedBox(width: 12),
            // Accept
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final user = ref.read(currentUserProvider);
                if (user == null) return;
                try {
                  final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
                  final res = await dio.post('/api/discover/collab/accept',
                      data: {'postId': postId, 'authorId': user.xameId});
                  if (res.data['success'] == true) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('🤝 Collab accepted! Post updated.'),
                        backgroundColor: Color(0xFF1A3A3A),
                      ));
                      _loadData(refresh: true);
                    }
                  }
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Accept Collab 🤝',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ]),
      ),
    );
  }

  void _onRegionSelected(DiscoveryRegion region) {
    HapticFeedback.selectionClick();
    setState(() { _regionCode = region.code; _regionName = region.name; });
    _loadData(refresh: true);
  }

  void _showDiscoveryMenu(BuildContext context, dynamic user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.xSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            // Stories bar — "You" always shown, even with no contact stories yet
            DiscoveryStoriesBar(users: [
              {'name':'You','avatar':user?.profilePic??'','hasSeen':true,'isOnline':false,'isSelf':true,
               'onTap':() { Navigator.pop(context); _showPostStoryDialog(context, user?.xameId??''); }},
              ..._stories.asMap().entries.map((e) => {
                'name': (e.value['authorName'] as String?) ?? '',
                'avatar': (e.value['authorAvatar'] as String?) ?? '',
                'hasSeen': e.value['hasSeen'] as bool?? false,
                'isOnline': e.value['isOnline'] as bool?? false,
                'onTap': () { Navigator.pop(context); _openStoryViewer(context, e.key); },
              }),
            ]),
            const SizedBox(height: 12),
            // Menu items
            _menuItem(context, '✍️', 'Create Post', () { Navigator.pop(context); _showPostDialog(context, user?.xameId??''); }),
            _menuItem(context, '📖', _stories.isNotEmpty ? 'Stories' : 'Add a Story', () {
              Navigator.pop(context);
              if (_stories.isNotEmpty) {
                _openStoryViewer(context, 0);
              } else {
                _showPostStoryDialog(context, user?.xameId ?? '');
              }
            }),
            _menuItem(context, '👥', 'People You May Know', () {
              Navigator.pop(context);
              showModalBottomSheet(context: context, backgroundColor: context.xSurface, isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.7, maxChildSize: 0.95,
                  builder: (_, sc) => _AllPeopleScreen(initialPeople: _people, userId: user?.xameId??'',
                    onAdd: (u) async { try { final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
                      await dio.post('/api/send-contact-request', data: {'userId': user?.xameId??'', 'contactId': u.id});
                      setState(() => u.isAdded = true); } catch (_) {} })));
            }),
            _menuItem(context, '📣', 'XamePage News', () {
              Navigator.pop(context);
              if (_officialPosts.isNotEmpty) showModalBottomSheet(context: context, backgroundColor: context.xSurface,
                isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.6, maxChildSize: 0.95,
                  builder: (_, sc) => ListView(controller: sc, children: [_XameNewsChannel(posts: _officialPosts, context: context)])));
            }),
            _menuItem(context, '👥', 'My Followers & Following', () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FollowersFollowingScreen(
                  userId: user?.xameId ?? '',
                  currentUserId: user?.xameId ?? '',
                ),
              ));
            }),
            _menuItem(context, '🏆', 'Leaderboard', () {
              Navigator.pop(context);
              showModalBottomSheet(context: context, backgroundColor: context.xSurface, isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.5, maxChildSize: 0.8,
                  builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
                    if (_leaderboard.isNotEmpty) _RewardsTicker(leaderboard: _leaderboard),
                  ])));
            }),
            _menuItem(context, '🔥', 'Trending Now', () {
              Navigator.pop(context);
              final trending = _feed.isNotEmpty ? (List.of(_feed)..sort((a,b) => b.viewCount.compareTo(a.viewCount))).take(12).toList() : <DiscoveryItem>[];
              if (trending.isNotEmpty)
                showModalBottomSheet(context: context, backgroundColor: context.xSurface,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.5, maxChildSize: 0.9,
                    builder: (_, sc) => ListView(controller: sc, children: [
                      _TrendingPulseStrip(
                        posts: trending,
                        onTap: (item) { Navigator.pop(context); DiscoveryApiService.viewPost(item.id, userId: user?.xameId); _openDetail(context, item); }),
                    ])));
            }),
            _menuItem(context, '🗺️', 'Discovery Map', () { Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => DiscoveryMapScreen(
                posts: _feed, regions: discoveryRegions, currentRegion: _regionCode, onRegionSelected: _onRegionSelected)));
            }),
            _menuItem(context, '📺', 'XameTV', () { Navigator.pop(context); context.push('/tv'); }),
            _menuItem(context, '🔍', 'Search Posts', () { Navigator.pop(context); _openSearch(); }),
            _menuItem(context, '🔄', 'Refresh Feed', () { Navigator.pop(context); _loadData(refresh: true); }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, String emoji, String label, VoidCallback onTap) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
      title: Text(label, style: TextStyle(color: context.xText, fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Fullscreen vertical feed ──────────────────────────────────
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)))
        else if (_filtered.isEmpty)
          Center(child: _EmptyState(region: _regionName, onPost: () => _showPostDialog(context, user?.xameId??'')))
        else
          PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: _filtered.length,
            onPageChanged: (i) {
              setState(() => _currentFeedIndex = i);
              if (i >= _filtered.length - 3) _loadMore();
            },
            itemBuilder: (_, i) {
              final item = _filtered[i];
              return _FullscreenFeedPage(
                item: item,
                isActive: i == _currentFeedIndex && widget.isTabActive,
                currentUserId: user?.xameId??'',
                currentUserAvatar: user?.profilePic??'',
                onAvatarTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AuthorGalleryScreen(
                    authorId: item.authorId, authorName: item.authorName,
                    authorAvatar: item.authorAvatar, currentUserId: user?.xameId??'',
                    currentUserAvatar: user?.profilePic??''))),
                onPost: () => _showPostDialog(context, user?.xameId??''),
              );
            },
          ),

        // ── Top overlay (background, non-interactive) ──────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          height: 80,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ── Top overlay (interactive row, sits above video, only its own widgets are tappable) ──
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                if (widget.authorId != null)
                  GestureDetector(
                    onTap: () => context.canPop() ? context.pop() : context.go('/contacts'),
                    child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ShaderMask(
                    shaderCallback: (b) => const LinearGradient(colors: [Color(0xFF00C896), Color(0xFF00E5FF)]).createShader(b),
                    child: const Text('DISCOVERY', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ),
                ),
                const SizedBox(width: 8),
                _LiveCountBadge(count: _feed.where((f) => f.isLive).length),
                const Spacer(),
                // Region filter pill
                RegionFilterBar(onRegionSelected: _onRegionSelected, initialCode: _regionCode),
              ]),
            ),
          ),
        ),

        // ── Floating ⋮ menu button ────────────────────────────────────
        Positioned(
          top: 0, right: 16,
          child: SafeArea(
            child: GestureDetector(
              onTap: () => _showDiscoveryMenu(context, user),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text('Menu', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),



        // ── Search overlay ────────────────────────────────────────────
        if (_searchOpen)
          FadeTransition(
            opacity: _searchFade,
            child: _SearchOverlay(
              ctrl: _searchCtrl,
              onSearch: (q) => setState(() => _searchQuery = q),
              onClose: _closeSearch,
              feed: _feed,
              onItemTap: (item) {
                DiscoveryApiService.viewPost(item.id, userId: user?.xameId);
                _openDetail(context, item);
              },
            ),
          ),
      ]),
    );
  }

  void _openDetail(BuildContext context, DiscoveryItem item) {
    final user = ref.read(currentUserProvider);
    final posts = _filtered.map((e) => {
      'id':            e.id,
      'authorId':      e.authorId,
      'authorName':    e.authorName,
      'authorAvatar':  e.authorAvatar,
      'mediaUrl':      e.mediaUrl,
      'mediaType':     e.mediaType == DiscoveryMediaType.video ? 'video' : 'image',
      'title':         e.title,
      'category':      e.category,
      'likeCount':     e.likeCount,
      'commentCount':  e.commentCount,
      'viewCount':     e.viewCount,
      'ts':            e.ts?.toIso8601String(),
      'musicUrl':      e.musicUrl,
      'musicTitle':    e.musicTitle,
      'mediaUrls':     e.mediaUrls.isNotEmpty ? e.mediaUrls.map((u) => {'url': u}).toList() : null,
    }).toList();
    final idx = _filtered.indexWhere((e) => e.id == item.id);
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: DiscoveryFullscreenViewer(
          posts:            posts,
          initialIndex:     idx < 0 ? 0 : idx,
          currentUserId:    user?.xameId ?? '',
          currentUserAvatar: user?.profilePic ?? '',
        ),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    ));
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.xSurface,
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
      backgroundColor:  context.xSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => CreatePostSheet(
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
      transitionDuration:        Duration(milliseconds: 200),
      reverseTransitionDuration: Duration(milliseconds: 200),
    ));
  }

  void _showPostStoryDialog(BuildContext context, String userId) {
    showModalBottomSheet(
      context:          context,
      backgroundColor:  context.xSurface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreateStorySheet(
        userId:   userId,
        onPosted: () => _loadData(refresh: true),
      ),
    );
  }
}

// ── Post FAB ──────────────────────────────────────────────────────────────────
// ── All People Screen ────────────────────────────────────────────────────────
class _AllPeopleScreen extends StatefulWidget {
  final List<DiscoveryUser> initialPeople;
  final Future<void> Function(DiscoveryUser) onAdd;
  final String userId;
  const _AllPeopleScreen({required this.initialPeople, required this.onAdd, required this.userId});
  @override
  State<_AllPeopleScreen> createState() => _AllPeopleScreenState();
}

class _AllPeopleScreenState extends State<_AllPeopleScreen> {
  List<DiscoveryUser> _people = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int  _page = 1;
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _people = List.from(widget.initialPeople);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      // Fetch next page — reuse fetchPeople with page param
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get('/api/discover/people',
          queryParameters: {'userId': widget.userId, 'page': _page + 1, 'limit': 30});
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final more = (data['people'] as List).map((p) {
          final m = Map<String, dynamic>.from(p);
          return DiscoveryUser(
            id:          m['id']          as String? ?? '',
            name:        m['name']        as String? ?? '',
            avatarUrl:   m['avatarUrl']   as String? ?? '',
            mutualCount: (m['mutualCount'] as num?)?.toInt() ?? 0,
            isOnline:    m['isOnline']    as bool? ?? false,
            tagline:     m['tagline']     as String?,
          );
        }).toList();
        setState(() {
          _people.addAll(more);
          _page++;
          _hasMore = more.length >= 30;
          _loadingMore = false;
        });
      } else {
        setState(() { _hasMore = false; _loadingMore = false; });
      }
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  List<DiscoveryUser> get _filtered => _query.isEmpty
      ? _people
      : _people.where((u) => u.name.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      appBar: AppBar(
        backgroundColor: context.xBg,
        elevation: 0,
        title: Text('People on XamePage',
            style: TextStyle(color: context.xText, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.xText, size: 18),
          onPressed: () => Navigator.pop(context)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: context.xText),
              decoration: InputDecoration(
                hintText: 'Search people...',
                hintStyle: TextStyle(color: context.xMuted),
                filled: true,
                fillColor: context.xSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                prefixIcon: Icon(Icons.search, color: context.xMuted, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.xPrimary))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _filtered.length + (_loadingMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _filtered.length) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: context.xPrimary, strokeWidth: 2)));
                }
                final user = _filtered[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: user.avatarUrl.isNotEmpty
                        ? NetworkImage(user.avatarUrl) : null,
                    backgroundColor: context.xSurface,
                    child: user.avatarUrl.isEmpty
                        ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: TextStyle(color: context.xText,
                                fontWeight: FontWeight.w700)) : null),
                  title: Text(user.name,
                      style: TextStyle(color: context.xText,
                          fontWeight: FontWeight.w600)),
                  subtitle: user.mutualCount > 0
                      ? Text('${user.mutualCount} mutual',
                          style: TextStyle(color: context.xMuted, fontSize: 12))
                      : null,
                  trailing: user.isAdded
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: context.xSurface,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Requested',
                              style: TextStyle(color: context.xMuted,
                                  fontSize: 12, fontWeight: FontWeight.w600)))
                      : GestureDetector(
                          onTap: () async {
                            await widget.onAdd(user);
                            setState(() => user.isAdded = true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: [context.xPrimary, context.xSecondary]),
                              borderRadius: BorderRadius.circular(20)),
                            child: Text('Add',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 13, fontWeight: FontWeight.w700)))),
                );
              }),
    );
  }
}

class _PostFAB extends StatelessWidget {
  final VoidCallback onPost;
  _PostFAB({required this.onPost});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: onPost,
    backgroundColor: XameColors.primary,
    foregroundColor: context.xBg,
    elevation: 4,
    icon: const Icon(Icons.add_photo_alternate_outlined),
    label: const Text('Post',
        style: TextStyle(fontWeight: FontWeight.w700)),
  );
}

// ── Create Post Sheet ─────────────────────────────────────────────────────────
class CreatePostSheet extends StatefulWidget {
  final String   userId, region;
  final VoidCallback onPosted;
  const CreatePostSheet({
    required this.userId, required this.region,
    required this.onPosted});
  @override
  State<CreatePostSheet> createState() => CreatePostSheetState();
}

class CreatePostSheetState extends State<CreatePostSheet> {
  final _titleCtrl   = TextEditingController();
  final _captionCtrl = TextEditingController();
  final _quoteCtrl   = TextEditingController();
  final _authorCtrl  = TextEditingController();
  File?  _mediaFile;
  String _mediaType  = 'image';
  String _category   = 'General';
  bool   _uploading  = false;
  double _uploadProgress = 0;
  bool   _isWhisper    = false;
  bool   _isCollabOpen = false;
  String _musicUrl   = '';
  String _musicTitle = '';
  String? _detectedRegion;
  bool   _locating     = false;
  String? _error;
  final _picker = ImagePicker();
  final _screenshotCtrl = ScreenshotController();

  // Quote composer state
  bool   _quoteMode    = false;
  int    _gradientIndex = 0;
  int    _fontIndex    = 0;
  int    _alignIndex   = 0;
  Color  _textColor    = Colors.white;

  static const _gradients = [
    [Color(0xFF1a1a2e), Color(0xFF16213e)],
    [Color(0xFF0f3460), Color(0xFF533483)],
    [Color(0xFF00B0A0), Color(0xFF008A7D)],
    [Color(0xFF1B4332), Color(0xFF40916C)],
    [Color(0xFF6A0572), Color(0xFFAB47BC)],
    [Color(0xFFB5451B), Color(0xFFE8871E)],
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    [Color(0xFF000000), Color(0xFF434343)],
  ];

  static const _gradientNames = ['Midnight','Cosmic','XamePage','Forest','Purple','Sunset','Ocean','Noir'];
  static const _fonts = ['Default','Serif','Monospace','Cursive'];
  static const _aligns = [TextAlign.center, TextAlign.left, TextAlign.right];
  static const _alignIcons = [Icons.format_align_center, Icons.format_align_left, Icons.format_align_right];
  static const _textColors = [Colors.white, Colors.black, Color(0xFFFFD700), Color(0xFF00B0A0)];
  static const _textColorNames = ['White','Black','Gold','Teal'];

  @override
  void initState() {
    super.initState();
    _tryAutoLocate();
  }

  // Map lat/lng to nearest discoveryRegion code
  String _coordsToRegion(double lat, double lng) {
    // Simple bounding box matching
    if (lat >= 4  && lat <= 14  && lng >= 3   && lng <= 15)  return 'ng';  // Nigeria
    if (lat >= 5  && lat <= 11  && lng >= -3  && lng <= 1)   return 'gh';  // Ghana
    if (lat >= -5 && lat <= 5   && lng >= 33  && lng <= 42)  return 'ke';  // Kenya
    if (lat >= -35 && lat <= -22 && lng >= 16 && lng <= 33)  return 'za';  // South Africa
    if (lat >= 25  && lat <= 50  && lng >= -125 && lng <= -65) return 'us'; // USA
    if (lat >= 50  && lat <= 60  && lng >= -8  && lng <= 2)  return 'gb';  // UK
    if (lat >= 36  && lat <= 71  && lng >= -10 && lng <= 40) return 'eu';  // Europe
    if (lat >= 8   && lat <= 37  && lng >= 68  && lng <= 97) return 'in';  // India
    if (lat >= 22  && lat <= 26  && lng >= 51  && lng <= 56) return 'ae';  // UAE
    if (lat >= 1   && lat <= 2   && lng >= 103 && lng <= 104) return 'sg'; // Singapore
    if (lat >= 30  && lat <= 46  && lng >= 129 && lng <= 146) return 'jp'; // Japan
    if (lat >= -34 && lat <= 5   && lng >= -74 && lng <= -34) return 'br'; // Brazil
    if (lat >= 42  && lat <= 84  && lng >= -141 && lng <= -52) return 'ca'; // Canada
    if (lat >= -44 && lat <= -10 && lng >= 113 && lng <= 154) return 'au'; // Australia
    return 'global';
  }

  Future<void> _tryAutoLocate() async {
    // Check if autoLocate is enabled in settings
    final autoLocate = SettingsNotifier.currentSettings.autoLocate;
    if (!autoLocate) return;

    setState(() => _locating = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied ||
            req == LocationPermission.deniedForever) {
          setState(() => _locating = false);
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8));
      final code = _coordsToRegion(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _detectedRegion = code;
          _locating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _quoteCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  String _fontFamily() {
    switch (_fontIndex) {
      case 1: return 'Georgia';
      case 2: return 'Courier New';
      case 3: return 'cursive';
      default: return '';
    }
  }

  Widget _buildQuotePreview({bool forCapture = false}) {
    final gradient = _gradients[_gradientIndex];
    final align = _aligns[_alignIndex];
    final font = _fontFamily();
    return Container(
      width: 320,
      constraints: const BoxConstraints(minHeight: 320),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: forCapture ? null : BorderRadius.circular(16)),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('"', textAlign: align, style: TextStyle(
              color: _textColor.withOpacity(0.4), fontSize: 60,
              fontFamily: font.isNotEmpty ? font : null, height: 0.5)),
            SizedBox(height: 8),
            Text(
              _quoteCtrl.text.isEmpty ? 'Your quote here...' : _quoteCtrl.text,
              textAlign: align,
              maxLines: null,
              style: TextStyle(
                color: _quoteCtrl.text.isEmpty ? _textColor.withOpacity(0.4) : _textColor,
                fontSize: 18, fontWeight: FontWeight.w600, height: 1.5,
                fontFamily: font.isNotEmpty ? font : null)),
            if (_authorCtrl.text.isNotEmpty) ...[
              SizedBox(height: 16),
              Text('— ${_authorCtrl.text}', textAlign: align,
                style: TextStyle(color: _textColor.withOpacity(0.7),
                  fontSize: 13, fontStyle: FontStyle.italic,
                  fontFamily: font.isNotEmpty ? font : null)),
            ],
          ])),
        Positioned(bottom: 10, right: 14,
          child: Text('XamePage', style: TextStyle(
            color: _textColor.withOpacity(0.25), fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1))),
      ]));
  }

  Future<File?> _renderQuoteToFile() async {
    try {
      final gradient   = _gradients[_gradientIndex];
      final align      = _aligns[_alignIndex];
      final fontIndex  = _fontIndex;
      final textColor  = _textColor;
      final quoteText  = _quoteCtrl.text;
      final authorText = _authorCtrl.text;
      String getFont() {
        switch (fontIndex) {
          case 1: return 'Georgia';
          case 2: return 'Courier New';
          default: return '';
        }
      }
      final f = getFont();
      final ctrl = ScreenshotController();
      final bytes = await ctrl.captureFromWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('"', textAlign: align,
                        style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 60,
                          fontFamily: f.isNotEmpty ? f : null, height: 0.5)),
                      const SizedBox(height: 8),
                      Text(quoteText.isEmpty ? 'Your quote here...' : quoteText,
                        textAlign: align,
                        style: TextStyle(
                          color: quoteText.isEmpty ? textColor.withOpacity(0.4) : textColor,
                          fontSize: 18, fontWeight: FontWeight.w600, height: 1.5,
                          fontFamily: f.isNotEmpty ? f : null)),
                      if (authorText.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('— ' + authorText, textAlign: align,
                          style: TextStyle(color: textColor.withOpacity(0.7),
                            fontSize: 13, fontStyle: FontStyle.italic,
                            fontFamily: f.isNotEmpty ? f : null)),
                      ],
                    ])),
                  Positioned(bottom: 10, right: 14,
                    child: Text('XamePage',
                      style: TextStyle(color: textColor.withOpacity(0.25),
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
                ]),
              ),
            ),
          ),
        ),
        pixelRatio: 2.0,
        delay: const Duration(milliseconds: 200),
      ).timeout(const Duration(seconds: 20));
      if (bytes == null || bytes.isEmpty) return null;
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/quote_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      debugPrint('Quote render error: $e');
      if (mounted) setState(() => _error = 'Render error: $e');
      return null;
    }
  }

  Future<void> _pickMedia() async {
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        requestType: RequestType.image,
        maxAssets: 10,
      ),
    );
    if (assets == null || assets.isEmpty) return;
    final file = await assets.first.originFile;
    if (file != null) {
      setState(() { _mediaFile = file; _mediaType = 'image'; });
    }
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (picked == null) return;

    final videoFile = File(picked.path);
    final size = await videoFile.length();
    const maxBytes = 100 * 1024 * 1024; // 100MB limit

    if (size > maxBytes) {
      setState(() => _error =
          'Video too large (${(size/1024/1024).toStringAsFixed(1)}MB). Maximum is 100MB.');
      return;
    }
    setState(() {
      _mediaFile = videoFile;
      _mediaType = 'video';
      _error = null;
    });
  }

  File? _musicFile;

  Future<void> _pickMusic(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      setState(() {
        _musicFile  = File(file.path!);
        _musicUrl   = file.path ?? '';
        _musicTitle = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      });
    } catch (_) {}
  }

  Future<void> _pickMusicFromLibrary(BuildContext context) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get('/api/discover/music-library');
      final tracks = (res.data['tracks'] as List).cast<Map<String, dynamic>>();
      if (!context.mounted) return;
      final AudioPlayer previewPlayer = AudioPlayer();
      String previewingId = '';
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF12121E),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Choose Background Music',
                style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  final isSel = _musicUrl == t['url'];
                  final isPrev = previewingId == t['id'];
                  return ListTile(
                    leading: GestureDetector(
                      onTap: () async {
                        if (isPrev) {
                          await previewPlayer.stop();
                          setSheet(() => previewingId = '');
                        } else {
                          setSheet(() => previewingId = t['id'] as String);
                          await previewPlayer.stop();
                          await previewPlayer.setUrl(t['url'] as String);
                          await previewPlayer.play();
                        }
                      },
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: isPrev
                              ? const Color(0xFF00E5A0).withOpacity(0.2)
                              : isSel
                                  ? const Color(0xFF00E5A0).withOpacity(0.1)
                                  : Colors.white10,
                          borderRadius: BorderRadius.circular(8)),
                        child: Center(child: Icon(
                          isPrev ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          color: isPrev ? const Color(0xFF00E5A0) : Colors.white54,
                          size: 20)))),
                    title: Text(t['title'] as String,
                        style: TextStyle(
                            color: isSel
                                ? const Color(0xFF00E5A0)
                                : Colors.white,
                            fontWeight: isSel
                                ? FontWeight.w700 : FontWeight.normal)),
                    subtitle: Text('${t['genre']} • ${t['duration']}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    trailing: isSel
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF00E5A0), size: 18)
                        : null,
                    onTap: () {
                      previewPlayer.stop();
                      setState(() {
                        _musicUrl   = t['url'] as String;
                        _musicTitle = t['title'] as String;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.music_off_rounded,
                  color: Colors.white38, size: 20),
              title: const Text('No Music',
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                setState(() { _musicUrl = ''; _musicTitle = ''; });
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ]),
        )),
      ).whenComplete(() => previewPlayer.dispose());
    } catch (_) {}
  }

  void _pickRegion(BuildContext context) {
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
          const Text('Post to Region',
              style: TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: discoveryRegions.length,
              itemBuilder: (_, i) {
                final r = discoveryRegions[i];
                final isSel = _detectedRegion == r.code ||
                    (_detectedRegion == null && widget.region == r.name);
                return ListTile(
                  leading: Text(r.flag,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(r.name,
                      style: TextStyle(
                          color: isSel
                              ? const Color(0xFF00E5FF)
                              : Colors.white,
                          fontWeight: isSel
                              ? FontWeight.w700
                              : FontWeight.normal)),
                  trailing: isSel
                      ? const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF00E5FF), size: 18)
                      : null,
                  onTap: () {
                    setState(() => _detectedRegion = r.code);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (_quoteMode) {
      if (_quoteCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Please write your quote'); return;
      }
      setState(() { _uploading = true; _error = null; });
      final file = await _renderQuoteToFile();
      if (file == null) { setState(() { _uploading = false; _error = 'Failed to render quote'; }); return; }
      final err = await DiscoveryApiService.createPost(
        authorId:  widget.userId,
        title:     _quoteCtrl.text.trim(),
        caption:   _authorCtrl.text.trim(),
        region:    (_detectedRegion != null ? (discoveryRegions.firstWhere((r) => r.code == _detectedRegion, orElse: () => discoveryRegions.first).name) : widget.region),
        category:  'Quote',
        mediaFile: file,
        mediaType: 'image',
        isWhisper: _isWhisper,
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      if (err == null) { Navigator.pop(context); widget.onPosted();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Quote published!'), backgroundColor: XameColors.accent));
      } else { setState(() => _error = err); }
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title is required'); return;
    }
    if (_mediaFile == null) {
      setState(() => _error = 'Please select media'); return;
    }
    setState(() { _uploading = true; _error = null; });
    // Upload local audio file via server if picked from device
    String finalMusicUrl = _musicUrl;
    if (_musicFile != null && _musicUrl.startsWith('/')) {
      try {
        final audioForm = FormData.fromMap({
          'audio': await MultipartFile.fromFile(_musicFile!.path),
        });
        final uploadRes = await Dio(BaseOptions(baseUrl: AppConstants.serverUrl))
            .post('/api/discover/upload-music', data: audioForm);
        finalMusicUrl = uploadRes.data['url'] as String? ?? _musicUrl;
      } catch (_) {}
    }

    final err = await DiscoveryApiService.createPost(
      authorId:  widget.userId,
      title:     _titleCtrl.text.trim(),
      caption:   _captionCtrl.text.trim(),
      region:    (_detectedRegion != null ? (discoveryRegions.firstWhere((r) => r.code == _detectedRegion, orElse: () => discoveryRegions.first).name) : widget.region),
      category:  _category,
      mediaFile: _mediaFile!,
      mediaType: _mediaType,
      isWhisper:    _isWhisper,
      isCollabOpen: _isCollabOpen,
      musicUrl:     finalMusicUrl,
      musicTitle:   _musicTitle,
      onProgress: (sent, total) {
        if (total > 0 && mounted) {
          setState(() => _uploadProgress = sent / total);
        }
      },
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err == null) {
      Navigator.pop(context);
      widget.onPosted();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Post published!'),
        backgroundColor: context.xSurface));
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20,
        MediaQuery.of(context).viewInsets.bottom + 20),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 4,
        decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2))),
      SizedBox(height: 16),
      Text(_quoteMode ? 'Create Quote' : 'Create Post', style: TextStyle(color: context.xText,
          fontSize: 18, fontWeight: FontWeight.w700)),
      SizedBox(height: 16),

      // Mode toggle
      Container(
        decoration: BoxDecoration(color: context.xBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _quoteMode = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !_quoteMode ? XameColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.photo_outlined, size: 16, color: !_quoteMode ? Colors.black : context.xMuted),
                SizedBox(width: 6),
                Text('Media', style: TextStyle(color: !_quoteMode ? Colors.black : context.xMuted, fontWeight: FontWeight.w600, fontSize: 13)),
              ])))),
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _quoteMode = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _quoteMode ? XameColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.format_quote_rounded, size: 16, color: _quoteMode ? Colors.black : context.xMuted),
                SizedBox(width: 6),
                Text('Quote', style: TextStyle(color: _quoteMode ? Colors.black : context.xMuted, fontWeight: FontWeight.w600, fontSize: 13)),
              ])))),
        ])),
      SizedBox(height: 16),

      if (_quoteMode) ...[
        // Live preview
        Center(child: Screenshot(controller: _screenshotCtrl, child: _buildQuotePreview())),
        SizedBox(height: 16),
        // Quote text input
        TextField(
          controller: _quoteCtrl, maxLines: 4,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.xText),
          decoration: InputDecoration(
            hintText: 'Write your quote or inspiration...',
            hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.5)),
            filled: true, fillColor: context.xBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: XameColors.accent, width: 1)))),
        SizedBox(height: 8),
        TextField(
          controller: _authorCtrl,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.xText),
          decoration: InputDecoration(
            hintText: 'Author / Source (optional)',
            hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.5)),
            filled: true, fillColor: context.xBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: XameColors.accent, width: 1)))),
        SizedBox(height: 12),
        // Style options
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          // Gradients
          ...List.generate(_gradients.length, (i) => GestureDetector(
            onTap: () => setState(() => _gradientIndex = i),
            child: Container(
              width: 32, height: 32, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _gradients[i]),
                shape: BoxShape.circle,
                border: Border.all(color: _gradientIndex == i ? XameColors.accent : Colors.transparent, width: 2))))),
          SizedBox(width: 8),
          // Text color
          ...List.generate(_textColors.length, (i) => GestureDetector(
            onTap: () => setState(() => _textColor = _textColors[i]),
            child: Container(
              width: 28, height: 28, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _textColors[i], shape: BoxShape.circle,
                border: Border.all(color: _textColor == _textColors[i] ? XameColors.accent : context.xMuted.withOpacity(0.3), width: 2))))),
          SizedBox(width: 8),
          // Alignment
          ...List.generate(_alignIcons.length, (i) => GestureDetector(
            onTap: () => setState(() => _alignIndex = i),
            child: Container(
              width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _alignIndex == i ? XameColors.accent.withOpacity(0.15) : context.xBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _alignIndex == i ? XameColors.accent : Colors.transparent)),
              child: Icon(_alignIcons[i], size: 18, color: _alignIndex == i ? XameColors.accent : context.xMuted)))),
          SizedBox(width: 8),
          // Font
          ...List.generate(_fonts.length, (i) => GestureDetector(
            onTap: () => setState(() => _fontIndex = i),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _fontIndex == i ? XameColors.accent.withOpacity(0.15) : context.xBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _fontIndex == i ? XameColors.accent : Colors.transparent)),
              child: Text(_fonts[i], style: TextStyle(fontSize: 11, color: _fontIndex == i ? XameColors.accent : context.xMuted, fontWeight: FontWeight.w600))))),
        ])),
        SizedBox(height: 16),
      ] else ...[

      // Media picker
      GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: context.xBg.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.xSurface)),
          child: _mediaFile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(fit: StackFit.expand, children: [
                  _mediaType == 'video'
                    ? Container(
                        color: context.xText,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_rounded,
                                color: XameColors.primary, size: 48),
                            SizedBox(height: 8),
                            Text(
                              _mediaFile!.path.split('/').last,
                              style: TextStyle(
                                  color: context.xText.withValues(alpha: 0.6), fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            FutureBuilder<int>(
                              future: _mediaFile!.length(),
                              builder: (_, snap) => Text(
                                snap.hasData
                                    ? '${(snap.data! / 1024 / 1024).toStringAsFixed(1)}MB'
                                    : '',
                                style: TextStyle(
                                    color: context.xMuted, fontSize: 11)),
                            ),
                          ],
                        ),
                      )
                    : Image.file(_mediaFile!, fit: BoxFit.cover,
                        width: double.infinity),
                  if (_mediaType == 'video')
                    Center(child: Icon(Icons.play_circle_outline,
                        color: context.xText.withValues(alpha: 0.54), size: 40)),
                ]))
            : Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(Icons.add_photo_alternate_outlined,
                    color: context.xMuted, size: 40),
                SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  GestureDetector(onTap: _pickMedia,
                    child: Text('Photo',
                      style: TextStyle(color: XameColors.primary,
                          fontWeight: FontWeight.w600))),
                  Text('  or  ',
                      style: TextStyle(color: context.xSurface)),
                  GestureDetector(onTap: _pickVideo,
                    child: Text('Video',
                      style: TextStyle(color: XameColors.primary,
                          fontWeight: FontWeight.w600))),
                ]),
              ]),
        ),
      ),
      ], // end else (media mode)
      SizedBox(height: 12),

      // Title & Caption (shared for both modes — hidden in quote mode)
      if (!_quoteMode) ...[
      TextField(
        controller: _titleCtrl,
        style: TextStyle(color: context.xText),
        decoration: InputDecoration(
          hintText:  'Title',
          hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
          filled: true, fillColor: context.xBg,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: XameColors.primary, width: 1))),
      ),
      SizedBox(height: 8),

      // Caption
      TextField(
        controller: _captionCtrl,
        style: TextStyle(color: context.xText),
        maxLines: 2,
        decoration: InputDecoration(
          hintText:  'Caption (optional)',
          hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3)),
          filled: true, fillColor: context.xBg,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: XameColors.primary, width: 1))),
      ),
      ], // end if (!_quoteMode)
      SizedBox(height: 8),

      // Region indicator — always visible
      GestureDetector(
        onTap: _locating ? null : () => _pickRegion(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _detectedRegion != null
                ? const Color(0xFF1B3A2A)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _detectedRegion != null
                  ? const Color(0xFF00E5A0).withOpacity(0.4)
                  : Colors.white12),
          ),
          child: Row(children: [
            _locating
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Colors.white54))
                : const Text('📍', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _locating
                  ? 'Detecting your location...'
                  : 'Posting to ${_detectedRegion != null ? (discoveryRegions.firstWhere((r) => r.code == _detectedRegion, orElse: () => discoveryRegions.first).name) : widget.region} ${discoveryRegions.firstWhere((r) => r.code == (_detectedRegion ?? 'global') || r.name == widget.region, orElse: () => discoveryRegions.first).flag}',
              style: TextStyle(
                color: _detectedRegion != null
                    ? const Color(0xFF00E5A0)
                    : const Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.w500),
            )),
            const Icon(Icons.arrow_drop_down_rounded,
                color: Colors.white38, size: 18),
            if (_detectedRegion != null)
              GestureDetector(
                onTap: () => setState(() => _detectedRegion = null),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 16),
              ),
          ]),
        ),
      ),

      // Music picker
      GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF12121E),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.audio_file_rounded, color: Color(0xFF00E5A0)),
                title: const Text('Pick from Device', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Choose any audio file', style: TextStyle(color: Colors.white38, fontSize: 11)),
                onTap: () { Navigator.pop(context); _pickMusic(context); },
              ),
              ListTile(
                leading: const Icon(Icons.library_music_rounded, color: Color(0xFF00E5FF)),
                title: const Text('XamePage Sounds', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Curated royalty-free tracks', style: TextStyle(color: Colors.white38, fontSize: 11)),
                onTap: () { Navigator.pop(context); _pickMusicFromLibrary(context); },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _musicUrl.isNotEmpty
                ? const Color(0xFF1B3A2A).withOpacity(0.8)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _musicUrl.isNotEmpty
                  ? const Color(0xFF00E5A0).withOpacity(0.4)
                  : Colors.white12)),
          child: Row(children: [
            Text(_musicUrl.isNotEmpty ? '🎵' : '🎵',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _musicUrl.isNotEmpty ? _musicTitle : 'Add Background Music',
              style: TextStyle(
                color: _musicUrl.isNotEmpty
                    ? const Color(0xFF00E5A0)
                    : Colors.white54,
                fontSize: 13, fontWeight: FontWeight.w500),
            )),
            if (_musicUrl.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() { _musicUrl = ''; _musicTitle = ''; }),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 16)),
            if (_musicUrl.isEmpty)
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white24, size: 18),
          ]),
        ),
      ),

      // Whisper toggle
      GestureDetector(
        onTap: () => setState(() => _isWhisper = !_isWhisper),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isWhisper
                ? const Color(0xFF6A1B9A).withOpacity(0.15)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isWhisper
                  ? const Color(0xFFCE93D8).withOpacity(0.5)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(children: [
            Text(_isWhisper ? '🤫' : '👁️',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isWhisper ? 'Whisper Post' : 'Public Post',
                    style: TextStyle(
                      color: _isWhisper
                          ? const Color(0xFFCE93D8)
                          : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
                Text(_isWhisper
                    ? 'Only mutual contacts can see this'
                    : 'Visible to everyone on Discovery',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            )),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36, height: 20,
              decoration: BoxDecoration(
                color: _isWhisper
                    ? const Color(0xFF9C27B0)
                    : Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _isWhisper
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ]),
        ),
      ),

      // Collab toggle
      GestureDetector(
        onTap: () => setState(() => _isCollabOpen = !_isCollabOpen),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isCollabOpen
                ? const Color(0xFF00E5FF).withOpacity(0.08)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isCollabOpen
                  ? const Color(0xFF00E5FF).withOpacity(0.4)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(children: [
            Text(_isCollabOpen ? '🤝' : '🔒',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isCollabOpen ? 'Open for Collab' : 'Solo Post',
                    style: TextStyle(
                      color: _isCollabOpen
                          ? const Color(0xFF00E5FF)
                          : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
                Text(_isCollabOpen
                    ? 'Others can add their media to this post'
                    : 'Only you can post this content',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            )),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36, height: 20,
              decoration: BoxDecoration(
                color: _isCollabOpen
                    ? const Color(0xFF00E5FF)
                    : Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _isCollabOpen
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ]),
        ),
      ),

      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: TextStyle(
              color: XameColors.danger, fontSize: 13))),

      if (_uploading && _mediaType == 'video') ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _uploadProgress > 0 ? _uploadProgress : null,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(XameColors.primary),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _uploadProgress > 0
              ? 'Uploading... ${(_uploadProgress * 100).toInt()}%'
              : 'Preparing upload...',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _uploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: XameColors.primary,
            foregroundColor: context.xBg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: _uploading
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: context.xText, strokeWidth: 2))
            : const Text('Publish',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ])),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Story posted! Expires in 24hrs'),
        backgroundColor: context.xSurface));
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
        decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2))),
      SizedBox(height: 16),
      Text('Add to Your Story',
        style: TextStyle(color: context.xText, fontSize: 18,
            fontWeight: FontWeight.w700)),
      SizedBox(height: 8),
      Text('Stories disappear after 24 hours',
        style: TextStyle(color: context.xMuted, fontSize: 13)),
      SizedBox(height: 16),
      GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: context.xBg.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.xSurface)),
          child: _mediaFile != null
            ? ClipRRect(borderRadius: BorderRadius.circular(16),
                child: Image.file(_mediaFile!, fit: BoxFit.cover,
                    width: double.infinity))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(Icons.camera_alt_outlined,
                    color: context.xMuted, size: 48),
                SizedBox(height: 8),
                Text('Tap to select photo',
                  style: TextStyle(color: context.xSurface)),
              ]),
        ),
      ),
      SizedBox(height: 12),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: TextStyle(
              color: XameColors.danger, fontSize: 13))),
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _uploading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: XameColors.secondary,
            foregroundColor: context.xBg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: _uploading
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: context.xText, strokeWidth: 2))
            : Text('Share Story',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

// ── Live count badge ──────────────────────────────────────────────────────────
class _LiveCountBadge extends StatelessWidget {
  final int count;
  _LiveCountBadge({this.count = 0});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.xDanger.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: context.xDanger.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: context.xDanger)),
        SizedBox(width: 4),
        Text('$count LIVE', style: TextStyle(
            color: context.xDanger, fontSize: 9,
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
  final Function(DiscoveryItem)? onItemTap;
  _SearchOverlay({required this.ctrl, required this.onSearch,
      required this.onClose, required this.feed, this.onItemTap});
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
    color: context.xBg.withValues(alpha: 0.94),
    child: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: widget.ctrl,
              autofocus:  true,
              onChanged:  _search,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:  'Search people, topics, moments...',
                hintStyle: TextStyle(color: context.xMuted.withValues(alpha: 0.3), fontSize: 14),
                prefixIcon: Icon(Icons.search,
                    color: context.xMuted, size: 20),
                filled: true, fillColor: context.xSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: XameColors.primary, width: 1)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(onTap: widget.onClose,
            child: Text('Cancel', style: TextStyle(
                color: XameColors.primary, fontSize: 14,
                fontWeight: FontWeight.w600))),
        ]),
      ),
      Expanded(
        child: _results.isEmpty && widget.ctrl.text.isEmpty
          ? _SearchSuggestions(ctrl: widget.ctrl, onSearch: widget.onSearch)
          : _results.isEmpty
            ? Center(child: Text('No results found',
                style: TextStyle(color: context.xSurface)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      widget.onClose();
                      widget.onItemTap?.call(item);
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: item.mediaUrl,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 52, height: 52,
                          color: context.xSurface))),
                    title: Text(item.title, style: TextStyle(
                        color: context.xText, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                    subtitle: Text(item.category, style: TextStyle(
                        color: context.xMuted, fontSize: 12)),
                    trailing: item.isLive
                      ? LivePulseIndicator(compact: true) : null,
                  );
                }),
      ),
    ])),
  );
}

class _SearchSuggestions extends StatelessWidget {
  final TextEditingController ctrl;
  final Function(String) onSearch;
  _SearchSuggestions({required this.ctrl, required this.onSearch});
  final _trending = const [
    '🔥 Afrobeats','⚡ Tech Africa','🌍 Global Culture',
    '🎬 Nollywood','🏆 Sport','🎨 Street Art',
    '💡 Startups','🌊 Ocean Life',
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TRENDING SEARCHES', style: TextStyle(
          color: context.xMuted, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      SizedBox(height: 14),
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
              color: context.xBg.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.xSurface)),
            child: Text(t, style: TextStyle(
                color: context.xText.withValues(alpha: 0.6), fontSize: 13)),
          ),
        )).toList()),
    ]),
  );
}

// ── Filter sheet ──────────────────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final String currentRegion;
  final Function(DiscoveryRegion) onApply;
  _FilterSheet({required this.currentRegion, required this.onApply});
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
          decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2))),
        SizedBox(height: 20),
        Text('Filter by Region', style: TextStyle(
            color: context.xText, fontSize: 18,
            fontWeight: FontWeight.w700)),
        SizedBox(height: 16),
        SizedBox(height: 320,
          child: GridView.builder(
            gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 2.2,
                crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: discoveryRegions.length,
            itemBuilder: (_, i) {
              final r          = discoveryRegions[i];
              final isSelected = r.code == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = r.code),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                      ? XameColors.primary.withOpacity(0.15)
                      : context.xBg.withOpacity(0.04),
                    border: Border.all(
                      color: isSelected
                        ? XameColors.primary.withOpacity(0.5)
                        : context.xSurface)),
                  child: Center(child: Text('${r.flag} ${r.name}',
                    style: TextStyle(
                      color: isSelected
                        ? XameColors.primary : context.xText.withValues(alpha: 0.54),
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
        SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () {
              final r = discoveryRegions.firstWhere(
                  (r) => r.code == _selected);
              widget.onApply(r);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: XameColors.primary,
              foregroundColor: context.xBg,
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

// ── XamePage News Channel Widget ─────────────────────────────────────────────
class _XameNewsChannel extends StatefulWidget {
  final List<_OfficialPost> posts;
  final BuildContext context;
  const _XameNewsChannel({required this.posts, required this.context});
  @override
  State<_XameNewsChannel> createState() => _XameNewsChannelState();
}

class _XameNewsChannelState extends State<_XameNewsChannel>
    with SingleTickerProviderStateMixin {
  int _active = 0;
  late PageController _pageCtrl;
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.92);
    _shimmer = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Channel header
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
        child: Row(children: [
          // Animated verified badge
          AnimatedBuilder(
            animation: _shimmer,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    XameColors.accent.withOpacity(0.15 + _shimmer.value * 0.1),
                    XameColors.accent.withOpacity(0.05),
                    XameColors.accent.withOpacity(0.15 + _shimmer.value * 0.1),
                  ],
                  stops: [0.0, _shimmer.value, 1.0],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: XameColors.accent.withOpacity(0.6), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_rounded, color: XameColors.accent, size: 13),
                const SizedBox(width: 5),
                Text('XAMEPAGE NEWS',
                  style: TextStyle(color: XameColors.accent,
                    fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ]),
            )),
          const Spacer(),
          // Post count indicator
          if (widget.posts.length > 1)
            Text('${widget.posts.length} updates',
              style: TextStyle(color: context.xMuted, fontSize: 11)),
        ]),
      ),

      // ── Card carousel
      SizedBox(
        height: 260,
        child: PageView.builder(
          controller: _pageCtrl,
          scrollDirection: Axis.horizontal,
          itemCount: widget.posts.length,
          onPageChanged: (i) => setState(() => _active = i),
          itemBuilder: (_, i) {
            final p = widget.posts[i];
            final isActive = i == _active;
            return AnimatedScale(
              scale: isActive ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: () {
                  if (p.mediaType == 'video' && p.mediaUrl.isNotEmpty) {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.black,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: _DetailVideoPlayer(url: p.mediaUrl),
                      ),
                    );
                  } else if (p.mediaUrl.isNotEmpty && p.mediaType == 'image') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        body: Stack(children: [
                          Center(child: InteractiveViewer(
                            child: CachedNetworkImage(
                              imageUrl: p.mediaUrl, fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image, color: Colors.white54, size: 64)))),
                          Positioned(
                            top: 48, left: 12,
                            child: IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(shape: BoxShape.circle,
                                  color: Colors.black.withOpacity(0.6)),
                                child: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 20)),
                              onPressed: () => Navigator.pop(context))),
                          if (p.actionUrl.isNotEmpty)
                            Positioned(left: 0, right: 0, bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black.withOpacity(0.85), Colors.transparent])),
                                padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
                                child: GestureDetector(
                                  onTap: () => launchUrl(Uri.parse(p.actionUrl),
                                    mode: LaunchMode.externalApplication),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(color: XameColors.accent,
                                      borderRadius: BorderRadius.circular(12)),
                                    child: Text(
                                      p.actionLabel.isNotEmpty ? p.actionLabel : 'Learn More',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.black,
                                        fontSize: 13, fontWeight: FontWeight.w800)))))),
                        ]),
                      )));
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: isActive ? [
                      BoxShadow(color: XameColors.accent.withOpacity(0.25),
                        blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 8)),
                    ] : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(fit: StackFit.expand, children: [
                      // Media
                      p.mediaUrl.isNotEmpty
                        ? Builder(builder: (context) {
                            // YouTube thumbnail
                            final ytMatch = RegExp(r'(?:youtube\.com/(?:watch\?v=|embed/|shorts/)|youtu\.be/)([\w-]{11})').firstMatch(p.mediaUrl);
                            final thumbUrl = ytMatch != null
                              ? 'https://img.youtube.com/vi/\${ytMatch.group(1)}/hqdefault.jpg'
                              : (p.mediaType == 'video' ? '' : p.mediaUrl);
                            return Stack(fit: StackFit.expand, children: [
                              thumbUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: thumbUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: context.xSurface,
                                      child: Center(child: CircularProgressIndicator(color: XameColors.accent, strokeWidth: 2))),
                                    errorWidget: (_, __, ___) => Container(color: context.xSurface,
                                      child: Icon(Icons.campaign_outlined, color: XameColors.accent, size: 48)))
                                : Container(color: context.xSurface,
                                    child: Icon(Icons.play_circle_outline_rounded, color: XameColors.accent, size: 56)),
                              if (p.mediaType == 'video' || ytMatch != null)
                                Center(child: Container(
                                  width: 48, height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28))),
                            ]);
                          })
                        : Container(
                            color: context.xSurface,
                            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.campaign_outlined,
                                  color: XameColors.accent, size: 48),
                                  const SizedBox(height: 8),
                                  Text('XamePage News',
                                    style: TextStyle(color: context.xMuted, fontSize: 13)),
                                ])),

                      // Cinematic gradient overlay
                      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.3),
                            Colors.black.withOpacity(0.92),
                          ],
                          stops: const [0.2, 0.5, 1.0])))),

                      // Top row: Official badge + version tag
                      Positioned(top: 14, left: 14, right: 14,
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: XameColors.accent.withOpacity(0.7))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.verified_rounded, color: XameColors.accent, size: 11),
                              const SizedBox(width: 4),
                              Text('XamePage Official',
                                style: TextStyle(color: Colors.white,
                                  fontSize: 10, fontWeight: FontWeight.w700)),
                            ])),
                          const Spacer(),
                          if (p.version.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: XameColors.accent.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(6)),
                              child: Text('v\${p.version}',
                                style: const TextStyle(color: Colors.black,
                                  fontSize: 10, fontWeight: FontWeight.w800))),
                        ])),

                      // Bottom content
                      Positioned(left: 16, right: 16, bottom: 16,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min, children: [
                          Text(p.title, maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white,
                              fontSize: 18, fontWeight: FontWeight.w800,
                              height: 1.2, letterSpacing: 0.1)),
                          if (p.caption.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(p.caption, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.72),
                                fontSize: 12, height: 1.4)),
                          ],
                          if (p.actionUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => launchUrl(Uri.parse(p.actionUrl),
                                  mode: LaunchMode.externalApplication),
                                child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: XameColors.accent,
                                  borderRadius: BorderRadius.circular(12)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(
                                    p.actionLabel.toLowerCase().contains('watch')
                                      ? Icons.play_circle_outline_rounded
                                      : p.actionLabel.toLowerCase().contains('download')
                                        ? Icons.download_rounded
                                        : Icons.open_in_new_rounded,
                                    color: Colors.black, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    p.actionLabel.isNotEmpty ? p.actionLabel : 'Learn More',
                                    style: const TextStyle(color: Colors.black,
                                      fontSize: 12, fontWeight: FontWeight.w800)),
                                ]))),
                              const SizedBox(width: 10),
                              Icon(Icons.touch_app_rounded,
                                color: Colors.white.withOpacity(0.4), size: 14),
                              Text(' Tap to open',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4), fontSize: 11)),
                            ]),
                          ],
                        ])),
                    ])),
                )),
            );
          }),
      ),

      // ── Page indicator dots
      if (widget.posts.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children:
            List.generate(widget.posts.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _active == i ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _active == i ? XameColors.accent : XameColors.accent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3)),
            ))),
        ),
      const SizedBox(height: 8),
    ]);
  }
}

class _OfficialPost {
  final String postId, title, caption, mediaUrl, mediaType, actionUrl, actionLabel, version, platform, ipaUrl;
  _OfficialPost({required this.postId, required this.title,
    required this.caption, required this.mediaUrl, required this.mediaType,
    required this.actionUrl, required this.actionLabel, required this.version,
    required this.platform, required this.ipaUrl});
  factory _OfficialPost.fromJson(Map<String, dynamic> j) {
    final platform  = j['platform'] as String? ?? 'both';
    final ipaUrl    = j['ipaUrl']   as String? ?? '';
    final apkUrl    = j['actionUrl'] as String? ?? j['downloadUrl'] as String? ?? '';
    final effectiveUrl = Platform.isIOS && ipaUrl.isNotEmpty ? ipaUrl : apkUrl;
    return _OfficialPost(
      postId:      j['announcementId'] as String? ?? j['postId']     as String? ?? '',
      title:       j['title']         as String? ?? '',
      caption:     j['caption']       as String? ?? '',
      mediaUrl:    j['mediaUrl']      as String? ?? '',
      mediaType:   j['mediaType']     as String? ?? 'image',
      actionUrl:   effectiveUrl,
      actionLabel: j['actionLabel']   as String? ?? '',
      version:     j['version']       as String? ?? '',
      platform:    platform,
      ipaUrl:      ipaUrl,
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
  bool   _showControls = false;
  bool   _playing      = true;
  bool   _isFullscreen = false;
  bool   _muted        = false;
  Duration _position   = Duration.zero;
  Duration _duration   = Duration.zero;
  Timer?   _hideTimer;
  bool   _dragging     = false;
  double _dragProgress = 0.0;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    // BetterPlayer as pure engine — no built-in controls UI
    _ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay:     true,
        looping:      true,
        fit:          BoxFit.contain,
        aspectRatio:  9/16,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enablePlayPause:      false,
          enableMute:           false,
          enableFullscreen:     false,
          enableProgressBar:    false,
          enableSkips:          false,
          enableAudioTracks:    false,
          enableOverflowMenu:   false,
          enableProgressText:   false,
        ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2000,
          maxBufferMs: 15000,
          bufferForPlaybackMs: 500,
          bufferForPlaybackAfterRebufferMs: 1000,
        ),
      ),
    );
    _ctrl!.addEventsListener(_onEvent);
  }

  void _onEvent(BetterPlayerEvent e) {
    if (!mounted) return;
    final pos = _ctrl?.videoPlayerController?.value.position;
    final dur = _ctrl?.videoPlayerController?.value.duration;
    setState(() {
      if (pos != null) _position = pos;
      if (dur != null && dur > Duration.zero) _duration = dur;
      _playing = _ctrl?.isPlaying() ?? false;
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _togglePlay() {
    if (_playing) {
      _ctrl?.pause();
    } else {
      _ctrl?.play();
    }
    setState(() => _playing = !_playing);
    _resetHideTimer();
  }

  void _toggleMute() {
    _muted ? _ctrl?.setVolume(1.0) : _ctrl?.setVolume(0.0);
    setState(() => _muted = !_muted);
    _resetHideTimer();
  }

  void _seekTo(double ratio) {
    if (_duration.inMilliseconds == 0) return;
    final ms = (ratio * _duration.inMilliseconds).toInt();
    _ctrl?.seekTo(Duration(milliseconds: ms));
    _resetHideTimer();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl?.removeEventsListener(_onEvent);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final progress = _dragging
        ? _dragProgress
        : (_duration.inMilliseconds > 0
            ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0);

    return SizedBox(
      width: sw, height: sh,
      child: Stack(children: [

        // ── Video surface — IgnorePointer so BetterPlayer never consumes events ──
        if (_ctrl != null)
          IgnorePointer(
            child: SizedBox(width: sw, height: sh,
              child: BetterPlayer(controller: _ctrl!)),
          ),

        // ── Controls overlay — independent of video tap ───────────
        if (_showControls) ...[
          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent])),
              ),
            ),
          ),

          // Bottom gradient + controls bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Progress bar — raw Listener bypasses BetterPlayer gesture arena
                LayoutBuilder(builder: (ctx, constraints) {
                  final barWidth = constraints.maxWidth;
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      _hideTimer?.cancel();
                      final ratio = (e.localPosition.dx / barWidth).clamp(0.0, 1.0);
                      setState(() { _dragging = true; _dragProgress = ratio; });
                    },
                    onPointerMove: (e) {
                      final ratio = (e.localPosition.dx / barWidth).clamp(0.0, 1.0);
                      setState(() => _dragProgress = ratio);
                    },
                    onPointerUp: (e) {
                      final ratio = (e.localPosition.dx / barWidth).clamp(0.0, 1.0);
                      _seekTo(ratio);
                      setState(() => _dragging = false);
                      _resetHideTimer();
                    },
                    onPointerCancel: (_) {
                      setState(() => _dragging = false);
                      _resetHideTimer();
                    },
                    child: SizedBox(
                      height: 52,
                      child: Stack(alignment: Alignment.center, children: [
                        Container(height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3))),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(height: 4,
                              decoration: BoxDecoration(
                                color: XameColors.primary,
                                borderRadius: BorderRadius.circular(3))))),
                        Align(
                          alignment: Alignment(
                              (progress.clamp(0.0, 1.0) * 2) - 1, 0),
                          child: Container(width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                color: Colors.black38,
                                blurRadius: 4)]))),
                      ]),
                    ),
                  );
                }),
                // Controls row
                Row(children: [
                  // Play/Pause
                  GestureDetector(
                    onTap: _togglePlay,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(_playing),
                        color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${_fmt(_position)} / ${_fmt(_duration)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  // Mute
                  GestureDetector(
                    onTap: _toggleMute,
                    child: Icon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  // Fullscreen
                  GestureDetector(
                    onTap: () {
                      setState(() => _isFullscreen = !_isFullscreen);
                      if (_isFullscreen) {
                        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                      } else {
                        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      }
                    },
                    child: Icon(
                      _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      color: Colors.white, size: 26),
                  ),
                ]),
              ]),
            ),
            ), // end Material
          ),
        ],

        // Tap layer — only active when controls hidden
        // When controls visible, disabled so Listener gets drag events
        if (!_showControls)
          Positioned.fill(
            child: GestureDetector(
              onTap: _onTap,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        // When controls visible, tap anywhere outside controls hides them
        if (_showControls)
          Positioned(
            top: 0, left: 0, right: 0,
            bottom: 150, // above the controls bar
            child: GestureDetector(
              onTap: _onTap,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),

        // Centre play indicator when paused
        if (!_playing)
          GestureDetector(
            onTap: _togglePlay,
            child: Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.6),
                  border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
      ]),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _checkFollowing();
  }

  Future<void> _checkFollowing() async {
    final self = ref.read(currentUserProvider);
    if (self == null) return;
    try {
      final contacts = ref.read(contactsProvider).valueOrNull ?? [];
      final already = contacts.any((c) => c.id == widget.item.authorId);
      if (mounted) setState(() => _following = already);
    } catch (_) {}
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
                    Icons.broken_image, color: Colors.white54, size: 64)),
            ),
          ),
        ),
      ),
    ));
  }

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
            content: Text('Unfollowed ${widget.item.authorName}'),
            backgroundColor: context.xSurface,
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
            content: Text('Now following ${widget.item.authorName}'),
            backgroundColor: context.xSurface,
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
    final topPad = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isVideo = item.mediaType == DiscoveryMediaType.video;

    final self = ref.read(currentUserProvider);
    final isOwner = self?.xameId == item.authorId;
    final isOwnerCheck = self?.xameId == item.authorId;

    final infoPanel = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.92), Colors.transparent]),
      ),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.xPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.xPrimary.withOpacity(0.5))),
            child: Text(item.category.toUpperCase(),
              style: TextStyle(color: context.xPrimary,
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
          const Spacer(),
          Text('${_fmt(item.viewCount)} views',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Text(item.title, style: const TextStyle(color: Colors.white,
            fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.subtitle, style: TextStyle(
              color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          CircleAvatar(radius: 18,
            backgroundImage: item.authorAvatar.isNotEmpty
                ? NetworkImage(item.authorAvatar) : null,
            backgroundColor: Colors.white24,
            child: item.authorAvatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white) : null),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.authorName, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            Text(item.region, style: TextStyle(
                color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ]),
          const Spacer(),
          // Follow button
          if (!isOwnerCheck)
            GestureDetector(
              onTap: _toggleFollow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: _following ? null : const LinearGradient(
                      colors: [Color(0xFF2196F3), Color(0xFF7B2FFF)]),
                  color: _following ? Colors.white12 : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _followLoading
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white))
                    : Text(_following ? 'Following' : '+ Follow',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ]),
    );

    final backBtn = Positioned(
      top: topPad + 4, left: 4,
      child: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.black.withOpacity(0.55)),
          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16)),
        onPressed: () => Navigator.pop(context)),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Media — full width, natural height, centered ────────────
        Positioned.fill(
          child: Center(
            child: isVideo
                ? SizedBox(
                    width: screenW,
                    height: screenH,
                    child: _DetailVideoPlayer(url: item.mediaUrl))
                : InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: GestureDetector(
                      onTap: () => _showFullscreenImage(context, item.mediaUrl),
                      child: CachedNetworkImage(
                        imageUrl: item.mediaUrl,
                        fit: BoxFit.contain,
                        width: screenW,
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54, size: 64))))),
        ),
        // ── Info overlay at bottom ───────────────────────────────────
        Positioned(left: 0, right: 0, bottom: 0, child: infoPanel),
        backBtn,
        if (item.isLive)
          Positioned(top: topPad + 12, right: 20, child: LivePulseIndicator()),
        // Delete button — owner only
        if (isOwner)
          Positioned(
            top: topPad + 8, right: 8,
            child: GestureDetector(
              onTap: () => _confirmDelete(context, item, self!.xameId),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.55)),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 22)),
            ),
          ),
      ]),
    );
  }

  void _confirmDelete(BuildContext ctx, DiscoveryItem item, String userId) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: ctx.xSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Post',
            style: TextStyle(color: ctx.xText, fontWeight: FontWeight.w700)),
        content: Text('Remove this post permanently?',
            style: TextStyle(color: ctx.xMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ctx.xMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await DiscoveryApiService.deletePost(item.id, userId);
              if (ok && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Post deleted'),
                  backgroundColor: ctx.xSurface));
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent,
                    fontWeight: FontWeight.w700))),
        ],
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



// ══════════════════════════════════════════════════════════════════════════════
// REWARDS TICKER
// ══════════════════════════════════════════════════════════════════════════════

class _RewardsTicker extends StatefulWidget {
  final List<Map<String,dynamic>> leaderboard;
  const _RewardsTicker({required this.leaderboard});
  @override State<_RewardsTicker> createState() => _RewardsTickerState();
}

class _RewardsTickerState extends State<_RewardsTicker>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollCtrl;
  late AnimationController _animCtrl;

  String _tierBadge(String tier) {
    switch (tier) {
      case 'diamond': return '💎';
      case 'gold':    return '🥇';
      case 'silver':  return '🥈';
      default:        return '🥉';
    }
  }

  static const double _pixelsPerSecond = 40.0; // lower = slower
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _animCtrl   = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_scroll)
      ..repeat();
  }

  void _scroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final now = DateTime.now();
    final elapsed = _lastTick == null ? 0.0
        : now.difference(_lastTick!).inMicroseconds / 1000000.0;
    _lastTick = now;
    final next = _scrollCtrl.offset + (_pixelsPerSecond * elapsed);
    _scrollCtrl.jumpTo(next >= max ? 0 : next);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.leaderboard;
    return Container(
      height: 36,
      color: const Color(0xFF0A1A28),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: const Color(0xFF00B0A0),
          child: const Text('🏆 TOP', style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: ListView.builder(
            controller:    _scrollCtrl,
            scrollDirection: Axis.horizontal,
            physics:       const NeverScrollableScrollPhysics(),
            itemCount:     items.length * 10, // repeat for infinite feel
            itemBuilder:   (_, i) {
              final item = items[i % items.length];
              final name  = item['name']        as String? ?? '';
              final coins = item['weeklyCoins'] as int?    ?? 0;
              final tier  = item['tier']        as String? ?? 'bronze';
              final rank  = (i % items.length) + 1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  '#$rank ${_tierBadge(tier)} $name · $coins coins  ·',
                  style: const TextStyle(color: Color(0xFF8AAFC8), fontSize: 12),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Mood Filter Bar ───────────────────────────────────────────────────────────
class _MoodFilterBar extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _MoodFilterBar({required this.selected, required this.onSelect});

  static const _moods = [
    ('🔥', 'Hot'),
    ('😂', 'Funny'),
    ('🎵', 'Music'),
    ('💼', 'Business'),
    ('🏆', 'Sport'),
    ('🎨', 'Art'),
    ('💡', 'Tech'),
    ('🙏', 'Faith'),
    ('❤️', 'Love'),
    ('🌍', 'Culture'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final mood     = _moods[i];
          final isActive = selected == mood.$2;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(mood.$2);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF00E5FF).withOpacity(0.15)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF00E5FF)
                      : Colors.white12,
                  width: isActive ? 1.2 : 0.8,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(mood.$1, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(mood.$2,
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF00E5FF)
                          : Colors.white60,
                      fontSize:   12,
                      fontWeight: isActive
                          ? FontWeight.w700
                          : FontWeight.normal,
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Trending Pulse Strip ──────────────────────────────────────────────────────
class _TrendingPulseStrip extends StatefulWidget {
  final List<DiscoveryItem> posts;
  final void Function(DiscoveryItem) onTap;
  const _TrendingPulseStrip({required this.posts, required this.onTap});

  @override
  State<_TrendingPulseStrip> createState() => _TrendingPulseStripState();
}

class _TrendingPulseStripState extends State<_TrendingPulseStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          AnimatedBuilder(
            animation: _ripple,
            builder: (_, __) => Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF1744),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFFF1744)
                      .withOpacity(0.6 * (1 - _ripple.value)),
                  blurRadius: 8 + 8 * _ripple.value,
                  spreadRadius: 2 * _ripple.value,
                )],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('TRENDING NOW',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
        ]),
      ),
      SizedBox(
        height: 90,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: widget.posts.length,
          itemBuilder: (_, i) {
            final post = widget.posts[i];
            return GestureDetector(
              onTap: () => widget.onTap(post),
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                    animation: _ripple,
                    builder: (_, child) {
                      final glow = post.isLive
                          ? const Color(0xFFFF1744)
                          : const Color(0xFF00E5FF);
                      return Container(
                        width: 58, height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: glow.withOpacity(
                                post.isLive
                                    ? 0.5 * (0.5 + 0.5 * _ripple.value)
                                    : 0.3),
                            blurRadius: post.isLive
                                ? 10 + 8 * _ripple.value
                                : 8,
                            spreadRadius: post.isLive
                                ? 2 * _ripple.value
                                : 0,
                          )],
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 58, height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: post.isLive
                              ? const Color(0xFFFF1744)
                              : const Color(0xFF00E5FF),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: post.authorAvatar,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(Icons.person,
                                color: Colors.white38, size: 24)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 58,
                    child: Text(
                      post.authorName,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (post.isLive)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ── Sticky Region Bar Delegate ────────────────────────────────────────────────
class _StickyRegionBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _StickyRegionBarDelegate({required this.child});

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.xBg,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyRegionBarDelegate old) => old.child != child;
}

// ── Fullscreen Feed Page ─────────────────────────────────────────────────────
class _FullscreenFeedPage extends StatelessWidget {
  final DiscoveryItem item;
  final bool isActive;
  final String currentUserId;
  final String currentUserAvatar;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onPost;

  const _FullscreenFeedPage({
    required this.item,
    required this.isActive,
    required this.currentUserId,
    this.currentUserAvatar = '',
    this.onAvatarTap,
    this.onPost,
  });

  @override
  Widget build(BuildContext context) {
    final post = {
      'id':           item.id,
      'authorId':     item.authorId,
      'authorName':   item.authorName,
      'authorAvatar': item.authorAvatar,
      'mediaUrl':     item.mediaUrl,
      'mediaType':    item.mediaType == DiscoveryMediaType.video ? 'video' : 'image',
      'thumbnailUrl': item.thumbnailUrl ?? '',
      'title':        item.title,
      'category':     item.category,
      'likeCount':    item.likeCount,
      'commentCount': item.commentCount,
      'viewCount':    item.viewCount,
      'ts':           item.ts?.toIso8601String(),
      'musicUrl':     item.musicUrl,
      'musicTitle':   item.musicTitle,
      'mediaUrls':    item.mediaUrls.isNotEmpty ? item.mediaUrls.map((u) => {'url': u}).toList() : null,
    };
    return DiscoveryFullscreenViewer(
      posts: [post],
      initialIndex: 0,
      currentUserId: currentUserId,
      currentUserAvatar: currentUserAvatar,
      embedded: true,
      isActive: isActive,
    );
  }
}
