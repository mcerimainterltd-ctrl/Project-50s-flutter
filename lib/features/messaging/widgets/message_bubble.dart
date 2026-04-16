// Mirrors: messageBubble() in messaging.js
// Handles: text, emoji-only, image, video, audio, file, reply quote,
//          forwarded label, status ticks, long-press menu, view-once
// BUG 3 FIX: images open full-screen viewer, videos/files download & open

import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/message.dart';

class MessageBubble extends ConsumerWidget {
  final XameMessage  message;
  final bool         isSelf;
  final bool         isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.isSelected,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: onLongPress,
      onTap:       onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? XameColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Align(
          alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Column(
              crossAxisAlignment:
                  isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.replyToId != null)
                  _ReplyQuote(text: message.replyToText ?? ''),
                Container(
                  margin: EdgeInsets.only(
                      left: isSelf ? 40 : 0, right: isSelf ? 0 : 40),
                  padding: _needsPadding
                      ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isSelf
                        ? const Color(0xFF1A4A3A)
                        : XameColors.darkCard,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isSelf ? 18 : 4),
                      bottomRight: Radius.circular(isSelf ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.forwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: const [
                            Icon(Icons.forward, size: 12, color: Colors.white38),
                            SizedBox(width: 4),
                            Text('Forwarded',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic)),
                          ]),
                        ),
                      _buildContent(context),
                      _buildTimeRow(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _needsPadding =>
      message.type == MessageType.text || message.type == MessageType.file;

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return _ImageBubble(
            url: message.fileUrl ?? '',
            caption: message.text,
            viewOnce: message.viewOnce);
      case MessageType.video:
        return _VideoBubble(
            url: message.fileUrl ?? '',
            fileName: message.fileName ?? 'video');
      case MessageType.audio:
        return _AudioBubble(
            url: message.fileUrl ?? '',
            fileName: message.fileName ?? 'audio',
            isSelf: isSelf);
      case MessageType.file:
        return _FileBubble(
            url: message.fileUrl ?? '',
            fileName: message.fileName ?? 'file',
            mime: message.fileMime ?? '');
      case MessageType.text:
        return _TextContent(text: message.text, isSelf: isSelf);
    }
  }

  Widget _buildTimeRow() {
    final dt   = DateTime.fromMillisecondsSinceEpoch(message.ts);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: _needsPadding
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(time,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if (isSelf) ...[
          const SizedBox(width: 4),
          _StatusTick(status: message.status),
        ],
      ]),
    );
  }
}

// ── Text content ──────────────────────────────────────────────────────────
class _TextContent extends StatelessWidget {
  final String text;
  final bool   isSelf;
  const _TextContent({required this.text, required this.isSelf});

  bool get _isEmojiOnly {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;
    return RegExp(r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\s]+$', unicode: true)
        .hasMatch(cleaned);
  }

  @override
  Widget build(BuildContext context) => _isEmojiOnly
      ? Text(text.trim(), style: const TextStyle(fontSize: 36))
      : Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, height: 1.4));
}

// ── Status ticks ──────────────────────────────────────────────────────────
class _StatusTick extends StatelessWidget {
  final String status;
  const _StatusTick({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'seen')
      return const Icon(Icons.done_all, size: 14, color: Color(0xFF4FC3F7));
    if (status == 'delivered')
      return const Icon(Icons.done_all, size: 14, color: Colors.white38);
    return const Icon(Icons.done, size: 14, color: Colors.white38);
  }
}

// ── Reply quote ───────────────────────────────────────────────────────────
class _ReplyQuote extends StatelessWidget {
  final String text;
  const _ReplyQuote({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
          left: BorderSide(color: XameColors.primary, width: 3)),
    ),
    child: Text(text.isNotEmpty ? text : '📎 Attachment',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        maxLines: 2, overflow: TextOverflow.ellipsis),
  );
}

