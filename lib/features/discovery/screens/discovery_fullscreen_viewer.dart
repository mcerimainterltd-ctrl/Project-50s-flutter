import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:better_player_enhanced/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'author_gallery_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/comments_sheet.dart';

// Inherited widget to lock/unlock vertical swipe when image carousel is active
class DiscoveryVerticalLock extends InheritedWidget {
  final void Function() lock;
  final void Function() unlock;

  const DiscoveryVerticalLock({
    Key? key,
    required this.lock,
    required this.unlock,
    required Widget child,
  }) : super(key: key, child: child);

  static DiscoveryVerticalLock? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscoveryVerticalLock>();

  @override
  bool updateShouldNotify(DiscoveryVerticalLock old) => lock != old.lock || unlock != old.unlock;
}

class DiscoveryFullscreenViewer extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  final bool embedded;
  final bool isActive;
  const DiscoveryFullscreenViewer({
    Key? key,
    required this.posts,
    required this.initialIndex,
    required this.currentUserId,
    this.currentUserName = '',
    this.currentUserAvatar = '',
    this.embedded = false,
    this.isActive = true,
  }) : super(key: key);

  @override
  State<DiscoveryFullscreenViewer> createState() =>
      _DiscoveryFullscreenViewerState();
}

class _DiscoveryFullscreenViewerState
    extends State<DiscoveryFullscreenViewer> {
  late PageController _verticalCtrl;
  int _currentIndex = 0;
  int _activePointers = 0;
  bool _locked = false;

  void _onPointerDown(PointerDownEvent e) => setState(() => _activePointers++);
  void _onPointerUp(PointerUpEvent e)   => setState(() => _activePointers = (_activePointers - 1).clamp(0, 10));
  void _onPointerCancel(PointerCancelEvent e) => setState(() => _activePointers = (_activePointers - 1).clamp(0, 10));

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.posts.isEmpty ? 0 : widget.posts.length - 1);
    _verticalCtrl = PageController(initialPage: _currentIndex);
    // Track view for initial post
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.posts.isNotEmpty) {
        final postId = widget.posts[_currentIndex]['id'] as String? ?? widget.posts[_currentIndex]['postId'] as String? ?? '';
        if (postId.isNotEmpty) {
          try {
            final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
            dio.post('/api/discover/view', data: {'postId': postId, 'userId': widget.currentUserId});
          } catch (_) {}
        }
      }
    });
    if (!widget.embedded) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    if (!widget.embedded) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return DiscoveryVerticalLock(
        lock:   () { if (mounted) setState(() => _locked = true); },
        unlock: () { if (mounted) setState(() => _locked = false); },
        child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: PageView.builder(
        controller: _verticalCtrl,
        scrollDirection: Axis.vertical,
        physics: (_locked || _activePointers >= 2) ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
        itemCount: widget.posts.length,
        onPageChanged: (i) async {
          setState(() => _currentIndex = i);
          if (i < widget.posts.length) {
            final postId = widget.posts[i]['id'] as String? ?? widget.posts[i]['postId'] as String? ?? '';
            if (postId.isNotEmpty) {
              try {
                final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
                await dio.post('/api/discover/view', data: {'postId': postId, 'userId': widget.currentUserId});
              } catch (_) {}
            }
          }
        },
        itemBuilder: (_, i) {
          final post = widget.posts[i];
          return _FullscreenPostPage(
            post: post,
            isActive: i == _currentIndex && widget.isActive,
            currentUserId: widget.currentUserId,
            currentUserAvatar: widget.currentUserAvatar,
            onClose: () => Navigator.of(context, rootNavigator: true).pop(),
            embedded: true,
          );
        },
      )));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: PageView.builder(
        controller: _verticalCtrl,
        scrollDirection: Axis.vertical,
        physics: _activePointers >= 2 ? const NeverScrollableScrollPhysics() : null,
        itemCount: widget.posts.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final post = widget.posts[i];
          return _FullscreenPostPage(
            post: post,
            isActive: i == _currentIndex && widget.isActive,
            currentUserId: widget.currentUserId,
            currentUserAvatar: widget.currentUserAvatar,
            onClose: () => Navigator.of(context, rootNavigator: true).pop(),
          );
        },
      )),
    );
  }
}

class _FullscreenPostPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isActive;
  final String currentUserId;
  final String currentUserAvatar;
  final String currentUserName;
  final VoidCallback onClose;
  final bool embedded;

  const _FullscreenPostPage({
    Key? key,
    required this.post,
    required this.isActive,
    required this.currentUserId,
    required this.currentUserAvatar,
    required this.onClose,
    this.currentUserName = '',
    this.embedded = false,
  }) : super(key: key);

  @override
  State<_FullscreenPostPage> createState() => _FullscreenPostPageState();
}

