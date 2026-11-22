// XAMELIVE_MEDIA_V1: the broadcaster can put a photo or video on screen for everyone. New file; hooked in by small injections.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as dart_io;

import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt;

import '../../../core/config/constants.dart';

class _LiveMediaBus {
  static final ValueNotifier<int> nudge = ValueNotifier<int>(0);
  static Map<String, dynamic>? media;
  static DateTime fetchedAt = DateTime.now();
  static final ValueNotifier<bool> hostSound = ValueNotifier<bool>(false);
  static int durationMs = 0;
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
  yt.YoutubePlayerController? _yt;
  String _ytId = '';
  int _ytSeq = -1;
  int _ytErr = 0;
  bool _ytReady = false;
  bool _ytReadySeen = false;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _LiveMediaBus.media = null;
    _LiveMediaBus.nudge.addListener(_onNudge);
    _LiveMediaBus.hostSound.addListener(_onSound);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  double _vol() => widget.muted ? (_LiveMediaBus.hostSound.value ? 1.0 : 0.0) : 1.0;

  void _onSound() {
    final yc = _yt;
    if (yc != null && yc.value.isReady) {
      if (_vol() <= 0) {
        yc.mute();
      } else {
        yc.unMute();
      }
    }
    final v = _vc;
    if (v != null && _vcReady) {
      unawaited(v.setVolume(_vol()));
    }
  }

