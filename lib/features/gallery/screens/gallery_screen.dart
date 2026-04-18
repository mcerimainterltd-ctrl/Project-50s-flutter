import 'dart:io';
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

// ── Colours ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF080C14);
const _kCard    = Color(0xFF111827);
const _kBorder  = Color(0xFF1F2937);
const _kTeal    = Color(0xFF00D4AA);
const _kGold    = Color(0xFFFFB800);
const _kRed     = Color(0xFFEF4444);

// ── Model ─────────────────────────────────────────────────────────────────────
class GalleryItem {
  final String  id, userId, url, type, caption, description,
                price, phone, email, visibility, mode;
  final int     likes, views;
  final DateTime createdAt;

  const GalleryItem({
    required this.id,          required this.userId,
    required this.url,         required this.type,
    required this.caption,     required this.description,
    required this.price,       required this.phone,
    required this.email,       required this.visibility,
    required this.mode,        required this.createdAt,
    this.likes = 0,            this.views = 0,
  });

  bool get isVideo    => type == 'video';
  bool get isBusiness => mode == 'business';
  bool get hasPrice   => price.isNotEmpty;
  bool get hasContact => phone.isNotEmpty || email.isNotEmpty;

  factory GalleryItem.fromJson(Map<String, dynamic> j) => GalleryItem(
    id:          j['_id']         ?? '',
    userId:      j['userId']      ?? '',
    url:         j['url']         ?? '',
    type:        j['type']        ?? 'image',
    caption:     j['caption']     ?? '',
    description: j['description'] ?? '',
    price:       j['price']       ?? '',
    phone:       j['phone']       ?? '',
    email:       j['email']       ?? '',
    visibility:  j['visibility']  ?? 'contacts',
    mode:        j['mode']        ?? 'personal',
    likes:       (j['likes']  as num?)?.toInt() ?? 0,
    views:       (j['views']  as num?)?.toInt() ?? 0,
    createdAt:   DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────
final _galleryProvider = FutureProvider.autoDispose
    .family<List<GalleryItem>, String>((ref, userId) async {
  final dio = Dio(BaseOptions(baseUrl: AppConstants.serverUrl));
  final res = await dio.get('/api/gallery/$userId');
  if (res.data['success'] == true) {
    return (res.data['items'] as List)
        .map((i) => GalleryItem.fromJson(Map<String, dynamic>.from(i)))
        .toList();
  }
  return [];
});

// ── Main Screen ───────────────────────────────────────────────────────────────
class GalleryScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool   isOwner;
  const GalleryScreen({super.key, required this.userId, required this.isOwner});
  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _layout = 'grid';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (!widget.isOwner) _markViewed();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _markViewed() async {
    try {
      final self = ref.read(currentUserProvider);
      if (self == null) return;
      await Dio(BaseOptions(baseUrl: AppConstants.serverUrl))
          .post('/api/gallery/${widget.userId}/viewed',
              data: {'viewerId': self.xameId});
      ref.read(contactsProvider.notifier).clearGalleryDot(widget.userId);
    } catch (_) {}
  }

  Future<void> _delete(String itemId) async {
    final self = ref.read(currentUserProvider);
    if (self == null) return;
    try {
      await Dio(BaseOptions(baseUrl: AppConstants.serverUrl))
          .delete('/api/gallery/$itemId', data: {'userId': self.xameId});
      ref.refresh(_galleryProvider(widget.userId));
    } catch (_) {}
  }

  void _openLightbox(List<GalleryItem> all, GalleryItem item) {
    final list = all.where((i) => i.mode == item.mode).toList();
    final idx  = list.indexOf(item);
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _Lightbox(items: list, initialIndex: idx),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final self    = ref.read(currentUserProvider);
    final gallery = ref.watch(_galleryProvider(widget.userId));

    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true, expandedHeight: 140,
            backgroundColor: _kBg,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white70, size: 18),
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                else context.go('/contacts');
              }),
            actions: [
              IconButton(
                icon: Icon(_layout == 'grid'
                    ? Icons.dashboard_outlined : Icons.grid_view_rounded,
                    color: Colors.white38, size: 20),
                onPressed: () => setState(() =>
                    _layout = _layout == 'grid' ? 'masonry' : 'grid')),
              if (widget.isOwner)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: _kTeal, size: 24),
                  onPressed: () => _showUploadSheet(self?.xameId ?? '')),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 56),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Xame Gallery',
                      style: TextStyle(color: Colors.white, fontSize: 22,
                          fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  if (!widget.isOwner)
                    const Text('Viewing profile',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_kBg, Color(0xFF0F172A)])),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _kBorder))),
                child: TabBar(
                  controller: _tabs,
                  indicatorColor: _kTeal, indicatorWeight: 2,
                  labelColor: _kTeal,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  dividerColor: Colors.transparent,
                  tabs: const [Tab(text: 'Personal'), Tab(text: 'Business')],
                ),
              ),
            ),
          ),
        ],
        body: gallery.when(
          loading: () => const Center(child: CircularProgressIndicator(
              color: _kTeal, strokeWidth: 1.5)),
          error: (_, __) => Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 48),
              const SizedBox(height: 12),
              const Text('Failed to load gallery',
                  style: TextStyle(color: Colors.white38)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.refresh(_galleryProvider(widget.userId)),
                child: const Text('Retry', style: TextStyle(color: _kTeal))),
            ],
          )),
          data: (items) => TabBarView(
            controller: _tabs,
            children: [
              _PersonalTab(
                items: items.where((i) => i.mode == 'personal').toList(),
                isOwner: widget.isOwner, layout: _layout,
                onTap: (item) => _openLightbox(items, item),
                onDelete: _delete),
              _BusinessTab(
                items: items.where((i) => i.mode == 'business').toList(),
                isOwner: widget.isOwner, layout: _layout,
                onTap: (item) => _openLightbox(items, item),
                onDelete: _delete),
            ],
          ),
        ),
      ),
    );
  }

  void _showUploadSheet(String userId) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(
          userId: userId,
          onUploaded: () => ref.refresh(_galleryProvider(widget.userId))),
    );
  }
}

