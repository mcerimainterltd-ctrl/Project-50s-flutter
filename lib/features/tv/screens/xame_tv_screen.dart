// lib/features/tv/screens/xame_tv_screen.dart
// XameTV — Ultramodern multi-channel live TV for XamePage 2.1
// Features: channel guide, HLS streaming, vertical swipe, overlay info,
//           channel list sheet, error recovery, volume/fullscreen controls

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../data/tv_channels.dart';

class XameTvScreen extends StatefulWidget {
  const XameTvScreen({Key? key}) : super(key: key);
  @override
  State<XameTvScreen> createState() => _XameTvScreenState();
}

class _XameTvScreenState extends State<XameTvScreen>
    with TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────
  String        _category        = kTvCategories.first;
  int           _channelIndex    = 0;
  bool          _showOverlay     = true;
  bool          _showChannelList = false;
  bool          _isMuted         = false;
  bool          _isFullscreen    = false;
  Timer?        _overlayTimer;

  // ── Player ─────────────────────────────────────────────────────────────
  VideoPlayerController? _ctrl;
  bool _playerReady   = false;
  bool _playerError   = false;
  bool _playerLoading = true;
  int  _retryCount    = 0;

  // ── Animations ─────────────────────────────────────────────────────────
  late AnimationController _overlayAnim;
  late AnimationController _channelSwitchAnim;
  late Animation<double>   _overlayFade;
  late Animation<Offset>   _channelSlide;

  List<TvChannel> get _channels => channelsForCategory(_category);
  TvChannel get _current =>
      _channels.isNotEmpty ? _channels[_channelIndex % _channels.length]
                           : kTvChannels.first;

  @override
  void initState() {
    super.initState();
    _overlayAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _channelSwitchAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _overlayFade = CurvedAnimation(
        parent: _overlayAnim, curve: Curves.easeInOut);
    _channelSlide = Tween<Offset>(
        begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _channelSwitchAnim, curve: Curves.easeOut));
    _overlayAnim.forward();
    _initPlayer(_current.streamUrl);
    _startOverlayTimer();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _overlayAnim.dispose();
    _channelSwitchAnim.dispose();
    _ctrl?.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  // ── Player lifecycle ───────────────────────────────────────────────────
  Future<void> _initPlayer(String url) async {
    await _ctrl?.dispose();
    if (!mounted) return;
    setState(() {
      _playerReady   = false;
      _playerError   = false;
      _playerLoading = true;
    });

    if (url.isEmpty) {
      setState(() { _playerError = true; _playerLoading = false; });
      return;
    }

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _ctrl = ctrl;

    try {
      await ctrl.initialize();
      if (!mounted || _ctrl != ctrl) return;
      ctrl.setLooping(true);
      ctrl.setVolume(_isMuted ? 0 : 1);
      ctrl.play();
      _channelSwitchAnim.forward(from: 0);
      setState(() {
        _playerReady   = true;
        _playerLoading = false;
        _retryCount    = 0;
      });
    } catch (e) {
      if (!mounted || _ctrl != ctrl) return;
      setState(() { _playerError = true; _playerLoading = false; });
    }
  }

  void _retryPlayer() {
    if (_retryCount >= 3) return;
    _retryCount++;
    _initPlayer(_current.streamUrl);
  }

  void _switchChannel(TvChannel ch) {
    final idx = _channels.indexOf(ch);
    if (idx == _channelIndex) return;
    setState(() { _channelIndex = idx; });
    _initPlayer(ch.streamUrl);
    _showOverlayBriefly();
  }

  void _changeCategory(String cat) {
    if (cat == _category) return;
    setState(() {
      _category     = cat;
      _channelIndex = 0;
    });
    _initPlayer(_channels.isNotEmpty ? _channels.first.streamUrl : '');
    _showOverlayBriefly();
  }

  void _nextChannel() {
    if (_channels.isEmpty) return;
    setState(() { _channelIndex = (_channelIndex + 1) % _channels.length; });
    _initPlayer(_current.streamUrl);
    _showOverlayBriefly();
  }

  void _prevChannel() {
    if (_channels.isEmpty) return;
    setState(() {
      _channelIndex = (_channelIndex - 1 + _channels.length) % _channels.length;
    });
    _initPlayer(_current.streamUrl);
    _showOverlayBriefly();
  }

  // ── Overlay management ─────────────────────────────────────────────────
  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _overlayAnim.reverse();
        setState(() => _showOverlay = false);
      }
    });
  }

  void _showOverlayBriefly() {
    setState(() => _showOverlay = true);
    _overlayAnim.forward();
    _startOverlayTimer();
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _overlayTimer?.cancel();
      _overlayAnim.reverse();
      setState(() => _showOverlay = false);
    } else {
      _showOverlayBriefly();
    }
  }

  // ── Fullscreen ─────────────────────────────────────────────────────────
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ── Volume ─────────────────────────────────────────────────────────────
  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _ctrl?.setVolume(_isMuted ? 0 : 1);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        onVerticalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          if (d.primaryVelocity! < -300) _nextChannel();
          if (d.primaryVelocity! >  300) _prevChannel();
        },
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity == null) return;
          // Horizontal swipe opens channel list
          if (d.primaryVelocity! > 300) {
            setState(() => _showChannelList = true);
            _showOverlayBriefly();
          }
        },
        onLongPress: () {
          setState(() => _showChannelList = true);
          _showOverlayBriefly();
        },
        child: Stack(fit: StackFit.expand, children: [

          // ── Video layer ──────────────────────────────────────────────
          _buildVideoLayer(),

          // ── Loading / Error state ────────────────────────────────────
          if (_playerLoading) _buildLoadingState(),
          if (_playerError && !_playerLoading) _buildErrorState(),

          // ── Gradient overlay ─────────────────────────────────────────
          _buildGradient(),

          // ── Top bar (category selector + channel info) ───────────────
          FadeTransition(
            opacity: _overlayFade,
            child: Column(children: [
              _buildTopBar(),
              _buildCategoryStrip(),
            ]),
          ),

          // ── Bottom bar (channel info + controls) ─────────────────────
          FadeTransition(
            opacity: _overlayFade,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomBar(),
            ),
          ),

          // ── Channel swipe hint ───────────────────────────────────────
          if (_showOverlay) _buildSwipeHint(),

          // ── Channel list panel ───────────────────────────────────────
          if (_showChannelList) _buildChannelListPanel(),
        ]),
      ),
    );
  }

  // ── Video layer ─────────────────────────────────────────────────────────
  Widget _buildVideoLayer() {
    if (!_playerReady || _ctrl == null) {
      // Poster image while loading
      return CachedNetworkImage(
        imageUrl: _current.logo,
        fit: BoxFit.contain,
        color: Colors.black54,
        colorBlendMode: BlendMode.darken,
        errorWidget: (_, __, ___) => Container(color: Colors.black),
      );
    }
    return SlideTransition(
      position: _channelSlide,
      child: Center(
        child: AspectRatio(
          aspectRatio: _ctrl!.value.aspectRatio > 0
              ? _ctrl!.value.aspectRatio : 16 / 9,
          child: VideoPlayer(_ctrl!),
        ),
      ),
    );
  }

  // ── Loading state ────────────────────────────────────────────────────────
  Widget _buildLoadingState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 48, height: 48,
        child: CircularProgressIndicator(
          color: kCategoryColors[_category] ?? Colors.white,
          strokeWidth: 2,
        ),
      ),
      const SizedBox(height: 12),
      Text('Loading ${_current.name}...',
          style: const TextStyle(color: Colors.white60, fontSize: 13)),
    ]),
  );

  // ── Error state ──────────────────────────────────────────────────────────
  Widget _buildErrorState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.signal_wifi_connected_no_internet_4_rounded,
          color: Colors.white30, size: 56),
      const SizedBox(height: 12),
      Text('Stream unavailable', style: const TextStyle(
          color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(_current.name, style: const TextStyle(
          color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 20),
      if (_retryCount < 3)
        GestureDetector(
          onTap: _retryPlayer,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text('Retry', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      if (_retryCount >= 3) ...[
        const Text('Try another channel', style: TextStyle(
            color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _nextChannel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: (kCategoryColors[_category] ?? Colors.blue).withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Next Channel', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ]),
  );

  // ── Gradient ─────────────────────────────────────────────────────────────
  Widget _buildGradient() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.25, 0.65, 1.0],
        colors: [
          Color(0xCC000000),
          Colors.transparent,
          Colors.transparent,
          Color(0xDD000000),
        ],
      ),
    ),
  );

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 12),

        // XameTV logo
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                kCategoryColors[_category] ?? Colors.blue,
                (kCategoryColors[_category] ?? Colors.blue).withOpacity(0.6),
              ]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.live_tv_rounded, color: Colors.white, size: 14),
              SizedBox(width: 4),
              Text('XAME TV', style: TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
          ),
          const SizedBox(width: 8),
          // LIVE badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('LIVE', style: TextStyle(
                color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        ]),

        const Spacer(),

        // Mute button
        GestureDetector(
          onTap: () { _toggleMute(); _showOverlayBriefly(); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: Colors.black45, shape: BoxShape.circle,
                border: Border.all(color: Colors.white24)),
            child: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(width: 8),

        // Fullscreen button
        GestureDetector(
          onTap: () { _toggleFullscreen(); _showOverlayBriefly(); },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: Colors.black45, shape: BoxShape.circle,
                border: Border.all(color: Colors.white24)),
            child: Icon(
              _isFullscreen ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
              color: Colors.white, size: 20),
          ),
        ),
      ]),
    ),
  );

  // ── Category strip ────────────────────────────────────────────────────────
  Widget _buildCategoryStrip() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kTvCategories.length,
        itemBuilder: (_, i) {
          final cat   = kTvCategories[i];
          final isActive = cat == _category;
          final color = kCategoryColors[cat] ?? Colors.blue;
          return GestureDetector(
            onTap: () => _changeCategory(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? color : Colors.black45,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: isActive ? color : Colors.white24,
                    width: isActive ? 0 : 1),
              ),
              child: Text(cat, style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        },
      ),
    ),
  );

  // ── Bottom bar ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    child: SafeArea(
      top: false,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Channel logo
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: CachedNetworkImage(
              imageUrl: _current.logo, fit: BoxFit.contain,
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  _current.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Channel info
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (_current.isHD) Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('HD', style: TextStyle(
                    color: Colors.white, fontSize: 8,
                    fontWeight: FontWeight.w800)),
              ),
              Text(_current.name, style: const TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 2),
            Text(_current.description, style: const TextStyle(
                color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 2),
            Text('${_current.country} · ${_current.language}',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        )),

        // Channel counter + list button
        Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () {
              setState(() => _showChannelList = true);
              _showOverlayBriefly();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.list_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${_channelIndex + 1}/${_channels.length}',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ]),
    ),
  );

  // ── Swipe hint ────────────────────────────────────────────────────────────
  Widget _buildSwipeHint() => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.keyboard_arrow_up_rounded,
            color: Colors.white38, size: 18),
        const SizedBox(height: 2),
        const Text('Swipe', style: TextStyle(
            color: Colors.white30, fontSize: 9)),
        const SizedBox(height: 2),
        const Icon(Icons.keyboard_arrow_down_rounded,
            color: Colors.white38, size: 18),
      ]),
    ),
  );

  // ── Channel list panel ────────────────────────────────────────────────────
  Widget _buildChannelListPanel() => GestureDetector(
    onTap: () => setState(() => _showChannelList = false),
    child: Container(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () {}, // prevent close on panel tap
          child: Container(
            width: MediaQuery.of(context).size.width * 0.72,
            color: const Color(0xFF0D0D0D),
            child: Column(children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Text(_category, style: TextStyle(
                        color: kCategoryColors[_category] ?? Colors.blue,
                        fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _showChannelList = false),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white54, size: 20),
                    ),
                  ]),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _channels.length,
                  itemBuilder: (_, i) {
                    final ch = _channels[i];
                    final isActive = i == _channelIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _showChannelList = false);
                        _switchChannel(ch);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (kCategoryColors[_category] ?? Colors.blue)
                                  .withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? (kCategoryColors[_category] ?? Colors.blue)
                                    .withOpacity(0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(children: [
                          // Channel logo
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: ch.logo, fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(ch.name[0],
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(ch.name,
                                      style: TextStyle(
                                          color: isActive ? Colors.white : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: isActive
                                              ? FontWeight.w700
                                              : FontWeight.w400),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (ch.isHD) Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('HD', style: TextStyle(
                                      color: Colors.white60, fontSize: 7,
                                      fontWeight: FontWeight.w700)),
                                ),
                              ]),
                              Text(ch.country, style: const TextStyle(
                                  color: Colors.white30, fontSize: 10)),
                            ],
                          )),
                          if (isActive)
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: kCategoryColors[_category] ?? Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