class _FullscreenPostPageState extends State<_FullscreenPostPage>
    with TickerProviderStateMixin {

  final List<_BurstParticle> _particles = [];
  late AnimationController _burstAnim;

  late AnimationController _spotlightAnim;
  late Animation<Offset> _spotlightSlide;
  late Animation<double> _spotlightFade;

  bool _liked = false;
  int _likeCount = 0;
  bool _showGrid = true;
  AudioPlayer? _musicPlayer;

  static const _reactionEmojis = ['❤️', '🔥', '😍', '👏', '💯', '✨', '🎉', '⚡'];

  @override
  void initState() {
    super.initState();
    final authorId = widget.post['authorId'] as String? ?? '';
    _likeCount = (widget.post['likeCount'] as int?) ?? 0;

    _burstAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _burstAnim.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _particles.clear());
      }
    });

    _spotlightAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _spotlightSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _spotlightAnim, curve: Curves.easeOutCubic));
    _spotlightFade = CurvedAnimation(parent: _spotlightAnim, curve: Curves.easeOut);

    if (widget.isActive) _triggerSpotlight();
    _initMusic();
  }

  @override
  void didUpdateWidget(_FullscreenPostPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _triggerSpotlight();
      _musicPlayer?.play();
    } else if (!widget.isActive && old.isActive) {
      _musicPlayer?.pause();
    }
    // Re-init music if musicUrl changed (e.g. feed loaded after initial render)
    final newUrl = widget.post['musicUrl'] as String? ?? '';
    final oldUrl = old.post['musicUrl'] as String? ?? '';
    if (newUrl != oldUrl && newUrl.isNotEmpty) {
      _musicPlayer?.dispose();
      _musicPlayer = null;
      _initMusic();
    }
  }

  Future<void> _initMusic() async {
    final url = widget.post['musicUrl'] as String? ?? '';
    if (url.isEmpty) return;
    try {
      _musicPlayer = AudioPlayer();
      if (url.startsWith('/')) {
        // Local file path
        await _musicPlayer!.setFilePath(url);
      } else {
        // Remote URL
        await _musicPlayer!.setUrl(url);
      }
      await _musicPlayer!.setLoopMode(LoopMode.one);
      if (widget.isActive) await _musicPlayer!.play();
    } catch (e) {
      debugPrint('Music init error: $e');
    }
  }

  void _triggerSpotlight() {
    _spotlightAnim.forward(from: 0).then((_) async {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _spotlightAnim.reverse();
    });
  }

  @override
  void dispose() {
    _burstAnim.dispose();
    _spotlightAnim.dispose();
    _musicPlayer?.dispose();
    super.dispose();
  }

  void _onTapForReaction(TapDownDetails details) {
    HapticFeedback.mediumImpact();
    final rng = Random();
    final newParticles = List.generate(6, (i) => _BurstParticle(
      emoji: _reactionEmojis[rng.nextInt(_reactionEmojis.length)],
      offset: details.localPosition,
      angle: rng.nextDouble() * 2 * pi,
      speed: 80 + rng.nextDouble() * 120,
    ));
    setState(() {
      _particles.addAll(newParticles);
      if (!_liked) {
        _liked = true;
        _likeCount++;
        _toggleLike();
      }
    });
    _burstAnim.forward(from: 0);
  }

  Future<void> _requestCollab(BuildContext context) async {
    final post = widget.post;
    final postId = post['id'] as String? ?? post['postId'] as String? ?? '';
    final authorName = post['authorName'] as String? ?? 'this creator';
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Collab Request',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Send your media to collab with $authorName?',
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('Send 🤝',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('${AppConstants.serverUrl}/api/discover/collab/request'));
      req.fields['postId']          = postId;
      req.fields['requesterId']     = widget.currentUserId;
      req.fields['requesterName']   = widget.currentUserName.isNotEmpty ? widget.currentUserName : widget.currentUserId;
      req.fields['requesterAvatar'] = widget.currentUserAvatar;
      req.fields['mediaType']       = 'image';
      req.files.add(await http.MultipartFile.fromPath('media', picked.path));
      final res  = await req.send();
      final body = jsonDecode(await res.stream.bytesToString());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(body['success'] == true
              ? '🤝 Collab request sent!'
              : body['message'] ?? 'Failed'),
          backgroundColor: body['success'] == true
              ? const Color(0xFF1A3A3A) : Colors.redAccent,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send collab request'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _toggleLike() async {
    try {
      final postId = widget.post['id'] ?? widget.post['_id'] ?? '';
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      await dio.post('/api/discover/like',
          data: {'userId': widget.currentUserId, 'postId': postId});
    } catch (_) {}
  }

  void _openComments(Map<String, dynamic> post) {
    final postId = post['id'] ?? post['_id'] ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.92,
        expand: false,
        builder: (ctx, scroll) => CommentsSheet(
          postId:         postId,
          userId:         widget.currentUserId,
          authorName:     post['authorName'] as String? ?? '',
          authorAvatar:   post['authorAvatar'] as String? ?? '',
          initialCount:   (post['commentCount'] as int?) ?? 0,
          onCountChanged: (_) {},
        ),
      ),
    );
  }

  void _openViewers(Map<String, dynamic> post) {
    final postId = post['id'] as String? ?? post['postId'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PeopleListSheet(
        title: '👁️ Viewers',
        postId: postId,
        type: 'viewers',
        currentUserId: widget.currentUserId,
      ),
    );
  }

  void _openCommenters(Map<String, dynamic> post) {
    final postId = post['id'] as String? ?? post['postId'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PeopleListSheet(
        title: '💬 Commenters',
        postId: postId,
        type: 'commenters',
        currentUserId: widget.currentUserId,
      ),
    );
  }

  Future<void> _sharePost(Map<String, dynamic> post) async {
    HapticFeedback.mediumImpact();
    final title    = post['title']     as String? ?? '';
    final mediaUrl = post['mediaUrl']  as String? ?? '';
    final mimeType = (post['mediaType'] as String? ?? '') == 'video' ? 'video/mp4' : 'image/jpeg';
    final isVideo  = mimeType.startsWith('video');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          _ShareOption(
            icon: Icons.ios_share_rounded,
            label: 'Share Post',
            color: Colors.blue,
            onTap: () {
              Navigator.pop(context);
              final parts = <String>[];
              if (title.isNotEmpty) parts.add(title);
              if (mediaUrl.isNotEmpty) parts.add(mediaUrl);
              parts.add('Shared via XamePage');
              Share.share(parts.join('\n'));
            },
          ),
          if (mediaUrl.isNotEmpty) _ShareOption(
            icon: isVideo ? Icons.download_rounded : Icons.save_alt_rounded,
            label: isVideo ? 'Save Video' : 'Save Image',
            color: Colors.green,
            onTap: () async {
              Navigator.pop(context);
              try {
                const bridge = MethodChannel('com.xamepage.app/android_bridge');
                final ext      = isVideo ? 'mp4' : 'jpg';
                final fileName = 'xamepage_\${DateTime.now().millisecondsSinceEpoch}.\$ext';
                final success  = await bridge.invokeMethod<bool>('saveMedia', {
                  'url': mediaUrl, 'fileName': fileName, 'mimeType': mimeType,
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success == true
                        ? (isVideo ? 'Video saved to Movies/XamePage' : 'Image saved to Pictures/XamePage')
                        : 'Save failed — please try again'),
                    backgroundColor: success == true ? Colors.green : Colors.red,
                  ));
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Save failed')));
              }
            },
          ),
          _ShareOption(
            icon: Icons.link_rounded,
            label: 'Copy Link',
            color: Colors.orange,
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: mediaUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard')));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _timeAgo(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt   = ts is DateTime ? ts : DateTime.parse(ts.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0)    return '${diff.inDays}d ago';
      if (diff.inHours > 0)   return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'just now';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [

        Builder(builder: (_) {
          final collabAccepted = (widget.post['collabStatus'] as String? ?? '') == 'accepted';
          final collabMediaUrl = widget.post['collabMediaUrl'] as String? ?? '';
          if (collabAccepted && collabMediaUrl.isNotEmpty) {
            return _CollabCombinedView(
              layout:          widget.post['collabLayout'] as String? ?? 'side-by-side',
              mediaUrl:        widget.post['mediaUrl'] as String? ?? '',
              mediaType:       widget.post['mediaType'] as String? ?? 'image',
              collabMediaUrl:  collabMediaUrl,
              collabMediaType: widget.post['collabMediaType'] as String? ?? 'image',
              isActive:        widget.isActive,
              isRemix:         widget.post['isRemix'] as bool? ?? false,
            );
          }

          final isVid = (widget.post['mediaType'] as String? ?? '') == 'video';
          final mediaUrlsRaw = widget.post['mediaUrls'] as List?;
          final mediaUrls = mediaUrlsRaw != null
              ? mediaUrlsRaw.map((e) => (e as Map)['url'] as String).toList()
              : <String>[];
          Widget child;
          if (!isVid && mediaUrls.length > 1) {
            child = _showGrid
                ? _ImageGrid(urls: mediaUrls, onTap: () => setState(() => _showGrid = false))
                : _ImageCarousel(urls: mediaUrls, onDoubleTapDown: _onTapForReaction);
          } else {
            child = GestureDetector(
              onDoubleTapDown: _onTapForReaction,
              onDoubleTap: () {},
              behavior: HitTestBehavior.translucent,
              child: isVid
                  ? _VideoPage(url: widget.post['mediaUrl'] as String? ?? '', isActive: widget.isActive)
                  : _ImagePage(url: widget.post['mediaUrl'] as String? ?? ''),
            );
          }
          return child;
        }),


        if (_particles.isNotEmpty)
          AnimatedBuilder(
            animation: _burstAnim,
            builder: (_, __) {
              return Stack(
                children: _particles.map((p) {
                  final t  = _burstAnim.value;
                  final dx = cos(p.angle) * p.speed * t;
                  final dy = sin(p.angle) * p.speed * t - 60 * t;
                  return Positioned(
                    left: p.offset.dx + dx - 16,
                    top:  p.offset.dy + dy - 16,
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Text(p.emoji,
                          style: TextStyle(fontSize: 28 + (1 - t) * 8)),
                    ),
                  );
                }).toList(),
              );
            },
          ),

        if (!widget.embedded)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 16),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        widget.post['category'] as String? ?? '',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),

              ]),
            ),
          ),

        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Stack(children: [
            // Gradient background — IgnorePointer so the video progress bar
            // underneath remains draggable through this decorative overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.post['isRemix'] as bool? ?? false) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.change_circle_rounded, color: Color(0xFF00E5FF), size: 14),
                            SizedBox(width: 4),
                            Text('Collab Remix',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(children: [
                        GestureDetector(
                          onTap: () async {
                            _musicPlayer?.pause();
                            await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                              builder: (_) => AuthorGalleryScreen(
                                authorId:         widget.post['authorId']     as String? ?? '',
                                authorName:       widget.post['authorName']   as String? ?? '',
                                authorAvatar:     widget.post['authorAvatar'] as String? ?? '',
                                currentUserId:    widget.currentUserId,
                                currentUserAvatar: widget.currentUserAvatar,
                              ),
                            ));
                            if (widget.isActive && mounted) _musicPlayer?.play();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white54, width: 1.5),
                            ),
                            child: CircleAvatar(
                              radius: 20,
                              backgroundImage: CachedNetworkImageProvider(
                                widget.post['authorAvatar'] as String? ?? '',
                              ),
                              onBackgroundImageError: (_, __) {},
                              backgroundColor: Colors.grey[800],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.post['authorName'] as String? ?? '',
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              Text(
                                _timeAgo(widget.post['ts']),
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        _FollowChip(
                          authorId:      widget.post['authorId'] as String? ?? '',
                          currentUserId: widget.currentUserId,
                        ),
                        _CollabToggleChip(
                          postId:              widget.post['id'] as String? ?? widget.post['postId'] as String? ?? '',
                          authorId:            widget.post['authorId'] as String? ?? '',
                          currentUserId:       widget.currentUserId,
                          initialIsCollabOpen: widget.post['isCollabOpen'] as bool? ?? false,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        widget.post['title'] as String? ?? '',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((widget.post['musicTitle'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.music_note_rounded,
                              color: Color(0xFF00E5A0), size: 12),
                          const SizedBox(width: 4),
                          Expanded(child: Text(
                            widget.post['musicTitle'] as String,
                            style: const TextStyle(
                                color: Color(0xFF00E5A0),
                                fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ]),
                      ],

                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ActionColumn(
                  post:          widget.post,
                  liked:         _liked,
                  likeCount:     _likeCount,
                  currentUserId: widget.currentUserId,
                  embedded:      widget.embedded,
                  onLike: () {
                    setState(() {
                      _liked      = !_liked;
                      _likeCount += _liked ? 1 : -1;
                    });
                    _toggleLike();
                  },
                  onComment:    () => _openComments(widget.post),
                  onShare:      () => _sharePost(widget.post),
                  onViewers:    () => _openViewers(widget.post),
                  onCommenters: () => _openCommenters(widget.post),
                  onCollab:     () => _requestCollab(context),
                ),
              ],
            ),
          ),
          ])),

        Positioned(
          bottom: 140, left: 16,
          child: SlideTransition(
            position: _spotlightSlide,
            child: FadeTransition(
              opacity: _spotlightFade,
              child: _CreatorSpotlight(
                name:   widget.post['authorName'] as String? ?? '',
                region: widget.post['region']     as String? ?? '',
              ),
            ),
          ),
        ),

      ],
    );
  }
}