// ── Personal Tab ──────────────────────────────────────────────────────────────
class _PersonalTab extends StatelessWidget {
  final List<GalleryItem> items;
  final bool isOwner; final String layout;
  final Function(GalleryItem) onTap;
  final Function(String) onDelete;
  const _PersonalTab({required this.items, required this.isOwner,
      required this.layout, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _Empty(icon: Icons.photo_library_outlined,
        label: 'No personal photos yet',
        sub: isOwner ? 'Tap + to share your world' : null);
    if (layout == 'masonry') return _MasonryGrid(
        items: items, isOwner: isOwner, onTap: onTap, onDelete: onDelete);
    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3),
      itemCount: items.length,
      itemBuilder: (_, i) => _GridCell(item: items[i], isOwner: isOwner,
          onTap: onTap, onDelete: onDelete),
    );
  }
}

// ── Business Tab ──────────────────────────────────────────────────────────────
class _BusinessTab extends StatelessWidget {
  final List<GalleryItem> items;
  final bool isOwner; final String layout;
  final Function(GalleryItem) onTap;
  final Function(String) onDelete;
  const _BusinessTab({required this.items, required this.isOwner,
      required this.layout, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _Empty(icon: Icons.store_outlined,
        label: 'No business listings yet',
        sub: isOwner ? 'Showcase your products & services' : null);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _BizStats(items: items)),
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
              childAspectRatio: 0.72),
          delegate: SliverChildBuilderDelegate(
            (_, i) => _BizCard(item: items[i], isOwner: isOwner,
                onTap: onTap, onDelete: onDelete),
            childCount: items.length),
        ),
      ),
    ]);
  }
}

// ── Business Stats ────────────────────────────────────────────────────────────
class _BizStats extends StatelessWidget {
  final List<GalleryItem> items;
  const _BizStats({required this.items});
  @override
  Widget build(BuildContext context) {
    final priced  = items.where((i) => i.hasPrice).length;
    final videos  = items.where((i) => i.isVideo).length;
    final contact = items.where((i) => i.hasContact).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kTeal.withValues(alpha: 0.12), _kGold.withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kTeal.withValues(alpha: 0.2))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _Stat('Listings', '${items.length}', _kTeal),
        _SDivider(),
        _Stat('For Sale', '$priced', const Color(0xFF4CAF50)),
        _SDivider(),
        _Stat('Videos',   '$videos', const Color(0xFFFF9800)),
        _SDivider(),
        _Stat('Contacts', '$contact', const Color(0xFF8B5CF6)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value; final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 20,
          fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: Colors.white38,
          fontSize: 10, fontWeight: FontWeight.w500)),
    ]);
}

