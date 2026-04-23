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
        stream: FirebaseFirestore.instance
            .collection('broadcasts')
            .where('isLive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text("No Live Broadcasts Found", 
              style: TextStyle(color: Colors.white54))
            );
          }

          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return Stack(
                fit: StackFit.expand,
                children: [
                  DiscoveryVideoPlayer(
                    videoUrl: data['videoUrl'] ?? '',
                    posterUrl: data['posterUrl'] ?? '',
                  ),
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: TVBroadcastCard(
                      title: data['homeTeam'] + ' vs ' + data['awayTeam'],
                      subtitle: 'Live Match Coverage',
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
