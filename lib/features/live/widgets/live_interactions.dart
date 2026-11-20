import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// XAMELIVE_INTERACTIONS_V1: comments list and floating reactions drawn over a
// live screen. Touches pass through, so it never blocks video or buttons.
class LiveInteractionLayer extends StatefulWidget {
  const LiveInteractionLayer({
    super.key,
    required this.initialComments,
    required this.commentsStream,
    required this.reactionsStream,
    required this.onAttach,
    required this.onDetach,
    this.bottomOffset = 200,
  });

  final List<Map<String, dynamic>> initialComments;
  final Stream<List<Map<String, dynamic>>> commentsStream;
  final Stream<String> reactionsStream;
  final VoidCallback onAttach;
  final VoidCallback onDetach;
  final double bottomOffset;

  @override
  State<LiveInteractionLayer> createState() => _LiveInteractionLayerState();
}

class _FloatingReaction {
  _FloatingReaction(this.id, this.emoji, this.drift);
  final int id;
  final String emoji;
  final double drift;
}

class _LiveInteractionLayerState extends State<LiveInteractionLayer> {
  final math.Random _random = math.Random();
  late List<Map<String, dynamic>> _comments;
  final List<_FloatingReaction> _floating = <_FloatingReaction>[];
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSub;
  StreamSubscription<String>? _reactionsSub;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _comments = List<Map<String, dynamic>>.of(widget.initialComments);
    _commentsSub = widget.commentsStream.listen((items) {
      if (!mounted) return;
      setState(() => _comments = List<Map<String, dynamic>>.of(items));
    });
    _reactionsSub = widget.reactionsStream.listen((reaction) {
      if (!mounted) return;
      setState(() {
        if (_floating.length >= 24) _floating.removeAt(0);
        _floating.add(
          _FloatingReaction(
            _nextId++,
            (reaction == 'heart' || reaction.length > 4)
                ? '\u2764\uFE0F'
                : reaction,
            _random.nextDouble() * 36 - 18,
          ),
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAttach();
    });
  }

  @override
  void dispose() {
    _commentsSub?.cancel();
    _reactionsSub?.cancel();
    widget.onDetach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _comments.length > 6
        ? _comments.sublist(_comments.length - 6)
        : _comments;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: 16,
              right: 84,
              bottom: widget.bottomOffset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in recent) _CommentBubble(comment: c),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 96,
              width: 64,
              height: 280,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final r in _floating)
                    _FloatingHeart(
                      key: ValueKey<int>(r.id),
                      reaction: r,
                      onDone: () {
                        if (!mounted) return;
                        setState(
                          () => _floating.removeWhere((x) => x.id == r.id),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingHeart extends StatelessWidget {
  const _FloatingHeart({
    super.key,
    required this.reaction,
    required this.onDone,
  });

  final _FloatingReaction reaction;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2200),
      onEnd: onDone,
      builder: (context, t, child) {
        return Positioned(
          bottom: t * 240,
          left: 18 + reaction.drift + math.sin(t * math.pi * 3) * 8,
          child: Opacity(
            opacity: (1 - t * t).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Text(reaction.emoji, style: const TextStyle(fontSize: 28)),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final name = (comment['name']?.toString() ?? '').trim();
    final text = comment['text']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name.isEmpty ? 'Someone  ' : name + '  ',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

Future<void> showLiveCommentSheet(
  BuildContext context,
  bool Function(String text) onSend,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16161A),
    builder: (sheetContext) => _CommentSheet(onSend: onSend),
  );
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.onSend});

  final bool Function(String text) onSend;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Say something...',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
