import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/config/constants.dart';
import 'live_pulse.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Media Discover Card ───────────────────────────────────────────────────────
class MediaDiscoverCard extends StatefulWidget {
  final String  mediaUrl;
  final String  title;
  final String  category;
  final bool    isLive;
  final String? authorName;
  final String? authorAvatar;
  final int     viewCount;
  final int     likeCount;
  final String  postId;
  final String  userId;
  final VoidCallback? onTap;

  const MediaDiscoverCard({
    Key? key,
    required this.mediaUrl,
    required this.title,
    required this.category,
    this.isLive      = false,
    this.authorName,
    this.authorAvatar,
    this.viewCount   = 0,
    this.likeCount   = 0,
    this.postId      = '',
    this.userId      = '',
    this.onTap,
  }) : super(key: key);

  @override
  State<MediaDiscoverCard> createState() => _MediaDiscoverCardState();
}

class _MediaDiscoverCardState extends State<MediaDiscoverCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapCtrl;
  late Animation<double>   _tapScale;
  late AnimationController _likeCtrl;
  late Animation<double>   _likeScale;
  bool _liked = false;

  static const _boxName = 'xame_discovery_likes';

  @override
  void initState() {
    super.initState();
    _tapCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _tapScale = Tween(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOut));
    _likeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _likeScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _likeCtrl, curve: Curves.easeInOut));
    _loadLike();
  }

  Future<void> _loadLike() async {
    try {
      final box = await Hive.openBox<bool>(_boxName);
      if (mounted) setState(() => _liked = box.get(widget.title) ?? false);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();
    final next = !_liked;
    setState(() => _liked = next);
    _likeCtrl.forward(from: 0);
    // Persist locally
    try {
      final box = await Hive.openBox<bool>(_boxName);
      await box.put(widget.title, next);
    } catch (_) {}
    // Sync to server if postId available
    if (widget.postId.isNotEmpty && widget.userId.isNotEmpty) {
      try {
        final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
        await dio.post('/api/discover/like',
          data: {'userId': widget.userId, 'postId': widget.postId});
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    _likeCtrl.dispose();
    super.dispose();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final likeCount = widget.likeCount + (_liked ? 1 : 0);
    return GestureDetector(
      onTapDown:   (_) => _tapCtrl.forward(),
      onTapUp:     (_) { _tapCtrl.reverse(); widget.onTap?.call(); },
      onTapCancel: ()  => _tapCtrl.reverse(),
      onLongPress: ()  => _showPreview(context),
      child: ScaleTransition(
        scale: _tapScale,
        child: Hero(
          tag: 'discover_${widget.title}',
          child: Container(
            height: 420,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withOpacity(0.45),
                  blurRadius: 24,
                  offset:     const Offset(0, 10)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(fit: StackFit.expand, children: [
                // Image
                CachedNetworkImage(
                  imageUrl: widget.mediaUrl,
                  fit:      BoxFit.cover,
                  placeholder: (_, __) => const ShimmerBox(
                      width: double.infinity,
                      height: 420,
                      radius: 28),
                  errorWidget: (_, __, ___) => Container(
                    color: context.xSurface,
                    child: const Icon(Icons.image_outlined,
                        color: Colors.white12, size: 48)),
                ),

                // Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      stops:  [0.0, 0.45, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xEE000000),
                      ],
                    ),
                  ),
                ),

                // Live badge
                if (widget.isLive)
                  const Positioned(
                      top: 18, right: 18,
                      child: LivePulseIndicator()),

                // Category chip
                Positioned(
                  top: 18, left: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:        Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12)),
                    child: Text(widget.category.toUpperCase(),
                      style: TextStyle(
                        color:       context.xPrimary,
                        fontSize:    10,
                        fontWeight:  FontWeight.w800,
                        letterSpacing: 1.2)),
                  ),
                ),

                // Bottom content
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Author
                        if (widget.authorName != null)
                          Row(children: [
                            if (widget.authorAvatar != null)
                              Container(
                                width: 26, height: 26,
                                margin: const EdgeInsets.only(right: 7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white30, width: 1)),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl:    widget.authorAvatar!,
                                    fit:         BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                      Container(color: context.xSurface),
                                  ),
                                ),
                              ),
                            Text(widget.authorName!,
                              style: const TextStyle(
                                  color:      Colors.white60,
                                  fontSize:   12,
                                  fontWeight: FontWeight.w500)),
                          ]),
                        const SizedBox(height: 6),

                        // Title
                        Text(widget.title,
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   20,
                            fontWeight: FontWeight.w800,
                            height:     1.2)),
                        const SizedBox(height: 12),

                        // Stats row
                        Row(children: [
                          // Views
                          Row(children: [
                            const Icon(Icons.remove_red_eye_outlined,
                                color: Colors.white38, size: 14),
                            const SizedBox(width: 4),
                            Text(_fmt(widget.viewCount),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          ]),
                          const SizedBox(width: 14),

                          // Like button — persistent
                          ScaleTransition(
                            scale: _likeScale,
                            child: GestureDetector(
                              onTap: _toggleLike,
                              child: Row(children: [
                                Icon(
                                  _liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                  color: _liked
                                    ? context.xDanger
                                    : Colors.white38,
                                  size: 16),
                                const SizedBox(width: 4),
                                Text(_fmt(likeCount),
                                  style: TextStyle(
                                    color: _liked
                                      ? context.xDanger
                                      : Colors.white38,
                                    fontSize:   12,
                                    fontWeight: _liked
                                      ? FontWeight.w700 : FontWeight.normal)),
                              ]),
                            ),
                          ),

                          const Spacer(),

                          // Share
                          GestureDetector(
                            onTap: () => _sharePost(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: Colors.white.withOpacity(0.1),
                                border: Border.all(
                                    color: Colors.white24, width: 0.5)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.share_outlined,
                                      color: Colors.white60, size: 13),
                                  SizedBox(width: 4),
                                  Text('Share',
                                    style: TextStyle(
                                        color:      Colors.white60,
                                        fontSize:   11,
                                        fontWeight: FontWeight.w600)),
                                ]),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sharePost(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final parts = <String>[];
    if (widget.title.isNotEmpty) parts.add(widget.title);
    if (widget.mediaUrl.isNotEmpty) parts.add(widget.mediaUrl);
    parts.add('Shared via XamePage');
    final text = parts.join('\n');
    try {
      const ch = MethodChannel('com.xamepage.app/call');
      await ch.invokeMethod('shareText', <String, dynamic>{'text': text});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Link copied to clipboard'),
          backgroundColor: XameColors.darkSurface));
      }
    }
  }

  void _showPreview(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog(
      context:      context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: Hero(
              tag: 'discover_${widget.title}',
              child: Container(
                width:  MediaQuery.of(context).size.width * 0.88,
                height: MediaQuery.of(context).size.height * 0.62,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  image: DecorationImage(
                    image: NetworkImage(widget.mediaUrl),
                    fit:   BoxFit.cover),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withOpacity(0.6),
                      blurRadius: 40)]),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)])),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.category.toUpperCase(),
                        style: const TextStyle(
                          color:       XameColors.primary,
                          fontSize:    11,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Text(widget.title,
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   24,
                          fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Skeleton loader ───────────────────────────────────────────────────────────
class DiscoveryCardSkeleton extends StatelessWidget {
  const DiscoveryCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
    height: 420,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: const ShimmerBox(
        width: double.infinity, height: 420, radius: 28),
  );
}
