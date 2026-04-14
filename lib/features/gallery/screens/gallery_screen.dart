import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/auth_service.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../../../core/theme/app_theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class GalleryItem {
  final String  id, userId, url, type, caption, price, visibility, mode;
  final DateTime createdAt;

  const GalleryItem({
    required this.id,       required this.userId,
    required this.url,      required this.type,
    required this.caption,  required this.price,
    required this.visibility, required this.mode,
    required this.createdAt,
  });

  bool get isVideo => type == 'video';
  bool get isBusiness => mode == 'business';
  bool get hasPrice => price.isNotEmpty;

  factory GalleryItem.fromJson(Map<String, dynamic> j) => GalleryItem(
    id:         j['_id']        ?? '',
    userId:     j['userId']     ?? '',
    url:        j['url']        ?? '',
    type:       j['type']       ?? 'image',
    caption:    j['caption']    ?? '',
    price:      j['price']      ?? '',
    visibility: j['visibility'] ?? 'contacts',
    mode:       j['mode']       ?? 'personal',
    createdAt:  DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final _galleryProvider = FutureProvider.autoDispose
    .family<List<GalleryItem>, String>((ref, userId) async {
  final dio  = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final res  = await dio.get('/api/gallery/$userId');
  if (res.data['success'] == true) {
    return (res.data['items'] as List)
        .map((i) => GalleryItem.fromJson(Map<String, dynamic>.from(i)))
        .toList();
  }
  return [];
});

// ── Screen ────────────────────────────────────────────────────────────────────
class GalleryScreen extends ConsumerStatefulWidget {
  final String  userId;
  final bool    isOwner;
  const GalleryScreen({super.key, required this.userId, required this.isOwner});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _view = 'grid'; // 'grid' | 'masonry'

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Mark gallery as viewed
    if (!widget.isOwner) _markViewed();
  }

  Future<void> _markViewed() async {
    try {
      final self = ref.read(currentUserProvider);
      if (self == null) return;
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      await dio.post('/api/gallery/${widget.userId}/viewed',
          data: {'viewerId': self.xameId});
      // Clear dot locally
      ref.read(contactsProvider.notifier).clearGalleryDot(widget.userId);
    } catch (_) {}
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final gallery = ref.watch(_galleryProvider(widget.userId));
    final self    = ref.read(currentUserProvider);

    return Scaffold(backgroundColor: Colors.black,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned:           true,
            expandedHeight:   120,
            backgroundColor:  theme.bg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: theme.text, size: 18),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/contacts');
                }
              }),
            actions: [
              // View toggle
              IconButton(
                icon: Icon(
                  _view == 'grid'
                      ? Icons.dashboard_outlined
                      : Icons.grid_view_rounded,
                  color: theme.textSecondary, size: 20),
                onPressed: () => setState(() =>
                    _view = _view == 'grid' ? 'masonry' : 'grid')),
              if (widget.isOwner)
                IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      color: theme.primary, size: 22),
                  onPressed: () => _showUploadSheet(context, theme, self?.xameId ?? '')),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 60),
              title: Text('Xame Gallery',
                style: TextStyle(color: theme.text, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [theme.bg, theme.surface],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: TabBar(
                controller: _tabs,
                indicatorColor: theme.primary,
                indicatorWeight: 2.5,
                labelColor: theme.primary,
                unselectedLabelColor: theme.textSecondary,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                dividerColor: Colors.white10,
                tabs: const [
                  Tab(text: '  Personal  '),
                  Tab(text: '  Business  '),
                ],
              ),
            ),
          ),
        ],
        body: gallery.when(
          loading: () => Center(child: CircularProgressIndicator(
              color: theme.primary, strokeWidth: 1.5)),
          error: (_, __) => Center(child: Text('Failed to load gallery',
              style: TextStyle(color: theme.textSecondary))),
          data: (items) => TabBarView(
            controller: _tabs,
            children: [
              _GalleryTab(
                items:     items.where((i) => i.mode == 'personal').toList(),
                isOwner:   widget.isOwner,
                viewerId:  widget.userId,
                selfId:    self?.xameId ?? '',
                theme:     theme,
                view:      _view,
                onDelete:  (id) => _delete(id, self?.xameId ?? ''),
                onTap:     (item) => _openLightbox(context, item, items),
              ),
              _BusinessTab(
                items:    items.where((i) => i.mode == 'business').toList(),
                isOwner:  widget.isOwner,
                selfId:   self?.xameId ?? '',
                theme:    theme,
                view:     _view,
                onDelete: (id) => _delete(id, self?.xameId ?? ''),
                onTap:    (item) => _openLightbox(context, item, items),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(String itemId, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Item',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Remove this from your gallery?',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      await dio.delete('/api/gallery/$itemId',
          data: {'userId': userId});
      ref.refresh(_galleryProvider(widget.userId));
    } catch (_) {}
  }

  void _openLightbox(BuildContext context, GalleryItem item,
      List<GalleryItem> all) {
    final sameMode = all.where((i) => i.mode == item.mode).toList();
    final idx      = sameMode.indexOf(item);
    Navigator.push(context, PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _Lightbox(
          items: sameMode, initialIndex: idx),
    ));
  }

  void _showUploadSheet(BuildContext context, XameTheme theme, String userId) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder:            (_) => _UploadSheet(
          theme: theme, userId: userId,
          onUploaded: () => ref.refresh(_galleryProvider(widget.userId))),
    );
  }
}