class _CreatorSpotlight extends StatelessWidget {
  final String name;
  final String region;
  const _CreatorSpotlight({required this.name, required this.region});

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black87, Colors.black54],
        ),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF00E5FF), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: const TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          if (region.isNotEmpty)
            Text(region,
                style: const TextStyle(color: Color(0xFF00E5FF),
                    fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _BurstParticle {
  final String emoji;
  final Offset offset;
  final double angle;
  final double speed;
  const _BurstParticle({
    required this.emoji,
    required this.offset,
    required this.angle,
    required this.speed,
  });
}

class _VideoPage extends StatefulWidget {
  final String url;
  final bool isActive;
  const _VideoPage({Key? key, required this.url, required this.isActive})
      : super(key: key);

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  BetterPlayerController? _ctrl;
  bool _muted  = true;
  bool _paused = false;
  bool _controlsVisible = true;
  double _progress = 0;
  Duration _total  = Duration.zero;
  Duration _pos    = Duration.zero;
  Timer? _hideTimer;
  int _activeTouches = 0;

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Never hide while a finger is still on the screen (e.g. dragging slider)
    if (_activeTouches > 0) return;
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_paused && _activeTouches == 0) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _onPointerDown(PointerDownEvent e) {
    _activeTouches++;
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
  }

  void _onPointerUpOrCancel(PointerEvent e) {
    _activeTouches = (_activeTouches - 1).clamp(0, 10);
    if (_activeTouches == 0) _scheduleHide();
  }

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    _ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay:    widget.isActive,
        looping:     true,
        fit:         BoxFit.cover,
        aspectRatio: 9 / 16,
        fullScreenByDefault: false,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
            showControls: false),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2000,
          maxBufferMs: 10000,
          bufferForPlaybackMs: 500,
          bufferForPlaybackAfterRebufferMs: 1000,
        ),
      ),
    );
    _ctrl!.addEventsListener(_onEvent);
    _ctrl!.setVolume(0);
  }

  void _onEvent(BetterPlayerEvent e) {
    if (!mounted) return;
    if (e.betterPlayerEventType == BetterPlayerEventType.progress) {
      final pos   = _ctrl?.videoPlayerController?.value.position ?? Duration.zero;
      final total = _ctrl?.videoPlayerController?.value.duration ?? Duration.zero;
      if (total.inMilliseconds > 0) {
        setState(() {
          _pos      = pos;
          _total    = total;
          _progress = pos.inMilliseconds / total.inMilliseconds;
        });
      }
    }
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl?.play();
    } else if (!widget.isActive && old.isActive) {
      _ctrl?.pause();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl?.removeEventsListener(_onEvent);
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() => _muted = !_muted);
    _ctrl?.setVolume(_muted ? 0 : 1);
  }

  void _togglePause() {
    HapticFeedback.lightImpact();
    setState(() {
      _paused = !_paused;
      _controlsVisible = true;
    });
    if (_paused) {
      _ctrl?.pause();
      _hideTimer?.cancel();
    } else {
      _ctrl?.play();
      _scheduleHide();
    }
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      behavior: HitTestBehavior.translucent,
      child: Stack(children: [
        // The actual video — always painted, never intercepts touches itself.
        IgnorePointer(child: BetterPlayer(controller: _ctrl!)),
        // Tap-to-toggle layer — always active but pointer events are
        // passed through to children (slider, buttons) via Stack hit testing.
        // Excludes bottom 80px so slider drag is never intercepted.
        Positioned(
          top: 0, left: 0, right: 0,
          bottom: 80,
          child: GestureDetector(
            onTap: _toggleControlsVisibility,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        if (_paused)
          Center(
            child: GestureDetector(
              onTap: _togglePause,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 48),
              ),
            ),
          ),
        IgnorePointer(
          ignoring: !_controlsVisible,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Stack(children: [
              Positioned(
                top: 80, right: 16,
                child: GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: Colors.white70, size: 20),
                  ),
                ),
              ),
              Positioned(
                top: 80, left: 16,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Icon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white70, size: 20),
                  ),
                ),
              ),
              if (_total.inSeconds > 0)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Text(_fmtDur(_pos),
                            style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        const Spacer(),
                        Text(_fmtDur(_total),
                            style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      ]),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: const Color(0xFF00E5FF),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: _progress.clamp(0.0, 1.0),
                        onChangeStart: (_) => _hideTimer?.cancel(),
                        onChanged: (v) {
                          if (_total.inMilliseconds > 0) {
                            setState(() => _progress = v);
                            final seek = Duration(
                                milliseconds: (v * _total.inMilliseconds).round());
                            _ctrl?.seekTo(seek);
                          }
                        },
                        onChangeEnd: (_) => _scheduleHide(),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Horizontal image carousel within a single Discovery post ────────────
