import 'dart:async';
import 'dart:math';
import 'package:better_player_enhanced/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/comments_sheet.dart';

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
  late List<String> _authorOrder;
  late Map<String, List<Map<String, dynamic>>> _postsByAuthor;

  @override
  void initState() {
    super.initState();
    // Map post index to author index
    final initialPost = widget.posts.length > widget.initialIndex
        ? widget.posts[widget.initialIndex]
        : (widget.posts.isNotEmpty ? widget.posts.first : null);
    final initialAuthorId = initialPost?['authorId'] as String? ?? '';
    _currentIndex = 0;

    // Build author-grouped structure first so we can find the author index
    _authorOrder = [];
    _postsByAuthor = {};
    for (final p in widget.posts) {
      final aId = p['authorId'] as String? ?? '';
      if (!_postsByAuthor.containsKey(aId)) {
        _authorOrder.add(aId);
        _postsByAuthor[aId] = [];
      }
      _postsByAuthor[aId]!.add(p);
    }
    final authorIdx = _authorOrder.indexOf(initialAuthorId);
    _currentIndex = authorIdx < 0 ? 0 : authorIdx;
    _verticalCtrl = PageController(initialPage: _currentIndex);
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
    with TickerProviderStateMixin {

  final List<_BurstParticle> _particles = [];
  late AnimationController _burstAnim;

  late AnimationController _spotlightAnim;
  late Animation<Offset> _spotlightSlide;
  late Animation<double> _spotlightFade;

  bool _liked = false;
  int _likeCount = 0;

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
  }

  @override
  void didUpdateWidget(_FullscreenPostPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _triggerSpotlight();
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
      builder: (_) => CommentsSheet(
        postId:         postId,
        userId:         widget.currentUserId,
        authorName:     post['authorName'] as String? ?? '',
        authorAvatar:   post['authorAvatar'] as String? ?? '',
        initialCount:   (post['commentCount'] as int?) ?? 0,
        onCountChanged: (_) {},
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
    return GestureDetector(
      onDoubleTapDown: _onTapForReaction,
      onDoubleTap: () {},
      behavior: HitTestBehavior.translucent,
      child: Stack(children: [

        Builder(builder: (_) {
          final isVid = (widget.post['mediaType'] as String? ?? '') == 'video';
          return isVid
              ? _VideoPage(url: widget.post['mediaUrl'] as String? ?? '', isActive: widget.isActive)
              : _ImagePage(url: widget.post['mediaUrl'] as String? ?? '');
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
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end:   Alignment.topCenter,
                colors: [Colors.black87, Colors.black45, Colors.transparent],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 36),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Container(
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
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        widget.post['title'] as String? ?? '',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ActionColumn(
                  post:          widget.post,
                  liked:         _liked,
                  likeCount:     _likeCount,
                  currentUserId: widget.currentUserId,
                  onLike: () {
                    setState(() {
                      _liked      = !_liked;
                      _likeCount += _liked ? 1 : -1;
                    });
                    _toggleLike();
                  },
                  onComment: () => _openComments(widget.post),
                  onShare:   () => _sharePost(widget.post),
                ),
              ],
            ),
          ),
        ),

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

      ]),
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
  double _progress = 0;
  Duration _total  = Duration.zero;
  Duration _pos    = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay:    widget.isActive,
        looping:     true,
        fit:         BoxFit.contain,
        aspectRatio: 9 / 16,
        fullScreenByDefault: false,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
            showControls: false),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
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
    setState(() => _paused = !_paused);
    _paused ? _ctrl?.pause() : _ctrl?.play();
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePause,
      behavior: HitTestBehavior.opaque,
      child: Stack(children: [
        IgnorePointer(child: BetterPlayer(controller: _ctrl!)),
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
                  onChanged: (v) {
                    if (_total.inMilliseconds > 0) {
                      final seek = Duration(
                          milliseconds: (v * _total.inMilliseconds).round());
                      _ctrl?.seekTo(seek);
                    }
                  },
                ),
              ),
            ]),
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
      minScale: 1.0,
      maxScale: 5.0,
      panEnabled: false,
      scaleEnabled: true,
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

  const _ActionColumn({
    Key? key,
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
    required this.onShare,
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
        Navigator.pop(context); // close fullscreen viewer
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
          color: Colors.white, label: _fmt(commentCount), onTap: widget.onComment),
      const SizedBox(height: 22),
      _ActionBtn(icon: Icons.remove_red_eye_outlined,
          color: Colors.white, label: _fmt(viewCount), onTap: null),
      const SizedBox(height: 22),
      _ActionBtn(icon: Icons.ios_share_rounded,
          color: Colors.white, label: 'Share', onTap: widget.onShare),
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
