// lib/features/messaging/widgets/message_bubble.dart
// XamePage 2.1 — Build 237+
// Full media bubbles: video frame thumbnails, PDF page-1 preview,
// rich document cards, shimmer loading, download + open.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/screens/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/settings/screens/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:better_player_enhanced/better_player.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/message.dart';
import '../../../core/config/constants.dart';


// ─── Resolve relative URLs from server ───────────────────────────────────
String _resolveUrl(String url, {bool forDisplay = false}) {
  if (url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) {
    if (url.contains('res.cloudinary.com')) {
      // Raw files uploaded via unsigned preset are publicly accessible as-is
      // fl_attachment transformation causes 401 on raw resource type
      // so we serve the direct URL without any transformation
    }
    return url;
  }
  // Relative path → prepend server base
  final base = AppConstants.serverUrl.replaceAll(RegExp(r'/\$'), '');
  final path = url.startsWith('/') ? url : '/\$url';
  return '\$base\$path';
}
// ─── In-memory thumbnail caches (process lifetime) ────────────────────────
final _videoThumbCache = <String, Uint8List?>{};
final _pdfThumbCache   = <String, Uint8List?>{};

class MessageBubble extends ConsumerWidget {
  final XameMessage  message;
  final bool         isSelf;
  final bool         isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final void Function(String emoji)? onReact;

  MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.isSelected,
    required this.onLongPress,
    required this.onTap,
    this.onReact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress:       onLongPress,
      onTap:             onTap,
      onDoubleTap:       () => _showReactionPicker(context),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        color: isSelected
            ? context.xPrimary.withValues(alpha: 0.15)
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
                    color: isSelf ? context.xBubbleSent : context.xBubbleRecv,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isSelf ? 18 : 4),
                      bottomRight: Radius.circular(isSelf ? 4  : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.forwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Icon(Icons.forward, size: 12, color: context.xMuted),
                            SizedBox(width: 4),
                            Text('Forwarded',
                                style: TextStyle(color: context.xMuted,
                                    fontSize: 11, fontStyle: FontStyle.italic)),
                          ]),
                        ),
                      _buildContent(context),
                      _buildTimeRow(context),
                      if ((message.reactions ?? {}).isNotEmpty)
                        _ReactionBar(reactions: message.reactions!, isSelf: isSelf),
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

  void _showReactionPicker(BuildContext context) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '👏'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: XameColors.darkCard,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis.map((e) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onReact?.call(e);
            },
            child: Text(e, style: const TextStyle(fontSize: 28)),
          )).toList(),
        ),
      ),
    );
  }

  bool get _needsPadding =>
      message.type == MessageType.text || message.type == MessageType.file;

  Widget _buildContent(BuildContext context) {
    if (message.isDeleted) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 13, color: context.xMuted),
        SizedBox(width: 5),
        Text(
          isSelf ? "You deleted this message" : "This message was deleted",
          style: TextStyle(color: context.xMuted, fontSize: 13, fontStyle: FontStyle.italic),
        ),
      ]);
    }
    switch (message.type) {
      case MessageType.image:
        return _ImageBubble(
            url: message.fileUrl ?? '',
            caption: message.text,
            viewOnce: message.viewOnce);
      case MessageType.video:
        return _VideoBubble(
            url:       message.fileUrl ?? '',
            fileName:  message.fileName ?? 'video',
            fileSize:  message.fileSize,
            localPath: message.localPath);
      case MessageType.audio:
        return _AudioBubble(
            url:      message.fileUrl ?? '',
            fileName: message.fileName ?? 'audio',
            isSelf:   isSelf);
      case MessageType.file:
        return _FileBubble(
            url:       message.fileUrl ?? '',
            fileName:  message.fileName ?? 'file',
            mime:      message.fileMime ?? '',
            fileSize:  message.fileSize,
            localPath: message.localPath);
      case MessageType.text:
        return _TextContent(text: message.text, isSelf: isSelf);
    }
  }

  Widget _buildTimeRow(BuildContext context) {
    final dt   = DateTime.fromMillisecondsSinceEpoch(message.ts);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: _needsPadding
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(time, style: TextStyle(color: context.xMuted, fontSize: 10)),
        if (isSelf) ...[
          const SizedBox(width: 4),
          _StatusTick(status: message.status),
        ],
      ]),
    );
  }
}