  String _ytIdOf(String url) {
    final u = Uri.tryParse(url);
    final v = u == null ? '' : (u.queryParameters['v'] ?? '');
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v) ? v : '';
  }

  void _dropYt() {
    final c = _yt;
    _yt = null;
    _ytId = '';
    _ytSeq = -1;
    _ytErr = 0;
    _ytReady = false;
    _ytReadySeen = false;
    if (c != null) {
      c.removeListener(_onYt);
      try {
        c.dispose();
      } catch (_) {}
    }
  }

  void _onYt() {
    final c = _yt;
    if (_gone || !mounted || c == null) return;
    final err = c.value.errorCode;
    final ready = c.value.isReady;
    final changed = err != _ytErr || ready != _ytReady;
    _ytErr = err;
    _ytReady = ready;
    if (ready && !_ytReadySeen) {
      _ytReadySeen = true;
      _syncYt(_LiveMediaBus.media);
    }
    if (changed) setState(() {});
  }

  Future<void> _applyYoutube(Map<String, dynamic> m) async {
    final id = _ytIdOf(m['url']?.toString() ?? '');
    await _dropPlayer();
    if (id.isEmpty) {
      _dropYt();
      _failed = true;
      if (mounted) setState(() => _media = m);
      return;
    }
    if (_yt == null || _ytId != id) {
      _dropYt();
      _ytId = id;
      _failed = false;
      final c = yt.YoutubePlayerController(
        initialVideoId: id,
        flags: yt.YoutubePlayerFlags(
          autoPlay: false,
          mute: true,
          hideControls: true,
          disableDragSeek: true,
          enableCaption: false,
        ),
      );
      c.addListener(_onYt);
      _yt = c;
    }
    if (mounted) setState(() => _media = m);
    _syncYt(m);
  }

  void _syncYt(Map<String, dynamic>? m) {
    final c = _yt;
    if (c == null || m == null || !c.value.isReady) return;
    final mode = m['mode']?.toString() ?? 'media';
    final playing = m['playing'] == true;
    final seq = _lmInt(m['seq']);
    final pos = _lmInt(m['positionMs']);
    final age = DateTime.now().difference(_LiveMediaBus.fetchedAt).inMilliseconds;
    final dur = c.value.metaData.duration.inMilliseconds;
    if (dur > 0) _LiveMediaBus.durationMs = dur;
    var target = pos + (playing ? age : 0);
    if (dur > 400 && target > dur - 200) target = dur - 200;
    final cur = c.value.position.inMilliseconds;
    final changed = seq != _ytSeq;
    _ytSeq = seq;
    try {
      if (_vol() <= 0) {
        c.mute();
      } else {
        c.unMute();
      }
      if (mode != 'media') {
        c.pause();
        return;
      }
      final overEnd = dur > 400 && target >= dur - 300;
      final ended = c.value.playerState == yt.PlayerState.ended;
      if (changed ||
          ((cur - target).abs() > 4000 &&
              DateTime.now().difference(_lastSeek).inMilliseconds > 8000)) {
        _lastSeek = DateTime.now();
        c.seekTo(Duration(milliseconds: target));
      }
      if (playing && !overEnd) {
        if (!(ended && !changed)) c.play();
      } else {
        c.pause();
      }
    } catch (_) {}
  }

  Widget _ytContent() {
    final c = _yt;
    if (c == null || _failed) {
      return const Center(
        child: Text('Unable to play this video.', style: TextStyle(color: Colors.white70)),
      );
    }
    if (c.value.errorCode != 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This YouTube video cannot be played here (its owner may block embedding).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return Center(child: yt.YoutubePlayer(controller: c, aspectRatio: 16 / 9));
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
    _dropYt();
    await _dropPlayer();
  }

  Future<void> _dropPlayer() async {
    final old = _vc;
    _vc = null;
    _vcUrl = '';
    _LiveMediaBus.durationMs = 0;
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

    if (kind == 'youtube') {
      await _applyYoutube(m);
      return;
    }

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
        await nc.setVolume(_vol());
        await nc.setLooping(false);
        if (_gone || _vc != nc) return;
        _vcReady = true;
        _LiveMediaBus.durationMs = nc.value.duration.inMilliseconds;
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
    if (dur > 400 && target > dur - 200) target = dur - 200;
    final cur = vc.value.position.inMilliseconds;
    final changed = seq != _seq;
    _seq = seq;
    if (mode != 'media') {
      if (vc.value.isPlaying) await vc.pause();
    } else {
      final needSeek = changed ||
          (!vc.value.isBuffering &&
              (cur - target).abs() > 4000 &&
              DateTime.now().difference(_lastSeek).inMilliseconds > 8000);
      if (needSeek) {
        _lastSeek = DateTime.now();
        await vc.seekTo(Duration(milliseconds: target));
      }
      final overEnd = dur > 400 && target >= dur - 300;
      final atEnd = dur > 0 && vc.value.position.inMilliseconds >= dur - 300;
      if (playing && overEnd) {
        if (vc.value.isPlaying) await vc.pause();
      } else if (playing && !vc.value.isPlaying && !atEnd) {
        await vc.play();
      }
      if (!playing && vc.value.isPlaying) await vc.pause();
    }
    if (mounted) setState(() => _media = m);
  }

  @override
  void dispose() {
    _gone = true;
    _timer?.cancel();
    _LiveMediaBus.nudge.removeListener(_onNudge);
    _LiveMediaBus.hostSound.removeListener(_onSound);
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
      if (kind == 'youtube') {
        content = _ytContent();
      } else if (_failed) {
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

  @override
  void initState() {
    super.initState();
    _LiveMediaBus.hostSound.value = false;
  }

  void _toggleSound() {
    final next = !_LiveMediaBus.hostSound.value;
    _LiveMediaBus.hostSound.value = next;
    setState(() {});
    if (next) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use headphones so the clip is not picked up by your microphone.'),
        ),
      );
    }
  }

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _cc = false;
  bool _ccBusy = false;
  String _ccLocale = 'en_US';
  int _ccErrors = 0;
  DateTime _ccLastCb = DateTime.now();
  Timer? _ccKick;
  Timer? _ccWatch;

  @override
  void dispose() {
    _cc = false;
    _ccKick?.cancel();
    _ccWatch?.cancel();
    unawaited(_stt.cancel());
    super.dispose();
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _toggleCc() async {
    if (_cc) {
      await _ccStop();
      return;
    }
    final loc = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language you speak'),
        children: [
          for (final e in _lmCcLocales.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (loc == null || !mounted) return;
    _ccLocale = loc;
    bool ok = false;
    try {
      ok = await _stt.initialize(onError: (_) => _ccAfter(true));
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _snack('Speech recognition is not available on this phone.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _cc = true;
    });
    _ccErrors = 0;
    _ccLastCb = DateTime.now();
    _ccWatch?.cancel();
    _ccWatch = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_cc && DateTime.now().difference(_ccLastCb).inSeconds > 40) {
        _ccKick?.cancel();
        unawaited(_ccListen());
      }
    });
    _snack('Captions on. If viewers stop hearing you, switch captions off.');
    await _ccListen();
  }

  Future<void> _ccStop() async {
    _cc = false;
    _ccKick?.cancel();
    _ccWatch?.cancel();
    try {
      await _stt.stop();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _ccAfter(bool error) {
    if (!_cc || !mounted) return;
    _ccLastCb = DateTime.now();
    if (error) {
      _ccErrors++;
      if (_ccErrors >= 6) {
        unawaited(_ccStop());
        _snack('Captions stopped. This phone could not recognise that language.');
        return;
      }
    }
    _ccKick?.cancel();
    _ccKick = Timer(Duration(milliseconds: error ? 1500 : 300), () {
      unawaited(_ccListen());
    });
  }

  Future<void> _ccListen() async {
    if (!_cc || _ccBusy || !mounted) return;
    _ccBusy = true;
    try {
      await _stt.listen(
        onResult: (r) {
          _ccLastCb = DateTime.now();
          if (!r.finalResult) return;
          final w = r.recognizedWords.trim();
          if (w.isNotEmpty) {
            _ccErrors = 0;
            unawaited(
              _lmApi('POST', widget.sessionId, '/captions', body: <String, dynamic>{'text': w})
                  .catchError((_) => <String, dynamic>{}),
            );
          }
          _ccAfter(false);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
        localeId: _ccLocale,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (_) {
      _ccAfter(true);
    } finally {
      _ccBusy = false;
    }
  }

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
          _lmRoundButton(
            icon: _LiveMediaBus.hostSound.value ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            onTap: _toggleSound,
          ),
          const SizedBox(height: 10),
          _lmRoundButton(icon: Icons.perm_media_rounded, onTap: _openSheet),
          const SizedBox(height: 10),
          _lmRoundButton(
            icon: Icons.closed_caption_rounded,
            bg: _cc ? Colors.green.shade700 : null,
            onTap: _toggleCc,
          ),
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
  Timer? _tick;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _LiveMediaBus.nudge.addListener(_r);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
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
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          requestType: RequestType.common,
          maxAssets: 1,
        ),
      );
      if (assets == null || assets.isEmpty) return;
      final asset = assets.first;
      if (asset.duration > 600) {
        _note('That video is longer than 10 minutes.');
        return;
      }
      final file = await asset.originFile;
      if (file == null) {
        _note('Unable to read that file.');
        return;
      }
      final path = file.path;
      final size = await file.length();
      if (size <= 0) {
        _note('That file is empty.');
        return;
      }
      if (size > AppConstants.maxFileSizeBytes) {
        _note('That file is too large.');
        return;
      }
      final lower = path.toLowerCase();
      final dot = lower.lastIndexOf('.');
      final ext = dot >= 0 ? lower.substring(dot + 1) : '';
      const types = <String, String>{
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
      };
      final contentType = types[ext];
      if (contentType == null) {
        _note('Use a JPG, PNG, WEBP, GIF, MP4, WEBM or MOV file.');
        return;
      }
      final kind = contentType.startsWith('video/') ? 'video' : 'image';
      final token = await _lmStorage.read(key: AppConstants.keySessionToken);
      if (token == null || token.isEmpty) {
        _note('Please sign in again.');
        return;
      }
      if (mounted) {
        setState(() {
          _busy = true;
          _msg = 'Uploading… 0%';
        });
      }
      final url = await _directUpload(file, size, path.split('/').last, contentType, token);
      if (!mounted) return;
      await _show(url, kind);
    } catch (e) {
      if (e is StateError && e.message == 'cancelled') return;
      _note('Upload failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _directUpload(
    dart_io.File file,
    int size,
    String name,
    String contentType,
    String token,
  ) async {
    final init = await http
        .post(
          Uri.parse('${AppConstants.serverUrl}/api/live/${widget.sessionId}/media/upload-init'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'fileName': name,
            'contentType': contentType,
            'size': size,
            'folder': 'live_media',
          }),
        )
        .timeout(const Duration(seconds: 30));
    final initData = jsonDecode(init.body);
    if (initData is! Map ||
        initData['success'] != true ||
        initData['key'] == null ||
        initData['uploadId'] == null ||
        initData['capability'] == null) {
      throw StateError('Upload could not start.');
    }
    final key = initData['key'] as String;
    final uploadId = initData['uploadId'] as String;
    final capability = initData['capability'] as String;
    final worker = dio.Dio(
      dio.BaseOptions(
        baseUrl: AppConstants.mediaWorkerUrl,
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    const chunk = 8 * 1024 * 1024;
    final totalParts = (size + chunk - 1) ~/ chunk;
    final parts = <Map<String, dynamic>>[];
    var done = 0;
    var lastPct = -1;
    try {
      for (var n = 1; n <= totalParts; n++) {
        if (!mounted) throw StateError('cancelled');
        final start = (n - 1) * chunk;
        final end = start + chunk < size ? start + chunk : size;
        final len = end - start;
        Map<String, dynamic>? okPart;
        Object? lastErr;
        for (var attempt = 1; attempt <= 3 && okPart == null; attempt++) {
          try {
            final r = await worker.put(
              '/multipart/part',
              queryParameters: <String, dynamic>{
                'key': key,
                'uploadId': uploadId,
                'partNumber': n,
              },
              data: file.openRead(start, end),
              options: dio.Options(
                headers: <String, dynamic>{
                  'Authorization': 'Bearer $capability',
                  'Content-Type': 'application/octet-stream',
                  'Content-Length': len,
                },
              ),
              onSendProgress: (sent, total) {
                final overall = done + (sent > len ? len : sent);
                final pct = overall * 100 ~/ size;
                if (pct != lastPct) {
                  lastPct = pct;
                  _note('Uploading… $pct%');
                }
              },
            );
            final d = r.data;
            if (d is Map && d['success'] == true && d['etag'] != null) {
              okPart = <String, dynamic>{'partNumber': n, 'etag': d['etag']};
            } else {
              throw StateError('Part failed.');
            }
          } catch (e) {
            lastErr = e;
            if (attempt < 3) {
              await Future<void>.delayed(Duration(seconds: attempt));
            }
          }
        }
        if (okPart == null) {
          throw StateError('Upload failed: $lastErr');
        }
        parts.add(okPart);
        done += len;
      }
      final c = await worker.post(
        '/multipart/complete',
        data: <String, dynamic>{
          'key': key,
          'uploadId': uploadId,
          'parts': parts,
        },
        options: dio.Options(
          headers: <String, dynamic>{
            'Authorization': 'Bearer $capability',
            'Content-Type': 'application/json',
          },
        ),
      );
      final cd = c.data;
      if (cd is Map && cd['success'] == true && cd['url'] != null) {
        return cd['url'] as String;
      }
      throw StateError('Upload could not finish.');
    } catch (e) {
      try {
        await worker.post(
          '/multipart/abort',
          data: <String, dynamic>{'key': key, 'uploadId': uploadId},
          options: dio.Options(
            headers: <String, dynamic>{
              'Authorization': 'Bearer $capability',
              'Content-Type': 'application/json',
            },
          ),
        );
      } catch (_) {}
      rethrow;
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
          TextButton(onPressed: () => Navigator.of(ctx).pop('youtube'), child: const Text('YouTube')),
        ],
      ),
    );
    final link = ctrl.text.trim();
    if (kind == null || link.isEmpty) return;
    if (mounted) setState(() => _busy = true);
    try {
      if (kind == 'youtube') {
        _accept(await _lmCall('POST', widget.sessionId, '/youtube', body: <String, dynamic>{'url': link}));
      } else {
        await _show(link, kind);
      }
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
    final isVideo = m != null && (m['kind'] == 'video' || m['kind'] == 'youtube');
    final playing = m != null && m['playing'] == true;
    final camera = m != null && m['mode'] == 'camera';
    final durMs = _LiveMediaBus.durationMs;
    final ended = isVideo && durMs > 0 && _curPos() >= durMs - 300;
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
                    onPressed: _busy ? null : () => (ended ? _send('play', pos: 0) : _send(playing ? 'pause' : 'play')),
                    icon: Icon(
                      ended ? Icons.replay_rounded : (playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
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
              subtitle: const Text('Up to 10 minutes. Keep this open while uploading.', style: TextStyle(color: Colors.white54)),
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

// XAMELIVE_MEDIA2_V1: live captions (viewer side) and shared helpers.
const Map<String, String> _lmCcLocales = <String, String>{
  'en_US': 'English',
  'fr_FR': 'French',
  'sw_KE': 'Swahili',
  'ha_NG': 'Hausa',
  'yo_NG': 'Yoruba',
  'ak_GH': 'Twi',
  'ar_SA': 'Arabic',
  'pt_PT': 'Portuguese',
};

const Map<String, String> _lmCapLangs = <String, String>{
  'orig': 'Original (as spoken)',
  'en': 'English',
  'fr': 'French',
  'sw': 'Swahili',
  'ha': 'Hausa',
  'yo': 'Yoruba',
  'tw': 'Twi',
  'ar': 'Arabic',
  'pt': 'Portuguese',
};

class _LiveCapBus {
  static final ValueNotifier<String> lang = ValueNotifier<String>('');
}

Future<Map<String, dynamic>> _lmApi(
  String method,
  String sessionId,
  String path, {
  Map<String, dynamic>? body,
}) async {
  final token = await _lmStorage.read(key: AppConstants.keySessionToken);
  if (token == null || token.isEmpty) return <String, dynamic>{'success': false};
  final uri = Uri.parse('${AppConstants.serverUrl}/api/live/$sessionId$path');
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

/// Viewer's CC chip: choose caption language (or off).
class LiveCaptionsButton extends StatelessWidget {
  const LiveCaptionsButton({super.key});

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Captions off', style: TextStyle(color: Colors.white)),
                trailing: _LiveCapBus.lang.value.isEmpty
                    ? const Icon(Icons.check, color: Colors.greenAccent)
                    : null,
                onTap: () => Navigator.of(ctx).pop('off'),
              ),
              for (final e in _lmCapLangs.entries)
                ListTile(
                  title: Text(e.value, style: const TextStyle(color: Colors.white)),
                  trailing: _LiveCapBus.lang.value == e.key
                      ? const Icon(Icons.check, color: Colors.greenAccent)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    _LiveCapBus.lang.value = choice == 'off' ? '' : choice;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _LiveCapBus.lang,
      builder: (context, lang, _) {
        return Material(
          color: lang.isNotEmpty
              ? Colors.green.shade700
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _pick(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(Icons.closed_caption_rounded, color: Colors.white, size: 20),
            ),
          ),
        );
      },
    );
  }
}

class _CapLine {
  _CapLine(this.text) : at = DateTime.now();

  final String text;
  final DateTime at;
}

/// Viewer's caption lines, shown above the host info.
class LiveCaptionsOverlay extends StatefulWidget {
  const LiveCaptionsOverlay({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<LiveCaptionsOverlay> createState() => _LiveCaptionsOverlayState();
}

class _LiveCaptionsOverlayState extends State<LiveCaptionsOverlay> {
  Timer? _timer;
  bool _busy = false;
  int _since = -1;
  final List<_CapLine> _lines = <_CapLine>[];

  @override
  void initState() {
    super.initState();
    _LiveCapBus.lang.addListener(_onLang);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void _onLang() {
    _since = -1;
    _lines.clear();
    if (mounted) setState(() {});
    _tick();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final before = _lines.length;
    _lines.removeWhere((l) => DateTime.now().difference(l.at).inSeconds >= 7);
    if (_lines.length != before) setState(() {});
    final lang = _LiveCapBus.lang.value;
    if (lang.isEmpty || _busy) return;
    _busy = true;
    try {
      final q = _since < 0 ? '' : '&since=$_since';
      final d = await _lmApi('GET', widget.sessionId, '/captions?lang=$lang$q');
      if (!mounted || _LiveCapBus.lang.value != lang) return;
      if (d['success'] == true) {
        final seq = d['seq'];
        final items = d['items'];
        if (seq is num) _since = seq.toInt();
        if (items is List && items.isNotEmpty) {
          for (final it in items) {
            if (it is Map && it['text'] != null) {
              _lines.add(_CapLine(it['text'].toString()));
            }
          }
          while (_lines.length > 3) {
            _lines.removeAt(0);
          }
          setState(() {});
        }
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _LiveCapBus.lang.removeListener(_onLang);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 84,
      bottom: 156,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in _lines)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.25),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
