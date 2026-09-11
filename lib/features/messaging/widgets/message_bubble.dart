// lib/features/messaging/widgets/message_bubble.dart
// XamePage 2.1 — Build 237+
// Full media bubbles: video frame thumbnails, PDF page-1 preview,
// rich document cards, shimmer loading, download + open.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
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
import '../../../features/settings/screens/settings_screen.dart';


BorderRadius _bubbleBorderRadius(String style, bool isSelf) {
  switch (style) {
    case 'classic':
      return BorderRadius.only(
        topLeft:     const Radius.circular(4),
        topRight:    const Radius.circular(4),
        bottomLeft:  Radius.circular(isSelf ? 4 : 0),
        bottomRight: Radius.circular(isSelf ? 0 : 4),
      );
    case 'minimal':
      return BorderRadius.circular(24);
    default: // modern
      return BorderRadius.only(
        topLeft:     const Radius.circular(18),
        topRight:    const Radius.circular(18),
        bottomLeft:  Radius.circular(isSelf ? 18 : 4),
        bottomRight: Radius.circular(isSelf ? 4  : 18),
      );
  }
}

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
  final void Function(String)? onQuoteTap;
  final List<XameMessage>? allMessages;

  MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.isSelected,
    required this.onLongPress,
    required this.onTap,
    this.onReact,
    this.onQuoteTap,
    this.allMessages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress:       onLongPress,
      onTap:             onTap,
      onDoubleTap:       () => _showReactionPicker(context),
      child: AnimatedContainer(
        duration: Duration(milliseconds: ref.watch(settingsProvider).reducedMotion ? 0 : 150),
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
                  GestureDetector(
                    onTap: message.replyToId != null ? () => onQuoteTap?.call(message.replyToId!) : null,
                    child: _ReplyQuote(text: message.replyToText ?? '', fileUrl: message.replyToFileUrl, fileMime: message.replyToFileMime),
                  ),
                Container(
                  margin: EdgeInsets.only(
                      left: isSelf ? 40 : 0, right: isSelf ? 0 : 40),
                  padding: _needsPadding
                      ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isSelf ? context.xBubbleSent : context.xBubbleRecv,
                    borderRadius: _bubbleBorderRadius(ref.watch(settingsProvider).bubbleStyle, isSelf),
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
                      if (message.type == MessageType.video)
                        Stack(
                          children: [
                            _buildContent(context, ref),
                            Positioned(
                              bottom: 6, right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: _buildTimeRow(context),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildContent(context, ref),
                        _buildTimeRow(context),
                      ],
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
      message.type == MessageType.text || message.type == MessageType.file || message.type == MessageType.call;

  Widget _buildContent(BuildContext context, WidgetRef ref) {
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
        final albumSiblings = (message.albumId != null && allMessages != null)
            ? allMessages!.where((m) => m.albumId == message.albumId).toList()
            : <XameMessage>[];
        final chat = ref.read(chatProvider(message.recipientId).notifier);
        return _ImageBubble(
            url: message.fileUrl ?? '',
            caption: message.text,
            viewOnce: message.viewOnce,
            albumIndex: message.albumIndex,
            albumTotal: message.albumTotal,
              albumSiblings: albumSiblings,
              status: message.status,
              uploadProgress: message.uploadProgress,
              onPauseUpload: isSelf && message.status == "uploading"
                  ? () => chat.pauseUpload(message.id)
                  : null,
              onResumeUpload: isSelf && message.status == "paused"
                  ? () => chat.resumeUpload(message.id)
                  : null,
              onRetryUpload: isSelf && message.status == "failed" && message.localPath != null
                  ? () async {
                      final file = File(message.localPath!);
                      if (await file.exists()) {
                        await chat.retryFile(message, file);
                      }
                    }
                  : null);
      case MessageType.video:
        final chat = ref.read(chatProvider(message.recipientId).notifier);
        return _VideoBubble(
            url: message.fileUrl ?? "",
            fileName: message.fileName ?? "video",
            fileSize: message.fileSize,
            localPath: message.localPath,
            status: message.status,
            uploadProgress: message.uploadProgress,
            onPauseUpload: isSelf && message.status == "uploading" ? () => chat.pauseUpload(message.id) : null,
            onResumeUpload: isSelf && message.status == "paused" ? () => chat.resumeUpload(message.id) : null,
            onRetryUpload: isSelf && message.status == "failed" && message.localPath != null ? () async {
              final file = File(message.localPath!);
              if (await file.exists()) await chat.retryFile(message, file);
            } : null);
      case MessageType.audio:
        final chat = ref.read(chatProvider(message.recipientId).notifier);
        return _AudioBubble(
            url: message.fileUrl ?? '',
            fileName: message.fileName ?? 'audio',
            isSelf: isSelf,
            localPath: message.localPath,
            status: message.status,
            uploadProgress: message.uploadProgress,
            onPauseUpload: isSelf && message.status == "uploading"
                ? () => chat.pauseUpload(message.id)
                : null,
            onResumeUpload: isSelf && message.status == "paused"
                ? () => chat.resumeUpload(message.id)
                : null,
            onRetryUpload: isSelf &&
                    message.status == "failed" &&
                    message.localPath != null
                ? () async {
                    final file = File(message.localPath!);
                    if (await file.exists()) {
                      await chat.retryFile(message, file);
                    }
                  }
                : null);
      case MessageType.file:
          final chat = ref.read(
            chatProvider(message.recipientId).notifier,
          );
          return _FileBubble(
              url:             message.fileUrl ?? '',
              fileName:        message.fileName ?? 'file',
              mime:            message.fileMime ?? '',
              fileSize:        message.fileSize,
              localPath:       message.localPath,
              status:          message.status,
              uploadProgress:  message.uploadProgress,
              onPauseUpload:   isSelf && message.status == 'uploading'
                  ? () => chat.pauseUpload(message.id)
                  : null,
              onResumeUpload:  isSelf && message.status == 'paused'
                  ? () => chat.resumeUpload(message.id)
                  : null,
              onRetryUpload:   isSelf &&
                      message.status == 'failed' &&
                      message.localPath != null
                  ? () async {
                      final file = File(message.localPath!);
                      if (await file.exists()) {
                        await chat.retryFile(message, file);
                      }
                    }
                  : null);
      case MessageType.text:
        return _TextContent(text: message.text, isSelf: isSelf, actionButton: message.actionButton);
      case MessageType.call:
        return _CallBubble(
          callType:     message.callType     ?? 'voice',
          callStatus:   message.callStatus   ?? 'ended',
          callDuration: message.callDuration ?? 0,
          isSelf:       isSelf,
        );
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
          _StatusTick(message: message),
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
  final String text;
  final bool isSelf;
  final Map<String, dynamic>? actionButton;

  _TextContent({
    required this.text,
    required this.isSelf,
    this.actionButton,
  });

  bool get _isEmojiOnly {
    final c = text.trim();
    if (c.isEmpty) return false;
    return RegExp(
      r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\s]+$',
      unicode: true,
    ).hasMatch(c);
  }

  double _fontSize(WidgetRef ref) {
    final fs = ref.watch(settingsProvider).fontSize;
    if (fs == 'small') return 13;
    if (fs == 'large') return 17;
    return 15;
  }

  static final RegExp _urlPattern = RegExp(
    r'(https?://[^\s]+)',
    caseSensitive: false,
  );

  String _cleanUrl(String value) {
    // Remove punctuation that normally follows a URL in a sentence.
    return value.replaceFirst(RegExp(r'[.,!?;:)\]}]+$'), '');
  }

  Widget _buildMessageText(BuildContext context, WidgetRef ref) {
    final style = TextStyle(
      color: context.xBubbleSentText,
      fontSize: _fontSize(ref),
      height: 1.4,
    );

    if (_isEmojiOnly) {
      return Text(text.trim(), style: const TextStyle(fontSize: 36));
    }

    final matches = _urlPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final raw = match.group(0)!;
      final url = _cleanUrl(raw);

      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: Colors.lightBlueAccent,
            decoration: TextDecoration.underline,
            decorationThickness: 1.2,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri == null) return;

              final canOpen = await canLaunchUrl(uri);
              if (canOpen) {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              }
            },
        ),
      );

      // Preserve punctuation removed from the clickable URL.
      if (url.length < raw.length) {
        spans.add(
          TextSpan(
            text: raw.substring(url.length),
            style: style,
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textWidget = _buildMessageText(context, ref);

    final label = actionButton?['label'] as String?;
    final url = actionButton?['url'] as String?;

    if (label == null || url == null || url.isEmpty) {
      return textWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        textWidget,
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: context.xPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Status ticks ─────────────────────────────────────────────────────────
class _StatusTick extends StatelessWidget {
  final XameMessage message;

  const _StatusTick({required this.message});

  @override
  Widget build(BuildContext context) {
    final status = message.status;

    if (status == 'uploading') {
      final percent = (message.uploadProgress * 100)
          .clamp(0.0, 100.0)
          .round();

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: message.uploadProgress > 0
                  ? message.uploadProgress
                  : null,
              strokeWidth: 1.5,
              color: context.xText.withValues(alpha: 0.54),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$percent%',
            style: TextStyle(
              color: context.xText.withValues(alpha: 0.70),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (status == 'failed') {
      return Tooltip(
        message: 'Upload failed — long press to retry',
        child: Icon(
          Icons.error_outline,
          size: 14,
          color: context.xDanger,
        ),
      );
    }

    if (status == 'seen') {
      return Icon(
        Icons.done_all,
        size: 14,
        color: context.xPrimary,
      );
    }

    if (status == 'delivered') {
      return Icon(
        Icons.done_all,
        size: 14,
        color: context.xMuted,
      );
    }

    return Icon(
      Icons.done,
      size: 14,
      color: context.xMuted,
    );
  }
}

// ─── Reply quote ──────────────────────────────────────────────────────────
class _ReplyQuote extends StatelessWidget {
  final String  text;
  final String? fileUrl;
  final String? fileMime;
  _ReplyQuote({required this.text, this.fileUrl, this.fileMime});

  bool get _isImage => fileMime != null && fileMime!.startsWith('image');
  bool get _isVideo => fileMime != null && fileMime!.startsWith('video');
  bool get _isAudio => fileMime != null && fileMime!.startsWith('audio');

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
      child: Row(
        children: [
          // Media thumbnail
          if (fileUrl != null && fileUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _isImage
                ? CachedNetworkImage(
                    imageUrl: fileUrl!,
                    width: 48, height: 48, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 48, height: 48, color: Colors.white12,
                      child: const Icon(Icons.image, color: Colors.white38, size: 20)))
                : Container(
                    width: 48, height: 48, color: Colors.white12,
                    child: Icon(
                      _isVideo ? Icons.videocam_rounded
                        : _isAudio ? Icons.audiotrack_rounded
                        : Icons.insert_drive_file_rounded,
                      color: Colors.white54, size: 24)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replied message',
                  style: TextStyle(color: XameColors.primary,
                      fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  text.isNotEmpty ? text
                    : _isImage ? '📷 Photo'
                    : _isVideo ? '🎥 Video'
                    : _isAudio ? '🎵 Audio'
                    : fileUrl != null ? '📎 Attachment'
                    : 'Message',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Image bubble ─────────────────────────────────────────────────────────
class _UploadStatusOverlay extends StatelessWidget {
  final String status;
  final double progress;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;

  const _UploadStatusOverlay({
    required this.status,
    required this.progress,
    this.onPause,
    this.onResume,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (status != "uploading" && status != "paused" && status != "failed") {
      return const SizedBox.shrink();
    }
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final isPaused = status == "paused";
    final isFailed = status == "failed";
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.58),
        child: Center(
          child: GestureDetector(
            onTap: isFailed ? onRetry : (isPaused ? onResume : onPause),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: Icon(
                    isFailed ? Icons.refresh_rounded : (isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                if (!isFailed) ...[
                  const SizedBox(height: 7),
                  Text(
                    "$percent%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String url, caption;
  final bool   viewOnce;
  final int?   albumIndex;
  final int?   albumTotal;
  final List<XameMessage> albumSiblings;
  final String status;
  final double uploadProgress;
  final VoidCallback? onPauseUpload;
  final VoidCallback? onResumeUpload;
  final VoidCallback? onRetryUpload;

  _ImageBubble(
      {required this.url, required this.caption, required this.viewOnce,
       this.albumIndex, this.albumTotal, this.albumSiblings = const [],
       this.status = "", this.uploadProgress = 0.0,
       this.onPauseUpload, this.onResumeUpload, this.onRetryUpload});

  void _openFullScreen(BuildContext context) {
    if (albumSiblings.length > 1) {
      final urls = albumSiblings
          .map((m) => m.fileUrl ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      final startIndex = (albumIndex ?? 0).clamp(0, urls.length - 1);
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            _FullScreenAlbumViewer(urls: urls, initialIndex: startIndex),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ));
      return;
    }
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
    // ── Album grid rendering ─────────────────────────────────────────────
    // Only the first image (albumIndex == 0) renders the full grid.
    // All other siblings are hidden to avoid duplicate bubbles.
    if (albumIndex != null && albumIndex! > 0 && albumSiblings.length > 1) {
      return const SizedBox.shrink();
    }

    if (albumIndex == 0 && albumSiblings.length > 1) {
      final allUrls = albumSiblings
          .map((m) => m.fileUrl ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      final displayCount = allUrls.length > 4 ? 4 : allUrls.length;
      final overflow = allUrls.length - 4;

      return Stack(children: [GestureDetector(
        onTap: () => _openFullScreen(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: allUrls.length == 1 ? 1 : 2,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: allUrls.length == 1 ? 16/9 : 1.0,
              ),
              itemCount: displayCount,
              itemBuilder: (ctx, i) {
                final isLast = i == 3 && overflow > 0;
                return GestureDetector(
                  onTap: () {
                    final startIdx = i.clamp(0, allUrls.length - 1);
                    Navigator.of(context).push(PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.black87,
                      pageBuilder: (_, __, ___) => _FullScreenAlbumViewer(
                          urls: allUrls, initialIndex: startIdx),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ));
                  },
                  child: Stack(fit: StackFit.expand, children: [
                    _RetryableCachedImage(
                      imageUrl: _resolveUrl(allUrls[i]),
                      fit: BoxFit.cover,
                      placeholder: Container(color: Colors.grey[800]),
                    ),
                    if (isLast)
                      Container(
                        color: Colors.black.withOpacity(0.55),
                        child: Center(
                          child: Text('+$overflow',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: Text(caption,
                  style: TextStyle(color: context.xText, fontSize: 13))),
        ]),
          _UploadStatusOverlay(
            status: status,
            progress: uploadProgress,
            onPause: onPauseUpload,
            onResume: onResumeUpload,
            onRetry: onRetryUpload,
          ),
        ]);
    }

    final showBadge = albumTotal != null && albumTotal! > 1;
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
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
          if (showBadge)
            Positioned(
              right: 8, bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${(albumIndex ?? 0) + 1}/$albumTotal',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
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

// ─── Full-screen swipeable album viewer (multiple images sent together) ──
class _FullScreenAlbumViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _FullScreenAlbumViewer({required this.urls, required this.initialIndex});
  @override
  State<_FullScreenAlbumViewer> createState() => _FullScreenAlbumViewerState();
}

class _FullScreenAlbumViewerState extends State<_FullScreenAlbumViewer> {
  late PageController _ctrl;
  late int _current;
  bool   _downloading = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      const bridge = MethodChannel('com.xamepage.app/android_bridge');
      final fileName = 'xamepage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final success = await bridge.invokeMethod<bool>('saveMedia', {
        'url': _resolveUrl(widget.urls[_current]),
        'fileName': fileName,
        'mimeType': 'image/jpeg',
      });
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success == true ? 'Image saved to Pictures/XamePage' : 'Save failed — please try again'),
            backgroundColor: success == true ? Colors.green : Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Save failed'),
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
      title: Text('${_current + 1} / ${widget.urls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      centerTitle: true,
      actions: [
        if (_downloading)
          const Padding(padding: EdgeInsets.all(14),
            child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
        else
          IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              onPressed: _download),
      ],
    ),
    body: PageView.builder(
      controller: _ctrl,
      itemCount: widget.urls.length,
      onPageChanged: (i) => setState(() => _current = i),
      itemBuilder: (_, i) => InteractiveViewer(
        minScale: 0.5, maxScale: 5.0,
        child: Center(child: CachedNetworkImage(
          imageUrl: _resolveUrl(widget.urls[i]), fit: BoxFit.contain,
          placeholder: (_, __) =>
              CircularProgressIndicator(color: XameColors.primary),
          errorWidget: (_, __, ___) =>
              Icon(Icons.broken_image, color: XameColors.darkSurface.withValues(alpha: 0.5), size: 60),
        )),
      ),
    ),
  );
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  bool   _downloading = false;
  double _progress    = 0;

  Future<void> _download() async {
    setState(() { _downloading = true; _progress = 0; });
    try {
      const bridge = MethodChannel('com.xamepage.app/android_bridge');
      final fileName = 'xamepage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final success = await bridge.invokeMethod<bool>('saveMedia', {
        'url': _resolveUrl(widget.url),
        'fileName': fileName,
        'mimeType': 'image/jpeg',
      });
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success == true ? 'Image saved to Pictures/XamePage' : 'Save failed — please try again'),
            backgroundColor: success == true ? Colors.green : Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Save failed'),
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
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
      actions: [
        if (_downloading)
          Padding(padding: const EdgeInsets.all(14),
            child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: Colors.white, strokeWidth: 2)))
        else
          IconButton(
              icon: Icon(Icons.download_outlined, color: Colors.white),
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
       this.localPath,
       this.status = "",
       this.uploadProgress = 0.0,
       this.onPauseUpload,
       this.onResumeUpload,
       this.onRetryUpload});
  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}


class _VideoBubbleState extends State<_VideoBubble> {
  Uint8List? _thumb;
  bool _thumbLoading = true;
  bool _playing = false;
  double _videoAspectRatio = 16 / 9;
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
      final cached = _videoThumbCache[widget.url];

      if (cached != null) {
        try {
          final codec = await ui.instantiateImageCodec(cached);
          final frame = await codec.getNextFrame();
          final width = frame.image.width;
          final height = frame.image.height;

          if (width > 0 && height > 0 && mounted) {
            setState(() {
              _videoAspectRatio = width / height;
              _thumb = cached;
              _thumbLoading = false;
            });
            return;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _thumb = cached;
          _thumbLoading = false;
        });
      }
      return;
    }

    try {
      final source =
          (widget.localPath != null &&
                  File(widget.localPath!).existsSync())
              ? widget.localPath!
              : _resolveUrl(widget.url);

      if (source.isEmpty) {
        _videoThumbCache[widget.url] = null;
        if (mounted) {
          setState(() => _thumbLoading = false);
        }
        return;
      }

      final bytes = await VideoThumbnail.thumbnailData(
        video: source,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 72,
        timeMs: 0,
      );

      _videoThumbCache[widget.url] = bytes;

      if (bytes != null) {
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final width = frame.image.width;
          final height = frame.image.height;

          if (width > 0 && height > 0 && mounted) {
            setState(() {
              _videoAspectRatio = width / height;
              _thumb = bytes;
              _thumbLoading = false;
            });
            return;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _thumb = bytes;
          _thumbLoading = false;
        });
      }
    } catch (_) {
      _videoThumbCache[widget.url] = null;

      if (mounted) {
        setState(() => _thumbLoading = false);
      }
    }
  }

  BetterPlayerDataSource _dataSource() {
    if (widget.localPath != null &&
        File(widget.localPath!).existsSync()) {
      return BetterPlayerDataSource(
        BetterPlayerDataSourceType.file,
        widget.localPath!,
      );
    }

    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      _resolveUrl(widget.url),
    );
  }

  void _playInline() {
    _playerCtrl?.dispose();

    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,

        // Use video's native aspect ratio to avoid cropping.
        aspectRatio: _videoAspectRatio,

        // Contain — show full video without cropping.
        fit: BoxFit.contain,

        // XamePage modes:
        // Mode 1 = portrait bubble.
        // Mode 2 = portrait magnified presentation.
        // Mode 3 = normal BetterPlayer fullscreen in landscape.
        deviceOrientationsOnFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
        ],

        // Do NOT destroy the video/controller when playback finishes.
        // Leaving the controller alive allows the user to replay it.
        controlsConfiguration:
            BetterPlayerControlsConfiguration(
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

        placeholder: _thumb != null
            ? Image.memory(
                _thumb!,
                fit: BoxFit.cover,
              )
            : null,
      ),
      betterPlayerDataSource: _dataSource(),
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _playerCtrl = controller;
      _playing = true;
    });
  }

  void _replayVideo() {
    _playInline();
  }

  Future<void> _openMagnifiedMode() async {
    if (_playerCtrl == null) {
      _playInline();
    }

    if (!mounted) return;

    final controller = _playerCtrl;
    if (controller == null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final sourceRect =
        box.localToGlobal(Offset.zero) & box.size;

    final position =
        controller.videoPlayerController?.value.position ??
            Duration.zero;

    // Keep Mode 1 alive, but pause it while Mode 2 owns playback.
    if (controller.isPlaying() == true) {
      await controller.pause();
    }

    if (!mounted) return;

    final returnedPosition =
        await Navigator.of(context).push<Duration>(
      PageRouteBuilder<Duration>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration:
            const Duration(milliseconds: 350),
        reverseTransitionDuration:
            const Duration(milliseconds: 300),
        pageBuilder: (_, animation, __) =>
            _MagnifiedVideoPage(
          dataSource: _dataSource(),
          startAt: position,
          sourceRect: sourceRect,
          thumbnail: _thumb,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            child,
      ),
    );

    if (!mounted) return;

    // Restore Mode 1's controller instead of replacing it.
    if (returnedPosition != null &&
        controller.videoPlayerController != null) {
      try {
        await controller.seekTo(returnedPosition);
      } catch (_) {}
    }

    try {
      if (controller.isPlaying() == false) {
        await controller.play();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {

    // Full-width video bubble — width fills the message area,
    // height derived from the video's actual aspect ratio.
    final w = MediaQuery.of(context).size.width * 0.78;
    final maxH = MediaQuery.of(context).size.height * 0.65;
    final h = (w / _videoAspectRatio).clamp(120.0, maxH).toDouble();

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: w,
            height: h,
            child: _playing && _playerCtrl != null
                ? BetterPlayerMultipleGestureDetector(
                    onDoubleTap: _openMagnifiedMode,
                    child: BetterPlayer(
                      controller: _playerCtrl!,
                    ),
                  )
                : GestureDetector(
                    onTap: _playInline,
                    onDoubleTap: _openMagnifiedMode,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_thumbLoading)
                          _Shimmer(
                            width: w,
                            height: h,
                            radius: 0,
                          )
                        else if (_thumb != null)
                          Image.memory(
                            _thumb!,
                            fit: BoxFit.cover,
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  context.xBg,
                                  context.xSurface,
                                  context.xCard,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: context.xMuted.withValues(
                                  alpha: 0.5,
                                ),
                                size: 48,
                              ),
                            ),
                          ),
                        Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        _UploadStatusOverlay(
          status: widget.status,
          progress: widget.uploadProgress,
          onPause: widget.onPauseUpload,
          onResume: widget.onResumeUpload,
          onRetry: widget.onRetryUpload,
        ),
      ],
    );;

    // BetterPlayerDataSource does not support startAt in
    // better_player_enhanced 0.0.5. Seek after initialization.
    if (widget.startAt > Duration.zero) {
      var positionRestored = false;

      _controller!.addEventsListener((event) {
        if (positionRestored ||
            event.betterPlayerEventType !=
                BetterPlayerEventType.initialized) {
          return;
        }

        positionRestored = true;
        _controller?.seekTo(widget.startAt);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _close() {
    final position =
        _controller?.videoPlayerController?.value.position ??
            widget.startAt;

    Navigator.of(context).pop(position);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final targetRect = Offset.zero & screenSize;

    final routeAnimation =
        ModalRoute.of(context)!.animation!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: routeAnimation,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(
            routeAnimation.value,
          );

          final rect = Rect.lerp(
            widget.sourceRect,
            targetRect,
            t,
          )!;

          return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: t,
                  ),
                ),
              ),

              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(14 * (1 - t)),
                  child: SizedBox.expand(
                    child: _controller == null
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : BetterPlayer(
                            controller: _controller!,
                          ),
                  ),
                ),
              ),

              if (t > 0.85)
                Positioned(
                  top:
                      MediaQuery.of(context).padding.top + 12,
                  right: 12,
                  child: Opacity(
                    opacity: ((t - 0.85) / 0.15)
                        .clamp(0.0, 1.0),
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder:
                            const CircleBorder(),
                        onTap: _close,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── File bubble — PDF page-1 preview + rich doc cards ───────────────────
class _FileBubble extends StatefulWidget {
  final String  url, fileName, mime;
  final int?    fileSize;
  final String? localPath;
  final String  status;
  final double  uploadProgress;
  final VoidCallback? onPauseUpload;
  final VoidCallback? onResumeUpload;
  final VoidCallback? onRetryUpload;

  const _FileBubble({
    required this.url,
    required this.fileName,
    required this.mime,
    this.fileSize,
    this.localPath,
    required this.status,
    required this.uploadProgress,
    this.onPauseUpload,
    this.onResumeUpload,
    this.onRetryUpload,
  });

  @override
  State<_FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<_FileBubble> {
  Uint8List? _pdfThumb;
  bool _pdfLoading = false;
  bool _opening = false;

  double _downloadProgress = 0.0;
  String _downloadState = 'idle';
  String? _downloadPath;
  CancelToken? _downloadCancelToken;

  bool get _isPdf =>
      widget.mime.toLowerCase().contains('pdf') ||
      widget.fileName.toLowerCase().endsWith('.pdf');

  bool get _isApk =>
      widget.mime.toLowerCase() ==
          'application/vnd.android.package-archive' ||
      widget.fileName.toLowerCase().endsWith('.apk');

  bool get _hasLocalFile {
    final path = widget.localPath ?? _downloadPath;
    return path != null && File(path).existsSync();
  }

  @override
  void initState() {
    super.initState();
    if (_isPdf) _loadPdfThumb();
  }

  @override
  void dispose() {
    _downloadCancelToken?.cancel('bubble disposed');
    super.dispose();
  }

  Future<void> _loadPdfThumb() async {
    final cacheKey = widget.url.isNotEmpty ? widget.url : widget.fileName;

    if (_pdfThumbCache.containsKey(cacheKey)) {
      if (!mounted) return;
      setState(() {
        _pdfThumb = _pdfThumbCache[cacheKey];
        _pdfLoading = false;
      });
      return;
    }

    if (widget.localPath != null &&
        File(widget.localPath!).existsSync()) {
      try {
        final doc = await PdfDocument.openFile(widget.localPath!);
        final page = await doc.getPage(1);
        final img = await page.render(
          width: 480,
          height: (480 * page.height / page.width).roundToDouble(),
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        await page.close();
        await doc.close();

        _pdfThumbCache[cacheKey] = img?.bytes;
        if (mounted) {
          setState(() {
            _pdfThumb = img?.bytes;
            _pdfLoading = false;
          });
        }
        return;
      } catch (_) {}
    }

    if (widget.url.isEmpty) return;

    if (mounted) setState(() => _pdfLoading = true);

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${cacheKey.hashCode}.pdf';
      final cached = File(path);

      if (!cached.existsSync() || cached.lengthSync() == 0) {
        if (cached.existsSync()) await cached.delete();
        await Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
        )).download(_resolveUrl(widget.url), path);
      }

      final doc = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      final img = await page.render(
        width: 480,
        height: (480 * page.height / page.width).roundToDouble(),
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      await doc.close();

      _pdfThumbCache[cacheKey] = img?.bytes;
      if (mounted) {
        setState(() {
          _pdfThumb = img?.bytes;
          _pdfLoading = false;
        });
      }
    } catch (_) {
      _pdfThumbCache[cacheKey] = null;
      if (mounted) setState(() => _pdfLoading = false);
    }
  }

  Future<String> _downloadFile() async {
    final dir = await getTemporaryDirectory();
    final safeName = widget.fileName.isNotEmpty
        ? widget.fileName.replaceAll(RegExp(r'[/\\]'), '_')
        : 'xamepage_file';

    return '${dir.path}/xamepage_${widget.url.hashCode}_$safeName';
  }

  Future<void> _startOrResumeDownload() async {
    if (widget.url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is not available yet')),
        );
      }
      return;
    }

    final existingPath = widget.localPath ?? _downloadPath;
    if (existingPath != null && File(existingPath).existsSync()) {
      _downloadPath = existingPath;
      await _openLocalFile(existingPath);
      return;
    }

    final path = _downloadPath ?? await _downloadFile();
    _downloadPath = path;

    final file = File(path);
    final offset = file.existsSync() ? await file.length() : 0;

    if (mounted) {
      setState(() {
        _downloadState = 'downloading';
        _downloadProgress =
            widget.fileSize != null && widget.fileSize! > 0
                ? (offset / widget.fileSize!).clamp(0.0, 1.0)
                : 0.0;
      });
    }

    final cancel = CancelToken();
    _downloadCancelToken = cancel;

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
      ));

      final response = await dio.get<ResponseBody>(
        _resolveUrl(widget.url),
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
          followRedirects: true,
          validateStatus: (code) => code != null && code >= 200 && code < 400,
        ),
      );

      final responseBody = response.data;
      if (responseBody == null) {
        throw Exception('Empty download response');
      }

      final isPartial = response.statusCode == 206;
      final startingOffset = isPartial ? offset : 0;

      if (!isPartial && offset > 0) {
        await file.writeAsBytes(const <int>[], flush: true);
      }

      final sink = file.openWrite(
        mode: startingOffset > 0 ? FileMode.append : FileMode.write,
      );

      var received = startingOffset;
      final contentLength = responseBody.contentLength;
      final total = widget.fileSize != null && widget.fileSize! > 0
          ? widget.fileSize!
          : (contentLength > 0 ? startingOffset + contentLength : 0);

      try {
        await for (final chunk in responseBody.stream) {
          if (cancel.isCancelled) break;
          sink.add(chunk);
          received += chunk.length;

          if (mounted && total > 0) {
            setState(() {
              _downloadProgress =
                  (received / total).clamp(0.0, 1.0);
            });
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (cancel.isCancelled) {
        if (mounted) setState(() => _downloadState = 'paused');
        return;
      }

      if (!file.existsSync() || await file.length() == 0) {
        throw Exception('Downloaded file is empty');
      }

      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
          _downloadState = 'completed';
        });
      }

      await _openLocalFile(path);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (mounted) setState(() => _downloadState = 'paused');
        return;
      }

      if (mounted) {
        setState(() => _downloadState = 'failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.message ?? e}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadState = 'failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      _downloadCancelToken = null;
    }
  }

  void _pauseDownload() {
    if (_downloadState != 'downloading') return;
    _downloadCancelToken?.cancel('paused by user');
  }

  Future<void> _openLocalFile(String path) async {
    if (!File(path).existsSync()) {
      if (mounted) setState(() => _downloadState = 'failed');
      return;
    }

    if (mounted) setState(() => _opening = true);

    try {
      if (_isApk) {
        final ok = await const MethodChannel(
          'com.xamepage.app/android_bridge',
        ).invokeMethod<bool>('installApk', {'path': path});

        if (ok != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to start APK installation')),
          );
        }
      } else {
        final result = await OpenFilex.open(
          path,
          type: widget.mime.isNotEmpty ? widget.mime : null,
        );

        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No app found to open this file (${result.message})',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _handleMainTap() async {
    if (_opening) return;

    final local = widget.localPath ?? _downloadPath;

    if (local != null && File(local).existsSync()) {
      await _openLocalFile(local);
      return;
    }

    if (_downloadState == 'downloading') return;

    await _startOrResumeDownload();
  }

  _DocStyle get _style {
    final m = widget.mime.toLowerCase();
    final n = widget.fileName.toLowerCase();

    if (_isApk)
      return _DocStyle(
        Icons.android_outlined,
        XameColors.primary,
        const Color(0xFF23001155),
        'APK',
      );

    if (m.contains('pdf') || n.endsWith('.pdf'))
      return _DocStyle(
        Icons.picture_as_pdf_outlined,
        XameColors.danger,
        const Color(0xFF23111100),
        'PDF',
      );

    if (m.contains('word') || n.endsWith('.doc') || n.endsWith('.docx'))
      return _DocStyle(
        Icons.description_outlined,
        XameColors.primary,
        const Color(0xFF23001155),
        'WORD',
      );

    if (m.contains('sheet') ||
        m.contains('excel') ||
        n.endsWith('.xls') ||
        n.endsWith('.xlsx'))
      return _DocStyle(
        Icons.table_chart_outlined,
        XameColors.accent,
        const Color(0xFF23001100),
        'EXCEL',
      );

    if (m.contains('presentation') ||
        m.contains('powerpoint') ||
        n.endsWith('.ppt') ||
        n.endsWith('.pptx'))
      return _DocStyle(
        Icons.slideshow_outlined,
        XameColors.danger,
        const Color(0xFF23110000),
        'PPT',
      );

    if (m.contains('zip') ||
        m.contains('rar') ||
        m.contains('tar') ||
        n.endsWith('.zip') ||
        n.endsWith('.rar'))
      return _DocStyle(
        Icons.folder_zip_outlined,
        XameColors.accent,
        const Color(0xFF23110B00),
        'ZIP',
      );

    if (m.contains('audio') ||
        n.endsWith('.mp3') ||
        n.endsWith('.aac'))
      return _DocStyle(
        Icons.audio_file_outlined,
        XameColors.secondary,
        const Color(0xFF23050011),
        'AUDIO',
      );

    if (m.contains('video') ||
        n.endsWith('.mp4') ||
        n.endsWith('.mov'))
      return _DocStyle(
        Icons.video_file_outlined,
        XameColors.accent,
        const Color(0xFF23001111),
        'VIDEO',
      );

    if (m.contains('text') || n.endsWith('.txt'))
      return _DocStyle(
        Icons.article_outlined,
        XameColors.darkBg.withValues(alpha: 0.7),
        const Color(0xFF23111111),
        'TXT',
      );

    return _DocStyle(
      Icons.insert_drive_file_outlined,
      XameColors.accent,
      const Color(0xFF23000B1A),
      'FILE',
    );
  }

  Widget _buildThumbnail(BuildContext context, _DocStyle st) {
    final cacheKey = widget.url.isNotEmpty ? widget.url : widget.fileName;

    return SizedBox(
      width: 70,
      height: 82,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isPdf && _pdfThumb != null)
              Image.memory(
                _pdfThumb!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            else
              Container(
                color: st.bgTint,
                child: Center(
                  child: _pdfLoading && _isPdf
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: st.color,
                          ),
                        )
                      : Icon(st.icon, color: st.color, size: 34),
                ),
              ),
            if (_isPdf && _pdfThumb != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  color: Colors.black.withValues(alpha: 0.58),
                  child: Text(
                    st.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: 7,
                right: 7,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: st.color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    st.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                size: const Size(18, 18),
                painter: _FileFoldPainter(
                  color: context.xCard,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferControl(BuildContext context) {
    if (_downloadState == 'downloading') {
      return IconButton(
        tooltip: 'Pause download',
        onPressed: _pauseDownload,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        icon: const Icon(Icons.pause_circle_filled_rounded, size: 28),
      );
    }

    if (_downloadState == 'paused') {
      return IconButton(
        tooltip: 'Continue download',
        onPressed: _startOrResumeDownload,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        icon: const Icon(Icons.play_circle_fill_rounded, size: 28),
      );
    }

    if (_downloadState == 'failed') {
      return IconButton(
        tooltip: 'Retry download',
        onPressed: _startOrResumeDownload,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        icon: const Icon(Icons.refresh_rounded, size: 27),
      );
    }

    if (widget.status == 'uploading' &&
        widget.onPauseUpload != null) {
      final percent =
          (widget.uploadProgress * 100).clamp(0.0, 100.0).round();

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$percent%',
            style: TextStyle(
              color: context.xMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Pause upload',
            onPressed: widget.onPauseUpload,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 34,
            ),
            icon: const Icon(Icons.pause_circle_filled_rounded, size: 27),
          ),
        ],
      );
    }

    if (widget.status == 'paused' &&
        widget.onResumeUpload != null) {
      final percent =
          (widget.uploadProgress * 100).clamp(0.0, 100.0).round();

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$percent%',
            style: TextStyle(
              color: context.xMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Continue upload',
            onPressed: widget.onResumeUpload,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 34,
            ),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 27),
          ),
        ],
      );
    }

    if (widget.status == 'failed' &&
        widget.onRetryUpload != null) {
      return IconButton(
        tooltip: 'Retry upload',
        onPressed: widget.onRetryUpload,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        icon: const Icon(Icons.refresh_rounded, size: 27),
      );
    }

    if (_hasLocalFile) {
      return IconButton(
        tooltip: _isApk ? 'Install APK' : 'Open file',
        onPressed: _opening ? null : _handleMainTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        icon: Icon(
          _isApk ? Icons.install_mobile_rounded : Icons.open_in_new_rounded,
          color: stColor.withValues(alpha: 0.75),
          size: 22,
        ),
      );
    }

    return Icon(
      Icons.download_rounded,
      color: context.xMuted.withValues(alpha: 0.8),
      size: 22,
    );
  }

  Color get stColor => _style.color;

  String _transferText() {
    if (widget.status == 'uploading') {
      final p = (widget.uploadProgress * 100).clamp(0.0, 100.0).round();
      return 'Uploading $p%';
    }

    if (widget.status == 'paused') {
      final p = (widget.uploadProgress * 100).clamp(0.0, 100.0).round();
      return 'Upload paused · $p%';
    }

    if (widget.status == 'failed' &&
        widget.onRetryUpload != null) {
      return 'Upload failed';
    }

    if (_downloadState == 'downloading') {
      return 'Downloading ${(_downloadProgress * 100).round()}%';
    }

    if (_downloadState == 'paused') {
      return 'Download paused · ${(_downloadProgress * 100).round()}%';
    }

    if (_downloadState == 'failed') {
      return 'Download failed · tap retry';
    }

    if (_hasLocalFile) {
      return _isApk ? 'Ready to install' : 'Ready to open';
    }

    return 'Tap to download';
  }

  Widget _buildProgress(BuildContext context) {
    final uploading =
        widget.status == 'uploading' || widget.status == 'paused';
    final downloading =
        _downloadState == 'downloading' || _downloadState == 'paused';

    if (!uploading && !downloading) {
      return const SizedBox.shrink();
    }

    final value = uploading
        ? widget.uploadProgress.clamp(0.0, 1.0)
        : _downloadProgress.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 4,
          backgroundColor: stColor.withValues(alpha: 0.12),
          color: stColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _style;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 250,
        maxWidth: 340,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.xCard.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: st.color.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _opening ? null : _handleMainTap,
              child: _buildThumbnail(context, st),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _opening ? null : _handleMainTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName.isNotEmpty
                            ? widget.fileName
                            : 'XamePage file',
                        style: TextStyle(
                          color: context.xText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (widget.fileSize != null)
                            Text(
                              _fmtSize(widget.fileSize),
                              style: TextStyle(
                                color: context.xMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          if (widget.fileSize != null)
                            Text(
                              '  ·  ',
                              style: TextStyle(
                                color: context.xMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: st.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              st.label,
                              style: TextStyle(
                                color: st.color,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _transferText(),
                        style: TextStyle(
                          color: context.xMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      _buildProgress(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          _buildTransferControl(context),
        ],
      ),
    );
  }
}

class _FileFoldPainter extends CustomPainter {
  final Color color;

  const _FileFoldPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FileFoldPainter oldDelegate) =>
      oldDelegate.color != color;
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
  final bool isSelf;
  final String? localPath;
  final String status;
  final double uploadProgress;
  final VoidCallback? onPauseUpload;
  final VoidCallback? onResumeUpload;
  final VoidCallback? onRetryUpload;

  const _AudioBubble({
    required this.url,
    required this.fileName,
    required this.isSelf,
    this.localPath,
    this.status = "",
    this.uploadProgress = 0.0,
    this.onPauseUpload,
    this.onResumeUpload,
    this.onRetryUpload,
  });
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
    _prepareAudio();
  }

  Future<void> _prepareAudio() async {
    try {
      if (widget.localPath != null &&
          widget.localPath!.isNotEmpty &&
          File(widget.localPath!).existsSync()) {
        await _player!.setFilePath(widget.localPath!);
      } else if (widget.url.isNotEmpty) {
        await _player!.setUrl(_resolveUrl(widget.url));
      }
    } catch (_) {
      // Playback will retry from the selected source when the user taps play.
    }
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
      try {
        await _player?.play();
        if (mounted) setState(() => _playing = true);
      } catch (_) {
        try {
          if (widget.localPath != null &&
              widget.localPath!.isNotEmpty &&
              File(widget.localPath!).existsSync()) {
            await _player?.setFilePath(widget.localPath!);
          } else if (widget.url.isNotEmpty) {
            await _player?.setUrl(_resolveUrl(widget.url));
          }
          await _player?.play();
          if (mounted) setState(() => _playing = true);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to play this voice note'),
              ),
            );
          }
        }
      }
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

    return Stack(
      children: [
        Container(
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
        _UploadStatusOverlay(
          status: widget.status,
          progress: widget.uploadProgress,
          onPause: widget.onPauseUpload,
          onResume: widget.onResumeUpload,
          onRetry: widget.onRetryUpload,
        ),
      ],
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

// ── Call Bubble ───────────────────────────────────────────────────────────────
class _CallBubble extends StatelessWidget {
  final String callType;
  final String callStatus;
  final int    callDuration;
  final bool   isSelf;

  const _CallBubble({
    required this.callType,
    required this.callStatus,
    required this.callDuration,
    required this.isSelf,
  });

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '$m min${s > 0 ? ' $s sec' : ''}';
    return '$s sec';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo    = callType == 'video';
    final isMissed      = callStatus == 'no-answer' || callStatus == 'declined';
    final isCancelled   = callStatus == 'cancelled';
    final isEnded       = callStatus == 'ended';
    final isUnavailable = callStatus == 'unavailable';
    final isBusy        = callStatus == 'busy';
    final icon          = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
    final label         = isEnded
        ? _formatDuration(callDuration)
        : isMissed      ? (isSelf ? 'No answer'      : 'Missed call')
        : isCancelled   ? (isSelf ? 'Cancelled'      : 'Missed call')
        : isUnavailable ? (isSelf ? 'Unavailable'    : 'Missed call')
        : isBusy        ? (isSelf ? 'On another call': 'Missed call')
        : '';
    final color         = (isMissed || isCancelled || isUnavailable || isBusy)
        ? context.xDanger
        : (isSelf ? Colors.white70 : context.xAccent);

    return IntrinsicWidth(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isMissed || isCancelled)
                ? context.xDanger.withOpacity(0.15)
                : context.xAccent.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isVideo ? 'Video call' : 'Voice call',
              style: TextStyle(
                color: isSelf ? Colors.white : context.xText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              label.isNotEmpty ? label : (isEnded ? 'Ended' : ''),
              style: TextStyle(
                color: color,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