// ─── Shimmer loading placeholder ─────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  final double width, height;
  final double radius;
  const _Shimmer({required this.width, required this.height, this.radius = 14});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width, height: widget.height,
        child: CustomPaint(painter: _ShimmerPainter(_anim.value)),
      ),
    ),
  );
}

class _ShimmerPainter extends CustomPainter {
  final double position;
  _ShimmerPainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final base    = XameColors.darkSurface;
    final highlight = XameColors.darkCard;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final gradient = LinearGradient(
      begin: Alignment(-1 + position * 2, 0),
      end:   Alignment(position * 2, 0),
      colors: [base, highlight, base],
      stops: const [0.0, 0.5, 1.0],
    );
    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.position != position;
}

// ─── File size formatter ──────────────────────────────────────────────────
String _fmtSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}

// ─── Text content ─────────────────────────────────────────────────────────
class _TextContent extends ConsumerWidget {
  final String text; final bool isSelf;
  _TextContent({required this.text, required this.isSelf});

  bool get _isEmojiOnly {
    final c = text.trim();
    if (c.isEmpty) return false;
    return RegExp(r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\s]+$', unicode: true)
        .hasMatch(c);
  }

  double _fontSize(WidgetRef ref) {
    final fs = ref.watch(settingsProvider).fontSize;
    if (fs == 'small') return 13;
    if (fs == 'large') return 17;
    return 15;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => _isEmojiOnly
      ? Text(text.trim(), style: TextStyle(fontSize: 36))
      : Text(text,
            style: TextStyle(
                color: context.xBubbleSentText,
                fontSize: _fontSize(ref),
                height: 1.4));
}

// ─── Status ticks ─────────────────────────────────────────────────────────
class _StatusTick extends StatelessWidget {
  final String status;
  _StatusTick({required this.status});
  @override
  Widget build(BuildContext context) {
    if (status == 'uploading')
      return SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: context.xText.withValues(alpha: 0.54)));
    if (status == 'failed')
      return Tooltip(
        message: 'Upload failed — long press to retry',
        child: Icon(Icons.error_outline, size: 14, color: context.xDanger));
    if (status == 'seen')
      return Icon(Icons.done_all, size: 14, color: context.xPrimary);
    if (status == 'delivered')
      return Icon(Icons.done_all, size: 14, color: context.xMuted);
    return Icon(Icons.done, size: 14, color: context.xMuted);
  }
}

// ─── Reply quote ──────────────────────────────────────────────────────────
class _ReplyQuote extends StatelessWidget {
  final String text;
  _ReplyQuote({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      border: Border(left: BorderSide(color: XameColors.primary, width: 3)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replied message',
            style: TextStyle(color: XameColors.primary,
                fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(text.isNotEmpty ? text : '📎 Attachment',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}

// ─── Image bubble ─────────────────────────────────────────────────────────
class _ImageBubble extends StatelessWidget {
  final String url, caption;
  final bool   viewOnce;
  _ImageBubble(
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, color: context.xText.withValues(alpha: 0.54), size: 18),
            SizedBox(width: 8),
            Text('Tap to view',
                style: TextStyle(color: context.xText.withValues(alpha: 0.54), fontSize: 13)),
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
            child: CachedNetworkImage(
              imageUrl: _resolveUrl(url), fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => _Shimmer(
                  width: double.infinity, height: 180),
              errorWidget: (_, __, ___) => SizedBox(height: 80,
                  child: Center(
                      child: Icon(Icons.broken_image, color: context.xMuted.withValues(alpha: 0.5)))),
            ),
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(caption,
                style: TextStyle(color: context.xText, fontSize: 13))),
      ]),
    );
  }
}

