// XAMELIVE_MEDIA_V1: the broadcaster can put a photo or video on screen for everyone. New file; hooked in by small injections.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as dart_io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../../core/config/constants.dart';

class _LiveMediaBus {
  static final ValueNotifier<int> nudge = ValueNotifier<int>(0);
  static Map<String, dynamic>? media;
  static DateTime fetchedAt = DateTime.now();
}

const FlutterSecureStorage _lmStorage = FlutterSecureStorage();

int _lmInt(dynamic v) => v is num ? v.toInt() : 0;

Future<Map<String, dynamic>> _lmCall(
  String method,
  String sessionId,
  String suffix, {
  Map<String, dynamic>? body,
}) async {
  final token = await _lmStorage.read(key: AppConstants.keySessionToken);
  if (token == null || token.isEmpty) {
    return <String, dynamic>{'success': false, 'message': 'Please sign in again.'};
  }
  final uri = Uri.parse('${AppConstants.serverUrl}/api/live/$sessionId/media$suffix');
  final headers = <String, String>{
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  final r = method == 'GET'
      ? await http.get(uri, headers: headers)
      : await http.post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
  try {
    final d = jsonDecode(r.body);
    if (d is Map<String, dynamic>) {
      d['_status'] = r.statusCode;
      return d;
    }
  } catch (_) {}
  return <String, dynamic>{'_status': r.statusCode};
}

/// Full-screen photo/video layer. Everyone watching sees what the broadcaster puts on screen.
class LiveMediaLayer extends StatefulWidget {
  const LiveMediaLayer({super.key, required this.sessionId, this.muted = false});

  final String sessionId;
  final bool muted;

  @override
  State<LiveMediaLayer> createState() => _LiveMediaLayerState();
}

class _LiveMediaLayerState extends State<LiveMediaLayer> {
  Timer? _timer;
  bool _polling = false;
  bool _again = false;
  bool _gone = false;
  bool _applying = false;
  bool _rerun = false;
  Map<String, dynamic>? _wanted;
  Map<String, dynamic>? _media;
  VideoPlayerController? _vc;
  String _vcUrl = '';
  bool _vcReady = false;
  bool _failed = false;
  int _seq = -1;

  @override
  void initState() {
    super.initState();
    _LiveMediaBus.media = null;
    _LiveMediaBus.nudge.addListener(_onNudge);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  void _onNudge() {
    unawaited(_apply(_LiveMediaBus.media));
  }

  Future<void> _poll() async {
    if (_gone) return;
    if (_polling) {
      _again = true;
      return;
    }
    _polling = true;
    try {
      final d = await _lmCall('GET', widget.sessionId, '');
      if (_gone || !mounted) return;
      if (d['success'] == true) {
        final raw = d['media'];
        final m = raw is Map ? Map<String, dynamic>.from(raw) : null;
        final cur = _LiveMediaBus.media;
        if (m != null &&
            cur != null &&
            m['mediaId'] == cur['mediaId'] &&
            _lmInt(m['seq']) < _lmInt(cur['seq'])) {
          return;
        }
        _LiveMediaBus.media = m;
        _LiveMediaBus.fetchedAt = DateTime.now();
        await _apply(m);
      }
    } catch (_) {
    } finally {
      _polling = false;
      if (_again && !_gone) {
        _again = false;
        unawaited(_poll());
      }
    }
  }

  Future<void> _apply(Map<String, dynamic>? m) async {
    _wanted = m;
    if (_applying) {
      _rerun = true;
      return;
    }
    _applying = true;
    try {
      do {
        _rerun = false;
        await _applyOnce(_wanted);
      } while (_rerun && !_gone);
    } finally {
      _applying = false;
    }
  }

  Future<void> _dropVideo() async {
    final old = _vc;
    _vc = null;
    _vcUrl = '';
    _vcReady = false;
    if (old != null) {
      try {
        await old.pause();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  Future<void> _applyOnce(Map<String, dynamic>? m) async {
    if (_gone || !mounted) return;
    if (m == null) {
      await _dropVideo();
      _failed = false;
      _seq = -1;
      if (mounted) setState(() => _media = null);
      return;
    }
    final kind = m['kind']?.toString() ?? '';
    final url = m['url']?.toString() ?? '';
    final mode = m['mode']?.toString() ?? 'media';
    final playing = m['playing'] == true;
    final seq = _lmInt(m['seq']);
    final pos = _lmInt(m['positionMs']);
    final age = DateTime.now().difference(_LiveMediaBus.fetchedAt).inMilliseconds;

    if (kind != 'video') {
      await _dropVideo();
      _failed = false;
      if (mounted) setState(() => _media = m);
      return;
    }

    if (_vc == null || _vcUrl != url) {
      await _dropVideo();
      _vcUrl = url;
      final nc = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _vc = nc;
      _vcReady = false;
      try {
        await nc.initialize();
        await nc.setVolume(widget.muted ? 0.0 : 1.0);
        await nc.setLooping(false);
        if (_gone || _vc != nc) return;
        _vcReady = true;
        _failed = false;
        _seq = -1;
      } catch (_) {
        await _dropVideo();
        _failed = true;
        if (mounted) setState(() => _media = m);
        return;
      }
    }

    final vc = _vc;
    if (vc == null || !_vcReady) {
      if (mounted) setState(() => _media = m);
      return;
    }
    final dur = vc.value.duration.inMilliseconds;
    var target = pos + (playing ? age : 0);
    if (dur > 0 && target > dur) target = dur;
    final cur = vc.value.position.inMilliseconds;
    final changed = seq != _seq;
    _seq = seq;
    if (mode != 'media') {
      if (vc.value.isPlaying) await vc.pause();
    } else {
      if (changed || (cur - target).abs() > 1500) {
        await vc.seekTo(Duration(milliseconds: target));
      }
      if (playing && !vc.value.isPlaying) await vc.play();
      if (!playing && vc.value.isPlaying) await vc.pause();
    }
    if (mounted) setState(() => _media = m);
  }

  @override
  void dispose() {
    _gone = true;
    _timer?.cancel();
    _LiveMediaBus.nudge.removeListener(_onNudge);
    unawaited(_dropVideo());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _media;
    if (m == null || m['mode']?.toString() != 'media') {
      return const Positioned(left: 0, top: 0, width: 0, height: 0, child: SizedBox.shrink());
    }
    final kind = m['kind']?.toString() ?? '';
    final url = m['url']?.toString() ?? '';
    Widget content;
    if (kind == 'image') {
      content = Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (c, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator()),
        errorBuilder: (c, e, s) => const Center(
          child: Text('Unable to load this photo.', style: TextStyle(color: Colors.white70)),
        ),
      );
    } else {
      final vc = _vc;
      if (_failed) {
        content = const Center(
          child: Text('Unable to play this video.', style: TextStyle(color: Colors.white70)),
        );
      } else if (vc == null || !_vcReady) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        final ar = vc.value.aspectRatio;
        content = Center(
          child: AspectRatio(aspectRatio: ar <= 0 ? 16 / 9 : ar, child: VideoPlayer(vc)),
        );
      }
    }
    return Positioned.fill(
      child: IgnorePointer(child: ColoredBox(color: Colors.black, child: content)),
    );
  }
}

Widget _lmRoundButton({required IconData icon, required VoidCallback onTap, Color? bg}) {
  return Material(
    color: bg ?? Colors.black.withValues(alpha: 0.55),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    ),
  );
}

/// Broadcaster controls: microphone on/off and the media sheet.
class LiveMediaControls extends StatefulWidget {
  const LiveMediaControls({super.key, required this.sessionId, required this.streamGetter});

  final String sessionId;
  final MediaStream? Function() streamGetter;

  @override
  State<LiveMediaControls> createState() => _LiveMediaControlsState();
}

class _LiveMediaControlsState extends State<LiveMediaControls> {
  bool _micOn = true;

  void _toggleMic() {
    final s = widget.streamGetter();
    if (s == null) return;
    final next = !_micOn;
    for (final t in s.getAudioTracks()) {
      t.enabled = next;
    }
    setState(() => _micOn = next);
  }

  Future<void> _openSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (ctx) => _MediaSheet(sessionId: widget.sessionId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _lmRoundButton(
            icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            bg: _micOn ? null : Colors.red.shade700,
            onTap: _toggleMic,
          ),
          const SizedBox(height: 10),
          _lmRoundButton(icon: Icons.perm_media_rounded, onTap: _openSheet),
        ],
      ),
    );
  }
}

