import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/constants.dart';
import '../models/discovery_comment.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class CommentsSheet extends StatefulWidget {
  final String postId;
  final String userId;
  final String authorName;
  final String authorAvatar;
  final int    initialCount;
  final void Function(int) onCountChanged;

  const CommentsSheet({
    Key? key,
    required this.postId,
    required this.userId,
    required this.authorName,
    required this.authorAvatar,
    required this.initialCount,
    required this.onCountChanged,
  }) : super(key: key);

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _ctrl    = TextEditingController();
  final _scroll  = ScrollController();
  final _dio     = Dio();
  List<DiscoveryComment> _comments = [];
  bool   _loading  = false;
  bool   _posting  = false;
  int    _total    = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get(
        '${AppConstants.serverUrl}/api/discover/${widget.postId}/comments',
        queryParameters: { 'limit': 50 },
      );
      if (r.data['success'] == true) {
        setState(() {
          _comments = (r.data['comments'] as List)
              .map((e) => DiscoveryComment.fromJson(e as Map<String, dynamic>))
              .toList();
          _total = r.data['total'] as int? ?? _comments.length;
        });
        widget.onCountChanged(_total);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _posting = true);
    try {
      final r = await _dio.post(
        '${AppConstants.serverUrl}/api/discover/comment',
        data: {
          'postId':       widget.postId,
          'userId':       widget.userId,
          'authorName':   widget.authorName,
          'authorAvatar': widget.authorAvatar,
          'text':         text,
        },
      );
      if (r.data['success'] == true) {
        _ctrl.clear();
        final c = DiscoveryComment.fromJson(r.data['comment'] as Map<String, dynamic>);
        setState(() {
          _comments.add(c);
          _total++;
        });
        widget.onCountChanged(_total);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut);
          }
        });
      }
    } catch (_) {}
    setState(() => _posting = false);
  }

  Future<void> _delete(DiscoveryComment c) async {
    try {
      final r = await _dio.delete(
        '${AppConstants.serverUrl}/api/discover/comment/${c.commentId}',
        data: { 'userId': widget.userId },
      );
      if (r.data['success'] == true) {
        setState(() {
          _comments.removeWhere((x) => x.commentId == c.commentId);
          _total = (_total - 1).clamp(0, 999999);
        });
        widget.onCountChanged(_total);
      }
    } catch (_) {}
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return '${diff.inSeconds}s';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m';
    if (diff.inHours   < 24)  return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.xSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: context.xMuted.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('Comments', style: TextStyle(
                color: context.xText, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('$_total', style: TextStyle(color: context.xMuted, fontSize: 14)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
            ? Center(child: CircularProgressIndicator(color: context.xAccent))
            : _comments.isEmpty
              ? Center(child: Text('No comments yet. Be the first!',
                  style: TextStyle(color: context.xMuted, fontSize: 13)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _comments.length,
                  itemBuilder: (ctx, i) {
                    final c = _comments[i];
                    final isOwn = c.authorId == widget.userId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: context.xAccent.withOpacity(0.2),
                          backgroundImage: c.authorAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(c.authorAvatar) : null,
                          child: c.authorAvatar.isEmpty
                            ? Text(c.authorName.isNotEmpty ? c.authorName[0].toUpperCase() : '?',
                                style: TextStyle(color: context.xAccent, fontSize: 12,
                                    fontWeight: FontWeight.w700))
                            : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(c.authorName,
                                style: TextStyle(color: context.xText, fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Text(_timeAgo(c.ts),
                                style: TextStyle(color: context.xMuted, fontSize: 11)),
                              if (isOwn) ...[
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => _delete(c),
                                  child: Icon(Icons.delete_outline_rounded,
                                      size: 15, color: context.xDanger.withOpacity(0.7)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.xText.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(c.text,
                                style: TextStyle(color: context.xText, fontSize: 13)),
                            ),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Container(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8),
            decoration: BoxDecoration(
              color: context.xSurface,
              border: Border(top: BorderSide(color: context.xMuted.withOpacity(0.15))),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: context.xText, fontSize: 14),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: context.xMuted),
                    filled: true,
                    fillColor: context.xText.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _posting ? null : _post,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.xAccent,
                    shape: BoxShape.circle,
                  ),
                  child: _posting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
