import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/config/constants.dart';
import '../../../core/theme/app_theme.dart';

class FollowersFollowingScreen extends StatefulWidget {
  final String userId;
  final String currentUserId;
  final int initialTab;

  const FollowersFollowingScreen({
    Key? key,
    required this.userId,
    required this.currentUserId,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get('/api/discover/followers-list/${widget.userId}');
      if (mounted && res.data['success'] == true) {
        setState(() {
          _followers = List<Map<String, dynamic>>.from(res.data['followers'] ?? []);
          _loadingFollowers = false;
        });
      } else if (mounted) {
        setState(() => _loadingFollowers = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFollowers = false);
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get('/api/discover/following-list/${widget.userId}');
      if (mounted && res.data['success'] == true) {
        setState(() {
          _following = List<Map<String, dynamic>>.from(res.data['following'] ?? []);
          _loadingFollowing = false;
        });
      } else if (mounted) {
        setState(() => _loadingFollowing = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFollowing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      appBar: AppBar(
        backgroundColor: context.xBg,
        elevation: 0,
        foregroundColor: context.xText,
        title: Text('Followers & Following',
            style: TextStyle(color: context.xText, fontSize: 16, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: context.xPrimary,
          labelColor: context.xPrimary,
          unselectedLabelColor: context.xMuted,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Followers (${_followers.length})'),
            Tab(text: 'Following (${_following.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList(_followers, _loadingFollowers, isFollowersTab: true),
          _buildList(_following, _loadingFollowing, isFollowersTab: false),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, bool loading, {required bool isFollowersTab}) {
    if (loading) {
      return Center(child: CircularProgressIndicator(color: context.xPrimary));
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          isFollowersTab ? 'No followers yet' : 'Not following anyone yet',
          style: TextStyle(color: context.xMuted, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final u = list[i];
        final name = u['name'] as String? ?? '';
        final avatar = u['avatar'] as String? ?? '';
        final userId = u['userId'] as String? ?? '';
        final isSelf = userId == widget.currentUserId;

        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: context.xSurface,
            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(color: context.xText, fontWeight: FontWeight.w700))
                : null,
          ),
          title: Text(name, style: TextStyle(color: context.xText, fontWeight: FontWeight.w600)),
          trailing: isSelf ? null : _FollowActionChip(authorId: userId, currentUserId: widget.currentUserId),
        );
      },
    );
  }
}

class _FollowActionChip extends StatefulWidget {
  final String authorId;
  final String currentUserId;
  const _FollowActionChip({Key? key, required this.authorId, required this.currentUserId}) : super(key: key);

  @override
  State<_FollowActionChip> createState() => _FollowActionChipState();
}

class _FollowActionChipState extends State<_FollowActionChip> {
  bool _following = false;
  bool _loading = false;
  bool _initLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.get(
        '/api/discover/follow-status/${widget.authorId}',
        queryParameters: {'followerId': widget.currentUserId},
      );
      if (mounted && res.data['success'] == true) {
        setState(() {
          _following = res.data['isFollowing'] == true;
          _initLoading = false;
        });
      } else if (mounted) {
        setState(() => _initLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _initLoading = false);
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    final wasFollowing = _following;
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final endpoint = wasFollowing
          ? '/api/discover/unfollow/${widget.authorId}'
          : '/api/discover/follow/${widget.authorId}';
      final res = await dio.post(endpoint, data: {'followerId': widget.currentUserId});
      if (res.data['success'] == true && mounted) {
        setState(() {
          _following = !wasFollowing;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _following ? context.xSurface : context.xPrimary,
          borderRadius: BorderRadius.circular(20),
          border: _following ? Border.all(color: context.xMuted.withOpacity(0.3)) : null,
        ),
        child: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(
                _following ? 'Following' : 'Follow',
                style: TextStyle(color: _following ? context.xMuted : Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
