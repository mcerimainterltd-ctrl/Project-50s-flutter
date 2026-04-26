import '../../discovery/screens/discovery_aura_feed.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../calls/screens/call_history_screen.dart';
import '../../calls/screens/calls_hub_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../../screens/phone_screen.dart';
import '../../../screens/xame_pay_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../gallery/screens/gallery_screen.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/config/constants.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/xame_user.dart';
import '../providers/contacts_provider.dart';
import '../../messaging/broadcast.dart';
import '../../messaging/groups.dart';
import '../../calling/call_schedule.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;
  String _filter = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && _tabCtrl.indexIsChanging) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => CallsHubScreen()));
          _tabCtrl.index = _tab;
        });
      } else {
        setState(() => _tab = _tabCtrl.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectSocket());
  }

  void _connectSocket() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final socket = ref.read(socketServiceProvider);
    socket.connect(user.xameId);
    socket.startHeartbeat(user.xameId);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: context.xBg,
      body: SafeArea(child: Column(children: [
        _buildHeader(user),
        Expanded(child: IndexedStack(index: _tab, children: [
          _ChatsTab(filter: _filter),
          const SizedBox.shrink(), // Calls tab opens fullscreen
          Consumer(builder: (_, ref, __) {
            final self = ref.read(currentUserProvider);
            return DiscoveryAuraFeed();
          }),
          Consumer(builder: (_, ref, __) { final u = ref.read(currentUserProvider); return PhoneScreen(
                    userId:       u?.xameId ?? '',
                    serverUrl:    'https://project-50s.onrender.com',
                    xameContacts: (ref.watch(contactsProvider).valueOrNull ?? [])
                        .map((c) => XameContact(
                              id:         c.id,
                              name:       c.name,
                              profilePic: c.profilePic,
                            ))
                        .toList(),
                  ); }),
          Consumer(builder: (_, ref, __) {
              final u = ref.read(currentUserProvider);
              return XamePayScreen(
                userId:       u?.xameId ?? '',
                serverUrl:    AppConstants.serverUrl,
                xameContacts: (ref.read(contactsProvider).valueOrNull ?? [])
                    .map((c) => {'id': c.id, 'name': c.name})
                    .toList(),
              );
            }),
        ])),
      ])),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _tab == 0 ? FloatingActionButton(
        onPressed:       _showAddContactDialog,
        backgroundColor: context.xPrimary,
        foregroundColor: Colors.black,
        child:           Icon(Icons.add_rounded, size: 28),
      ) : null,
    );
  }

  Widget _buildHeader(XameUser? user) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
    child: Row(children: [
      GestureDetector(
        onTap: () => context.go('/profile'),
        child: XameAvatar(
          name: user?.displayName ?? '',
          profilePic: user?.profilePic,
          size: 36, isOnline: true),
      ),
      SizedBox(width: 12),
      Expanded(child: _tab == 0
        ? TextField(
            controller: _searchCtrl,
            onChanged:  (v) => setState(() => _filter = v),
            style: TextStyle(color: context.xText, fontSize: 14),
            decoration: InputDecoration(
              hintText:  'Search chats...',
              hintStyle: TextStyle(color: context.xMuted, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: context.xMuted, size: 18),
              suffixIcon: _filter.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, color: context.xMuted, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _filter = '');
                    })
                : null,
              filled: true, fillColor: context.xCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            ),
          )
        : Text(['Chats','Calls','Discover','Phone','Pay'][_tab],
            style: TextStyle(color: context.xText, fontSize: 20,
              fontWeight: FontWeight.bold)),
      ),
      _ConnectionDot(),
      IconButton(
        icon: Icon(Icons.more_vert, color: context.xText),
        onPressed: _showMainMenu),
    ]),
  );

  Widget _buildBottomNav() {
    final ctx = context;
    return Container(
    decoration: BoxDecoration(
      color: ctx.xSurface,
      border: Border(top: BorderSide(
        color: ctx.xMuted.withValues(alpha: 0.1)))),
    child: TabBar(
      controller: _tabCtrl,
      indicatorColor: ctx.xPrimary,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: ctx.xPrimary,
      unselectedLabelColor: ctx.xMuted,
      labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      tabs: [
        const Tab(icon: Icon(Icons.chat_bubble_outline_rounded, size: 22), text: 'Chats'),
        Tab(
          icon: Consumer(builder: (_, ref, __) {
            final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
            final missed = contacts.fold<int>(0, (sum, c) => sum + c.missedCallsCount);
            if (missed <= 0) return const Icon(Icons.call_outlined, size: 22);
            return Badge(
                  label: Text(missed > 99 ? '99+' : '$missed',
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: XameColors.danger,
                  child: const Icon(Icons.call_outlined, size: 22));
          }),
          text: 'Calls'),
        Tab(icon: Icon(Icons.explore_outlined,            size: 22), text: 'Discover'),
        Tab(icon: Icon(Icons.phone_outlined,              size: 22), text: 'Phone'),
        Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 22), text: "Pay"),
      ],
    ),
  );
  }

  void _showAddContactDialog() {
    final ctrl = TextEditingController();
    String? error;
    Map<String, dynamic>? foundUser;
    bool searching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.xCard,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) =>
        Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Add Contact',
                style: TextStyle(color: context.xText, fontSize: 18,
                  fontWeight: FontWeight.bold)),
              Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: context.xMuted),
                onPressed: () => Navigator.pop(ctx)),
            ]),
            SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  style: TextStyle(color: context.xText),
                  onSubmitted: (_) => _doSearch(
                    ctrl, setS,
                    (e) => error = e,
                    (u) => foundUser = u,
                    (s) => searching = s),
                  decoration: InputDecoration(
                    hintText:  'Enter Xame-ID',
                    hintStyle: TextStyle(color: context.xMuted),
                    prefixIcon: Icon(Icons.alternate_email,
                      color: context.xMuted, size: 20),
                    filled: true, fillColor: context.xCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: XameColors.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(height: 50,
                child: ElevatedButton(
                  onPressed: searching ? null : () => _doSearch(
                    ctrl, setS,
                    (e) => error = e,
                    (u) => foundUser = u,
                    (s) => searching = s),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: XameColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  child: searching
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2))
                    : const Text('Search'),
                )),
            ]),
            if (error != null) ...[
              SizedBox(height: 10),
              Row(children: [
                Icon(Icons.info_outline,
                  color: XameColors.danger, size: 16),
                SizedBox(width: 6),
                Text(error!,
                  style: TextStyle(
                    color: XameColors.danger, fontSize: 13)),
              ]),
            ],
            if (foundUser != null) ...[
              SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: XameColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: XameColors.primary.withValues(alpha: 0.3))),
                child: Row(children: [
                  XameAvatar(name: _contactName(foundUser!), size: 44),
                  SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_contactName(foundUser!),
                        style: TextStyle(color: context.xText,
                          fontWeight: FontWeight.w600, fontSize: 15)),
                      SizedBox(height: 2),
                      Text(foundUser!['xameId']?.toString() ?? '',
                        style: TextStyle(
                          color: context.xMuted, fontSize: 12)),
                    ])),
                  ElevatedButton(
                    onPressed: () async {
                      final self = ref.read(currentUserProvider);
                      if (self == null) return;
                      final contactId =
                        foundUser!['xameId']?.toString();
                      if (contactId == null) return;
                      await ref.read(contactsProvider.notifier)
                        .addContact(self.xameId, contactId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact added!'),
                            backgroundColor: XameColors.accent));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: XameColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    child: const Text('Add',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  String _contactName(Map<String, dynamic> u) {
    final first = u['firstName']?.toString() ?? '';
    final last  = u['lastName']?.toString()  ?? '';
    final full  = '$first $last'.trim();
    return full.isNotEmpty ? full : (u['xameId']?.toString() ?? 'Unknown');
  }

  Future<void> _doSearch(
    TextEditingController ctrl,
    StateSetter setS,
    Function(String?) setError,
    Function(Map<String,dynamic>?) setFound,
    Function(bool) setSearching,
  ) async {
    final xameId = ctrl.text.trim();
    if (xameId.isEmpty) {
      setS(() => setError('Please enter a Xame-ID'));
      return;
    }
    setS(() { setError(null); setFound(null); setSearching(true); });
    try {
      final result = await ref.read(contactsProvider.notifier)
        .searchUser(xameId);
      setS(() {
        setSearching(false);
        if (result == null) setError('User not found');
        else setFound(result);
      });
    } catch (e) {
      setS(() { setSearching(false); setError('Network error. Try again.'); });
    }
  }

  void _showMainMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.xCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 8),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: context.xMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2))),

        ListTile(
          leading: Icon(Icons.photo_library_outlined, color: context.xMuted),
          title: Text('My Portfolio',
            style: TextStyle(color: context.xText)),
          onTap: () => context.push("/gallery")),
        ListTile(
          leading: Icon(Icons.campaign_outlined, color: context.xMuted),
          title: Text("Mass Messaging",
            style: TextStyle(color: context.xText)),
          onTap: () {
            Navigator.pop(context);
            final user = ref.read(currentUserProvider);
            final socket = ref.read(socketServiceProvider);
            if (user == null) return;
            final svc = BroadcastService(socket, user.xameId);
            svc.load().then((_) => BroadcastScreen.show(context,
              service: svc,
              contacts: (ref.read(contactsProvider).value ?? []).map((c) => {"id": c.id, "name": c.name}).toList(),
              currentUserId: user.xameId,
            ));
          }),
        ListTile(
          leading: Icon(Icons.group_outlined, color: context.xMuted),
          title: Text("Groups",
            style: TextStyle(color: context.xText)),
          onTap: () {
            Navigator.pop(context);
            final user = ref.read(currentUserProvider);
            final socket = ref.read(socketServiceProvider);
            if (user == null) return;
            final svc = GroupsService(socket, user.xameId);
            GroupsListScreen.show(context,
              service: svc,
              contacts: (ref.read(contactsProvider).value ?? []).map((c) => {"id": c.id, "name": c.name}).toList(),
              currentUserId: user.xameId,
              onOpenChat: (group) {
                debugPrint("Open group chat: ${group.groupId}");
              },
            );
          }),
        ListTile(
          leading: Icon(Icons.settings_outlined, color: context.xMuted),
          title: Text('Settings',
            style: TextStyle(color: context.xText)),
          onTap: () { Navigator.pop(context); context.go('/settings'); }),
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: XameColors.danger),
          title: Text('Sign Out',
            style: TextStyle(color: XameColors.danger)),
          onTap: () { Navigator.pop(context); _signOut(); }),
        SizedBox(height: 16),
      ])),
    );
  }

  Future<void> _signOut() async {
    final user = ref.read(currentUserProvider);
    if (user != null) {
      await ref.read(authServiceProvider).logout(user.xameId);
      ref.read(socketServiceProvider).disconnect();
    }
    ref.read(currentUserProvider.notifier).state = null;
    if (mounted) context.go('/login');
  }
}

