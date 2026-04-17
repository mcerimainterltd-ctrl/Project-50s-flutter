import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'live_pulse.dart';
import '../models/discovery_item.dart';

class PeoplePerspectiveCarousel extends StatefulWidget {
  final List<DiscoveryUser> users;
  final Function(DiscoveryUser)? onAdd;
  const PeoplePerspectiveCarousel({
    Key? key,
    required this.users,
    this.onAdd,
  }) : super(key: key);

  @override
  State<PeoplePerspectiveCarousel> createState() =>
      _PeoplePerspectiveCarouselState();
}

class _PeoplePerspectiveCarouselState
    extends State<PeoplePerspectiveCarousel> {
  late PageController _ctrl;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(viewportFraction: 0.62);
    _ctrl.addListener(() {
      if (_ctrl.page != null) setState(() => _page = _ctrl.page!);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Row(children: [
          const Text('PEOPLE YOU MAY KNOW',
            style: TextStyle(
              color:       Colors.white38,
              fontSize:    11,
              fontWeight:  FontWeight.w800,
              letterSpacing: 1.2)),
          const Spacer(),
          Text('${widget.users.length} suggested',
            style: const TextStyle(
              color: Colors.white24, fontSize: 11)),
        ]),
      ),
      SizedBox(
        height: 210,
        child: PageView.builder(
          controller:  _ctrl,
          itemCount:   widget.users.length,
          itemBuilder: (_, i) {
            final rel  = i - _page;
            final user = widget.users[i];
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(rel * 0.35)
                ..scale(1 - rel.abs() * 0.08),
              alignment: Alignment.center,
              child: _PersonCard(
                user:  user,
                onAdd: () {
                  setState(() => user.isAdded = true);
                  widget.onAdd?.call(user);
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _PersonCard extends StatefulWidget {
  final DiscoveryUser  user;
  final VoidCallback   onAdd;
  const _PersonCard({required this.user, required this.onAdd});

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _addCtrl;
  late Animation<double>   _addScale;

  @override
  void initState() {
    super.initState();
    _addCtrl  = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 300));
    _addScale = Tween(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _addCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _addCtrl.dispose(); super.dispose(); }

  Future<void> _handleAdd() async {
    await _addCtrl.forward();
    await _addCtrl.reverse();
    widget.onAdd();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar with online pulse
          Stack(alignment: Alignment.center, children: [
            // Glow ring
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  const Color(0xFF7B2FFF),
                  const Color(0xFF2196F3),
                  const Color(0xFF00FF88),
                  const Color(0xFF7B2FFF),
                ])),
            ),
            Container(
              width: 68, height: 68,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0A0A0F)),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl:    user.avatarUrl,
                  fit:         BoxFit.cover,
                  placeholder: (_, __) =>
                    Container(color: const Color(0xFF1A1A2E)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A2E),
                    child: const Icon(
                      Icons.person, color: Colors.white24, size: 32)),
                ),
              ),
            ),
            if (user.isOnline)
              Positioned(
                bottom: 2, right: 2,
                child: OnlinePulseDot(size: 10)),
          ]),
          const SizedBox(height: 10),
          Text(user.name,
            style: const TextStyle(
              color:      Colors.white,
              fontSize:   14,
              fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(
            user.mutualCount > 0
              ? '${user.mutualCount} mutual${user.mutualCount > 1 ? 's' : ''}'
              : user.tagline ?? 'New to XamePage',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          // Add button with state
          ScaleTransition(
            scale: _addScale,
            child: user.isAdded
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFF00FF88).withOpacity(0.12),
                    border: Border.all(
                      color: const Color(0xFF00FF88).withOpacity(0.3))),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded,
                      color: Color(0xFF00FF88), size: 14),
                    SizedBox(width: 5),
                    Text('Added',
                      style: TextStyle(
                        color:      Color(0xFF00FF88),
                        fontSize:   12,
                        fontWeight: FontWeight.w700)),
                  ]),
                )
              : GestureDetector(
                  onTap: _handleAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(colors: [
                        Color(0xFF2196F3),
                        Color(0xFF7B2FFF),
                      ])),
                    child: const Text('Add',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   12,
                        fontWeight: FontWeight.w700)),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