// ── Personal Tab ──────────────────────────────────────────────────────────────
class _GalleryTab extends StatelessWidget {
  final List<GalleryItem> items;
  final bool   isOwner;
  final String viewerId, selfId, view;
  final XameTheme theme;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;

  const _GalleryTab({required this.items, required this.isOwner,
      required this.viewerId, required this.selfId, required this.theme,
      required this.view, required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyState(theme: theme,
        label: 'No personal photos yet',
        sub: isOwner ? 'Tap + to add your first photo' : null);

    if (view == 'masonry') {
      return _MasonryGrid(items: items, theme: theme, isOwner: isOwner,
          selfId: selfId, onDelete: onDelete, onTap: onTap);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:  3, crossAxisSpacing: 3, mainAxisSpacing: 3),
      itemCount: items.length,
      itemBuilder: (_, i) => _GridCell(item: items[i], theme: theme,
          isOwner: isOwner, selfId: selfId,
          onDelete: onDelete, onTap: onTap),
    );
  }
}

// ── Business Tab ──────────────────────────────────────────────────────────────
class _BusinessTab extends StatelessWidget {
  final List<GalleryItem> items;
  final bool   isOwner;
  final String selfId, view;
  final XameTheme theme;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;

  const _BusinessTab({required this.items, required this.isOwner,
      required this.selfId, required this.theme, required this.view,
      required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyState(theme: theme,
        label: 'No business listings yet',
        sub: isOwner ? 'Showcase your products & services' : null,
        icon: Icons.store_outlined);

    return CustomScrollView(slivers: [
      // Stats bar
      SliverToBoxAdapter(child: _BusinessStats(items: items, theme: theme)),

      // Items
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:  2, crossAxisSpacing: 12, mainAxisSpacing: 12,
            childAspectRatio: 0.75),
          delegate: SliverChildBuilderDelegate(
            (_, i) => _BusinessCard(item: items[i], theme: theme,
                isOwner: isOwner, selfId: selfId,
                onDelete: onDelete, onTap: onTap),
            childCount: items.length,
          ),
        ),
      ),
    ]);
  }
}

// ── Business Stats Bar ────────────────────────────────────────────────────────
class _BusinessStats extends StatelessWidget {
  final List<GalleryItem> items;
  final XameTheme theme;
  const _BusinessStats({required this.items, required this.theme});

  @override
  Widget build(BuildContext context) {
    final priced   = items.where((i) => i.hasPrice).length;
    final videos   = items.where((i) => i.isVideo).length;
    final total    = items.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primary.withValues(alpha: 0.15),
                   theme.secondary.withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'Listings', value: '$total', theme: theme),
          _Divider(),
          _Stat(label: 'For Sale', value: '$priced', theme: theme,
              color: const Color(0xFF4CAF50)),
          _Divider(),
          _Stat(label: 'Videos', value: '$videos', theme: theme,
              color: const Color(0xFFFF9800)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final XameTheme theme;
  final Color? color;
  const _Stat({required this.label, required this.value,
      required this.theme, this.color});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: TextStyle(color: color ?? theme.primary,
          fontSize: 20, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: theme.textSecondary,
          fontSize: 11, fontWeight: FontWeight.w500)),
    ],
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 28, color: Colors.white12);
}

