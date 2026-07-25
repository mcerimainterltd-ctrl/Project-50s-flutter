import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/constants.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/models/xame_user.dart';

class CollabMessage {
  final String messageId, senderId, senderName, text;
  final DateTime ts;
  CollabMessage({required this.messageId, required this.senderId,
    required this.senderName, required this.text, required this.ts});
  factory CollabMessage.fromJson(Map<String, dynamic> j) => CollabMessage(
    messageId:  j['messageId'] as String? ?? '',
    senderId:   j['senderId']  as String? ?? '',
    senderName: j['senderName'] as String? ?? '',
    text:       j['text']      as String? ?? '',
    ts: j['ts'] != null ? DateTime.parse(j['ts'].toString()) : DateTime.now(),
  );
}

class CollabThreadScreen extends ConsumerStatefulWidget {
  final String threadId;
  final String postTitle;
  final String postMediaUrl;
  final String otherUserId;
  final bool isAuthor;

  const CollabThreadScreen({
    Key? key,
    required this.threadId,
    required this.postTitle,
    required this.postMediaUrl,
    required this.otherUserId,
    this.isAuthor = false,
  }) : super(key: key);

  @override
  ConsumerState<CollabThreadScreen> createState() => _CollabThreadScreenState();
}

class _CollabThreadScreenState extends ConsumerState<CollabThreadScreen> {
  final _ctrl       = TextEditingController();
  final _scroll     = ScrollController();
  final List<CollabMessage> _messages = [];
  StreamSubscription? _sub;
  StreamSubscription? _authorizedSub;
  StreamSubscription? _submittedSub;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadThread();
    _sub = ref.read(socketServiceProvider).collabMessage.listen((data) {
      if (data['threadId'] != widget.threadId) return;
      final msg = CollabMessage.fromJson(data['message'] as Map<String, dynamic>);
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
    });
    _authorizedSub = ref.read(socketServiceProvider).collabAuthorized.listen((data) {
      if (data['threadId'] != widget.threadId) return;
      _loadThread();
    });
    _submittedSub = ref.read(socketServiceProvider).collabSubmitted.listen((data) {
      if (data['threadId'] != widget.threadId) return;
      _loadThread();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authorizedSub?.cancel();
    _submittedSub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await http.get(Uri.parse(
        '${AppConstants.serverUrl}/api/discover/collab/thread/${widget.threadId}?userId=${user.xameId}'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final msgs = (data['thread']['messages'] as List)
            .map((m) => CollabMessage.fromJson(m as Map<String, dynamic>)).toList();
        if (mounted) setState(() { _messages.addAll(msgs); _loading = false; });
        _scrollToBottom();
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/discover/collab/thread/${widget.threadId}/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': user.xameId, 'senderName': user.displayName, 'text': text}),
      );
      final msg = CollabMessage(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: user.xameId, senderName: user.displayName, text: text, ts: DateTime.now());
      if (mounted) setState(() => _messages.add(msg));
      _scrollToBottom();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(currentUserProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🤝 Collab Thread',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          Text(widget.postTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.4))),
            child: const Text('Private · 7 days',
              style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600))),
        ]),
      body: Column(children: [
        // Post context banner
        if (widget.postMediaUrl.isNotEmpty)
          Container(
            height: 80,
            decoration: BoxDecoration(color: const Color(0xFF12121E)),
            child: Row(children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(bottomRight: Radius.circular(12)),
                child: CachedNetworkImage(
                  imageUrl: widget.postMediaUrl,
                  width: 80, height: 80, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 80, color: const Color(0xFF1A1A2E),
                    child: const Icon(Icons.image_outlined, color: Colors.white24)))),
              const SizedBox(width: 12),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Collaborating on',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text(widget.postTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w600)),
              ])),
              const SizedBox(width: 12),
            ])),

        // Privacy notice
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1A1A2E),
          child: const Text(
            '🔒 This is a private collab space. Neither party is added to your contacts.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center)),

        // Messages
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
            : _messages.isEmpty
              ? const Center(child: Text('Start your collab conversation 🤝',
                  style: TextStyle(color: Colors.white38, fontSize: 13)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg   = _messages[i];
                    final isMine = msg.senderId == user?.xameId;
                    return Align(
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMine ? const Color(0xFF00B0A0) : const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.only(
                            topLeft:     const Radius.circular(16),
                            topRight:    const Radius.circular(16),
                            bottomLeft:  Radius.circular(isMine ? 16 : 4),
                            bottomRight: Radius.circular(isMine ? 4 : 16))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!isMine)
                            Text(msg.senderName,
                              style: const TextStyle(color: Color(0xFF00E5FF),
                                fontSize: 11, fontWeight: FontWeight.w700)),
                          Text(msg.text,
                            style: TextStyle(
                              color: isMine ? Colors.black : Colors.white, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('${msg.ts.hour}:${msg.ts.minute.toString().padLeft(2,'0')}',
                            style: TextStyle(
                              color: isMine ? Colors.black45 : Colors.white24,
                              fontSize: 10)),
                        ])));
                  })),

        // Input
        // Action buttons — author sees Authorize, requester sees Submit
        if (widget.isAuthor)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B0A0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.verified_rounded, color: Colors.black, size: 18),
                label: const Text('Authorize Collab',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14)),
                onPressed: () async {
                  final user = ref.read(currentUserProvider);
                  if (user == null) return;
                  try {
                    final res = await http.post(
                      Uri.parse('${AppConstants.serverUrl}/api/discover/collab/authorize'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'threadId': widget.threadId, 'authorId': user.xameId}));
                    final data = jsonDecode(res.body);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(data['success'] == true ? '✅ Collab authorized!' : data['message'] ?? 'Failed'),
                      backgroundColor: data['success'] == true ? const Color(0xFF1A3A3A) : Colors.redAccent));
                  } catch (_) {}
                }),
            )),
        if (!widget.isAuthor)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.upload_rounded, color: Colors.black, size: 18),
                label: const Text('Submit Collab',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14)),
                onPressed: () async {
                  final user = ref.read(currentUserProvider);
                  if (user == null) return;
                  try {
                    final res = await http.post(
                      Uri.parse('${AppConstants.serverUrl}/api/discover/collab/submit'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'threadId': widget.threadId, 'requesterId': user.xameId}));
                    final data = jsonDecode(res.body);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(data['success'] == true ? '🤝 Collab submitted!' : data['message'] ?? 'Failed'),
                      backgroundColor: data['success'] == true ? const Color(0xFF1A3A3A) : Colors.redAccent));
                  } catch (_) {}
                }),
            )),
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          decoration: const BoxDecoration(
            color: Color(0xFF12121E),
            border: Border(top: BorderSide(color: Colors.white10))),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message your collab partner...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true, fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF00B0A0), shape: BoxShape.circle),
                child: _sending
                  ? const Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, color: Colors.black, size: 20))),
          ])),
      ]),
    );
  }
}
