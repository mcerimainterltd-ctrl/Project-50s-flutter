import 'package:flutter/material.dart';
import 'package:realtimekit_ui/realtimekit_ui.dart';

import '../data/live_api.dart';

// XAMELIVE_STAGE_POC_V1: hidden proof-of-concept screen for the RealtimeKit
// stage. Reached by long-pressing the "Go Live" title on the setup screen.
class LiveStageTestScreen extends StatefulWidget {
  const LiveStageTestScreen({super.key});

  @override
  State<LiveStageTestScreen> createState() => _LiveStageTestScreenState();
}

class _LiveStageTestScreenState extends State<LiveStageTestScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _join(String role) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final authToken = await LiveApi().stagePocToken(role);
      if (!mounted) return;

      final meetingInfo = RtkMeetingInfo(authToken: authToken);
      final uiInfo = RealtimeKitUIInfo(meetingInfo);
      final dynamic ui = RealtimeKitUIBuilder.build(uiKitInfo: uiInfo);

      Widget page;
      try {
        page = ui.loadUI() as Widget;
      } catch (_) {
        page = ui as Widget;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XameLive stage test')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Test only. One shared room. Join as presenter on one phone '
              'and as viewer on another, then request to join the stage '
              'from the viewer phone.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _join('presenter'),
              child: const Text('Join as presenter'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : () => _join('viewer'),
              child: const Text('Join as viewer'),
            ),
            const SizedBox(height: 16),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_message != null)
              Text(
                _message!,
                style: const TextStyle(color: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }
}
