import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'live_pulse.dart';

class MediaDiscoverCard extends StatefulWidget {
  final String  mediaUrl;
  final String  title;
  final String  category;
  final bool    isLive;
  final String? authorName;
  final String? authorAvatar;
  final int     viewCount;
  final int     likeCount;
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
    this.onTap,
  }) : super(key: key);

  @override
  State<MediaDiscoverCard> createState() => _MediaDiscoverCardState();
}

class _MediaDiscoverCardState extends State<MediaDiscoverCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: ()  => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Hero(
          tag: 'card_${widget.title}',
          child: Container(
            height: 420,
            margin: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color:       Colors.black.withOpacity(0.4),
                  blurRadius:  20,
                  offset:      const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(children: [
                // Background image
                CachedNetworkImage(
                  imageUrl:  widget.mediaUrl,
                  fit:       BoxFit.cover,
                  width:     double.infinity,
                  height:    double.infinity,
                  placeholder: (_, __) => const ShimmerBox(
                    width: double.infinity, height: 420, radius: 28),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A2E),
                    child: const Icon(Icons.image_outlined,
                      color: Colors.white12, size: 48)),
                ),

                // Gradient overlay
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      stops:  [0.0, 0.4, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xDD000000),
                      ],
                    ),
                  ),
                ),

                // Live indicator
                if (widget.isLive)
                  const Positioned(
                    top: 18, right: 18,
                    child: LivePulseIndicator()),

                // Category chip top-left
                Positioned(
                  top: 18, left: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:        Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(color: Colors.white12)),
                    child: Text(
                      widget.category.toUpperCase(),
                      style: const TextStyle(
                        color:       Color(0xFF2196F3),
                        fontSize:    10,
                        fontWeight:  FontWeight.w800,
                        letterSpacing: 1)),
                  ),
                ),

                // Bottom info
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author row
                        if (widget.authorName != null)
                          Row(children: [
                            if (widget.authorAvatar != null)
                              Container(
                                width: 28, height: 28,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white24, width: 1)),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: widget.authorAvatar!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                      Container(color: const Color(0xFF1A1A2E)),
                                  ),
                                ),
                              ),
                            Text(widget.authorName!,
                              style: const TextStyle(
                                color:      Colors.white70,
                                fontSize:   12,
                                fontWeight: FontWeight.w500)),
                          ]),
                        const SizedBox(height: 6),
                        Text(widget.title,
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   20,
                            fontWeight: FontWeight.w800,
                            height:     1.2)),
                        const SizedBox(height: 12),
                        // Stats row
                        Row(children: [
                          _StatChip(
                            icon:  Icons.remove_red_eye_outlined,
                            label: _fmtCount(widget.viewCount)),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () =>
                              setState(() => _liked = !_liked),
                            child: _StatChip(
                              icon:  _liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                              label: _fmtCount(
                                widget.likeCount + (_liked ? 1 : 0)),
                              color: _liked
                                ? const Color(0xFFFF6B6B) : null),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.white.withOpacity(0.12),
                              border: Border.all(
                                color: Colors.white24, width: 0.5)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_outlined,
                                  color: Colors.white70, size: 14),
                                SizedBox(width: 5),
                                Text('Share',
                                  style: TextStyle(
                                    color:      Colors.white70,
                                    fontSize:   12,
                                    fontWeight: FontWeight.w600)),
                              ]),
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
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _StatChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: color ?? Colors.white54, size: 14),
    const SizedBox(width: 4),
    Text(label,
      style: TextStyle(
        color:      color ?? Colors.white54,
        fontSize:   12,
        fontWeight: FontWeight.w500)),
  ]);
}

// ── Skeleton loader card ──────────────────────────────────────────────────────
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
