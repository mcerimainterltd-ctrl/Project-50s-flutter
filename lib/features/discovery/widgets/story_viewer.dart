import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/config/constants.dart';

// ── Story Viewer ──────────────────────────────────────────────────────────────
// Full-screen immersive story viewer with progress bars, auto-advance,
// tap navigation, swipe-down dismiss, and server-side seen tracking.

class StoryViewerScreen extends StatefulWidget {
  final List<StoryGroup> groups;
  final int              initialGroupIndex;
  final String           currentUserId;

  const StoryViewerScreen({
    Key? key,
    required this.groups,
    required this.initialGroupIndex,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int    _groupIndex;
  late int    _storyIndex;
  late AnimationController _progressCtrl;
  Timer?      _timer;
  bool        _paused    = false;
  bool        _dragging  = false;
  double      _dragStart = 0;

  static const _storyDuration = Duration(seconds: 5);

  StoryGroup get _currentGroup => widget.groups[_groupIndex];
  StoryData  get _currentStory =>
      _currentGroup.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;
    _progressCtrl = AnimationController(
        vsync: this, duration: _storyDuration);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _nextStory();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _startStory();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startStory() {
    _progressCtrl.forward(from: 0);
    _markSeen();
  }

  void _markSeen() {
    final storyId = _currentStory.storyId;
    if (storyId.isNotEmpty && widget.currentUserId.isNotEmpty) {
      Dio(BaseOptions(baseUrl: AppConstants.serverUrl))
        .post('/api/discover/story/seen', data: {
          'userId':  widget.currentUserId,
          'storyId': storyId,
        }).catchError((_) {});
    }
  }

  void _nextStory() {
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      _startStory();
    } else {
      _nextGroup();
    }
  }

  void _prevStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startStory();
    } else {
      _prevGroup();
    }
  }

  void _nextGroup() {
    if (_groupIndex < widget.groups.length - 1) {
      setState(() { _groupIndex++; _storyIndex = 0; });
      _startStory();
    } else {
      _dismiss();
    }
  }

  void _prevGroup() {
    if (_groupIndex > 0) {
      setState(() { _groupIndex--; _storyIndex = 0; });
      _startStory();
    }
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  void _pause() {
    if (!_paused) {
      _progressCtrl.stop();
      setState(() => _paused = true);
    }
  }

  void _resume() {
    if (_paused) {
      _progressCtrl.forward();
      setState(() => _paused = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown:    (_) => _pause(),
        onTapUp:      (d) {
          _resume();
          // Left 35% → prev, Right 35% → next, Middle → pause/resume
          final x = d.globalPosition.dx;
          if (x < size.width * 0.35) {
            _prevStory();
          } else if (x > size.width * 0.65) {
            _nextStory();
          }
        },
        onVerticalDragStart: (d) {
          _pause();
          _dragStart = d.globalPosition.dy;
          setState(() => _dragging = true);
        },
        onVerticalDragUpdate: (d) {
          final delta = d.globalPosition.dy - _dragStart;
          if (delta > 80) _dismiss();
        },
        onVerticalDragEnd: (_) {
          setState(() => _dragging = false);
          _resume();
        },
        child: AnimatedOpacity(
          opacity: _dragging ? 0.7 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Stack(fit: StackFit.expand, children: [
            // ── Story media ─────────────────────────────────────
            _StoryMedia(story: _currentStory),

            // ── Gradient overlays ────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.topCenter,
                  end:    Alignment.bottomCenter,
                  stops:  [0.0, 0.25, 0.75, 1.0],
                  colors: [
                    Color(0xCC000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xAA000000),
                  ],
                ),
              ),
            ),

            // ── Progress bars ─────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12, right: 12,
              child: Row(
                children: List.generate(
                  _currentGroup.stories.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: i < _storyIndex
                          // Fully watched
                          ? Container(color: Colors.white)
                          : i == _storyIndex
                            // Currently playing
                            ? AnimatedBuilder(
                                animation: _progressCtrl,
                                builder: (_, __) => LinearProgressIndicator(
                                  value:            _progressCtrl.value,
                                  backgroundColor:  Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation(
                                      Colors.white),
                                  minHeight: 2.5,
                                ),
                              )
                            // Not yet watched
                            : Container(color: Colors.white30),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Author header ─────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 28,
              left: 16, right: 16,
              child: Row(children: [
                // Avatar
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                  child: ClipOval(
                    child: _currentGroup.authorAvatar.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _currentGroup.authorAvatar,
                          fit:      BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                            Container(color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.person,
                                  color: Colors.white38, size: 20)))
                      : Container(color: const Color(0xFF1A1A2E),
                          child: const Icon(Icons.person,
                              color: Colors.white38, size: 20)),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + time
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentGroup.authorName,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   14,
                        fontWeight: FontWeight.w700)),
                    Text(_timeAgo(_currentStory.ts),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11)),
                  ],
                )),
                // Pause indicator
                if (_paused)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        Colors.black45,
                      borderRadius: BorderRadius.circular(8)),
                    child: const Text('PAUSED',
                      style: TextStyle(color: Colors.white60,
                          fontSize: 9, letterSpacing: 1)),
                  ),
                const SizedBox(width: 8),
                // Close
                GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black38),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 18)),
                ),
              ]),
            ),

            // ── Story group navigation dots ───────────────────────
            if (widget.groups.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.groups.length, (i) =>
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width:  i == _groupIndex ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _groupIndex
                          ? Colors.white : Colors.white30),
                    )
                  ),
                ),
              ),

            // ── Tap zones (visual hint on first open) ─────────────
            Positioned(
              left: 0, top: 0, bottom: 0,
              width: size.width * 0.35,
              child: const SizedBox.expand()),
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: size.width * 0.35,
              child: const SizedBox.expand()),
          ]),
        ),
      ),
    );
  }

  String _timeAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Story media widget ────────────────────────────────────────────────────────
