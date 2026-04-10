import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix 1: Ensure onTrack binds the stream directly to the renderer
content = content.replace(
    '_pc!.onTrack = (e) => e.streams.isNotEmpty ? _remoteStreamController.add(e.streams[0]) : null;',
    '''_pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
        _callStateController.add(_callState); // Force UI update
      }
    };'''
)

# Fix 2: Ensure Local Audio Routing (Mirroring your AndroidBridge)
content = content.replace(
    'localStream!.getTracks().forEach((t) => _pc!.addTrack(t, localStream!));',
    '''localStream!.getTracks().forEach((t) => _pc!.addTrack(t, localStream!));
    if (v) Helper.setSpeakerphoneOn(true); // Mirroring your setCallAudioMode(true)'''
)

with open(path, 'w') as f:
    f.write(content)
