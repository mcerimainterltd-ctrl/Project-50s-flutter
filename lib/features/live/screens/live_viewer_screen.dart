import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/live_api.dart';
import '../models/live_session.dart';
import '../providers/live_provider.dart';
import '../services/live_webrtc_service.dart';

class LiveViewerScreen extends ConsumerStatefulWidget {
  const LiveViewerScreen({
    super.key,
    required this.session,
  });

  final LiveSession session;

  @override
  ConsumerState<LiveViewerScreen> createState() =>
      _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  final LiveWebRTCService _webrtc = LiveWebRTCService();
  final RTCVideoRenderer _renderer = RTCVideoRenderer();

  bool _joining = true;
  bool _leaving = false;
  bool _left = false;
  bool _watchOnly = false;
  bool _participating = false;
  String _connectionStatus = 'Connecting…';

  @override
  void initState() {
    super.initState();
    _joinAndPlay();
  }

  Future<void> _joinAndPlay() async {
    try {
      await _renderer.initialize();

      LiveSession? session;

      try {
        session = await ref.read(liveProvider.notifier).joinLive(
              widget.session.sessionId,
            );

        if (session == null) {
          throw StateError(
            ref.read(liveProvider).error ??
                'Unable to join this live broadcast.',
          );
        }

        _participating = true;
      } on LiveApiException catch (e) {
        if (e.code != 'GO_LIVE_SUBSCRIPTION_REQUIRED') {
          rethrow;
        }

        session = await ref.read(liveProvider.notifier).watchLive(
              widget.session.sessionId,
            );

        if (session == null) {
          throw StateError(
            ref.read(liveProvider).error ??
                'Unable to watch this live broadcast.',
          );
        }

        _watchOnly = true;
        _participating = false;
      }

      final playbackUrl = session.playbackUrl;

      if (playbackUrl == null || playbackUrl.isEmpty) {
        throw StateError(
          'This live broadcast is not ready for playback.',
        );
      }

      if (!mounted) return;

      setState(() {
        _connectionStatus = 'Connecting…';
      });

      await _webrtc.startViewer(
        playbackUrl: playbackUrl,
        renderer: _renderer,
      );

      if (!mounted) return;

      setState(() {
        _joining = false;
        _connectionStatus = 'Live';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _joining = false;
        _connectionStatus = 'Connection failed';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('StateError: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _leave() async {
    if (_leaving || _left) return;

    _leaving = true;

    if (mounted) {
      setState(() {
        _connectionStatus = 'Leaving…';
      });
    }

    await _webrtc.dispose();

    if (_participating) {
      await ref.read(liveProvider.notifier).leaveLive();
    }

    _left = true;

    if (!mounted) return;

    context.pop();
  }

  Future<void> _showLeaveConfirmation() async {
    if (_leaving) return;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.xSurface,
        title: Text(
          'Leave XameLive?',
          style: TextStyle(color: context.xText),
        ),
        content: Text(
          'You can return to Live Now at any time while the broadcast is active.',
          style: TextStyle(color: context.xMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      await _leave();
    }
  }

  @override
  void dispose() {
    _webrtc.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(liveProvider);

    final currentSession = liveState.activeLives
        .where(
          (session) =>
              session.sessionId == widget.session.sessionId,
        )
        .firstOrNull;

    final viewerCount =
        currentSession?.viewerCount ??
            widget.session.viewerCount;

    final ended =
        currentSession == null &&
        liveState.activeLives.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_leaving) {
          _showLeaveConfirmation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_renderer.srcObject != null)
              RTCVideoView(
                _renderer,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),

            // Subtle readability gradient.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 150,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 250,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Top information.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    10,
                    14,
                    8,
                  ),
                  child: Row(
                    children: [
                      _LiveStatusBadge(
                        status: _connectionStatus,
                      ),
                      const SizedBox(width: 8),
                      _ViewerBadge(
                        count: viewerCount,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed:
                            _leaving
                                ? null
                                : _showLeaveConfirmation,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.45),
                        ),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom live information.
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 18,
                    right: 8,
                  ),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: context.xSurface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: context.xMuted,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    widget.session
                                        .broadcasterXameId,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.session.title ??
                                  'XameLive',
                              maxLines: 2,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if ((widget.session.category ??
                                    '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.session.category!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (_watchOnly) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  8,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(
                                    alpha: 0.58,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Want to join this live? You can watch for free. To join the live session, you need an active XameLive subscription.',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      onPressed: _leaving
                                          ? null
                                          : () => context.push(
                                                '/live/setup',
                                              ),
                                      child: const Text(
                                        'View Plans',
                                        style: TextStyle(
                                          fontWeight:
                                              FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _InteractionRail(
                        enabled:
                            _participating &&
                            !_joining &&
                            !_leaving,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_joining)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
              ),

            if (ended)
              const Positioned.fill(
                child: Center(
                  child: Text(
                    'Live ended',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveStatusBadge extends StatelessWidget {
  const _LiveStatusBadge({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final isLive = status == 'Live';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isLive
                ? Colors.redAccent
                : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(
            isLive ? 'LIVE' : status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerBadge extends StatelessWidget {
  const _ViewerBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.visibility_outlined,
            color: Colors.white,
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractionRail extends StatelessWidget {
  const _InteractionRail({
    required this.enabled,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.favorite_border_rounded,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        _ActionButton(
          icon: Icons.share_outlined,
          enabled: enabled,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.enabled,
  });

  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