// Locks the OUTER vertical PageView's scrolling while a horizontal drag is
// active here, then releases it once the drag ends — this prevents the two
// PageViews from fighting over the same gesture (Instagram-style behavior).
class _ImageGrid extends StatelessWidget {
  final List<String> urls;
  final VoidCallback onTap;
  const _ImageGrid({required this.urls, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tileCount = urls.length > 4 ? 4 : urls.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.black,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: tileCount,
          itemBuilder: (_, i) {
            final isLastTile = i == tileCount - 1;
            final remaining = urls.length - tileCount;
            return Stack(fit: StackFit.expand, children: [
              CachedNetworkImage(
                imageUrl: urls[i],
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey[900]),
                errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.broken_image, color: Colors.white24)),
              ),
              if (isLastTile && remaining > 0)
                Container(
                  color: Colors.black.withOpacity(0.55),
                  alignment: Alignment.center,
                  child: Text('+$remaining',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 28, fontWeight: FontWeight.w700)),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> urls;
  final void Function(TapDownDetails)? onDoubleTapDown;
  const _ImageCarousel({required this.urls, this.onDoubleTapDown});
  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  late PageController _ctrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: widget.onDoubleTapDown,
      onDoubleTap: () {},
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) =>
          DiscoveryVerticalLock.of(context)?.lock(),
      onHorizontalDragEnd: (_) =>
          DiscoveryVerticalLock.of(context)?.unlock(),
      onHorizontalDragCancel: () =>
          DiscoveryVerticalLock.of(context)?.unlock(),
      child: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) => _ImagePage(url: widget.urls[i]),
        ),
        Positioned(
          top: 12, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.urls.length, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _current ? 7 : 5,
              height: i == _current ? 7 : 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _current ? Colors.white : Colors.white38,
              ),
            )),
          ),
        ),
        Positioned(
          bottom: 12, right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${_current + 1}/${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      ]),
    );
  }
}