// ─── Full-screen image viewer ─────────────────────────────────────────────
class _FullScreenImageViewer extends StatefulWidget {
  final String url;
  _FullScreenImageViewer({required this.url});
  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  bool   _downloading = false;
  double _progress    = 0;

  Future<void> _download() async {
    setState(() { _downloading = true; _progress = 0; });
    try {
      final dir  = await getExternalStorageDirectory() ??
                   await getApplicationDocumentsDirectory();
      final name = widget.url.split('/').last.split('?').first;
      final path = '${dir.path}/$name';
      final cached = File(path);
      if (cached.existsSync() && cached.lengthSync() == 0) await cached.delete();
      await Dio(BaseOptions(
        connectTimeout: Duration(seconds: 30),
        receiveTimeout: Duration(minutes: 5),
      )).download(_resolveUrl(widget.url), path,
          onReceiveProgress: (r, t) {
        if (t > 0 && mounted) setState(() => _progress = r / t);
      });
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved to $path'),
            backgroundColor: XameColors.darkCard));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black54,
      leading: IconButton(
          icon: Icon(Icons.close, color: XameColors.darkBg),
          onPressed: () => Navigator.pop(context)),
      actions: [
        if (_downloading)
          Padding(padding: const EdgeInsets.all(14),
            child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: XameColors.darkBg, strokeWidth: 2)))
        else
          IconButton(
              icon: Icon(Icons.download_outlined, color: XameColors.darkBg),
              onPressed: _download),
      ],
    ),
    body: Hero(
      tag: widget.url,
      child: InteractiveViewer(
        minScale: 0.5, maxScale: 5.0,
        child: Center(child: CachedNetworkImage(
          imageUrl: _resolveUrl(widget.url), fit: BoxFit.contain,
          placeholder: (_, __) =>
              CircularProgressIndicator(color: XameColors.primary),
          errorWidget: (_, __, ___) =>
              Icon(Icons.broken_image, color: XameColors.darkSurface.withValues(alpha: 0.5), size: 60),
        )),
      ),
    ),
  );
}

// ─── Video bubble — frame thumbnail ──────────────────────────────────────
class _VideoBubble extends StatefulWidget {
  final String  url, fileName;
  final int?    fileSize;
  final String? localPath;
  const _VideoBubble(
      {required this.url, required this.fileName, this.fileSize,
       this.localPath});
  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}


class _VideoBubbleState extends State<_VideoBubble> {
  Uint8List? _thumb;
  bool _thumbLoading = true;
  bool _playing = false;
  BetterPlayerController? _playerCtrl;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void dispose() {
    _playerCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (_videoThumbCache.containsKey(widget.url)) {
      if (mounted) setState(() {
        _thumb = _videoThumbCache[widget.url];
        _thumbLoading = false;
      });
      return;
    }
    try {
      final source = (widget.localPath != null && File(widget.localPath!).existsSync())
          ? widget.localPath! : _resolveUrl(widget.url);
      if (source.isEmpty) {
        _videoThumbCache[widget.url] = null;
        if (mounted) setState(() => _thumbLoading = false);
        return;
      }
      final bytes = await VideoThumbnail.thumbnailData(
        video: source, imageFormat: ImageFormat.JPEG,
        maxWidth: 480, quality: 72, timeMs: 0);
      _videoThumbCache[widget.url] = bytes;
      if (mounted) setState(() { _thumb = bytes; _thumbLoading = false; });
    } catch (_) {
      _videoThumbCache[widget.url] = null;
      if (mounted) setState(() => _thumbLoading = false);
    }
  }