// ── Image bubble — BUG 3 FIX: tapping opens full-screen hero viewer ───────
class _ImageBubble extends StatelessWidget {
  final String url;
  final String caption;
  final bool   viewOnce;
  const _ImageBubble(
      {required this.url, required this.caption, required this.viewOnce});

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _FullScreenImageViewer(url: url),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (viewOnce) {
      return GestureDetector(
        onTap: () => _openFullScreen(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, color: Colors.white54, size: 18),
            SizedBox(width: 8),
            Text('Tap to view',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Hero(
          tag: url,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: CachedNetworkImage(
              imageUrl: url,
              fit:      BoxFit.cover,
              width:    double.infinity,
              placeholder: (_, __) => const SizedBox(
                  height: 180,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: XameColors.primary, strokeWidth: 2))),
              errorWidget: (_, __, ___) => const SizedBox(
                  height: 80,
                  child: Center(
                      child: Icon(Icons.broken_image, color: Colors.white24))),
            ),
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(caption,
                style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );
  }
}

// ── Full-screen image viewer with download ────────────────────────────────
class _FullScreenImageViewer extends StatefulWidget {
  final String url;
  const _FullScreenImageViewer({required this.url});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  bool _downloading = false;
  double _progress  = 0;

  Future<void> _download() async {
    setState(() { _downloading = true; _progress = 0; });
    try {
      final dir  = await getExternalStorageDirectory() ??
                   await getApplicationDocumentsDirectory();
      final name = widget.url.split('/').last.split('?').first;
      final path = '${dir.path}/$name';
      await Dio().download(widget.url, path,
          onReceiveProgress: (recv, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = recv / total);
        }
      });
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved to $path'),
          backgroundColor: XameColors.darkCard,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black54,
      leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
      actions: [
        if (_downloading)
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: Colors.white, strokeWidth: 2),
            ),
          )
        else
          IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              onPressed: _download),
      ],
    ),
    body: Hero(
      tag: widget.url,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(
                color: XameColors.primary),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white24, size: 60),
          ),
        ),
      ),
    ),
  );
}

// ── Video bubble — BUG 3 FIX: tap downloads then opens with system player ─
class _VideoBubble extends StatefulWidget {
  final String url, fileName;
  const _VideoBubble({required this.url, required this.fileName});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool   _loading  = false;
  double _progress = 0;

  Future<void> _open() async {
    setState(() { _loading = true; _progress = 0; });
    try {
      final dir  = await getTemporaryDirectory();
      final name = widget.url.split('/').last.split('?').first
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path = '${dir.path}/$name';
      if (!File(path).existsSync()) {
        await Dio().download(widget.url, path,
            onReceiveProgress: (recv, total) {
          if (total > 0 && mounted) setState(() => _progress = recv / total);
        });
      }
      if (mounted) setState(() => _loading = false);
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open video: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _loading ? null : _open,
    child: Container(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: XameColors.secondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12)),
          ),
          if (_loading)
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: XameColors.secondary, strokeWidth: 2),
            )
          else
            const Icon(Icons.play_circle_outline,
                color: XameColors.secondary, size: 28),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.fileName,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(_loading
              ? 'Opening${_progress > 0 ? ' ${(_progress * 100).toInt()}%' : '...'}'
              : 'Tap to play',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
      ]),
    ),
  );
}

// ── File bubble — BUG 3 FIX: tap downloads to cache then opens ────────────
class _FileBubble extends StatefulWidget {
  final String url, fileName, mime;
  const _FileBubble(
      {required this.url, required this.fileName, required this.mime});

