import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCService webrtcService;
  const CallScreen({super.key, required this.webrtcService});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  void _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localRenderer.srcObject = widget.webrtcService.localStream;
    
    widget.webrtcService.remoteStream$.listen((stream) {
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          RTCVideoView(_remoteRenderer), // Remote Video
          Positioned(
            right: 20,
            bottom: 100,
            width: 120,
            height: 160,
            child: RTCVideoView(_localRenderer, mirror: true), // Local Video
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: () {
                  final webrtc = ProviderScope.containerOf(context).read(webRTCServiceProvider);
                  webrtc.endCall();
                  Navigator.pop(context);
                },
                child: const Icon(Icons.call_end),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
