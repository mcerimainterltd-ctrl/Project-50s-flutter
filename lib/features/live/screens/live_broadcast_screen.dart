import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/theme/app_theme.dart';
import '../data/live_api.dart';
import '../models/live_session.dart';
import '../providers/live_provider.dart';
import '../services/live_webrtc_service.dart';

class LiveBroadcastScreen extends ConsumerStatefulWidget {
  const LiveBroadcastScreen({
    super.key,
    required this.result,
  });

  final LiveStartResult result;

  @override
  ConsumerState<LiveBroadcastScreen> createState() =>
      _LiveBroadcastScreenState();
}

class _LiveBroadcastScreenState
    extends ConsumerState<LiveBroadcastScreen> {
  final LiveWebRTCService _webrtc = LiveWebRTCService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _initializing = true;
  bool _ending = false;
  bool _backendEnded = false;
  Timer? _cutoffTimer;
  Duration _remainingUntilCutoff = Duration.zero;
  String _connectionStatus = 'Connecting…';

  @override
  void initState() {
    super.initState();

    ref.listenManual<LiveSession?>(
      liveProvider.select((state) => state.broadcasterSession),
      (previous, next) {
        if (previous != null && next == null && !_ending) {
          _handleBackendEnded();
        }
      },
    );

    ref.listenManual<List<LiveSession>>(
      liveProvider.select((state) => state.activeLives),
      (previous, next) {
        final sessionId = widget.result.session.sessionId;

        LiveSession? findSession(List<LiveSession>? sessions) {
          if (sessions == null) return null;

          for (final session in sessions) {
            if (session.sessionId == sessionId) {
              return session;
            }
          }
          return null;
        }

        final previousSession = findSession(previous);
        final nextSession = findSession(next);

        if (nextSession != null &&
            nextSession.usageCutoffAt !=
                previousSession?.usageCutoffAt) {
          _syncCutoffCountdown(nextSession);
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final sessionId = widget.result.session.sessionId;

      for (final session in ref.read(liveProvider).activeLives) {
        if (session.sessionId == sessionId) {
          _syncCutoffCountdown(session);
          break;
        }
      }
    });

    _initializeBroadcast();
  }

  Future<void> _initializeBroadcast() async {
    try {
      await _localRenderer.initialize();

      final camera = await Permission.camera.request();

      if (!camera.isGranted) {
        throw StateError(
          'Camera permission is required to start XameLive.',
        );
      }

      if (!mounted) return;

      setState(() {
        _connectionStatus = 'Connecting…';
      });

      await _webrtc.startBroadcast(
        publishUrl: widget.result.publishUrl,
        localRenderer: _localRenderer,
      );

      if (!mounted) return;

      setState(() {
        _initializing = false;
        _connectionStatus = 'Live';
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _initializing = false;
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

  void _syncCutoffCountdown(LiveSession session) {
    final cutoff = session.usageCutoffAt;

    if (cutoff == null) {
      _cutoffTimer?.cancel();
      _cutoffTimer = null;

      if (mounted && _remainingUntilCutoff != Duration.zero) {
        setState(() {
          _remainingUntilCutoff = Duration.zero;
        });
      }
      return;
    }

    _cutoffTimer?.cancel();

    void update() {
      if (!mounted || _backendEnded) return;

      final remaining = cutoff.difference(DateTime.now());
      final normalized =
          remaining.isNegative ? Duration.zero : remaining;

      if (_remainingUntilCutoff != normalized) {
        setState(() {
          _remainingUntilCutoff = normalized;
        });
      }

      if (normalized == Duration.zero) {
        _cutoffTimer?.cancel();
        _cutoffTimer = null;
      }
    }

    update();

    if (_remainingUntilCutoff > Duration.zero) {
      _cutoffTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => update(),
      );
    }
  }

  String _formatRemaining(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 863999).toInt();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handleBackendEnded() async {
    if (_backendEnded || _ending || !mounted) return;

    _backendEnded = true;
    _cutoffTimer?.cancel();
    _cutoffTimer = null;

    await _webrtc.dispose();

    if (!mounted) return;

    setState(() {
      _connectionStatus = 'Ended';
      _remainingUntilCutoff = Duration.zero;
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.xSurface,
        title: Text(
          'XameLive ended',
          style: TextStyle(color: context.xText),
        ),
        content: Text(
          'Your XameLive broadcast has ended.',
          style: TextStyle(color: context.xMuted),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) {
      context.pop();
    }
  }

  Future<void> _endLive() async {
    if (_ending) return;

    setState(() {
      _ending = true;
      _connectionStatus = 'Ending…';
    });

    await _webrtc.dispose();

    final ended = await ref.read(liveProvider.notifier).endLive();

    if (!mounted) return;

    if (!ended) {
      setState(() {
        _ending = false;
        _connectionStatus = 'Live';
      });
      return;
    }

    context.pop();
  }

  @override
  void dispose() {
    _cutoffTimer?.cancel();
    _cutoffTimer = null;
    _webrtc.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(liveProvider);

    final currentSession = liveState.activeLives
        .where(
          (session) =>
              session.sessionId == widget.result.session.sessionId,
        )
        .cast<dynamic>()
        .firstOrNull;

    final viewerCount =
        currentSession?.viewerCount ??
            widget.result.session.viewerCount;

    final backendStatus =
        currentSession?.status?.toString() ?? 'STARTING';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_ending) {
          _showEndConfirmation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_localRenderer.srcObject != null)
              RTCVideoView(
                _localRenderer,
                mirror: true,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Icon(
                    Icons.videocam_off_rounded,
                    color: Colors.white54,
                    size: 56,
                  ),
                ),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    8,
                  ),
                  child: Row(
                    children: [
                      _StatusBadge(
                        status: _connectionStatus,
                        backendStatus: backendStatus,
                      ),
                      const SizedBox(width: 10),
                      _ViewerBadge(count: viewerCount),
                      if (_remainingUntilCutoff > Duration.zero) ...[
                        const SizedBox(width: 10),
                        _LiveTimeBadge(
                          remaining: _formatRemaining(
                            _remainingUntilCutoff,
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        onPressed:
                            _ending ? null : _showEndConfirmation,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.45),
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.result.session.title ?? 'XameLive',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.result.session.category ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed:
                              (_initializing || _ending)
                                  ? null
                                  : _showEndConfirmation,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          icon: _ending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.stop_circle_outlined,
                                ),
                          label: Text(
                            _ending
                                ? 'Ending Live…'
                                : 'End Live',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEndConfirmation() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.xSurface,
        title: Text(
          'End XameLive?',
          style: TextStyle(color: context.xText),
        ),
        content: Text(
          'Your live broadcast will end for all viewers.',
          style: TextStyle(color: context.xMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Live'),
          ),
        ],
      ),
    );

    if (shouldEnd == true && mounted) {
      await _endLive();
    }
  }
}

class _LiveTimeBadge extends StatelessWidget {
  const _LiveTimeBadge({
    required this.remaining,
  });

  final String remaining;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white24,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_outlined,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              remaining,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.backendStatus,
  });

  final String status;
  final String backendStatus;

  @override
  Widget build(BuildContext context) {
    final connected =
        status == 'Live' && backendStatus == 'LIVE';

    final label = connected
        ? '● LIVE'
        : status;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: connected
              ? Colors.redAccent
              : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ViewerBadge extends StatelessWidget {
  const _ViewerBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
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
            size: 16,
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
