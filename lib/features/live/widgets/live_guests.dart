// XAMELIVE_GUESTS_V1: guests on camera in a live. New file; hooked in by small injections.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/constants.dart';
import '../services/live_webrtc_service.dart';

class LiveGuestsOverlay extends StatefulWidget {
  const LiveGuestsOverlay({
    super.key,
    required this.sessionId,
    required this.isHost,
    this.canRequest = false,
  });

  final String sessionId;
  final bool isHost;
  final bool canRequest;

  @override
  State<LiveGuestsOverlay> createState() => _LiveGuestsOverlayState();
}

class _LiveGuestsOverlayState extends State<LiveGuestsOverlay> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Timer? _timer;
  bool _busy = false;
  bool _polling = false;
  bool _starting = false;
  bool _publishing = false;
  bool _gone = false;
  List<Map<String, dynamic>> _guests = <Map<String, dynamic>>[];
  Map<String, dynamic>? _me;
  String? _error;
  LiveWebRTCService? _pub;
  RTCVideoRenderer? _pubRenderer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  Future<Map<String, dynamic>> _call(String method, String path) async {
    final token = await _storage.read(key: AppConstants.keySessionToken);
    if (token == null || token.isEmpty) return <String, dynamic>{};
    final uri = Uri.parse(
        '${AppConstants.serverUrl}/api/live/${widget.sessionId}$path');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final r = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers);
    try {
      final d = jsonDecode(r.body);
      if (d is Map<String, dynamic>) {
        d['_status'] = r.statusCode;
        return d;
      }
    } catch (_) {}
    return <String, dynamic>{'_status': r.statusCode};
  }

  Future<void> _poll() async {
    if (_polling || _gone) return;
    _polling = true;
    try {
      final g = await _call('GET', '/guests');
      var list = <Map<String, dynamic>>[];
      final raw = g['guests'];
      if (raw is List) {
        list = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      Map<String, dynamic>? me;
      if (!widget.isHost && (widget.canRequest || _me != null)) {
        final m = await _call('GET', '/guest/me');
        final mg = m['guest'];
        if (mg is Map) me = Map<String, dynamic>.from(mg);
      }
      if (_gone || !mounted) return;
      setState(() {
        _guests = list;
        _me = me;
      });
      if (!widget.isHost) await _syncPublishing(me);
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> _syncPublishing(Map<String, dynamic>? me) async {
    final status = me == null ? '' : (me['status']?.toString() ?? '');
    final url = me == null ? '' : (me['publishUrl']?.toString() ?? '');
    final shouldPublish =
        (status == 'APPROVED' || status == 'PUBLISHING') && url.isNotEmpty;
    if (shouldPublish && !_publishing && !_starting) {
      _starting = true;
      RTCVideoRenderer? renderer;
      try {
        final cam = await Permission.camera.request();
        final mic = await Permission.microphone.request();
        if (!cam.isGranted || !mic.isGranted) {
          throw StateError('Camera and microphone permission are required.');
        }
        renderer = RTCVideoRenderer();
        await renderer.initialize();
        final svc = LiveWebRTCService();
        await svc.startBroadcast(publishUrl: url, localRenderer: renderer);
        if (_gone) {
          await svc.dispose();
          await renderer.dispose();
          return;
        }
        _pub = svc;
        _pubRenderer = renderer;
        if (mounted) setState(() => _publishing = true);
        try {
          await _call('POST', '/guest/me/started');
        } catch (_) {}
      } catch (e) {
        if (_pub == null) {
          try {
            await renderer?.dispose();
          } catch (_) {}
        }
        try {
          await _call('POST', '/guest/me/leave');
        } catch (_) {}
        if (mounted) {
          setState(
              () => _error = e.toString().replaceFirst('Bad state: ', ''));
        }
      } finally {
        _starting = false;
      }
    } else if (!shouldPublish && _publishing) {
      await _stopPublishing();
    }
  }

  Future<void> _stopPublishing() async {
    final svc = _pub;
    final r = _pubRenderer;
    _pub = null;
    _pubRenderer = null;
    _publishing = false;
    try {
      await svc?.dispose();
    } catch (_) {}
    try {
      r?.srcObject = null;
      await r?.dispose();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _act(String method, String path) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await _call(method, path);
      final st = d['_status'];
      if (st is int && st >= 400 && mounted) {
        setState(() =>
            _error = d['message']?.toString() ?? 'Request failed ($st).');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Network problem. Please try again.');
    } finally {
      _busy = false;
    }
    await _poll();
  }

  @override
  void dispose() {
    _gone = true;
    _timer?.cancel();
    if (!widget.isHost && _me != null) {
      unawaited(_call('POST', '/guest/me/leave').catchError(
          (_) => <String, dynamic>{}));
    }
    unawaited(_stopPublishing());
    super.dispose();
  }

  Widget _pill(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );

  static const TextStyle _small = TextStyle(color: Colors.white, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final myId = _me == null ? '' : (_me!['guestXameId']?.toString() ?? '');
    final tiles = <Widget>[];
    final pr = _pubRenderer;
    if (_publishing && pr != null) {
      tiles.add(_GuestFrame(
        name: 'You',
        child: RTCVideoView(
          pr,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ));
    }
    for (final g in _guests) {
      final id = g['guestXameId']?.toString() ?? '';
      final url = g['playbackUrl']?.toString() ?? '';
      if (g['status'] != 'PUBLISHING' || url.isEmpty || id == myId) continue;
      tiles.add(_GuestTile(
        key: ValueKey('$id|$url'),
        playbackUrl: url,
        name: g['guestName']?.toString() ?? 'Guest',
        onRemove: widget.isHost
            ? () => _act('POST', '/guest/${Uri.encodeComponent(id)}/remove')
            : null,
      ));
    }

    final controls = <Widget>[];
    if (widget.isHost) {
      for (final g in _guests) {
        if (g['status'] != 'REQUESTED') continue;
        final id = g['guestXameId']?.toString() ?? '';
        final name = g['guestName']?.toString() ?? 'Guest';
        controls.add(_pill(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('$name wants to go on camera',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _small),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _busy
                  ? null
                  : () => _act(
                      'POST', '/guest/${Uri.encodeComponent(id)}/approve'),
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _busy
                  ? null
                  : () => _act(
                      'POST', '/guest/${Uri.encodeComponent(id)}/remove'),
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
            ),
          ],
        )));
      }
    } else if (widget.canRequest || _me != null) {
      final status = _me == null ? '' : (_me!['status']?.toString() ?? '');
      final reason = status == 'ENDED' ? (_me!['reason']?.toString() ?? '') : '';
      if (status == 'REQUESTED') {
        controls.add(_pill(Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Waiting for the host…', style: _small),
          TextButton(
            onPressed: _busy ? null : () => _act('POST', '/guest/me/leave'),
            child: const Text('Cancel'),
          ),
        ])));
      } else if (status == 'APPROVED') {
        controls.add(_pill(const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('Starting your camera…', style: _small),
        )));
      } else if (status == 'PUBLISHING') {
        controls.add(_pill(Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('You are on camera', style: _small),
          TextButton(
            onPressed: _busy ? null : () => _act('POST', '/guest/me/leave'),
            child: const Text('Stop'),
          ),
        ])));
      } else if (widget.canRequest) {
        controls.add(_pill(Row(mainAxisSize: MainAxisSize.min, children: [
          if (reason == 'declined' || reason == 'removed')
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text('Not approved.', style: _small),
            ),
          TextButton.icon(
            onPressed: _busy ? null : () => _act('POST', '/guest/request'),
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: const Text('Go on camera'),
          ),
        ])));
      }
    }
    if (_error != null) {
      controls.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(_error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
      ));
    }

    return Positioned.fill(
      child: Stack(
        children: [
          if (controls.isNotEmpty)
            Positioned(
              left: 12,
              right: 112,
              top: top + 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: controls,
              ),
            ),
          if (tiles.isNotEmpty)
            Positioned(
              right: 12,
              top: top + 64,
              child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
            ),
        ],
      ),
    );
  }
}

class _GuestFrame extends StatelessWidget {
  const _GuestFrame({required this.child, required this.name, this.onRemove});

  final Widget child;
  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 124,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuestTile extends StatefulWidget {
  const _GuestTile({
    super.key,
    required this.playbackUrl,
    required this.name,
    this.onRemove,
  });

  final String playbackUrl;
  final String name;
  final VoidCallback? onRemove;

  @override
  State<_GuestTile> createState() => _GuestTileState();
}

class _GuestTileState extends State<_GuestTile> {
  final LiveWebRTCService _svc = LiveWebRTCService();
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _renderer.initialize();
      await _svc.startViewer(
        playbackUrl: widget.playbackUrl,
        renderer: _renderer,
      );
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _svc.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GuestFrame(
      name: widget.name,
      onRemove: widget.onRemove,
      child: _failed
          ? const Center(
              child: Icon(Icons.videocam_off_rounded, color: Colors.white54))
          : (_ready
              ? RTCVideoView(
                  _renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )),
    );
  }
}
