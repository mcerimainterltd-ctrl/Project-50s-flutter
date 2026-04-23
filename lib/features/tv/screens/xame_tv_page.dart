import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../discovery/widgets/discovery_video_player.dart';
import '../widgets/tv_broadcast_card.dart';

class XameTVPage extends StatelessWidget {
  const XameTVPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('broadcasts').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: Colors.white)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;

          return PageView.builder(
            key: const PageStorageKey('tv_page_view'),
            scrollDirection: Axis.vertical,
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              // Keying by doc.id prevents the "identical card" glitch
              return Stack(
                key: ValueKey(doc.id),
                fit: StackFit.expand,
                children: [
                  DiscoveryVideoPlayer(
                    key: ValueKey("${doc.id}_video"),
                    videoUrl: data['videoUrl'] ?? '',
                    posterUrl: data['posterUrl'] ?? '',
                  ),
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: TVBroadcastCard(
                      key: ValueKey("${doc.id}_card"),
                      title: "${data['homeTeam'] ?? 'Team'} vs ${data['awayTeam'] ?? 'Team'}",
                      subtitle: "Live Match Coverage",
                      image: data['posterUrl'] ?? '',
                      isLive: true,
                      homeTeam: data['homeTeam'] ?? 'TBD',
                      awayTeam: data['awayTeam'] ?? 'TBD',
                      score: data['score'] ?? '0 - 0',
                      matchTime: data['matchTime'] ?? '00:00',
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
