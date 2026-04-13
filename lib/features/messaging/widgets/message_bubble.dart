// Mirrors: messageBubble() in messaging.js
// Handles: text, emoji-only, image, video, audio, file, reply quote,
//          forwarded label, status ticks, long-press menu, view-once

import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        color: isSelected ? XameColors.primary.withValues(alpha: 0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Align(
          alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Column(
              crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Reply quote
                if (message.replyToId != null) _ReplyQuote(text: message.replyToText ?? ''),
                // Main bubble
                Container(
                  margin: EdgeInsets.only(
                    left:  isSelf ? 40 : 0,
                    right: isSelf ? 0  : 40,
                  ),
                  padding: _needsPadding ? const EdgeInsets.fromLTRB(12, 8, 12, 6) : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isSelf ? const Color(0xFF1A4A3A) : XameColors.darkCard,
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
                      // Forwarded label
                      if (message.forwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: const [
                            Icon(Icons.forward, size: 12, color: Colors.white38),
                            SizedBox(width: 4),
                            Text('Forwarded', style: TextStyle(color: Colors.white38, fontSize: 11,
                              fontStyle: FontStyle.italic)),
                          ]),
                        ),
                      // Content
                      _buildContent(context),
                      // Time + ticks
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
        return _ImageBubble(url: message.fileUrl ?? '', caption: message.text, viewOnce: message.viewOnce);
      case MessageType.video:
        return _VideoBubble(url: message.fileUrl ?? '', fileName: message.fileName ?? 'video');
      case MessageType.audio:
        return _AudioBubble(url: message.fileUrl ?? '', fileName: message.fileName ?? 'audio', isSelf: isSelf);
      case MessageType.file:
        return _FileBubble(url: message.fileUrl ?? '', fileName: message.fileName ?? 'file', mime: '');
      case MessageType.text:
        return _TextContent(text: message.text, isSelf: isSelf);
    }
  }

  Widget _buildTimeRow() {
    final dt  = DateTime.fromMillisecondsSinceEpoch(message.ts);
    final time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return Padding(
      padding: _needsPadding ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if (isSelf) ...[
          const SizedBox(width: 4),
          _StatusTick(status: message.status),
        ],
      ]),
    );
  }
}

// ── Text content — handles emoji-only detection ───────────────────────────
class _TextContent extends StatelessWidget {
  final String text; final bool isSelf;
  const _TextContent({required this.text, required this.isSelf});

  bool get _isEmojiOnly {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;
    return RegExp(r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\s]+$', unicode: true).hasMatch(cleaned);
  }

  @override
  Widget build(BuildContext context) => _isEmojiOnly
    ? Text(text.trim(), style: const TextStyle(fontSize: 36))
    : Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4));
}

// ── Status ticks — mirrors renderTicks() ─────────────────────────────────
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
      border: const Border(left: BorderSide(color: XameColors.primary, width: 3)),
    ),
    child: Text(text.isNotEmpty ? text : '📎 Attachment',
      style: const TextStyle(color: Colors.white54, fontSize: 12),
      maxLines: 2, overflow: TextOverflow.ellipsis),
  );
}

// ── Image bubble ──────────────────────────────────────────────────────────
class _ImageBubble extends StatelessWidget {
  final String url; final String caption; final bool viewOnce;
  const _ImageBubble({required this.url, required this.caption, required this.viewOnce});

  @override
  Widget build(BuildContext context) {
    if (viewOnce) return Container(
      padding: const EdgeInsets.all(16),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.visibility_outlined, color: Colors.white54, size: 18),
        SizedBox(width: 8),
        Text('Tap to view', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: CachedNetworkImage(
          imageUrl:    url,
          fit:         BoxFit.cover,
          width:       double.infinity,
          placeholder: (_, __) => const SizedBox(height: 180,
            child: Center(child: CircularProgressIndicator(color: XameColors.primary, strokeWidth: 2))),
          errorWidget: (_, __, ___) => const SizedBox(height: 80,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white24))),
        ),
      ),
      if (caption.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Text(caption, style: const TextStyle(color: Colors.white, fontSize: 13))),
    ]);
  }
}

// ── Video bubble ──────────────────────────────────────────────────────────
class _VideoBubble extends StatelessWidget {
  final String url, fileName;
  const _VideoBubble({required this.url, required this.fileName});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      Container(width: 44, height: 44,
        decoration: BoxDecoration(color: XameColors.secondary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.play_circle_outline, color: XameColors.secondary, size: 28)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const Text('Video', style: TextStyle(color: Colors.white38, fontSize: 11)),
      ])),
    ]),
  );
}

// ── Audio bubble ──────────────────────────────────────────────────────────
class _AudioBubble extends StatefulWidget {
  final String url, fileName;
  final bool isSelf;
  const _AudioBubble({required this.url, required this.fileName,
      required this.isSelf});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  bool _isThisPlaying = false;

  String _fmtDur(Duration d) =>
      '${d.inMinutes.toString().padLeft(2,'0')}:${(d.inSeconds % 60).toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final voice   = ref.watch(voiceProvider);
    final notifier = ref.read(voiceProvider.notifier);
    final isPlaying = _isThisPlaying &&
        voice.recordState == VoiceRecordState.playing;
    final progress = voice.playDuration.inMilliseconds > 0
        ? voice.playPosition.inMilliseconds /
            voice.playDuration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Play/Pause button
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
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: XameColors.primary, size: 26),
            ),
          ),

          const SizedBox(width: 10),

          // Waveform + progress
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated waveform bars
              SizedBox(height: 32,
                child: _WaveformBars(progress: isPlaying ? progress : 0,
                    isSelf: widget.isSelf)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isPlaying
                        ? _fmtDur(_position)
                        : _fmtDur(_duration),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10)),

                ],
              ),
            ],
          )),
        ]),

        // Seek bar
        if (_playing)
          SliderTheme(
            data: SliderThemeData(
              trackHeight:      2,
              thumbShape:       const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:     const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: XameColors.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor:       XameColors.primary,
              overlayColor:     XameColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value:   progress.clamp(0.0, 1.0),
              onChanged: (v) => _player?.seek(Duration(
                  milliseconds: (v * _duration.inMilliseconds).round())),
            ),
          ),
      ]),
    );
  }
}

// ── Waveform bars ─────────────────────────────────────────────────────────
class _WaveformBars extends StatelessWidget {
  final double progress;
  final bool isSelf;
  const _WaveformBars({required this.progress, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    const bars = 28;
    final rng  = Random(42);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(bars, (i) {
        final h        = 8.0 + rng.nextDouble() * 20;
        final isActive = (i / bars) < progress;
        return Container(
          width: 3,
          height: h,
          decoration: BoxDecoration(
            color: isActive
                ? XameColors.primary
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ── Document/file bubble ──────────────────────────────────────────────────
class _FileBubble extends StatelessWidget {
  final String url, fileName, mime;
  const _FileBubble({required this.url, required this.fileName, required this.mime});

  IconData get _icon {
    if (mime.contains('pdf'))   return Icons.picture_as_pdf_outlined;
    if (mime.contains('word'))  return Icons.description_outlined;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 40, height: 40,
      decoration: BoxDecoration(color: XameColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10)),
      child: Icon(_icon, color: XameColors.accent, size: 22)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 2, overflow: TextOverflow.ellipsis),
      Text(mime.split('/').lastOrNull?.toUpperCase() ?? 'FILE',
        style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ])),
    const Icon(Icons.download_outlined, color: Colors.white38, size: 20),
  ]);
}
