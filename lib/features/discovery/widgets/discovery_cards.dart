import 'dart:ui';

import 'dart:convert';
import 'package:http/http.dart' as http;import 'package:better_player_enhanced/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/config/constants.dart';
import 'live_pulse.dart';
import 'comments_sheet.dart';
import 'package:xamepage/core/theme/app_theme.dart';

// ── Pulse Posts ──────────────────────────────────────────────────────────────
// Engagement velocity: total interactions per hour since post was created
// Returns 0.0 (dead) → 1.0 (viral)
double _pulseVelocity(DateTime ts, int views, int likes, int comments) {
  final ageHours = DateTime.now().difference(ts).inMinutes / 60.0;
  if (ageHours < 0.1) return 0.8; // brand new post
  final velocity = (views + (likes * 3) + (comments * 5)) / (ageHours * 10);
  return velocity.clamp(0.0, 1.0);
}

Color _pulseColor(double v) {
  if (v >= 0.7) return const Color(0xFFFF5722); // viral — fire orange
  if (v >= 0.4) return const Color(0xFFFFB300); // trending — gold
  if (v >= 0.15) return const Color(0xFF29B6F6); // active — blue
  return const Color(0xFF37474F);                // fading — grey
}

class _PulseArcPainter extends CustomPainter {
  final double velocity;
  final double animValue;
  _PulseArcPainter(this.velocity, this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    if (velocity < 0.02) return; // draw for almost all posts
    final color = _pulseColor(velocity);
    final rect  = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    final radius = 28.0;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Background track — subtle
    canvas.drawRRect(rrect, Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0);

    final sweep = 2 * 3.14159 * velocity;
    final startAngle = -3.14159 / 2 + (animValue * 0.4);

    // Outer glow layer 1 — widest, most transparent
    canvas.drawArc(
      rect.inflate(2),
      startAngle, sweep, false,
      Paint()
        ..color = color.withOpacity(0.15 + animValue * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Outer glow layer 2 — medium
    canvas.drawArc(
      rect.inflate(1),
      startAngle, sweep, false,
      Paint()
        ..color = color.withOpacity(0.25 + animValue * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Core arc — sharp and bright
    canvas.drawArc(
      rect, startAngle, sweep, false,
      Paint()
        ..color = color.withOpacity(0.85 + animValue * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round,
    );

    // Pulse dot at arc tip — glowing
    if (velocity >= 0.05) {
      final angle = startAngle + sweep;
      final cx = rect.center.dx + (rect.width / 2) * _cos(angle);
      final cy = rect.center.dy + (rect.height / 2) * _sin(angle);
      // Outer glow dot
      canvas.drawCircle(
          Offset(cx, cy), 8 + animValue * 3,
          Paint()
            ..color = color.withOpacity(0.2 + animValue * 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      // Core dot
      canvas.drawCircle(
          Offset(cx, cy), 4.5 + animValue * 2,
          Paint()..color = color.withOpacity(0.9 + animValue * 0.1));
      // White hot center
      canvas.drawCircle(
          Offset(cx, cy), 2.0,
          Paint()..color = Colors.white.withOpacity(0.8 + animValue * 0.2));
    }
  }

  double _cos(double a) => a == 0 ? 1 : (a > 0
      ? (1 - a * a / 2 + a * a * a * a / 24)
      : _cos(-a));
  double _sin(double a) {
    // Simple Taylor approximation good enough for small angles
    double x = a % (2 * 3.14159);
    return x - x*x*x/6 + x*x*x*x*x/120;
  }

  @override
  bool shouldRepaint(_PulseArcPainter old) =>
      old.velocity != velocity || old.animValue != animValue;
}

// ── XameScore ────────────────────────────────────────────────────────────────
// Score = engagement quality ratio (likes+comments per view)
// Gold ≥ 0.15 · Silver ≥ 0.07 · Bronze ≥ 0.02 · None below
({String emoji, Color color, String label})? _xameScore(int views, int likes, int comments) {
  if (views < 3) return null;
  final ratio = (likes + comments) / views;
  if (ratio >= 0.15) return (emoji: '👑', color: const Color(0xFFFFB300), label: 'Gold');
  if (ratio >= 0.07) return (emoji: '⭐', color: const Color(0xFFB0BEC5), label: 'Silver');
  if (ratio >= 0.02) return (emoji: '🥉', color: const Color(0xFFBF6B3A), label: 'Bronze');
  return null;
}

// ── Aura Reactions ───────────────────────────────────────────────────────────
enum AuraType { fire, ice, energy, love, crown, wave }

const _auraEmoji  = { AuraType.fire:'🔥', AuraType.ice:'❄️', AuraType.energy:'⚡', AuraType.love:'💜', AuraType.crown:'👑', AuraType.wave:'🌊' };
const _auraLabel  = { AuraType.fire:'Fire', AuraType.ice:'Ice', AuraType.energy:'Energy', AuraType.love:'Love', AuraType.crown:'Crown', AuraType.wave:'Wave' };
const _auraColor  = {
  AuraType.fire:   Color(0xFFFF5722),
  AuraType.ice:    Color(0xFF29B6F6),
  AuraType.energy: Color(0xFFFFD600),
  AuraType.love:   Color(0xFFCE93D8),
  AuraType.crown:  Color(0xFFFFB300),
  AuraType.wave:   Color(0xFF26C6DA),
};

// ── Media Discover Card ───────────────────────────────────────────────────────
class MediaDiscoverCard extends StatefulWidget {
  final String  mediaUrl;
  final String  mediaType;
  final String  title;
  final String  category;
  final bool    isLive;
  final String? authorName;
  final String? authorAvatar;
  final int     viewCount;
  final int     likeCount;
  final int     commentCount;
  final String  postId;
  final String  userId;
  final String  userAvatar;
  final String  userName;
  final String? thumbnailUrl;
  final String? authorId;
  final VoidCallback? onTap;
  final void Function(int)? onCountChanged;
  final DateTime? ts;
  final bool isWhisper;
  final bool   isCollabOpen;
  final String collabStatus;
  final String collabPartnerId;
  final String collabPartnerName;
  final String collabPartnerAvatar;
  final String collabMediaUrl;
  final String collabMediaType;

  const MediaDiscoverCard({
    Key? key,
    required this.mediaUrl,
    this.mediaType   = 'image',
    required this.title,
    required this.category,
    this.isLive      = false,
    this.authorName,
    this.authorAvatar,
    this.viewCount   = 0,
    this.likeCount   = 0,
    this.commentCount = 0,
    this.postId      = '',
    this.userId      = '',
    this.userAvatar  = '',
    this.userName    = '',
    this.authorId,
    this.thumbnailUrl,
    this.onTap,
    this.onCountChanged,
    this.ts,
    this.isWhisper           = false,
    this.isCollabOpen        = false,
    this.collabStatus        = 'none',
    this.collabPartnerId     = '',
    this.collabPartnerName   = '',
    this.collabPartnerAvatar = '',
    this.collabMediaUrl      = '',
    this.collabMediaType     = 'image',
  }) : super(key: key);

  @override
  State<MediaDiscoverCard> createState() => _MediaDiscoverCardState();
}

class _MediaDiscoverCardState extends State<MediaDiscoverCard>
    with TickerProviderStateMixin {
  late AnimationController _tapCtrl;
  late Animation<double>   _tapScale;
  late AnimationController _likeCtrl;
  late Animation<double>   _likeScale;
  bool _liked = false;
  bool _playing = false;
  late int _commentCount;
  BetterPlayerController? _playerCtrl;
  AuraType? _myAura;
  bool _showAuraPicker = false;
  late AnimationController _auraPickerCtrl;
  late Animation<double> _auraPickerScale;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  void _playVideo() {
    _playerCtrl?.dispose();
    _playerCtrl = null;
    final ctrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        aspectRatio: 16 / 9,
        fit: BoxFit.cover,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enableMute: true,
          enablePlayPause: true,
          enableProgressBar: true,
          enableSkips: false,
          controlBarColor: Colors.black54,
          iconsColor: Colors.white,
          progressBarPlayedColor: XameColors.primary,
          progressBarHandleColor: XameColors.primary,
          progressBarBackgroundColor: Colors.white24,
          controlsHideTime: Duration(seconds: 5),
        ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
          BetterPlayerDataSourceType.network, widget.mediaUrl),
    );
    setState(() { _playerCtrl = ctrl; _playing = true; });
  }

  static const _boxName = 'xame_discovery_likes';

  @override
  void initState() {
    super.initState();
    _commentCount = widget.commentCount;
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
    _auraPickerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _auraPickerScale = CurvedAnimation(
        parent: _auraPickerCtrl, curve: Curves.easeOutBack);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _loadAura();
  }

  Future<void> _loadLike() async {
    try {
      final box = await Hive.openBox<bool>(_boxName);
      if (mounted) setState(() => _liked = box.get(widget.postId.isNotEmpty ? widget.postId : widget.title) ?? false);
    } catch (_) {}
  }

  Future<void> _loadAura() async {
    try {
      final box = await Hive.openBox<String>('xame_auras');
      final stored = box.get(widget.postId.isNotEmpty ? widget.postId : widget.title);
      if (stored != null && mounted) {
        setState(() => _myAura = AuraType.values.firstWhere(
            (a) => a.name == stored, orElse: () => AuraType.fire));
      }
    } catch (_) {}
  }

  Future<void> _selectAura(AuraType aura) async {
    HapticFeedback.mediumImpact();
    setState(() { _myAura = aura; _showAuraPicker = false; _liked = true; });
    _auraPickerCtrl.reverse();
    _likeCtrl.forward(from: 0);
    // Persist locally
    try {
      final box = await Hive.openBox<String>('xame_auras');
      await box.put(widget.postId.isNotEmpty ? widget.postId : widget.title, aura.name);
      final likeBox = await Hive.openBox<bool>('xame_discovery_likes');
      await likeBox.put(widget.postId.isNotEmpty ? widget.postId : widget.title, true);
    } catch (_) {}
    // Sync to server
    if (widget.postId.isNotEmpty && widget.userId.isNotEmpty) {
      try {
        final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
        await dio.post('/api/discover/like',
            data: {'userId': widget.userId, 'postId': widget.postId, 'aura': aura.name});
      } catch (_) {}
    }
    widget.onCountChanged?.call(widget.likeCount + 1);
  }

  OverlayEntry? _auraOverlay;

  void _removeAuraOverlay() {
    _auraOverlay?.remove();
    _auraOverlay = null;
  }

  void _showAuraOverlay(BuildContext context) {
    HapticFeedback.lightImpact();
    _removeAuraOverlay();

    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? Size.zero;

    _auraOverlay = OverlayEntry(
      builder: (_) => Stack(children: [
        // Dismiss tap area
        Positioned.fill(
          child: GestureDetector(
            onTap: _removeAuraOverlay,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Picker positioned above the tap point
        Positioned(
          left: pos.dx,
          top:  pos.dy - 70,
          child: ScaleTransition(
            scale: _auraPickerScale,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(
                      color: Colors.black54, blurRadius: 20,
                      offset: Offset(0, 6))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: AuraType.values.map((aura) =>
                    GestureDetector(
                      onTap: () {
                        _removeAuraOverlay();
                        _selectAura(aura);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _myAura == aura
                              ? _auraColor[aura]!.withOpacity(0.3)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(_auraEmoji[aura]!,
                            style: TextStyle(
                                fontSize: _myAura == aura ? 24 : 20)),
                      ),
                    ),
                  ).toList(),
                ),
              ),
            ),
          ),
        ),
      ]),
    );

    _auraPickerCtrl.forward(from: 0);
    overlay.insert(_auraOverlay!);
  }

  void _toggleAuraPicker() {
    if (_auraOverlay != null) {
      _removeAuraOverlay();
    }
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();
    final next = !_liked;
    setState(() => _liked = next);
    _likeCtrl.forward(from: 0);
    // Persist locally
    try {
      final box = await Hive.openBox<bool>(_boxName);
      await box.put(widget.postId.isNotEmpty ? widget.postId : widget.title, next);
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
    _auraPickerCtrl.dispose();
    _pulseCtrl.dispose();
    _removeAuraOverlay();
    _playerCtrl?.dispose();
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
              border: _myAura != null ? Border.all(
                color: _auraColor[_myAura]!.withOpacity(0.6),
                width: 1.5,
              ) : null,
              boxShadow: [
                BoxShadow(
                  color: _myAura != null
                      ? _auraColor[_myAura]!.withOpacity(0.35)
                      : Colors.black.withOpacity(0.45),
                  blurRadius: _myAura != null ? 32 : 24,
                  offset: const Offset(0, 10)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(fit: StackFit.expand, children: [
                // Media — split screen for accepted collabs
                if (widget.collabStatus == 'accepted' && widget.collabMediaUrl.isNotEmpty)
                  Row(children: [
                    Expanded(child: SizedBox.expand(
                      child: CachedNetworkImage(
                          imageUrl: widget.mediaUrl, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A1A2E))),
                    )),
                    Container(width: 2, color: Colors.white24),
                    Expanded(child: SizedBox.expand(
                      child: CachedNetworkImage(
                          imageUrl: widget.collabMediaUrl, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A2E1A))),
                    )),
                  ])
                else if (widget.mediaType == 'video' && _playing && _playerCtrl != null)
                  BetterPlayer(controller: _playerCtrl!)
                else if (widget.mediaType == 'video')
                  GestureDetector(
                    onTap: _playVideo,
                    child: Stack(fit: StackFit.expand, children: [
                      CachedNetworkImage(
                        imageUrl: widget.thumbnailUrl?.isNotEmpty == true
                            ? widget.thumbnailUrl!
                            : widget.mediaUrl.replaceFirst('/upload/', '/upload/so_0/'),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: context.xSurface,
                          child: Icon(Icons.movie_outlined,
                              color: context.xMuted.withValues(alpha: 0.25), size: 48))),
                      Center(child: Container(
                        width: 64, height: 64,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40))),
                    ]),
                  )
                else
                  CachedNetworkImage(
                    imageUrl: widget.mediaUrl,
                    fit:      BoxFit.cover,
                    placeholder: (_, __) => ShimmerBox(
                        width: double.infinity,
                        height: 420,
                        radius: 28),
                    errorWidget: (_, __, ___) => Container(
                      color: context.xSurface,
                      child: Icon(Icons.image_outlined,
                          color: context.xMuted.withValues(alpha: 0.25), size: 48)),
                  ),

                // Gradient
                Container(
                  decoration: BoxDecoration(
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

                // Pulse arc — engagement velocity ring
                if (widget.ts != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => CustomPaint(
                          painter: _PulseArcPainter(
                            _pulseVelocity(widget.ts!, widget.viewCount,
                                widget.likeCount, widget.commentCount),
                            _pulseAnim.value,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Whisper blur overlay
                if (widget.isWhisper)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(fit: StackFit.expand, children: [
                        // Blur layer
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            color: Colors.black.withOpacity(0.35)),
                        ),
                        // Whisper badge
                        Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6A1B9A).withOpacity(0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFCE93D8)
                                        .withOpacity(0.4)),
                              ),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text('🤫', style: TextStyle(fontSize: 20)),
                                SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Whisper Post',
                                      style: TextStyle(
                                          color: Color(0xFFCE93D8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                    Text('Mutual contacts only',
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10)),
                                  ]),
                              ]),
                            ),
                          ],
                        )),
                      ]),
                    ),
                  ),

                // Live badge
                if (widget.isLive)
                  Positioned(
                      top: 18, right: 18,
                      child: LivePulseIndicator()),

                // Category chip
                Positioned(
                  top: 18, left: 18,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color:        Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.xMuted.withValues(alpha: 0.25))),
                      child: Text(widget.collabStatus == 'accepted'
                              ? 'COLLAB'
                              : widget.category.toUpperCase(),
                        style: TextStyle(
                          color: widget.collabStatus == 'accepted'
                              ? const Color(0xFF00E5FF)
                              : context.xPrimary,
                          fontSize:    10,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: 1.2)),
                    ),
                    if (widget.isCollabOpen && widget.collabStatus == 'none') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF00E5FF).withOpacity(0.5))),
                        child: const Text('🤝 OPEN',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
                      ),
                    ],
                  ]),
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
                                      color: context.xMuted.withValues(alpha: 0.3), width: 1)),
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
                              style: TextStyle(
                                  color:      context.xText.withValues(alpha: 0.6),
                                  fontSize:   12,
                                  fontWeight: FontWeight.w500)),
                            // XameScore badge
                            Builder(builder: (ctx) {
                              final score = _xameScore(
                                  widget.viewCount, widget.likeCount, widget.commentCount);
                              if (score == null) return const SizedBox.shrink();
                              return Tooltip(
                                message: '\${score.label} Creator',
                                child: Container(
                                  margin: const EdgeInsets.only(left: 5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: score.color.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: score.color.withOpacity(0.5), width: 0.8),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(score.emoji,
                                        style: const TextStyle(fontSize: 9)),
                                    const SizedBox(width: 2),
                                    Text(score.label,
                                      style: TextStyle(
                                        color: score.color,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3)),
                                  ]),
                                ),
                              );
                            }),
                            if (widget.authorId != null && widget.authorId != widget.userId)
                              _FollowButton(
                                authorId: widget.authorId!,
                                followerId: widget.userId,
                              ),
                          ]),
                        // Collab partner row
                        if (widget.collabStatus == 'accepted' &&
                            widget.collabPartnerName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              const Text('🤝',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              if (widget.collabPartnerAvatar.isNotEmpty)
                                Container(
                                  width: 20, height: 20,
                                  margin: const EdgeInsets.only(right: 5),
                                  child: ClipOval(child: CachedNetworkImage(
                                      imageUrl: widget.collabPartnerAvatar,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          Container(color: const Color(0xFF1A2E2E)))),
                                ),
                              Text(widget.collabPartnerName,
                                style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        SizedBox(height: 6),

                        // Title — hide for quotes (text is baked into the image)
                        if (widget.category.toUpperCase() != 'QUOTE')
                          Text(widget.title,
                            style: TextStyle(
                              color:      context.xText,
                              fontSize:   20,
                              fontWeight: FontWeight.w800,
                              height:     1.2)),
                        SizedBox(height: 12),

                        // Stats row
                        Row(children: [
                          // Views
                          Row(children: [
                            Icon(Icons.remove_red_eye_outlined,
                                color: context.xMuted, size: 14),
                            SizedBox(width: 4),
                            Text(_fmt(widget.viewCount),
                              style: TextStyle(
                                  color: context.xMuted, fontSize: 12)),
                          ]),
                          SizedBox(width: 14),

                          // Aura Reaction button
                          ScaleTransition(
                            scale: _likeScale,
                            child: GestureDetector(
                              onTap: () => _showAuraOverlay(context),
                              child: Row(children: [
                                _myAura != null
                                    ? Text(_auraEmoji[_myAura]!,
                                        style: const TextStyle(fontSize: 16))
                                    : Icon(Icons.auto_awesome_outlined,
                                        color: context.xMuted, size: 16),
                                const SizedBox(width: 4),
                                Text(_fmt(likeCount),
                                  style: TextStyle(
                                    color: _myAura != null
                                        ? _auraColor[_myAura]!
                                        : context.xMuted,
                                    fontSize: 12,
                                    fontWeight: _myAura != null
                                        ? FontWeight.w700
                                        : FontWeight.normal)),
                              ]),
                            ),
                          ),

                          SizedBox(width: 14),

                          // Comment button
                          GestureDetector(
                            onTap: () => _openComments(context),
                            child: Row(children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  color: context.xMuted, size: 15),
                              SizedBox(width: 4),
                              Text(_fmt(_commentCount),
                                style: TextStyle(
                                    color: context.xMuted, fontSize: 12)),
                            ]),
                          ),

                          Spacer(),

                          // Collab button — show if open and not own post
                          if (widget.isCollabOpen &&
                              widget.collabStatus == 'none' &&
                              widget.userId.isNotEmpty &&
                              widget.userId != widget.authorId) ...[
                            GestureDetector(
                              onTap: () => _requestCollab(context),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: const Color(0xFF00E5FF).withOpacity(0.12),
                                  border: Border.all(
                                      color: const Color(0xFF00E5FF).withOpacity(0.4),
                                      width: 0.8)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🤝', style: TextStyle(fontSize: 11)),
                                    SizedBox(width: 4),
                                    Text('Collab',
                                      style: TextStyle(
                                          color: Color(0xFF00E5FF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  ]),
                              ),
                            ),
                          ],

                          // Share
                          GestureDetector(
                            onTap: () => _sharePost(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: context.xText.withOpacity(0.1),
                                border: Border.all(
                                    color: context.xMuted.withValues(alpha: 0.5), width: 0.5)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.share_outlined,
                                      color: context.xText.withValues(alpha: 0.6), size: 13),
                                  SizedBox(width: 4),
                                  Text('Share',
                                    style: TextStyle(
                                        color:      context.xText.withValues(alpha: 0.6),
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

  void _openComments(BuildContext context) {
    HapticFeedback.lightImpact();
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
          postId:        widget.postId,
          userId:        widget.userId,
          authorName:    widget.userName,
          authorAvatar:  widget.userAvatar,
          initialCount:  _commentCount,
          onCountChanged: (n) { setState(() => _commentCount = n); widget.onCountChanged?.call(n); },
        ),
      ),
    );
  }

    Future<void> _requestCollab(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // Pick media for collab contribution
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Collab Request',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Text(
            'Send your media to collab with ${widget.authorName ?? 'this creator'}?',
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('Send 🤝',
                style: TextStyle(color: Colors.black,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('${AppConstants.serverUrl}/api/discover/collab/request'));
      req.fields['postId']     = widget.postId;
      req.fields['requesterId'] = widget.userId;
      req.fields['mediaType']  = 'image';
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

  Future<void> _sharePost(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final parts = <String>[];
    if (widget.title.isNotEmpty) parts.add(widget.title);
    if (widget.mediaUrl.isNotEmpty) parts.add(widget.mediaUrl);
    parts.add('Shared via XamePage');
    final text = parts.join('\n');
    await Share.share(text);
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
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)])),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.category.toUpperCase(),
                        style: TextStyle(
                          color:       XameColors.primary,
                          fontSize:    11,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: 1.2)),
                      SizedBox(height: 8),
                      Text(widget.title,
                        style: TextStyle(
                          color:      XameColors.darkBg,
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


// ── Follow Button ─────────────────────────────────────────────────────────────
class _FollowButton extends StatefulWidget {
  final String authorId;
  final String followerId;
  const _FollowButton({required this.authorId, required this.followerId});
  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _following = false;
  bool _loading   = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final r = await http.get(Uri.parse(
        AppConstants.serverUrl + '/api/discover/follow-status/' + widget.authorId + '?followerId=' + widget.followerId));
      final d = jsonDecode(r.body);
      if (mounted) setState(() { _following = d['isFollowing'] ?? false; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _toggle() async {
    final wasFollowing = _following;
    setState(() => _following = !_following);
    try {
      final endpoint = wasFollowing ? 'unfollow' : 'follow';
      await http.post(
        Uri.parse(AppConstants.serverUrl + '/api/discover/' + endpoint + '/' + widget.authorId),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'followerId': widget.followerId}),
      );
    } catch (_) { if (mounted) setState(() => _following = wasFollowing); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 12, height: 12,
      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54));
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _following ? Colors.white12 : const Color(0xFF00E5FF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _following ? Colors.white24 : const Color(0xFF00E5FF),
            width: 1),
        ),
        child: Text(
          _following ? 'Following' : '+ Follow',
          style: TextStyle(
            color: _following ? Colors.white54 : const Color(0xFF00E5FF),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

