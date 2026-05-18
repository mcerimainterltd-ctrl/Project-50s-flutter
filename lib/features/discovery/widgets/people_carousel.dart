import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'live_pulse.dart';
import '../models/discovery_item.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class PeoplePerspectiveCarousel extends StatefulWidget {
  final List<DiscoveryUser> users;
  final Function(DiscoveryUser)? onAdd;
  final VoidCallback? onSeeAll;
  const PeoplePerspectiveCarousel({
    Key? key, required this.users, this.onAdd, this.onSeeAll,
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(children: [
        Text('PEOPLE YOU MAY KNOW',
          style: TextStyle(color: context.xMuted, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        Spacer(),
        GestureDetector(
          onTap: widget.onSeeAll,
          child: Text('See more',
            style: TextStyle(color: XameColors.accent, fontSize: 11, fontWeight: FontWeight.w700))),
      ]),
    ),
    SizedBox(height: 210,
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

class _PersonCard extends StatefulWidget {
  final DiscoveryUser  user;
  final VoidCallback   onAdd;
  const _PersonCard({required this.user, required this.onAdd});
  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: Duration(milliseconds: 300));
    _scale = Tween(begin: 1.0, end: 0.92).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _handleAdd() async {
    await _ctrl.forward();
    await _ctrl.reverse();
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
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            context.xText.withOpacity(0.08),
            context.xText.withOpacity(0.03),
          ]),
        border: Border.all(color: context.xText.withOpacity(0.08))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(alignment: Alignment.center, children: [
            Container(width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  context.xSecondary, context.xPrimary,
                  context.xAccent, context.xSecondary,
                ]))),
            Container(width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: context.xBg),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: user.avatarUrl, fit: BoxFit.cover,
                  placeholder: (_, __) =>
                    Container(color: context.xSurface),
                  errorWidget: (_, __, ___) => Container(
                    color: context.xSurface,
                    child: Icon(Icons.person,
                        color: context.xMuted.withValues(alpha: 0.5), size: 32)),
                ),
              ),
            ),
            if (user.isOnline)
              Positioned(bottom: 2, right: 2,
                child: OnlinePulseDot(size: 10)),
          ]),
          SizedBox(height: 10),
          Text(user.name,
            style: TextStyle(color: context.xText,
                fontSize: 14, fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: 3),
          Text(
            user.mutualCount > 0
              ? '${user.mutualCount} mutual${user.mutualCount > 1 ? "s" : ""}'
              : user.tagline ?? 'New to XamePage',
            style: TextStyle(
                color: context.xMuted, fontSize: 11)),
          SizedBox(height: 12),
          ScaleTransition(
            scale: _scale,
            child: user.isAdded
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: context.xMuted.withOpacity(0.1),
                    border: Border.all(
                        color: context.xMuted.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min,
                    children: [
                    Icon(Icons.schedule_rounded,
                        color: context.xMuted, size: 14),
                    SizedBox(width: 5),
                    Text('Requested', style: TextStyle(
                        color: context.xMuted, fontSize: 12,
                        fontWeight: FontWeight.w700)),
                  ]))
              : GestureDetector(
                  onTap: _handleAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(colors: [
                        context.xPrimary, context.xSecondary,
                      ])),
                    child: Text('Add',
                      style: TextStyle(color: context.xText,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