  void _playInline() {
    final source = (widget.localPath != null && File(widget.localPath!).existsSync())
        ? BetterPlayerDataSource(BetterPlayerDataSourceType.file, widget.localPath!)
        : BetterPlayerDataSource(BetterPlayerDataSourceType.network, _resolveUrl(widget.url));

    _playerCtrl = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        aspectRatio: 16 / 9,
        fit: BoxFit.cover,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enableMute: true,
          enablePlayPause: true,
          enableProgressBar: true,
          enableSkips: false,
          controlBarColor: Colors.black54,
          iconsColor: Colors.white,
          progressBarPlayedColor: XameColors.primary,
          progressBarHandleColor: XameColors.primary,
          progressBarBackgroundColor: Colors.white24,
        ),
        placeholder: _thumb != null ? Image.memory(_thumb!, fit: BoxFit.cover) : null,
      ),
      betterPlayerDataSource: source,
    );
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.72;
    final h = w * 9 / 16;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: SizedBox(
        width: w, height: h,
        child: _playing && _playerCtrl != null
          ? BetterPlayer(controller: _playerCtrl!)
          : GestureDetector(
              onTap: _playInline,
              child: Stack(fit: StackFit.expand, children: [
                if (_thumbLoading)
                  _Shimmer(width: w, height: h, radius: 0)
                else if (_thumb != null)
                  Image.memory(_thumb!, fit: BoxFit.cover)
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [context.xBg, context.xSurface, context.xCard])),
                    child: Center(child: Icon(Icons.movie_outlined,
                        color: context.xMuted.withValues(alpha: 0.5), size: 48))),
                Center(child: Container(
                  width: 52, height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.black54),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32))),
              ]),
            ),
      ),
    );
  }
}

// ─── File bubble — PDF page-1 preview + rich doc cards ───────────────────
class _FileBubble extends StatefulWidget {
  final String  url, fileName, mime;
  final int?    fileSize;
  final String? localPath;
  const _FileBubble({
    required this.url,      required this.fileName,
    required this.mime,     this.fileSize,
    this.localPath,
  });
  @override
  State<_FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<_FileBubble> {
  Uint8List? _pdfThumb;
  bool _pdfLoading  = false;
  bool _opening     = false;
  double _progress  = 0;

  bool get _isPdf => widget.mime.toLowerCase().contains('pdf') ||
      widget.fileName.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    if (_isPdf) _loadPdfThumb();
  }