// ── Connection dot ─────────────────────────────────────────────────────────
class _ConnectionDot extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
      socketServiceProvider.select((s) => s.isConnected));
    return Container(
      width: 8, height: 8, margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? context.xAccent : Colors.orange),
    );
  }
}

// ── Chats Tab ──────────────────────────────────────────────────────────────
class _ChatsTab extends ConsumerWidget {
  final String filter;
  _ChatsTab({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final self     = ref.watch(currentUserProvider);

    return contacts.when(
      loading: () {
        final cached = contacts.valueOrNull;
        if (cached != null && cached.isNotEmpty) {
          // Cache already loaded — skip spinner and render directly
          return _buildChatList(context, ref, cached, filter, self);
        }
        return Center(
          child: CircularProgressIndicator(color: context.xPrimary));
      },
      error: (e, _) => Center(
        child: Text('Error: $e',
          style: TextStyle(color: context.xMuted))),
      data: (list) => _buildChatList(context, ref, list, filter, self),
    );
  }

  Widget _buildChatList(BuildContext context, WidgetRef ref,
      List<ContactModel> list, String filter, XameUser? self) {
        var filtered = list.where((c) =>
          filter.isEmpty ||
          c.name.toLowerCase().contains(filter.toLowerCase()) ||
          c.id.toLowerCase().contains(filter.toLowerCase())
        ).toList();

        filtered.sort((a, b) =>
          b.lastInteractionTs.compareTo(a.lastInteractionTs));

        final selfList = filtered.where((c) => c.id == self?.xameId).toList();
        final others   = filtered.where((c) => c.id != self?.xameId).toList();

        if (list.isEmpty) {
          return _EmptyChats();
        }

        final items = <Widget>[
          ...selfList.map((c) => _ContactTile(contact: c, isSelf: true)),
          if (others.isNotEmpty) _SectionHeader(others.length),
          ...others.map((c) => _ContactTile(contact: c)),
        ];

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: items.length,
          itemBuilder: (_, i) => items[i],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final int count;
  _SectionHeader(this.count);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Row(children: [
      Text('All Contacts',
        style: TextStyle(color: context.xMuted, fontSize: 12,
          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      SizedBox(width: 8),
      Text('$count',
        style: TextStyle(color: context.xMuted.withValues(alpha: 0.5), fontSize: 12)),
    ]),
  );
}

class _EmptyChats extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(
          color: XameColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24)),
        child: Icon(Icons.chat_bubble_outline_rounded,
          color: XameColors.primary, size: 36)),
      SizedBox(height: 20),
      Text('XamePage',
        style: TextStyle(color: XameColors.primary, fontSize: 28,
          fontWeight: FontWeight.w900, letterSpacing: 1)),
      SizedBox(height: 4),
      Text('created by Gibson Agbor',
        style: TextStyle(color: context.xMuted.withValues(alpha: 0.5), fontSize: 12)),
      SizedBox(height: 16),
      Text('Tap + to add a contact and start chatting',
        style: TextStyle(color: XameColors.darkSurface, fontSize: 14),
        textAlign: TextAlign.center),
    ]),
  );
}