class _StoryMedia extends StatelessWidget {
  final StoryData story;
  const _StoryMedia({required this.story});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: story.mediaType == 'video'
        ? _VideoStory(key: ValueKey(story.storyId), url: story.mediaUrl)
        : CachedNetworkImage(
            key:       ValueKey(story.storyId),
            imageUrl:  story.mediaUrl,
            fit:       BoxFit.cover,
            width:     double.infinity,
            height:    double.infinity,
            placeholder: (_, __) => Container(
              color: context.xBg,
              child: const Center(child: CircularProgressIndicator(
                  color: Colors.white30, strokeWidth: 1.5))),
            errorWidget: (_, __, ___) => Container(
              color: context.xBg,
              child: const Icon(Icons.broken_image,
                  color: Colors.white24, size: 48)),
          ),
    );
  }
}

// ── Video story placeholder ───────────────────────────────────────────────────
class _VideoStory extends StatelessWidget {
  final String url;
  const _VideoStory({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black,
    child: const Center(child: Icon(Icons.play_circle_outline,
        color: Colors.white38, size: 64)),
  );
}

// ── Data models ───────────────────────────────────────────────────────────────
class StoryGroup {
  final String          authorId;
  final String          authorName;
  final String          authorAvatar;
  final List<StoryData> stories;

  const StoryGroup({
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.stories,
  });

  factory StoryGroup.fromMap(Map<String, dynamic> m) {
    final storiesRaw = m['stories'] as List? ?? [];
    return StoryGroup(
      authorId:     m['authorId']     as String? ?? '',
      authorName:   m['authorName']   as String? ?? '',
      authorAvatar: m['authorAvatar'] as String? ?? '',
      stories: storiesRaw.map((s) =>
        StoryData.fromMap(Map<String, dynamic>.from(s))).toList(),
    );
  }
}

class StoryData {
  final String   storyId;
  final String   mediaUrl;
  final String   mediaType;
  final bool     seen;
  final DateTime ts;

  const StoryData({
    required this.storyId,
    required this.mediaUrl,
    required this.mediaType,
    required this.seen,
    required this.ts,
  });

  factory StoryData.fromMap(Map<String, dynamic> m) => StoryData(
    storyId:   m['storyId']   as String? ?? '',
    mediaUrl:  m['mediaUrl']  as String? ?? '',
    mediaType: m['mediaType'] as String? ?? 'image',
    seen:      m['seen']      as bool?   ?? false,
    ts: m['ts'] != null
      ? DateTime.tryParse(m['ts'].toString()) ?? DateTime.now()
      : DateTime.now(),
  );
}