class _ImagePage extends StatefulWidget {
  final String url;
  const _ImagePage({Key? key, required this.url}) : super(key: key);

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _zoom;
  late Animation<double>    _scale;
  late Animation<Alignment> _align;

  @override
  void initState() {
    super.initState();
    _zoom  = AnimationController(
        vsync: this, duration: const Duration(seconds: 10));
    _scale = Tween(begin: 1.0, end: 1.0)
        .animate(_zoom);
    _align = AlignmentTween(
      begin: Alignment.center,
      end:   Alignment.center,
    ).animate(_zoom);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 6.0,
      panEnabled: true,
      scaleEnabled: true,
      clipBehavior: Clip.none,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit:      BoxFit.contain,
        width:    double.infinity,
        height:   double.infinity,
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.broken_image,
              color: Colors.white30, size: 64),
        ),
      ),
    );
  }
}

class _ActionColumn extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool liked;
  final int likeCount;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback? onViewers;
  final VoidCallback? onCommenters;
  final VoidCallback? onCollab;
  final bool embedded;

  const _ActionColumn({
    Key? key,
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    this.onViewers,
    this.onCommenters,
    this.onCollab,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<_ActionColumn> createState() => _ActionColumnState();
}

class _ActionColumnState extends State<_ActionColumn>
    with SingleTickerProviderStateMixin {
  late AnimationController _likeAnim;
  late Animation<double> _likeScale;

  @override
  void initState() {
    super.initState();
    _likeAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _likeScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _likeAnim, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _likeAnim.dispose();
    super.dispose();
  }

  Future<void> _deletePost(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Post', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently delete your post. Are you sure?',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final postId = widget.post['id'] as String? ?? widget.post['postId'] as String? ?? '';
      final r = await dio.delete('/api/discover/post/' + postId,
          data: {'userId': widget.currentUserId});
      if (r.data['success'] == true && context.mounted) {
        // Only pop when this viewer was pushed as its own route — when
        // embedded (e.g. the main swipeable feed), there's no dedicated
        // route to pop, and calling Navigator.pop() anyway leaves a blank
        // screen since it pops an unrelated ancestor navigator instead.
        if (!widget.embedded) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted'), backgroundColor: Colors.red));
      }
    } catch (_) {}
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final commentCount = (widget.post['commentCount'] as int?) ?? 0;
    final viewCount    = (widget.post['viewCount']    as int?) ?? 0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () {
          widget.onLike();
          _likeAnim.forward(from: 0);
        },
        child: Column(children: [
          ScaleTransition(
            scale: _likeScale,
            child: Icon(
              widget.liked ? Icons.favorite : Icons.favorite_border,
              color: widget.liked ? Colors.redAccent : Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 4),
          Text(_fmt(widget.likeCount),
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 22),
      _ActionBtn(icon: Icons.chat_bubble_outline_rounded,
          color: Colors.white, label: _fmt(commentCount),
          onTap: widget.onComment),
      const SizedBox(height: 22),
      _ActionBtn(icon: Icons.remove_red_eye_outlined,
          color: Colors.white, label: _fmt(viewCount), onTap: widget.onViewers),
      const SizedBox(height: 22),
      _ActionBtn(icon: Icons.ios_share_rounded,
          color: Colors.white, label: 'Share', onTap: widget.onShare),
      // Collab — only for non-owners when post is open for collab
      if (widget.currentUserId.isNotEmpty &&
          widget.currentUserId != (widget.post['authorId'] as String? ?? '') &&
          (widget.post['isCollabOpen'] == true || widget.post['isCollabOpen'].toString() == 'true') &&
          (widget.post['collabStatus'] as String? ?? 'none') == 'none') ...[
        const SizedBox(height: 22),
        _ActionBtn(icon: Icons.handshake_outlined,
            color: const Color(0xFF00E5FF), label: 'Collab', onTap: widget.onCollab),
      ],
      // Delete — only for post owner
      if (widget.currentUserId.isNotEmpty &&
          widget.currentUserId == (widget.post['authorId'] as String? ?? '')) ...[
        const SizedBox(height: 22),
        _ActionBtn(icon: Icons.delete_outline_rounded,
            color: Colors.redAccent, label: 'Delete', onTap: () => _deletePost(context)),
      ],
    ]);
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionBtn({Key? key, required this.icon, required this.color,
      required this.label, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShareOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 20)),
    title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    onTap: onTap,
  );
}

class _FollowChip extends StatefulWidget {
  final String authorId;
  final String currentUserId;
  const _FollowChip({Key? key, required this.authorId,
      required this.currentUserId}) : super(key: key);

  @override
  State<_FollowChip> createState() => _FollowChipState();
}

class _FollowChipState extends State<_FollowChip> {
  bool _following = false;
  bool _loading   = false;
  bool _initLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (widget.authorId.isEmpty ||
        widget.authorId == widget.currentUserId) {
      if (mounted) setState(() => _initLoading = false);
      return;
    }
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get(
        '/api/discover/follow-status/${widget.authorId}',
        queryParameters: {'followerId': widget.currentUserId},
      );
      if (mounted && res.data['success'] == true) {
        setState(() {
          _following   = res.data['isFollowing'] == true;
          _initLoading = false;
        });
      } else if (mounted) {
        setState(() => _initLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _initLoading = false);
    }
  }

  Future<void> _toggle() async {
    if (_loading || widget.authorId.isEmpty ||
        widget.authorId == widget.currentUserId) return;
    setState(() => _loading = true);
    final wasFollowing = _following;
    try {
      final dio      = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final endpoint = wasFollowing
          ? '/api/discover/unfollow/${widget.authorId}'
          : '/api/discover/follow/${widget.authorId}';
      final res = await dio.post(endpoint, data: {
        'followerId': widget.currentUserId,
      });
      if (res.data['success'] == true) {
        setState(() { _following = !wasFollowing; _loading = false; });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initLoading) return const SizedBox.shrink();
    if (widget.authorId == widget.currentUserId) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _following ? Colors.white24 : const Color(0xFF00E5FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: _loading
            ? const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.white))
            : Text(
                _following ? 'Following' : 'Follow',
                style: TextStyle(
                  color: _following ? Colors.white70 : Colors.black,
                  fontSize: 11, fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _CollabToggleChip extends StatefulWidget {
  final String postId;
  final String authorId;
  final String currentUserId;
  final bool   initialIsCollabOpen;
  const _CollabToggleChip({
    Key? key,
    required this.postId,
    required this.authorId,
    required this.currentUserId,
    required this.initialIsCollabOpen,
  }) : super(key: key);

  @override
  State<_CollabToggleChip> createState() => _CollabToggleChipState();
}

class _CollabToggleChipState extends State<_CollabToggleChip> {
  bool _isOpen  = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.initialIsCollabOpen;
  }

  Future<void> _toggle() async {
    if (_loading || widget.authorId != widget.currentUserId) return;
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.post('/api/discover/collab/toggle', data: {
        'postId':   widget.postId,
        'authorId': widget.authorId,
      });
      if (res.data['success'] == true) {
        setState(() {
          _isOpen  = res.data['isCollabOpen'] as bool? ?? !_isOpen;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.authorId != widget.currentUserId) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _isOpen ? const Color(0xFF00E5FF) : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _loading
            ? const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.white))
            : Text(
                _isOpen ? '🤝 Collab Open' : '🤝 Collab Closed',
                style: TextStyle(
                  color: _isOpen ? Colors.black : Colors.white70,
                  fontSize: 11, fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CollabCombinedView — renders the author's and partner's media together once
// a collab has been accepted, arranged per the post's chosen collabLayout.
// ─────────────────────────────────────────────────────────────────────────────
class _CollabCombinedView extends StatelessWidget {
  final String layout;
  final String mediaUrl;
  final String mediaType;
  final String collabMediaUrl;
  final String collabMediaType;
  final bool isActive;
  final bool isRemix;

  const _CollabCombinedView({
    Key? key,
    required this.layout,
    required this.mediaUrl,
    required this.mediaType,
    required this.collabMediaUrl,
    required this.collabMediaType,
    required this.isActive,
    this.isRemix = false,
  }) : super(key: key);

  Widget _media(String url, String type, {bool active = false}) {
    return type == 'video'
        ? _VideoPage(url: url, isActive: active)
        : _ImagePage(url: url);
  }

  @override
  Widget build(BuildContext context) {
    final original = ClipRect(child: _media(mediaUrl, mediaType, active: isActive));
    final partner  = ClipRect(child: _media(collabMediaUrl, collabMediaType));

    Widget content;
    switch (layout) {
      case 'top-bottom':
        content = Column(children: [
          Expanded(child: original),
          Container(height: 2, color: Colors.white24),
          Expanded(child: partner),
        ]);
        break;
      case 'picture-in-picture':
        final pipWidth = MediaQuery.of(context).size.width * 0.32;
        content = Stack(fit: StackFit.expand, children: [
          original,
          Positioned(
            right: 16, bottom: 110,
            width: pipWidth, height: pipWidth * 1.6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: partner,
            ),
          ),
        ]);
        break;
      case 'side-by-side':
      default:
        content = Row(children: [
          Expanded(child: original),
          Container(width: 2, color: Colors.white24),
          Expanded(child: partner),
        ]);
    }

    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PeopleListSheet — shows viewers or commenters in a bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PeopleListSheet extends StatefulWidget {
  final String title;
  final String postId;
  final String type; // 'viewers' or 'commenters'
  final String currentUserId;

  const _PeopleListSheet({
    Key? key,
    required this.title,
    required this.postId,
    required this.type,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<_PeopleListSheet> createState() => _PeopleListSheetState();
}

class _PeopleListSheetState extends State<_PeopleListSheet> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final endpoint = widget.type == 'viewers'
          ? '/api/discover/${widget.postId}/viewers'
          : '/api/discover/${widget.postId}/commenters';
      final res = await dio.get(endpoint);
      if (mounted && res.data['success'] == true) {
        final key = widget.type == 'viewers' ? 'viewers' : 'commenters';
        setState(() {
          _list = List<Map<String, dynamic>>.from(res.data[key] ?? []);
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, sc) => Column(children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text(widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_list.length}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)))
              : _list.isEmpty
                  ? Center(child: Text(
                      widget.type == 'viewers' ? 'No viewers yet' : 'No comments yet',
                      style: const TextStyle(color: Colors.white54, fontSize: 13)))
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _list.length,
                      itemBuilder: (_, i) {
                        final u = _list[i];
                        final name   = u['name']   as String? ?? '';
                        final avatar = u['avatar']  as String? ?? '';
                        final comment = u['comment'] as String?;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white12,
                            backgroundImage: avatar.isNotEmpty
                                ? CachedNetworkImageProvider(avatar) : null,
                            child: avatar.isEmpty
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                                : null,
                          ),
                          title: Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: comment != null
                              ? Text(comment,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
