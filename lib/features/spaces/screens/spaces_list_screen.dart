import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/constants.dart';
import '../../../core/providers/user_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/xame_space_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/auth_service.dart';
import '../models/space_model.dart';
import 'space_screen.dart';
import 'create_space_screen.dart';

class SpacesListScreen extends ConsumerStatefulWidget {
  const SpacesListScreen({super.key});
  @override
  ConsumerState<SpacesListScreen> createState() => _SpacesListScreenState();
}

class _SpacesListScreenState extends ConsumerState<SpacesListScreen> {
  List<SpaceModel> _spaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserProvider)?.xameId;
    if (userId == null) {
      if (mounted) setState(() { _spaces = []; _loading = false; });
      return;
    }
    final spaces = await XameSpaceService.fetchMySpaces(userId);
    if (mounted) setState(() { _spaces = spaces; _loading = false; });
  }

  static const _archetypeEmoji = {
    'family': '👨‍👩‍👧‍👦', 'school': '🎓', 'business': '💼',
    'community': '🌍', 'project': '🚀', 'event': '🎉',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: XameColors.darkBg,
    appBar: AppBar(
      backgroundColor: XameColors.darkSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        tooltip: 'Back',
        onPressed: () => context.go('/contacts'),
      ),
      title: const Text('Spaces', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white),
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateSpaceScreen()))
            .then((_) => _load())),
      ]),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _spaces.isEmpty
        ? _buildEmpty()
        : RefreshIndicator(onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _spaces.length,
              itemBuilder: (_, i) => _SpaceCard(space: _spaces[i],
                emoji: _archetypeEmoji[_spaces[i].archetype] ?? '🌍',
                onDeleted: () => setState(() => _spaces.removeAt(i)))));

  Widget _buildEmpty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('🌍', style: TextStyle(fontSize: 64)),
    const SizedBox(height: 16),
    const Text('No Spaces yet', style: TextStyle(color: Colors.white,
      fontSize: 20, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    Text('Create or join a Space to collaborate\nwith family, friends, or your team.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const CreateSpaceScreen())).then((_) => _load()),
      icon: const Icon(Icons.add, color: Colors.black),
      label: const Text('Create a Space', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(backgroundColor: XameColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
  ]));
}

class _SpaceCard extends ConsumerWidget {
  final SpaceModel space;
  final String emoji;
  final VoidCallback? onDeleted;
  const _SpaceCard({required this.space, required this.emoji, this.onDeleted});

  Future<void> _deleteSpace(BuildContext context, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: XameColors.darkCard,
        title: const Text('Delete Space?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete the space and all messages.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await http.delete(
        Uri.parse('\${AppConstants.serverUrl}/api/v3/spaces/\${space.spaceSlug}?userId=\$userId'),
        headers: {'Content-Type': 'application/json'},
      );
      final d = jsonDecode(res.body);
      if (d['success'] == true) {
        onDeleted?.call();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(d['message'] ?? 'Delete failed')));
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.read(currentUserProvider)?.xameId ?? '';
    final isOwner = space.creatorId == userId;
    return GestureDetector(
    onLongPress: isOwner ? () => _deleteSpace(context, userId) : null,
    onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => SpaceScreen(spaceSlug: space.spaceSlug))),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: XameColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
      child: Row(children: [
        space.avatar.isNotEmpty
          ? CircleAvatar(radius: 26, backgroundImage: CachedNetworkImageProvider(space.avatar))
          : CircleAvatar(radius: 26, backgroundColor: XameColors.primary.withValues(alpha: 0.15),
              child: Text(emoji, style: const TextStyle(fontSize: 22))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(space.name, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 2),
          Text(space.description.isNotEmpty ? space.description : space.archetype,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.people_outline, size: 12, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text('${space.memberCount}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
            const SizedBox(width: 12),
            Icon(Icons.chat_bubble_outline, size: 12, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text('${space.messageCount}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          ]),
        ])),
        const Icon(Icons.chevron_right, color: Colors.white24),
      ]),
    ),
  );
}