  Future<void> _loadPdfThumb() async {
    if (_pdfThumbCache.containsKey(widget.url)) {
      if (mounted) setState(() {
        _pdfThumb   = _pdfThumbCache[widget.url];
        _pdfLoading = false;
      });
      return;
    }
    setState(() => _pdfLoading = true);
    try {
      // Download PDF to temp, render page 1
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/${widget.url.hashCode}.pdf';
      final pdfCached = File(path);
      if (!pdfCached.existsSync() || pdfCached.lengthSync() == 0) {
        if (pdfCached.existsSync()) await pdfCached.delete();
        await Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
        )).download(_resolveUrl(widget.url), path);
      }
      final doc  = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      final img  = await page.render(
        width:           480,
        height:          (480 * page.height / page.width).roundToDouble(),
        format:          PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      await doc.close();
      _pdfThumbCache[widget.url] = img?.bytes;
      if (mounted) setState(() {
        _pdfThumb   = img?.bytes;
        _pdfLoading = false;
      });
    } catch (_) {
      _pdfThumbCache[widget.url] = null;
      if (mounted) setState(() => _pdfLoading = false);
    }
  }

  Future<void> _openFile() async {
    setState(() { _opening = true; _progress = 0; });
    try {
      // 1. Use local path directly if file still exists on device
      if (widget.localPath != null && File(widget.localPath!).existsSync()) {
        if (mounted) setState(() => _opening = false);
        final mimeType = widget.mime.isNotEmpty ? widget.mime : null;
        final result = await OpenFilex.open(widget.localPath!, type: mimeType);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('No app found to open this file (${result.message})'),
              backgroundColor: XameColors.darkCard));
        }
        return;
      }

      // 2. No local file — need remote URL to download
      if (widget.url.isEmpty) {
        if (mounted) {
          setState(() => _opening = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('File not available — upload may still be in progress'),
              backgroundColor: Colors.orange));
        }
        return;
      }

      // 3. Download to cache then open
      final dir  = await getTemporaryDirectory();
      final name = widget.fileName.isNotEmpty
          ? widget.fileName
          : widget.url.split('/').last.split('?').first;
      final path = '${dir.path}/$name';
      final cached = File(path);
      if (!cached.existsSync() || cached.lengthSync() == 0) {
        if (cached.existsSync()) await cached.delete();
        final resolvedUrl = _resolveUrl(widget.url);
        await Dio(BaseOptions(
          connectTimeout: Duration(seconds: 30),
          receiveTimeout: Duration(minutes: 5),
        )).download(resolvedUrl, path,
            onReceiveProgress: (r, t) {
          if (t > 0 && mounted) setState(() => _progress = r / t);
        });
      }
      if (mounted) setState(() => _opening = false);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No app found to open this file type'),
            backgroundColor: XameColors.darkCard));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _opening = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent));
      }
    }
  }

  // ── Per-type visual config ───────────────────────────────────────────
  _DocStyle get _style {
    final m = widget.mime.toLowerCase();
    final n = widget.fileName.toLowerCase();
    if (m.contains('pdf')   || n.endsWith('.pdf'))
      return _DocStyle(Icons.picture_as_pdf_outlined,
          XameColors.danger, Color(0xFF23111100), 'PDF');
    if (m.contains('word')  || n.endsWith('.doc') || n.endsWith('.docx'))
      return _DocStyle(Icons.description_outlined,
          XameColors.primary, Color(0xFF23001155), 'WORD');
    if (m.contains('sheet') || m.contains('excel') ||
        n.endsWith('.xls')  || n.endsWith('.xlsx'))
      return _DocStyle(Icons.table_chart_outlined,
          XameColors.accent, Color(0xFF23001100), 'EXCEL');
    if (m.contains('presentation') || m.contains('powerpoint') ||
        n.endsWith('.ppt')  || n.endsWith('.pptx'))
      return _DocStyle(Icons.slideshow_outlined,
          XameColors.danger, Color(0xFF23110000), 'PPT');
    if (m.contains('zip')   || m.contains('rar') || m.contains('tar') ||
        n.endsWith('.zip')  || n.endsWith('.rar'))
      return _DocStyle(Icons.folder_zip_outlined,
          XameColors.accent, Color(0xFF23110B00), 'ZIP');
    if (m.contains('audio') || n.endsWith('.mp3') || n.endsWith('.aac'))
      return _DocStyle(Icons.audio_file_outlined,
          XameColors.secondary, Color(0xFF23050011), 'AUDIO');
    if (m.contains('video') || n.endsWith('.mp4') || n.endsWith('.mov'))
      return _DocStyle(Icons.video_file_outlined,
          XameColors.accent, Color(0xFF23001111), 'VIDEO');
    if (m.contains('text')  || n.endsWith('.txt'))
      return _DocStyle(Icons.article_outlined,
          XameColors.darkBg.withValues(alpha: 0.7), Color(0xFF23111111), 'TXT');
    return _DocStyle(Icons.insert_drive_file_outlined,
        XameColors.accent, const Color(0xFF23000B1A), 'FILE');
  }

  @override
  Widget build(BuildContext context) {
    final st = _style;

    return GestureDetector(
      onTap: _opening ? null : _openFile,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.xCard.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: st.color.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          // ── File type icon pill ───────────────────────────────────
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: st.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: st.color.withValues(alpha: 0.25)),
            ),
            child: _opening
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        color: st.color, strokeWidth: 2))
                : Icon(st.icon, color: st.color, size: 22),
          ),
          const SizedBox(width: 10),
          // ── Name + meta ───────────────────────────────────────────
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.fileName,
                  style: TextStyle(color: context.xText, fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                if (widget.fileSize != null) ...[
                  Text(_fmtSize(widget.fileSize),
                      style: TextStyle(color: context.xMuted, fontSize: 11)),
                  Text('  ·  ',
                      style: TextStyle(color: context.xMuted, fontSize: 11)),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: st.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(st.label,
                      style: TextStyle(color: st.color, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ),
              ]),
            ],
          )),
          const SizedBox(width: 8),
          // ── Download arrow ────────────────────────────────────────
          if (!_opening)
            Icon(Icons.download_rounded,
                color: st.color.withValues(alpha: 0.6), size: 20),
        ]),
      ),
    );
  }
}