class _SDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: Colors.white10);
}

// ── Grid Cell ─────────────────────────────────────────────────────────────────
class _GridCell extends StatelessWidget {
  final GalleryItem item; final bool isOwner;
  final Function(GalleryItem) onTap; final Function(String) onDelete;
  const _GridCell({required this.item, required this.isOwner,
      required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onTap(item),
    onLongPress: isOwner ? () => onDelete(item.id) : null,
    child: Stack(fit: StackFit.expand, children: [
      Image.network(item.url, fit: BoxFit.cover,
          loadingBuilder: (_, child, p) => p == null ? child
              : Container(color: _kCard, child: const Center(
                  child: CircularProgressIndicator(color: _kTeal, strokeWidth: 1))),
          errorBuilder: (_, __, ___) => Container(color: _kCard,
              child: const Icon(Icons.broken_image_outlined, color: Colors.white24))),
      if (item.isVideo) const Positioned.fill(child: Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 28))),
      if (item.hasPrice)
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent])),
            child: Text('₦${item.price}', style: const TextStyle(
                color: Color(0xFF4CAF50), fontSize: 10,
                fontWeight: FontWeight.w800)))),
    ]),
  );
}

// ── Masonry Grid ──────────────────────────────────────────────────────────────
class _MasonryGrid extends StatelessWidget {
  final List<GalleryItem> items; final bool isOwner;
  final Function(GalleryItem) onTap; final Function(String) onDelete;
  const _MasonryGrid({required this.items, required this.isOwner,
      required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final left = <GalleryItem>[], right = <GalleryItem>[];
    for (int i = 0; i < items.length; i++) {
      if (i.isEven) left.add(items[i]); else right.add(items[i]);
    }
    return SingleChildScrollView(padding: const EdgeInsets.all(4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(children: left.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _MasonryCell(item: item, isOwner: isOwner,
              onTap: onTap, onDelete: onDelete))).toList())),
        const SizedBox(width: 4),
        Expanded(child: Column(children: right.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _MasonryCell(item: item, isOwner: isOwner,
              onTap: onTap, onDelete: onDelete))).toList())),
      ]));
  }
}

class _MasonryCell extends StatelessWidget {
  final GalleryItem item; final bool isOwner;
  final Function(GalleryItem) onTap; final Function(String) onDelete;
  const _MasonryCell({required this.item, required this.isOwner,
      required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onTap(item),
    onLongPress: isOwner ? () => onDelete(item.id) : null,
    child: ClipRRect(borderRadius: BorderRadius.circular(10),
      child: Stack(children: [
        Image.network(item.url, fit: BoxFit.cover, width: double.infinity,
            loadingBuilder: (_, child, p) => p == null ? child
                : Container(height: 120, color: _kCard, child: const Center(
                    child: CircularProgressIndicator(color: _kTeal, strokeWidth: 1))),
            errorBuilder: (_, __, ___) => Container(height: 120, color: _kCard,
                child: const Icon(Icons.broken_image_outlined, color: Colors.white24))),
        if (item.isVideo) const Positioned.fill(child: Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32))),
        if (item.caption.isNotEmpty)
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent])),
              child: Text(item.caption, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11)))),
      ])),
  );
}