// ── Masonry Grid ──────────────────────────────────────────────────────────────
class _MasonryGrid extends StatelessWidget {
  final List<GalleryItem> items;
  final XameTheme theme;
  final bool isOwner;
  final String selfId;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;
  const _MasonryGrid({required this.items, required this.theme,
      required this.isOwner, required this.selfId,
      required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final left  = <GalleryItem>[];
    final right = <GalleryItem>[];
    for (int i = 0; i < items.length; i++) {
      if (i % 2 == 0) left.add(items[i]); else right.add(items[i]);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left.map((item) =>
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: _MasonryCell(item: item, theme: theme, isOwner: isOwner,
                    selfId: selfId, onDelete: onDelete, onTap: onTap))).toList())),
          const SizedBox(width: 4),
          Expanded(child: Column(children: right.map((item) =>
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: _MasonryCell(item: item, theme: theme, isOwner: isOwner,
                    selfId: selfId, onDelete: onDelete, onTap: onTap))).toList())),
        ],
      ),
    );
  }
}

class _MasonryCell extends StatelessWidget {
  final GalleryItem item;
  final XameTheme theme;
  final bool isOwner;
  final String selfId;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;
  const _MasonryCell({required this.item, required this.theme,
      required this.isOwner, required this.selfId,
      required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(item),
      onLongPress: isOwner && item.userId == selfId
          ? () => onDelete(item.id) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover,
              width: double.infinity),
          if (item.isVideo)
            Positioned.fill(child: Container(
              color: Colors.black26,
              child: const Center(child: Icon(Icons.play_circle_outline,
                  color: Colors.white, size: 32)))),
          if (item.hasPrice)
            Positioned(bottom: 6, left: 6, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(8)),
              child: Text('₦${item.price}',
                style: const TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700)))),
        ]),
      ),
    );
  }
}

// ── Grid Cell ─────────────────────────────────────────────────────────────────
class _GridCell extends StatelessWidget {
  final GalleryItem item;
  final XameTheme theme;
  final bool isOwner;
  final String selfId;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;
  const _GridCell({required this.item, required this.theme,
      required this.isOwner, required this.selfId,
      required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(item),
      onLongPress: isOwner && item.userId == selfId
          ? () => onDelete(item.id) : null,
      child: Stack(fit: StackFit.expand, children: [
        CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: theme.card,
            child: Icon(Icons.image_outlined, color: theme.textSecondary))),
        if (item.isVideo)
          Container(color: Colors.black26,
            child: const Center(child: Icon(Icons.play_circle_outline,
                color: Colors.white70, size: 28))),
        if (item.visibility == 'private')
          Positioned(top: 4, right: 4,
            child: Icon(Icons.lock_outline, color: Colors.white70, size: 14)),
      ]),
    );
  }
}

// ── Business Card ─────────────────────────────────────────────────────────────
class _BusinessCard extends StatelessWidget {
  final GalleryItem item;
  final XameTheme theme;
  final bool isOwner;
  final String selfId;
  final Function(String) onDelete;
  final Function(GalleryItem) onTap;
  const _BusinessCard({required this.item, required this.theme,
      required this.isOwner, required this.selfId,
      required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(item),
      child: Container(
        decoration: BoxDecoration(
          color:        theme.card,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: theme.surface,
                    child: Icon(Icons.store_outlined,
                        color: theme.textSecondary, size: 36))),
                if (item.isVideo)
                  Container(color: Colors.black38,
                    child: const Center(child: Icon(Icons.play_circle_outline,
                        color: Colors.white, size: 36))),
                // Visibility badge
                Positioned(top: 8, right: 8, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_visIcon(), color: Colors.white70, size: 10),
                    const SizedBox(width: 3),
                    Text(_visLabel(), style: const TextStyle(
                        color: Colors.white70, fontSize: 9)),
                  ]),
                )),
                // Owner delete
                if (isOwner && item.userId == selfId)
                  Positioned(top: 6, left: 6, child: GestureDetector(
                    onTap: () => onDelete(item.id),
                    child: Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 14)),
                  )),
              ]),
            ),
          ),
          // Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.caption.isNotEmpty)
                    Text(item.caption,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.text, fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Row(children: [
                    if (item.hasPrice) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
                        ),
                        child: Text('₦${item.price}',
                          style: const TextStyle(
                            color: Color(0xFF4CAF50), fontSize: 11,
                            fontWeight: FontWeight.w800)),
                      ),
                    ] else
                      Text('Free', style: TextStyle(
                          color: theme.textSecondary, fontSize: 11)),
                    const Spacer(),
                    Icon(item.isVideo
                        ? Icons.videocam_outlined : Icons.photo_outlined,
                        color: theme.textSecondary, size: 14),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  IconData _visIcon() {
    if (item.visibility == 'public')   return Icons.public;
    if (item.visibility == 'private')  return Icons.lock_outline;
    return Icons.people_outline;
  }

  String _visLabel() {
    if (item.visibility == 'public')   return 'Public';
    if (item.visibility == 'private')  return 'Private';
    return 'Contacts';
  }
}

