import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Ensure local camera is linked to the UI renderer
if '_localRenderer.srcObject = localStream;' not in content:
    content = content.replace(
        'localStream = await navigator.mediaDevices.getUserMedia(constraints);',
        'localStream = await navigator.mediaDevices.getUserMedia(constraints);\n    _localRenderer.srcObject = localStream;'
    )

# Ensure remote audio/video is linked to the UI renderer
if '_remoteRenderer.srcObject = stream;' not in content:
    content = content.replace(
        '_pc!.onAddStream = (stream) {',
        '_pc!.onAddStream = (stream) {\n      _remoteRenderer.srcObject = stream;'
    )

with open(path, 'w') as f:
    f.write(content)