class _MediaSheet extends StatefulWidget {
  const _MediaSheet({required this.sessionId});

  final String sessionId;

  @override
  State<_MediaSheet> createState() => _MediaSheetState();
}

class _MediaSheetState extends State<_MediaSheet> {
  bool _busy = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _LiveMediaBus.nudge.addListener(_r);
  }

  @override
  void dispose() {
    _LiveMediaBus.nudge.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  void _note(String s) {
    if (mounted) setState(() => _msg = s);
  }

  int _curPos() {
    final m = _LiveMediaBus.media;
    if (m == null) return 0;
    final base = _lmInt(m['positionMs']);
    if (m['playing'] != true) return base;
    return base + DateTime.now().difference(_LiveMediaBus.fetchedAt).inMilliseconds;
  }

  bool _accept(Map<String, dynamic> d) {
    if (d['success'] == true) {
      final raw = d['media'];
      _LiveMediaBus.media = raw is Map ? Map<String, dynamic>.from(raw) : null;
      _LiveMediaBus.fetchedAt = DateTime.now();
      _LiveMediaBus.nudge.value++;
      _note('');
      return true;
    }
    _note(d['message']?.toString() ?? 'Request failed (${d['_status']}).');
    return false;
  }

  Future<void> _send(String action, {int? pos}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final d = await _lmCall('POST', widget.sessionId, '/control', body: <String, dynamic>{
        'action': action,
        if (pos != null) 'positionMs': pos,
      });
      _accept(d);
    } catch (_) {
      _note('Network problem. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _show(String url, String kind) async {
    final d = await _lmCall('POST', widget.sessionId, '/show', body: <String, dynamic>{
      'url': url,
      'kind': kind,
    });
    return _accept(d);
  }

  Future<void> _upload() async {
    if (_busy) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      final path = res.files.single.path;
      if (path == null || path.isEmpty) return;
      final size = await dart_io.File(path).length();
      if (size > 60 * 1024 * 1024) {
        _note('That file is over 60 MB. Paste a link instead.');
        return;
      }
      final token = await _lmStorage.read(key: AppConstants.keySessionToken);
      if (token == null || token.isEmpty) {
        _note('Please sign in again.');
        return;
      }
      if (mounted) {
        setState(() {
          _busy = true;
          _msg = 'Uploading…';
        });
      }
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.serverUrl}/api/live/${widget.sessionId}/media/upload'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', path));
      final streamed = await req.send().timeout(const Duration(minutes: 4));
      final body = await streamed.stream.bytesToString();
      var d = <String, dynamic>{};
      try {
        final j = jsonDecode(body);
        if (j is Map<String, dynamic>) d = j;
      } catch (_) {}
      if (d['success'] == true && d['url'] != null && d['kind'] != null) {
        await _show(d['url'].toString(), d['kind'].toString());
      } else {
        _note(d['message']?.toString() ?? 'Upload failed (${streamed.statusCode}).');
      }
    } catch (_) {
      _note('Upload failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteLink() async {
    if (_busy) return;
    final ctrl = TextEditingController();
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste a media link'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://… (.jpg, .png, .mp4)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop('image'), child: const Text('As photo')),
          TextButton(onPressed: () => Navigator.of(ctx).pop('video'), child: const Text('As video')),
        ],
      ),
    );
    final link = ctrl.text.trim();
    if (kind == null || link.isEmpty) return;
    if (mounted) setState(() => _busy = true);
    try {
      await _show(link, kind);
    } catch (_) {
      _note('Network problem. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _LiveMediaBus.media;
    final has = m != null;
    final isVideo = m != null && m['kind'] == 'video';
    final playing = m != null && m['playing'] == true;
    final camera = m != null && m['mode'] == 'camera';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Media on screen',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (!has)
              const Text(
                'Nothing is on screen. Upload a photo or video, or paste a link.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            if (has)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Live camera'),
                    selected: camera,
                    onSelected: _busy ? null : (_) => _send('camera'),
                  ),
                  ChoiceChip(
                    label: const Text('Media'),
                    selected: !camera,
                    onSelected: _busy ? null : (_) => _send('media'),
                  ),
                ],
              ),
            if (isVideo)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => _send('seek', pos: (_curPos() - 10000).clamp(0, 86400000).toInt()),
                    icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => _send(playing ? 'pause' : 'play'),
                    icon: Icon(
                      playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => _send('seek', pos: (_curPos() + 10000).clamp(0, 86400000).toInt()),
                    icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                  ),
                ],
              ),
            if (has)
              TextButton.icon(
                onPressed: _busy ? null : () => _send('stop'),
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text('Stop and clear', style: TextStyle(color: Colors.redAccent)),
              ),
            const Divider(color: Colors.white24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.upload_file_rounded, color: Colors.white),
              title: const Text('Upload photo or video', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Up to 60 MB', style: TextStyle(color: Colors.white54)),
              onTap: _busy ? null : _upload,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_rounded, color: Colors.white),
              title: const Text('Paste a link', style: TextStyle(color: Colors.white)),
              subtitle: const Text('A direct https link to a photo or video file', style: TextStyle(color: Colors.white54)),
              onTap: _busy ? null : _pasteLink,
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_msg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_msg, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
