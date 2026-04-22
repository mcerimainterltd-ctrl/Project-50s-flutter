import 'package:flutter/material.dart';
import '../../discovery/widgets/discovery_video_player.dart';
import '../../discovery/widgets/live_pulse.dart';
import '../widgets/tv_broadcast_card.dart';

class XameTVPage extends StatelessWidget {
  const XameTVPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("XAME TV", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: TVBroadcastCard(
                title: "Premier League Live",
                subtitle: "Arsenal vs Chelsea",
                image: "https://images.unsplash.com/photo-1574629810360-7efbbe195018",
                isLive: true,
              ),
            ),
            _buildSectionHeader("Breaking News"),
            _buildNewsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
        ],
      ),
    );
  }

  Widget _buildNewsGrid() {
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 20),
        itemCount: 3,
        itemBuilder: (context, index) => Container(
          width: 200,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: const Center(child: LivePulseIndicator()),
        ),
      ),
    );
  }
}
