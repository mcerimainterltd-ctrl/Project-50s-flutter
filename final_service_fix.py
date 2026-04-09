import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Point A: Connect local camera to the local renderer
content = content.replace(
    'localStream = await navigator.mediaDevices.getUserMedia({\'audio\': true, \'video\': v});',
    'localStream = await navigator.mediaDevices.getUserMedia({\'audio\': true, \'video\': v});\n    _localRenderer.srcObject = localStream;'
)

# Point B: Connect incoming remote stream to the remote renderer
content = content.replace(
    '_pc!.onTrack = (e) => e.streams.isNotEmpty ? _remoteStreamController.add(e.streams[0]) : null;',
    '''_pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
      }
    };'''
)

with open(path, 'w') as f:
    f.write(content)
