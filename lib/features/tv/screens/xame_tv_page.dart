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
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
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
                      title: "${data['homeTeam']} vs ${data['awayTeam']}",
                      subtitle: "Live Match Coverage",
                      image: data['posterUrl'] ?? '',
                      isLive: true,
                      homeTeam: data['homeTeam'] ?? '',
                      awayTeam: data['awayTeam'] ?? '',
                      score: data['score'] ?? '',
                      matchTime: data['matchTime'] ?? '',
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
