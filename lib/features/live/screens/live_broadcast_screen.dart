import '../../../core/services/screen_awake.dart';
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
  bool _shutdownRequested = false;
  bool _screenDisposed = false;
  bool _backendTerminationSucceeded = false;
  Future<void>? _initializationFuture;
  Future<bool>? _backendTermination;
  Future<void>? _resourceCleanup;
  Timer? _cutoffTimer;
  Duration _remainingUntilCutoff = Duration.zero;
  String _connectionStatus = 'Connecting…';
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    ScreenAwake.acquire(this);

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

    _initializationFuture = _initializeBroadcast();
  }

  Future<void> _initializeBroadcast() async {
    try {
      await _localRenderer.initialize();

      if (_shutdownRequested || _screenDisposed) return;

      final camera = await Permission.camera.request();

      if (!camera.isGranted) {
        throw StateError(
          'Camera permission is required to start XameLive.',
        );
      }

      if (_shutdownRequested || _screenDisposed) return;

      if (mounted) {
        setState(() {
          _connectionError = null;
          _connectionStatus = 'Connecting…';
        });
      }

      await _webrtc.startBroadcast(
        publishUrl: widget.result.publishUrl,
        localRenderer: _localRenderer,
      );

      if (_shutdownRequested || _screenDisposed) return;
      if (!mounted) return;

      setState(() {
        _initializing = false;
        _connectionStatus = 'Live';
      });
    } catch (e, stackTrace) {
      // Preserve the original initialization failure for diagnosis.
      debugPrint('[XAMELIVE] Broadcast initialization failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      // Suppress provider-driven UI changes during failure cleanup.
      _ending = true;

      // Cleanup failure must not prevent backend termination.
      try {
        await _disposeWebRtcSafely();
      } catch (cleanupError, cleanupStack) {
        debugPrint(
          '[XAMELIVE] WebRTC cleanup after initialization failure '
          'threw: $cleanupError',
        );
        debugPrintStack(stackTrace: cleanupStack);
      }

      var backendTerminationConfirmed = false;

      try {
        backendTerminationConfirmed =
            await _terminateBackendSession();
      } catch (terminationError, terminationStack) {
        debugPrint(
          '[XAMELIVE] Backend termination after initialization failure '
          'threw: $terminationError',
        );
        debugPrintStack(stackTrace: terminationStack);
      }

      // Never update UI or show notifications after disposal.
      if (!mounted) return;

      // Preserve the original failure even if shutdown was requested.
      // _endLive() uses this state if backend termination fails.
      final message = backendTerminationConfirmed
          ? e.toString()
          : '${e.toString()} '
              'Backend session termination could not be confirmed.';

      if (_shutdownRequested) {
        try {
          setState(() {
            _initializing = false;
            _connectionError = message;
            _connectionStatus = 'Connection failed';
            // Keep _ending true while shutdown remains in progress.
          });
        } catch (stateError, stateStack) {
          debugPrint(
            '[XAMELIVE] Could not finalize initialization state '
            'during shutdown: $stateError',
          );
          debugPrintStack(stackTrace: stateStack);
        }
        return;
      }

      try {
        setState(() {
          _initializing = false;
          _ending = false;
          _connectionError = message;
          _connectionStatus = 'Connection failed';
        });
      } catch (stateError, stateStack) {
        debugPrint(
          '[XAMELIVE] Could not report broadcast initialization failure: '
          '$stateError',
        );
        debugPrintStack(stackTrace: stateStack);
        return;
      }

      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.replaceFirst('Bad state: ', ''),
            ),
          ),
        );
      } catch (notificationError) {
        // The failure state is already recorded.
        debugPrint(
          '[XAMELIVE] Could not show initialization failure notification: '
          '$notificationError',
        );
      }
    }
  }

  Future<bool> _terminateBackendSession() async {
    if (_backendTerminationSucceeded) return true;

    final existing = _backendTermination;
    if (existing != null) return existing;

    late final Future<bool> operation;

    try {
      operation = _screenDisposed
          ? _terminateBackendDirectly()
          : ref.read(liveProvider.notifier).endLiveSession(
                widget.result.session.sessionId,
              );
    } catch (e) {
      debugPrint('[XAMELIVE] Could not initiate backend termination: $e');
      return false;
    }

    _backendTermination = operation;

    try {
      final ended = await operation;
      if (ended) _backendTerminationSucceeded = true;
      return ended;
    } catch (e) {
      debugPrint('[XAMELIVE] Backend termination failed: $e');
      return false;
    } finally {
      if (identical(_backendTermination, operation)) {
        _backendTermination = null;
      }
    }
  }

  Future<bool> _terminateBackendDirectly() async {
    try {
      await LiveApi().endLive(widget.result.session.sessionId);
      return true;
    } catch (e) {
      debugPrint('[XAMELIVE] Backend cleanup failed: $e');
      return false;
    }
  }

  Future<void> _disposeWebRtcSafely() async {
    try {
      await _webrtc.dispose();
    } catch (e) {
      debugPrint('[XAMELIVE] WebRTC disposal failed: $e');
    }
  }

  Future<void> _disposeBroadcastResources() {
    return _resourceCleanup ??= () async {
      try {
        await _disposeWebRtcSafely();
      } finally {
        try {
          _localRenderer.srcObject = null;
        } finally {
          await _localRenderer.dispose();
        }
      }
    }();
  }

  Future<void> _cleanupAfterScreenDisposal() async {
    final initialization = _initializationFuture;
    if (initialization != null) {
      try {
        await initialization;
      } catch (e) {
        debugPrint('[XAMELIVE] Initialization cleanup wait failed: $e');
      }
    }

    try {
      if (!_backendEnded) {
        final ended = await _terminateBackendSession();
        if (!ended) {
          debugPrint(
            '[XAMELIVE] Backend termination was not confirmed '
            'during screen disposal.',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[XAMELIVE] Backend termination cleanup failed: $e',
      );
    } finally {
      try {
        await _disposeBroadcastResources();
      } catch (e) {
        debugPrint(
          '[XAMELIVE] Broadcast resource cleanup failed: $e',
        );
      }
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

    await _disposeWebRtcSafely();

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
      _shutdownRequested = true;
      _connectionStatus = 'Ending…';
    });

    final initialization = _initializationFuture;
    if (initialization != null) {
      await initialization;
    }

    await _disposeWebRtcSafely();
    final ended = await _terminateBackendSession();

    if (!mounted) return;

    if (!ended) {
      setState(() {
        _initializing = false;
        _ending = false;
        _connectionStatus =
            _connectionError == null ? 'Live' : 'Connection failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'XameLive could not confirm that the broadcast ended. Please retry.',
          ),
        ),
      );
      return;
    }

    context.pop();
  }

  @override
  void dispose() {
    _screenDisposed = true;
    _cutoffTimer?.cancel();
    _cutoffTimer = null;
    unawaited(_cleanupAfterScreenDisposal());
    ScreenAwake.release(this);
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

            if (_connectionError != null)
              Positioned(
                left: 16,
                right: 16,
                top: 76,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Connection error: $_connectionError',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
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