// ── Business Card ─────────────────────────────────────────────────────────────
class _BizCard extends StatelessWidget {
  final GalleryItem item; final bool isOwner;
  final Function(GalleryItem) onTap; final Function(String) onDelete;
  const _BizCard({required this.item, required this.isOwner,
      required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onTap(item),
    onLongPress: isOwner ? () => onDelete(item.id) : null,
    child: Container(
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(item.url, fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null ? child
                    : Container(color: _kBg, child: const Center(
                        child: CircularProgressIndicator(color: _kTeal, strokeWidth: 1))),
                errorBuilder: (_, __, ___) => Container(color: _kBg,
                    child: const Icon(Icons.store_outlined,
                        color: Colors.white24, size: 32))),
            if (item.isVideo) const Center(child: Icon(
                Icons.play_circle_fill, color: Colors.white70, size: 36)),
            Positioned(top: 8, right: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_visIcon(item.visibility), color: Colors.white70, size: 10),
                const SizedBox(width: 4),
                Text(_visLabel(item.visibility), style: const TextStyle(
                    color: Colors.white70, fontSize: 9,
                    fontWeight: FontWeight.w600)),
              ]))),
            if (isOwner) Positioned(top: 8, left: 8,
              child: GestureDetector(
                onTap: () => onDelete(item.id),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.close, color: Colors.white70, size: 12)))),
          ]))),
        Expanded(flex: 3, child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (item.caption.isNotEmpty)
              Text(item.caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
            const Spacer(),
            Row(children: [
              if (item.hasPrice)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50)
                        .withValues(alpha: 0.4))),
                  child: Text('₦${item.price}', style: const TextStyle(
                      color: Color(0xFF4CAF50), fontSize: 10,
                      fontWeight: FontWeight.w800)))
              else
                const Text('Free', style: TextStyle(
                    color: Colors.white38, fontSize: 10)),
              const Spacer(),
              if (item.hasContact) const Icon(Icons.contact_phone_outlined,
                  color: _kTeal, size: 14),
            ]),
          ]),
        )),
      ]),
    ),
  );

  IconData _visIcon(String v) => v == 'public' ? Icons.public
      : v == 'private' ? Icons.lock_outline : Icons.people_outline;
  String _visLabel(String v) => v == 'public' ? 'Public'
      : v == 'private' ? 'Private' : 'Contacts';
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
  late int _idx;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _idx  = widget.initialIndex;
    _page = PageController(initialPage: widget.initialIndex);
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
    final item = widget.items[_idx];
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(children: [
          // Full screen swipeable images
          PageView.builder(
            controller: _page, itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              return Center(
                child: Image.network(
                  it.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Center(
                          child: CircularProgressIndicator(
                              color: _kTeal, strokeWidth: 1.5)),
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white24, size: 64),
                ),
              );
            },
          ),

          // Top bar
          AnimatedOpacity(
            opacity: _showUI ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Positioned(top: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent])),
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 4,
                    left: 4, right: 16, bottom: 20),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${_idx + 1} / ${widget.items.length}',
                        style: const TextStyle(color: Colors.white70,
                            fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              )),
          ),

          // Bottom info
          if (item.caption.isNotEmpty || item.hasPrice ||
              item.hasContact || item.description.isNotEmpty)
            AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Positioned(bottom: 0, left: 0, right: 0,
                child: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black, Colors.transparent])),
                  padding: EdgeInsets.fromLTRB(20, 32, 20,
                      MediaQuery.of(context).padding.bottom + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.caption.isNotEmpty)
                        Text(item.caption, style: const TextStyle(
                            color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700)),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.description, style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (item.hasPrice)
                          _InfoChip('₦${item.price}', Icons.payments_outlined,
                              const Color(0xFF4CAF50)),
                        if (item.phone.isNotEmpty)
                          _InfoChip(item.phone, Icons.phone_outlined, _kTeal),
                        if (item.email.isNotEmpty)
                          _InfoChip(item.email, Icons.email_outlined,
                              const Color(0xFF8B5CF6)),
                      ]),
                    ],
                  ),
                )),
            ),
        ]),
      ),
    );
  }
}

Widget _InfoChip(String label, IconData icon, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: color.withValues(alpha: 0.5))),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: color, size: 13),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(color: color, fontSize: 12,
        fontWeight: FontWeight.w600)),
  ]),
);