// ── Contact Tile ───────────────────────────────────────────────────────────
class _ContactTile extends ConsumerWidget {
  final ContactModel contact;
  final bool isSelf;
  _ContactTile({required this.contact, this.isSelf = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTyping = ref.watch(typingProvider).contains(contact.id);

    return InkWell(
      onTap: () => context.go('/chat/${contact.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Stack(children: [
            XameAvatar(
              name: contact.name,
              profilePic: contact.isProfilePicHidden
                ? null : contact.profilePic,
              size: 50, isOnline: contact.isOnline,
              hasNewGallery: contact.hasNewGallery,
            ),
            if (contact.unreadCount > 0)
              Positioned(right: 0, top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.xPrimary, shape: BoxShape.circle),
                  child: Text(
                    contact.unreadCount > 99
                      ? '99+' : '${contact.unreadCount}',
                    style: TextStyle(color: Colors.black,
                      fontSize: 9, fontWeight: FontWeight.bold)),
                )),
          ]),
          SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(contact.name,
                style: TextStyle(color: context.xText, fontSize: 15,
                  fontWeight: contact.unreadCount > 0
                    ? FontWeight.w700 : FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (contact.lastInteractionTs > 0)
                Text(_fmtTime(contact.lastInteractionTs),
                  style: TextStyle(
                    color: contact.unreadCount > 0
                      ? context.xPrimary : context.xMuted.withValues(alpha: 0.3),
                    fontSize: 11)),
            ]),
            SizedBox(height: 3),
            Text(
              isTyping ? 'typing...'
                : contact.lastInteractionPreview.isNotEmpty
                  ? contact.lastInteractionPreview
                  : "Hey there I'm on XamePage",
              style: TextStyle(
                color: isTyping ? context.xAccent : context.xMuted,
                fontSize: 13,
                fontStyle: isTyping
                  ? FontStyle.italic : FontStyle.normal),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ])),
        ]),
      ),
    );
  }

  String _fmtTime(int ts) {
    final dt   = DateTime.fromMillisecondsSinceEpoch(ts);
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0)
      return '${dt.hour.toString().padLeft(2,'0')}:'
             '${dt.minute.toString().padLeft(2,'0')}';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)
      return ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][dt.weekday % 7];
    return '${dt.day}/${dt.month}/${dt.year.toString().substring(2)}';
  }
}

