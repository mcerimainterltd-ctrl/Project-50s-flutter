import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import '../../../core/config/constants.dart';
import 'discovery_fullscreen_viewer.dart';

class AuthorGalleryScreen extends StatefulWidget {
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String currentUserId;
  final String currentUserAvatar;

  const AuthorGalleryScreen({
    Key? key,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.currentUserId,
    this.currentUserAvatar = '',
  }) : super(key: key);

  @override
  State<AuthorGalleryScreen> createState() => _AuthorGalleryScreenState();
}

class _AuthorGalleryScreenState extends State<AuthorGalleryScreen> {
  final _dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _dio.get(
        '/api/discover/author/${widget.authorId}',
        queryParameters: {
          if (widget.currentUserId.isNotEmpty) 'userId': widget.currentUserId,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        setState(() {
          _posts = (data['posts'] as List)
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = data['message'] as String? ?? 'Failed to load posts';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load posts';
        _loading = false;
      });
    }
  }

  void _openFullscreen(int index) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: DiscoveryFullscreenViewer(
          posts: _posts,
          initialIndex: index,
          currentUserId: widget.currentUserId,
          currentUserAvatar: widget.currentUserAvatar,
        ),
      ),
      transitionDuration: const Duration(milliseconds: 250),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        elevation: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[800],
            backgroundImage: widget.authorAvatar.isNotEmpty
                ? CachedNetworkImageProvider(widget.authorAvatar)
                : null,
            child: widget.authorAvatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white54, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.authorName,
              style: const TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white54))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.white54)))
              : _posts.isEmpty
                  ? const Center(
                      child: Text('No posts yet',
                          style: TextStyle(color: Colors.white54, fontSize: 14)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: _posts.length,
                      itemBuilder: (_, i) {
                        final post = _posts[i];
                        final rawThumb = (post['thumbnailUrl'] as String?)?.isNotEmpty == true
                            ? post['thumbnailUrl'] as String
                            : post['mediaUrl'] as String? ?? '';
                        // For videos, ensure we get a poster image via Cloudinary transform
                        final thumb = isVideo && !rawThumb.contains('f_jpg')
                            ? rawThumb.replaceFirst('/upload/', '/upload/so_0,f_jpg/').replaceAll(RegExp(r'\.(mp4|mov|avi|webm)$', caseSensitive: false), '.jpg')
                            : rawThumb;
                        final isVideo = post['mediaType'] == 'video';
                        return GestureDetector(
                          onTap: () => _openFullscreen(i),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    color: Colors.grey[900]),
                                errorWidget: (_, __, ___) => Container(
                                    color: Colors.grey[900],
                                    child: const Icon(Icons.broken_image,
                                        color: Colors.white24)),
                              ),
                              if (isVideo)
                                const Positioned(
                                  top: 6, right: 6,
                                  child: Icon(Icons.play_circle_fill_rounded,
                                      color: Colors.white70, size: 20),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