class _DocStyle {
  final IconData icon;
  final Color    color;
  final Color    bgTint;
  final String   label;
  const _DocStyle(this.icon, this.color, this.bgTint, this.label);
}

// ─── Audio bubble ─────────────────────────────────────────────────────────
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
    _subs.add(_player!.positionStream
        .listen((p) { if (mounted) setState(() => _position = p); }));
    _subs.add(_player!.durationStream
        .listen((d) { if (d != null && mounted) setState(() => _duration = d); }));
    _subs.add(_player!.playerStateStream.listen((ps) async {
      if (ps.processingState == ProcessingState.completed && mounted) {
        await _player?.seek(Duration.zero);
        await _player?.stop();
        if (mounted) setState(() { _playing = false; _position = Duration.zero; });
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
      // Always seek to start if at end or position is zero after completion
      if (_position >= _duration && _duration > Duration.zero) {
        await _player?.seek(Duration.zero);
      }
      await _player?.play();
      setState(() => _playing = true);
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      constraints: BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: context.xPrimary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: context.xPrimary.withValues(alpha: 0.4)),
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: context.xPrimary, size: 26),
            ),
          ),
          SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 32,
              child: _WaveformBars(
                  progress: progress, isSelf: widget.isSelf,
                  isPlaying: _playing)),
            SizedBox(height: 4),
            Text(_playing ? _fmt(_position) : _fmt(_duration),
                style: TextStyle(color: context.xMuted, fontSize: 10)),
          ])),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight:        2,
            thumbShape:         RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape:       RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor:   context.xPrimary,
            inactiveTrackColor: context.xMuted.withValues(alpha: 0.25),
            thumbColor:         context.xPrimary,
            overlayColor:       context.xPrimary.withValues(alpha: 0.2),
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

// ─── Waveform bars ────────────────────────────────────────────────────────
class _WaveformBars extends StatefulWidget {
  final double progress;
  final bool   isSelf, isPlaying;
  const _WaveformBars(
      {required this.progress, required this.isSelf, required this.isPlaying});
  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  static const _bars = 28;
  static final _heights =
      List.generate(_bars, (i) => 8.0 + Random(i * 7 + 3).nextDouble() * 20);

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
    if (widget.isPlaying && !_ctrl.isAnimating)  _ctrl.repeat(reverse: true);
    if (!widget.isPlaying && _ctrl.isAnimating)   _ctrl.stop();
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
                : XameColors.darkBg.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    ),
  );
}
// ─── Reaction bar ────────────────────────────────────────────────────────────
class _ReactionBar extends StatelessWidget {
  final Map<String, String> reactions;
  final bool isSelf;
  const _ReactionBar({required this.reactions, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final Map<String, int> counts = {};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: isSelf ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        children: counts.entries.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: XameColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: XameColors.darkCard, width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(e.key, style: const TextStyle(fontSize: 13)),
            if (e.value > 1) ...[
              const SizedBox(width: 3),
              Text('\${e.value}',
                style: const TextStyle(fontSize: 11,
                    color: Colors.white70, fontWeight: FontWeight.w600)),
            ],
          ]),
        )).toList(),
      ),
    );
  }
}
