import 'package:better_player_enhanced/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/config/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/comments_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DiscoveryFullscreenViewer
//
// Layout:
//   • Outer: vertical PageView  → swipe up/down = next/previous post
//   • Inner: horizontal PageView per author → swipe left/right = more from that user
//   • Auto-play video when page is active; pause when scrolled away
//   • Double-tap = like with heart burst
//   • Overlay: author info (bottom-left), actions (bottom-right), top badge
// ─────────────────────────────────────────────────────────────────────────────

class DiscoveryFullscreenViewer extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final String currentUserId;
  final String currentUserAvatar;

  const DiscoveryFullscreenViewer({
    Key? key,
    required this.posts,
    required this.initialIndex,
    required this.currentUserId,
    this.currentUserAvatar = '',
  }) : super(key: key);

  @override
  State<DiscoveryFullscreenViewer> createState() =>
      _DiscoveryFullscreenViewerState();
}

class _DiscoveryFullscreenViewerState
    extends State<DiscoveryFullscreenViewer> {
  late PageController _verticalCtrl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _verticalCtrl = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _verticalCtrl,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final post = widget.posts[i];
          return _FullscreenPostPage(
            post: post,
            isActive: i == _currentIndex,
            currentUserId: widget.currentUserId,
            currentUserAvatar: widget.currentUserAvatar,
            allPosts: widget.posts,
            onClose: () => Navigator.of(context).pop(),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single post page
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenPostPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isActive;
  final String currentUserId;
  final String currentUserAvatar;
  final List<Map<String, dynamic>> allPosts;
  final VoidCallback onClose;

  const _FullscreenPostPage({
    Key? key,
    required this.post,
    required this.isActive,
    required this.currentUserId,
    required this.currentUserAvatar,
    required this.allPosts,
    required this.onClose,
  }) : super(key: key);

  @override
  State<_FullscreenPostPage> createState() => _FullscreenPostPageState();
}

class _FullscreenPostPageState extends State<_FullscreenPostPage>
    with SingleTickerProviderStateMixin {
  late PageController _horizCtrl;
  late List<Map<String, dynamic>> _authorPosts;
  int _horizIndex = 0;
  bool _showHeart = false;
  late AnimationController _heartAnim;
  late Animation<double> _heartScale;
  bool _liked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    final authorId = widget.post['authorId'] as String? ?? '';
    _authorPosts = widget.allPosts
        .where((p) => (p['authorId'] as String? ?? '') == authorId)
        .toList();
    if (_authorPosts.isEmpty) _authorPosts = [widget.post];
    _horizIndex = _authorPosts.indexWhere(
        (p) => (p['id'] ?? p['_id']) == (widget.post['id'] ?? widget.post['_id']));
    if (_horizIndex < 0) _horizIndex = 0;
    _horizCtrl = PageController(initialPage: _horizIndex);
    _likeCount = (widget.post['likeCount'] as int?) ?? 0;

    _heartAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.4), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _heartAnim, curve: Curves.easeOut));
    _heartAnim.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _horizCtrl.dispose();
    _heartAnim.dispose();
    super.dispose();
  }

  void _doubleTapLike() {
    setState(() {
      _showHeart = true;
      if (!_liked) {
        _liked = true;
        _likeCount++;
        _toggleLike();
      }
    });
    _heartAnim.forward(from: 0);
  }

  Future<void> _toggleLike() async {
    try {
      final postId = widget.post['id'] ?? widget.post['_id'] ?? '';
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      await dio.post('/api/discover/like/$postId',
          data: {'userId': widget.currentUserId});
    } catch (_) {}
  }

  void _openComments(Map<String, dynamic> post) {
    final postId = post['id'] ?? post['_id'] ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        postId: postId,
        userId: widget.currentUserId,
        userAvatar: widget.currentUserAvatar,
      ),
    );
  }

  String _timeAgo(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = ts is DateTime ? ts : DateTime.parse(ts.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'just now';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _doubleTapLike,
      child: Stack(children: [
        PageView.builder(
          controller: _horizCtrl,
          itemCount: _authorPosts.length,
          onPageChanged: (i) => setState(() => _horizIndex = i),
          itemBuilder: (_, i) {
            final p = _authorPosts[i];
            final isVid = (p['mediaType'] as String? ?? '') == 'video';
            final isHorizActive = widget.isActive && i == _horizIndex;
            return isVid
                ? _VideoPage(url: p['mediaUrl'] as String? ?? '', isActive: isHorizActive)
                : _ImagePage(url: p['mediaUrl'] as String? ?? '');
          },
        ),
        if (_showHeart)
          Center(
            child: ScaleTransition(
              scale: _heartScale,
              child: const Icon(Icons.favorite, color: Colors.white, size: 100),
            ),
          ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
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
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
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
                    _authorPosts[_horizIndex]['category'] as String? ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (_authorPosts.length > 1)
          Positioned(
            top: 60, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_authorPosts.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: i == _horizIndex ? 16 : 6,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == _horizIndex ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
                stops: [0.0, 1.0],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: CachedNetworkImageProvider(
                            _authorPosts[_horizIndex]['authorAvatar'] as String? ?? '',
                          ),
                          onBackgroundImageError: (_, __) {},
                          backgroundColor: Colors.grey[800],
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _authorPosts[_horizIndex]['authorName'] as String? ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            Text(
                              _timeAgo(_authorPosts[_horizIndex]['ts']),
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        _FollowChip(
                          authorId: _authorPosts[_horizIndex]['authorId'] as String? ?? '',
                          currentUserId: widget.currentUserId,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        _authorPosts[_horizIndex]['title'] as String? ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_authorPosts.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '← Swipe for more from ${_authorPosts[_horizIndex]['authorName'] ?? 'this user'} →',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ActionColumn(
                  post: _authorPosts[_horizIndex],
                  liked: _liked,
                  likeCount: _likeCount,
                  currentUserId: widget.currentUserId,
                  onLike: () {
                    setState(() {
                      _liked = !_liked;
                      _likeCount += _liked ? 1 : -1;
                    });
                    _toggleLike();
                  },
                  onComment: () => _openComments(_authorPosts[_horizIndex]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video page
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPage extends StatefulWidget {
  final String url;
  final bool isActive;
  const _VideoPage({Key? key, required this.url, required this.isActive}) : super(key: key);

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  BetterPlayerController? _ctrl;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: widget.isActive,
        looping: true,
        fit: BoxFit.cover,
        controlsConfiguration: const BetterPlayerControlsConfiguration(showControls: false),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
      ),
    );
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
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _paused ? _ctrl?.pause() : _ctrl?.play();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePause,
      child: Stack(children: [
        BetterPlayer(controller: _ctrl!),
        if (_paused)
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white54, size: 72)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image page — Ken Burns zoom
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePage extends StatefulWidget {
  final String url;
  const _ImagePage({Key? key, required this.url}) : super(key: key);

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _zoom;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _zoom = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    _scale = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _zoom, curve: Curves.easeInOut));
    _zoom.repeat(reverse: true);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.broken_image, color: Colors.white30, size: 64),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action column
// ─────────────────────────────────────────────────────────────────────────────

class _ActionColumn extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool liked;
  final int likeCount;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _ActionColumn({
    Key? key,
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
  }) : super(key: key);

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final commentCount = (post['commentCount'] as int?) ?? 0;
    final viewCount = (post['viewCount'] as int?) ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBtn(icon: liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.redAccent : Colors.white, label: _fmt(likeCount), onTap: onLike),
        const SizedBox(height: 20),
        _ActionBtn(icon: Icons.chat_bubble_outline_rounded, color: Colors.white, label: _fmt(commentCount), onTap: onComment),
        const SizedBox(height: 20),
        _ActionBtn(icon: Icons.remove_red_eye_outlined, color: Colors.white, label: _fmt(viewCount), onTap: null),
        const SizedBox(height: 20),
        _ActionBtn(icon: Icons.share_rounded, color: Colors.white, label: 'Share', onTap: () {}),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionBtn({Key? key, required this.icon, required this.color, required this.label, required this.onTap}) : super(key: key);

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

// ─────────────────────────────────────────────────────────────────────────────
// Follow chip
// ─────────────────────────────────────────────────────────────────────────────

class _FollowChip extends StatefulWidget {
  final String authorId;
  final String currentUserId;
  const _FollowChip({Key? key, required this.authorId, required this.currentUserId}) : super(key: key);

  @override
  State<_FollowChip> createState() => _FollowChipState();
}

class _FollowChipState extends State<_FollowChip> {
  bool _following = false;
  bool _loading = false;

  Future<void> _toggle() async {
    if (_loading || widget.authorId.isEmpty || widget.authorId == widget.currentUserId) return;
    setState(() => _loading = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final endpoint = _following
          ? '/api/discover/unfollow/${widget.authorId}'
          : '/api/discover/follow/${widget.authorId}';
      await dio.post(endpoint, data: {'followerId': widget.currentUserId});
      if (mounted) setState(() => _following = !_following);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.authorId == widget.currentUserId) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _following ? Colors.white24 : const Color(0xFF00C896),
          borderRadius: BorderRadius.circular(20),
          border: _following ? Border.all(color: Colors.white38) : null,
        ),
        child: _loading
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
            : Text(
                _following ? 'Following' : '+ Follow',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: _following ? FontWeight.w500 : FontWeight.w800),
              ),
      ),
    );
  }
}
