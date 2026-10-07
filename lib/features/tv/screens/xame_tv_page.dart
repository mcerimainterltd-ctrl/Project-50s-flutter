// lib/features/tv/screens/xame_tv_page.dart
// XameTV cinematic entry portal.
// The existing XameTvScreen remains the Free TV playback engine.

import 'package:flutter/material.dart';
import 'xame_tv_screen.dart';

class XameTVPage extends StatefulWidget {
  const XameTVPage({Key? key}) : super(key: key);

  @override
  State<XameTVPage> createState() => _XameTVPageState();
}

class _XameTVPageState extends State<XameTVPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _openFreeTV() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const XameTvScreen(isActive: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          const _CinematicBackdrop(),
          SafeArea(
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, child) {
                final eased = Curves.easeOutCubic.transform(_intro.value);

                return Opacity(
                  opacity: eased,
                  child: Transform.translate(
                    offset: Offset(0, 22 * (1 - eased)),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: _BackButton(
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Image.asset(
                              'assets/icons/xamepage_icon.png',
                              width: 94,
                              height: 94,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'XameTV',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'Your world of television',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.25,
                              ),
                            ),
                            const SizedBox(height: 42),
                            _TVDestinationCard(
                              icon: Icons.auto_awesome_rounded,
                              eyebrow: 'EXCLUSIVE',
                              title: 'PREMIUM TV',
                              description:
                                  'Elevated entertainment and premium viewing, coming to XamePage.',
                              accent: const Color(0xFF7B2FFF),
                              onTap: null,
                            ),
                            const SizedBox(height: 16),
                            _TVDestinationCard(
                              icon: Icons.live_tv_rounded,
                              eyebrow: '11,000+ CHANNELS',
                              title: 'FREE TV',
                              description:
                                  'Live television from around the world. No subscription required.',
                              accent: const Color(0xFF00D4FF),
                              onTap: _openFreeTV,
                              featured: true,
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'One world. Thousands of screens.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF596273),
                                fontSize: 12,
                                letterSpacing: 0.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CinematicBackdrop extends StatelessWidget {
  const _CinematicBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -170,
            right: -130,
            child: _Glow(
              size: 390,
              color: const Color(0xFF7B2FFF),
            ),
          ),
          Positioned(
            bottom: -210,
            left: -170,
            child: _Glow(
              size: 430,
              color: const Color(0xFF00D4FF),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0A0A0F).withOpacity(0.35),
                    const Color(0xFF0A0A0F),
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

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.14),
            color.withOpacity(0.035),
            Colors.transparent,
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141420).withOpacity(0.82),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.all(11),
          child: Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _TVDestinationCard extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback? onTap;
  final bool featured;

  const _TVDestinationCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF141420).withOpacity(0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withOpacity(featured ? 0.32 : 0.20),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(featured ? 0.09 : 0.045),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(21),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: accent.withOpacity(0.22),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xFF8D96A6),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.48),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