// ── Upload Sheet ──────────────────────────────────────────────────────────────
class _UploadSheet extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onUploaded;
  const _UploadSheet({required this.userId, required this.onUploaded});
  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  File?   _file;
  String  _visibility = 'contacts';
  String  _mode       = 'personal';
  bool    _uploading  = false;
  double  _progress   = 0;

  final _caption     = TextEditingController();
  final _description = TextEditingController();
  final _price       = TextEditingController();
  final _phone       = TextEditingController();
  final _email       = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() =>
        _mode = _tabs.index == 0 ? 'personal' : 'business'));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _caption.dispose(); _description.dispose();
    _price.dispose(); _phone.dispose(); _email.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (f != null) setState(() => _file = File(f.path));
  }

  Future<void> _upload() async {
    if (_file == null) return;
    setState(() { _uploading = true; _progress = 0; });
    try {
      final form = FormData.fromMap({
        'file':        await MultipartFile.fromFile(_file!.path),
        'userId':      widget.userId,
        'caption':     _caption.text.trim(),
        'description': _description.text.trim(),
        'price':       _price.text.trim(),
        'phone':       _phone.text.trim(),
        'email':       _email.text.trim(),
        'visibility':  _visibility,
        'mode':        _mode,
      });
      await Dio(BaseOptions(baseUrl: AppConstants.serverUrl))
          .post('/api/gallery/upload', data: form,
              onSendProgress: (s, t) =>
                  setState(() => _progress = s / t));
      widget.onUploaded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'),
              backgroundColor: _kRed));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 0, 20,
          MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
                color: _kCard, borderRadius: BorderRadius.circular(12)),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                color: _kTeal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
              labelColor: _kTeal,
              unselectedLabelColor: Colors.white38,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
              tabs: const [Tab(text: 'Personal'), Tab(text: 'Business')],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: _kCard, borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _file != null ? _kTeal : _kBorder, width: 1.5)),
              child: _file != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(14),
                      child: Image.file(_file!, fit: BoxFit.cover,
                          width: double.infinity))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: _kTeal, size: 40),
                        SizedBox(height: 8),
                        Text('Tap to select photo or video',
                            style: TextStyle(color: Colors.white38,
                                fontSize: 13)),
                      ]),
            ),
          ),
          const SizedBox(height: 16),
          _buildField(_caption, 'Title / Caption', Icons.title),
          if (_mode == 'business') ...[
            const SizedBox(height: 10),
            _buildField(_description, 'Description',
                Icons.description_outlined, maxLines: 3),
            const SizedBox(height: 10),
            _buildField(_price, 'Price (e.g. 5000)',
                Icons.payments_outlined,
                type: TextInputType.number),
            const SizedBox(height: 10),
            _buildField(_phone, 'Phone Number',
                Icons.phone_outlined,
                type: TextInputType.phone),
            const SizedBox(height: 10),
            _buildField(_email, 'Email Address',
                Icons.email_outlined,
                type: TextInputType.emailAddress),
          ],
          const SizedBox(height: 10),
          Row(children: [
            const Text('Visibility', style: TextStyle(
                color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 12),
            Expanded(child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _buildVisChip('contacts', Icons.people_outline, 'Contacts'),
                const SizedBox(width: 8),
                _buildVisChip('public', Icons.public, 'Public'),
                const SizedBox(width: 8),
                _buildVisChip('private', Icons.lock_outline, 'Private'),
              ]),
            )),
          ]),
          const SizedBox(height: 20),
          if (_uploading) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _progress,
                  color: _kTeal, backgroundColor: _kCard, minHeight: 6)),
            const SizedBox(height: 8),
            Center(child: Text('${(_progress * 100).toInt()}% uploaded',
                style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ] else
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _file == null ? null : _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Upload to Gallery',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: _kBorder,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              )),
        ],
      )),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text, int maxLines = 1}) =>
    TextField(
      controller: ctrl, keyboardType: type, maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white30, size: 18),
        filled: true, fillColor: _kCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kTeal, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12)),
    );

  Widget _buildVisChip(String val, IconData icon, String label) {
    final sel = _visibility == val;
    return GestureDetector(
      onTap: () => setState(() => _visibility = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _kTeal.withValues(alpha: 0.15) : _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _kTeal : _kBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: sel ? _kTeal : Colors.white38, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: sel ? _kTeal : Colors.white38,
              fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _Empty extends StatelessWidget {
  final IconData icon; final String label; final String? sub;
  const _Empty({required this.icon, required this.label, this.sub});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _kCard, shape: BoxShape.circle,
            border: Border.all(color: _kBorder)),
        child: Icon(icon, color: Colors.white24, size: 48)),
      const SizedBox(height: 16),
      Text(label, style: const TextStyle(color: Colors.white54,
          fontSize: 16, fontWeight: FontWeight.w600)),
      if (sub != null) ...[
        const SizedBox(height: 6),
        Text(sub!, style: const TextStyle(color: Colors.white30, fontSize: 13)),
      ],
    ]),
  );
}
