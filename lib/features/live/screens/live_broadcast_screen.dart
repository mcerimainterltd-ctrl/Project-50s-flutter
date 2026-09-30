import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/theme/app_theme.dart';
import '../data/live_api.dart';
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
  String _connectionStatus = 'Connecting…';

  @override
  void initState() {
    super.initState();
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