// ── Lightbox ──────────────────────────────────────────────────────────────────
class _Lightbox extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;
  const _Lightbox({required this.items, required this.initialIndex});
  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late PageController _page;
  late int _current;
  bool _showInfo = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page    = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _page.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_current];
    return Scaffold(backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showInfo = !_showInfo),
        child: Stack(children: [
          // Swipeable images
          PageView.builder(
            controller:  _page,
            itemCount:   widget.items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              return Center(
                child: InteractiveViewer(
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl:    it.url,
                    fit:         BoxFit.contain,
                    width:       MediaQuery.of(context).size.width,
                    placeholder: (_, __) => const SizedBox(
                      width: 40, height: 40,
                      child: CircularProgressIndicator(
                          color: Colors.white38, strokeWidth: 1.5)),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white30, size: 48),
                  ),
                ),
              );
            },
          ),

          // Top bar
          AnimatedOpacity(
            opacity:  _showInfo ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Positioned(top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8, right: 8, bottom: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent])),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/contacts');
                }
              }),
                  const Spacer(),
                  Text('${_current + 1} / ${widget.items.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),

          // Bottom info
          if (item.caption.isNotEmpty || item.hasPrice)
            AnimatedOpacity(
              opacity:  _showInfo ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Positioned(bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, 24, 20,
                      MediaQuery.of(context).padding.bottom + 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent])),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.caption.isNotEmpty)
                        Text(item.caption,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      if (item.hasPrice) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(20)),
                            child: Text('₦${item.price}',
                              style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w800, fontSize: 14))),
                          const SizedBox(width: 10),
                          const Text('for sale',
                            style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Upload Sheet ──────────────────────────────────────────────────────────────
class _UploadSheet extends ConsumerStatefulWidget {
  final XameTheme theme;
  final String    userId;
  final VoidCallback onUploaded;
  const _UploadSheet({required this.theme, required this.userId,
      required this.onUploaded});
  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet> {
  final _captionCtrl = TextEditingController();
  final _priceCtrl   = TextEditingController();
  final _picker      = ImagePicker();

  File?   _file;
  String  _mode       = 'personal';
  String  _visibility = 'contacts';
  bool    _uploading  = false;

  @override
  void dispose() { _captionCtrl.dispose(); _priceCtrl.dispose(); super.dispose(); }

  Future<void> _pick(ImageSource source, {bool video = false}) async {
    final picked = video
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) setState(() => _file = File(picked.path));
  }

  Future<void> _upload() async {
    if (_file == null) { _snack('Pick a photo or video first'); return; }
    setState(() => _uploading = true);
    try {
      final form = FormData.fromMap({
        'userId':     widget.userId,
        'caption':    _captionCtrl.text.trim(),
        'price':      _priceCtrl.text.trim(),
        'visibility': _visibility,
        'mode':       _mode,
        'file':       await MultipartFile.fromFile(_file!.path),
      });
      final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
      final res = await dio.post('/api/gallery/upload', data: form);
      if (res.data['success'] == true) {
        widget.onUploaded();
        if (mounted) Navigator.pop(context);
        _snack('Uploaded successfully! ✓');
      } else {
        _snack(res.data['message'] ?? 'Upload failed');
      }
    } catch (_) { _snack('Upload error'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg),
        backgroundColor: widget.theme.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color:        theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(controller: ctrl, padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)))),

            Text('Add to Gallery',
              style: TextStyle(color: theme.text, fontSize: 20,
                  fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),

            // File picker
            GestureDetector(
              onTap: () => _showPickOptions(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 200,
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _file != null
                        ? theme.primary : Colors.white12,
                    width: _file != null ? 2 : 1),
                ),
                child: _file != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Image.file(_file!, fit: BoxFit.cover))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: theme.primary, size: 48),
                          const SizedBox(height: 10),
                          Text('Tap to pick photo or video',
                            style: TextStyle(color: theme.textSecondary,
                                fontSize: 14)),
                        ]),
              ),
            ),

            const SizedBox(height: 16),

            // Caption
            _field(theme, _captionCtrl, 'Caption (optional)',
                Icons.text_fields_rounded),
            const SizedBox(height: 12),

            // Mode toggle
            Row(children: [
              _ModeChip(label: '👤 Personal', value: 'personal',
                  selected: _mode == 'personal', theme: theme,
                  onTap: () => setState(() => _mode = 'personal')),
              const SizedBox(width: 10),
              _ModeChip(label: '🏪 Business', value: 'business',
                  selected: _mode == 'business', theme: theme,
                  onTap: () => setState(() => _mode = 'business')),
            ]),

            if (_mode == 'business') ...[
              const SizedBox(height: 12),
              _field(theme, _priceCtrl, 'Price in ₦ (leave empty if free)',
                  Icons.attach_money_rounded,
                  type: TextInputType.number),
            ],

            const SizedBox(height: 12),

            // Visibility
            Text('Visibility',
              style: TextStyle(color: theme.textSecondary, fontSize: 12,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(children: [
              for (final v in [
                ('public', '🌍 Public'),
                ('contacts', '👥 Contacts'),
                ('private', '🔒 Private'),
              ])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _ModeChip(
                    label: v.$2, value: v.$1,
                    selected: _visibility == v.$1, theme: theme,
                    onTap: () => setState(() => _visibility = v.$1)),
                )),
            ]),

            const SizedBox(height: 24),

            SizedBox(width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _uploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor:  theme.primary,
                  foregroundColor:  Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
                child: _uploading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Text('Upload',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w800)),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showPickOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.theme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
            title: const Text('Camera', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pick(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
            title: const Text('Gallery', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pick(ImageSource.gallery); }),
          ListTile(leading: const Icon(Icons.videocam_outlined, color: Colors.white70),
            title: const Text('Video', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pick(ImageSource.gallery, video: true); }),
          const SizedBox(height: 8),
        ],
      )),
    );
  }

  Widget _field(XameTheme theme, TextEditingController ctrl, String hint,
      IconData icon, {TextInputType type = TextInputType.text}) =>
    Container(
      decoration: BoxDecoration(color: theme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10)),
      child: TextField(
        controller: ctrl, keyboardType: type,
        style: TextStyle(color: theme.text, fontSize: 14),
        decoration: InputDecoration(
          hintText:    hint,
          hintStyle:   TextStyle(color: theme.textSecondary),
          prefixIcon:  Icon(icon, color: theme.textSecondary, size: 18),
          border:      InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14)),
      ),
    );
}

class _ModeChip extends StatelessWidget {
  final String label, value;
  final bool     selected;
  final XameTheme theme;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.value,
      required this.selected, required this.theme, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? theme.primary.withValues(alpha: 0.15) : theme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? theme.primary : Colors.white12,
          width: selected ? 1.5 : 1)),
      child: Center(child: Text(label,
        style: TextStyle(
          color: selected ? theme.primary : theme.textSecondary,
          fontSize: 12, fontWeight: selected
              ? FontWeight.w700 : FontWeight.normal))),
    ),
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final XameTheme theme;
  final String    label;
  final String?   sub;
  final IconData  icon;
  const _EmptyState({required this.theme, required this.label,
      this.sub, this.icon = Icons.photo_library_outlined});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.05)),
        child: Icon(icon, color: Colors.white24, size: 36)),
      const SizedBox(height: 20),
      Text(label, style: TextStyle(color: theme.textSecondary,
          fontSize: 16, fontWeight: FontWeight.w500)),
      if (sub != null) ...[
        const SizedBox(height: 8),
        Text(sub!, style: TextStyle(color: theme.textSecondary
            .withValues(alpha: 0.5), fontSize: 13)),
      ],
    ]),
  );
}
