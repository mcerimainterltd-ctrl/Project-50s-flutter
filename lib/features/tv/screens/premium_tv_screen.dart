// XameTV Premium — isolated catalogue foundation.
// Sample local channels only; no backend, payment, or Free TV dependencies.

import 'package:flutter/material.dart';

enum _PremiumLayout { grid, list, large }

class PremiumTvScreen extends StatefulWidget {
  const PremiumTvScreen({Key? key}) : super(key: key);

  @override
  State<PremiumTvScreen> createState() => _PremiumTvScreenState();
}

class _PremiumTvScreenState extends State<PremiumTvScreen> {
  static const _gold = Color(0xFFE6C978);
  static const _goldDeep = Color(0xFFD2B36C);
  static const _background = Color(0xFF08080D);
  static const _surface = Color(0xFF141420);

  final TextEditingController _searchController = TextEditingController();

  _PremiumLayout _layout = _PremiumLayout.grid;
  String _query = '';

  final List<_PremiumChannel> _channels = const [
    _PremiumChannel(1, 'Xame Premier', 'Premium Entertainment', Icons.movie_rounded),
    _PremiumChannel(2, 'Xame Cinema', 'Premium Movies', Icons.local_movies_rounded),
    _PremiumChannel(3, 'Xame Drama', 'Drama & Series', Icons.theaters_rounded),
    _PremiumChannel(4, 'Xame Action', 'Action & Adventure', Icons.flash_on_rounded),
    _PremiumChannel(5, 'Xame World', 'International', Icons.public_rounded),
    _PremiumChannel(6, 'Xame News', 'Premium News', Icons.newspaper_rounded),
    _PremiumChannel(7, 'Xame Sports', 'Premium Sports', Icons.sports_soccer_rounded),
    _PremiumChannel(8, 'Xame Music', 'Music & Concerts', Icons.music_note_rounded),
    _PremiumChannel(9, 'Xame Kids', 'Family Entertainment', Icons.child_care_rounded),
    _PremiumChannel(10, 'Xame Nature', 'Nature & Wildlife', Icons.park_rounded),
    _PremiumChannel(11, 'Xame History', 'History & Culture', Icons.account_balance_rounded),
    _PremiumChannel(12, 'Xame Science', 'Science & Discovery', Icons.science_rounded),
    _PremiumChannel(13, 'Xame Lifestyle', 'Lifestyle', Icons.auto_awesome_rounded),
    _PremiumChannel(14, 'Xame Travel', 'Travel & Places', Icons.flight_takeoff_rounded),
    _PremiumChannel(15, 'Xame Food', 'Food & Cooking', Icons.restaurant_rounded),
    _PremiumChannel(16, 'Xame Select', 'Premium Select', Icons.workspace_premium_rounded),
    _PremiumChannel(17, 'Xame Live', 'Live Events', Icons.live_tv_rounded),
    _PremiumChannel(18, 'Xame Arena', 'Live Sports', Icons.stadium_rounded),
    _PremiumChannel(19, 'Xame Showcase', 'Featured Entertainment', Icons.star_rounded),
    _PremiumChannel(20, 'Xame Gold', 'Premium Originals', Icons.diamond_rounded),
    _PremiumChannel(21, 'Xame Classic', 'Classic Collection', Icons.auto_stories_rounded),
    _PremiumChannel(22, 'Xame Focus', 'Documentaries', Icons.camera_alt_rounded),
    _PremiumChannel(23, 'Xame Spotlight', 'Special Features', Icons.light_mode_rounded),
    _PremiumChannel(24, 'Xame One', 'Premium Flagship', Icons.emoji_events_rounded),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_PremiumChannel> get _filteredChannels {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _channels;

    return _channels.where((channel) {
      return channel.number.toString().padLeft(3, '0').contains(query) ||
          channel.name.toLowerCase().contains(query) ||
          channel.category.toLowerCase().contains(query);
    }).toList();
  }

  void _openChannel(_PremiumChannel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PremiumChannelViewer(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _filteredChannels;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        titleSpacing: 0,
        title: const Text(
          'PREMIUM TV',
          style: TextStyle(
            color: _gold,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        actions: const [
          SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: _PremiumSearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _PremiumLayoutSwitcher(
                value: _layout,
                onChanged: (value) => setState(() => _layout = value),
              ),
            ),
            Expanded(
              child: channels.isEmpty
                  ? const _EmptySearchState()
                  : _PremiumChannelCatalogue(
                      channels: channels,
                      layout: _layout,
                      onChannelTap: _openChannel,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumChannel {
  final int number;
  final String name;
  final String category;
  final IconData icon;

  // Supplied by the Premium TV catalogue when backend/live playback is wired.
  final String? artworkUrl;
  final bool isLive;
  final bool streamStarted;

  const _PremiumChannel(
    this.number,
    this.name,
    this.category,
    this.icon, {
    this.artworkUrl,
    this.isLive = false,
    this.streamStarted = false,
  });
}

class _PremiumChannelCatalogue extends StatelessWidget {
  final List<_PremiumChannel> channels;
  final _PremiumLayout layout;
  final ValueChanged<_PremiumChannel> onChannelTap;

  const _PremiumChannelCatalogue({
    required this.channels,
    required this.layout,
    required this.onChannelTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case _PremiumLayout.grid:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 9,
            mainAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: channels.length,
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _GridChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );

      case _PremiumLayout.list:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: channels.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _ListChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );

      case _PremiumLayout.large:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: channels.length,
          itemBuilder: (_, index) {
            final channel = channels[index];
            return _LargeChannelCard(
              channel: channel,
              onTap: () => onChannelTap(channel),
            );
          },
        );
    }
  }
}

class _PremiumSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PremiumSearchField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search channels...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.42)),
        prefixIcon: const Icon(Icons.search_rounded, color: _PremiumTvScreenState._gold),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                color: Colors.white54,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: _PremiumTvScreenState._surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _GridChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _GridChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ChannelCardShell(
      channel: channel,
      onTap: onTap,
      child: _PremiumChannelArtwork(
        channel: channel,
      ),
    );
  }
}

class _ListChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _ListChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 52,
                child: _PremiumChannelArtwork(
                  channel: channel,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LargeChannelCard extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;

  const _LargeChannelCard({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ChannelCardShell(
      channel: channel,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _PremiumChannelArtwork(
              channel: channel,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            channel.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            channel.category,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCardShell extends StatelessWidget {
  final _PremiumChannel channel;
  final VoidCallback onTap;
  final Widget child;

  const _ChannelCardShell({
    required this.channel,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PremiumTvScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A2417),
                      Color(0xFF141420),
                      Color(0xFF0E0E14),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: _PremiumTvScreenState._goldDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelNumber extends StatelessWidget {
  final int number;

  const _ChannelNumber({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: _PremiumTvScreenState._goldDeep.withOpacity(0.55),
        ),
      ),
      child: Text(
        number.toString().padLeft(3, '0'),
        style: const TextStyle(
          color: _PremiumTvScreenState._gold,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _PremiumLayoutSwitcher extends StatelessWidget {
  final _PremiumLayout value;
  final ValueChanged<_PremiumLayout> onChanged;

  const _PremiumLayoutSwitcher({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _PremiumTvScreenState._surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _PremiumTvScreenState._goldDeep.withOpacity(0.16),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _item(
            _PremiumLayout.grid,
            Icons.grid_view_rounded,
            'Grid',
          ),
          _item(
            _PremiumLayout.list,
            Icons.view_list_rounded,
            'List',
          ),
          _item(
            _PremiumLayout.large,
            Icons.view_agenda_rounded,
            'Large',
          ),
        ],
      ),
    );
  }

  Widget _item(
    _PremiumLayout layout,
    IconData icon,
    String label,
  ) {
    final selected = value == layout;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(layout),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? _PremiumTvScreenState._goldDeep.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(
                    color: _PremiumTvScreenState._goldDeep.withOpacity(0.32),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? _PremiumTvScreenState._gold
                    : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.35),
            ),
            const SizedBox(height: 14),
            const Text(
              'No channels found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try another channel number or name.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumChannelViewer extends StatelessWidget {
  final _PremiumChannel channel;

  const _PremiumChannelViewer({
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _PremiumChannelArtwork(
            channel: channel,
            viewer: true,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AnimatedOpacity(
                  opacity: channel.streamStarted ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOut,
                  child: _ChannelNumber(number: channel.number),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.category,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumChannelArtwork extends StatelessWidget {
  static const _logoAsset = 'assets/icons/xamepage_icon.png';

  final _PremiumChannel channel;
  final bool compact;
  final bool viewer;

  const _PremiumChannelArtwork({
    required this.channel,
    this.compact = false,
    this.viewer = false,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = channel.isLive && channel.artworkUrl != null
        ? Image.network(
            channel.artworkUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _openingSoon(),
          )
        : _openingSoon();

    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 11 : (viewer ? 0 : 14)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2A2417),
                  Color(0xFF141420),
                  Color(0xFF08080D),
                ],
              ),
            ),
          ),
          artwork,
          Positioned(
            top: compact ? 5 : 7,
            left: compact ? 5 : 7,
            child: AnimatedOpacity(
              opacity: channel.streamStarted ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOut,
              child: _ChannelNumber(number: channel.number),
            ),
          ),
        ],
      ),
    );
  }

  Widget _openingSoon() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.15,
          colors: [
            Color(0xFF292217),
            Color(0xFF141420),
            Color(0xFF08080D),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(compact ? 7 : 18),
                child: Image.asset(
                  _logoAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 2 : 8,
              0,
              compact ? 2 : 8,
              compact ? 2 : 12,
            ),
            child: Text(
              'Opening Soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: compact ? 7 : (viewer ? 15 : 12),
                fontWeight: FontWeight.w700,
                letterSpacing: compact ? 0.15 : 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
