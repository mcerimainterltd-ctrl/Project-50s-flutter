import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Attach local stream to renderer
if 'localStream = await' in content:
    content = content.replace(
        'localStream = await navigator.mediaDevices.getUserMedia(constraints);',
        'localStream = await navigator.mediaDevices.getUserMedia(constraints);\n    _localRenderer.srcObject = localStream;'
    )

# Attach remote stream to renderer
if 'onAddStream = (stream)' in content:
    content = content.replace(
        '_pc!.onAddStream = (stream) {',
        '_pc!.onAddStream = (stream) {\n      _remoteRenderer.srcObject = stream;'
    )

with open(path, 'w') as f:
    f.write(content)