  @override
  State<_FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<_FileBubble> {
  bool   _loading  = false;
  double _progress = 0;

  IconData get _icon {
    final m = widget.mime.toLowerCase();
    if (m.contains('pdf'))                         return Icons.picture_as_pdf_outlined;
    if (m.contains('word') || m.contains('doc'))   return Icons.description_outlined;
    if (m.contains('sheet') || m.contains('excel'))return Icons.table_chart_outlined;
    if (m.contains('image'))                        return Icons.image_outlined;
    if (m.contains('audio'))                        return Icons.audio_file_outlined;
    if (m.contains('video'))                        return Icons.video_file_outlined;
    if (m.contains('zip') || m.contains('rar'))     return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _openFile() async {
    setState(() { _loading = true; _progress = 0; });
    try {
      final dir  = await getTemporaryDirectory();
      final name = widget.fileName.isNotEmpty
          ? widget.fileName
          : widget.url.split('/').last.split('?').first;
      final path = '${dir.path}/$name';
      if (!File(path).existsSync()) {
        await Dio().download(widget.url, path,
            onReceiveProgress: (recv, total) {
          if (total > 0 && mounted) setState(() => _progress = recv / total);
        });
      }
      if (mounted) setState(() => _loading = false);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No app found to open this file type'),
          backgroundColor: XameColors.darkCard,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _loading ? null : _openFile,
    child: Row(children: [
      Stack(alignment: Alignment.center, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: XameColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10)),
        ),
        if (_loading)
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: XameColors.accent, strokeWidth: 2),
          )
        else
          Icon(_icon, color: XameColors.accent, size: 22),
      ]),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(_loading
            ? '${(_progress * 100).toInt()}%'
            : (widget.mime.split('/').lastOrNull?.toUpperCase() ?? 'FILE'),
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ])),
      _loading
          ? const SizedBox.shrink()
          : const Icon(Icons.download_outlined, color: Colors.white38, size: 20),
    ]),
  );
}

// ── Audio bubble ──────────────────────────────────────────────────────────
class _AudioBubble extends StatefulWidget {
  final String url, fileName;
  final bool   isSelf;
  const _AudioBubble(
      {required this.url, required this.fileName, required this.isSelf});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  AudioPlayer? _player;
  bool     _playing  = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _subs.add(_player!.positionStream.listen(
        (p) { if (mounted) setState(() => _position = p); }));
    _subs.add(_player!.durationStream.listen(
        (d) { if (d != null && mounted) setState(() => _duration = d); }));
    _subs.add(_player!.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed && mounted) {
        setState(() { _playing = false; _position = Duration.zero; });
      }
    }));
    _player!.setUrl(widget.url).catchError((_) {});
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player?.pause();
      setState(() => _playing = false);
    } else {
      if (_duration > Duration.zero && _position >= _duration) {
        await _player?.seek(Duration.zero);
      }
      await _player?.play();
      setState(() => _playing = true);
    }
  }

  String _fmtDur(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: XameColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: XameColors.primary.withValues(alpha: 0.4)),
              ),
              child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: XameColors.primary, size: 26),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 32,
              child: _WaveformBars(
                  progress:  progress,
                  isSelf:    widget.isSelf,
                  isPlaying: _playing)),
            const SizedBox(height: 4),
            Text(_playing ? _fmtDur(_position) : _fmtDur(_duration),
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ])),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight:        2,
            thumbShape:         const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape:       const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor:   XameColors.primary,
            inactiveTrackColor: Colors.white12,
            thumbColor:         XameColors.primary,
            overlayColor:       XameColors.primary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: progress,
            onChanged: _duration.inMilliseconds > 0
                ? (v) => _player?.seek(Duration(
                    milliseconds: (v * _duration.inMilliseconds).round()))
                : null,
          ),
        ),
      ]),
    );
  }
}

// ── Waveform bars ─────────────────────────────────────────────────────────
class _WaveformBars extends StatefulWidget {
  final double progress;
  final bool   isSelf;
  final bool   isPlaying;
  const _WaveformBars(
      {required this.progress, required this.isSelf, required this.isPlaying});

  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  static const _bars = 28;
  static final _heights = List.generate(
      _bars, (i) => 8.0 + Random(i * 7 + 3).nextDouble() * 20);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    if (widget.isPlaying) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_WaveformBars old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(_bars, (i) {
        final base     = _heights[i];
        final fraction = i / _bars;
        final isPast   = fraction < widget.progress;
        final animH    = widget.isPlaying && isPast
            ? base * (0.6 + 0.4 * (sin(_ctrl.value * pi + i * 0.4) * 0.5 + 0.5))
            : base;
        return Container(
          width: 3, height: animH,
          decoration: BoxDecoration(
            color: isPast
                ? XameColors.primary
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    ),
  );
}