// ── Shared Avatar widget ───────────────────────────────────────────────────
class XameAvatar extends StatelessWidget {
  final String  name;
  final String? profilePic;
  final double  size;
  final bool    isOnline;
  final bool    hasNewGallery;

  const XameAvatar({
    super.key, required this.name,
    this.profilePic, this.size = 44, this.isOnline = false,
    this.hasNewGallery = false,
  });

  String get _initials {
    final parts = name.trim().split(' ')
      .where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none, children: [
    Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isOnline
          ? Border.all(color: XameColors.primary, width: 2) : null),
      child: ClipOval(
        child: profilePic != null && profilePic!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: profilePic!, fit: BoxFit.cover,
              placeholder: (_, __) => _Initials(_initials, size),
              errorWidget: (_, __, ___) => _Initials(_initials, size))
          : _Initials(_initials, size),
      ),
    ),
    if (isOnline)
      Positioned(right: 0, bottom: 0,
        child: Container(
          width: size * 0.26, height: size * 0.26,
          decoration: BoxDecoration(
            color: hasNewGallery ? XameColors.accent : Colors.transparent,
            shape: BoxShape.circle,
            border: hasNewGallery
                ? Border.all(color: XameColors.darkBg, width: 1.5)
                : null),
        )),
  ]);
}

class _Initials extends StatelessWidget {
  final String text; final double size;
  _Initials(this.text, this.size);
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size, color: context.xCard,
    child: Center(child: Text(text,
      style: TextStyle(color: XameColors.primary,
        fontSize: size * 0.35, fontWeight: FontWeight.bold))),
  );
}

class _PlaceholderTab extends StatelessWidget {
  final String label; final IconData icon;
  _PlaceholderTab(this.label, this.icon);
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: XameColors.darkSurface.withValues(alpha: 0.5), size: 48),
      SizedBox(height: 12),
      Text(label, style: TextStyle(color: XameColors.darkSurface, fontSize: 16)),
      SizedBox(height: 4),
      Text('Coming soon',
        style: TextStyle(color: context.xMuted.withValues(alpha: 0.5), fontSize: 12)),
    ]),
  );
}
