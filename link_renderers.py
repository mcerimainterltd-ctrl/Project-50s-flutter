import os

path = 'lib/features/calling/screens/call_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Link the Full Screen view
content = content.replace(
    'showLocalFull ? webrtc.localRenderer : webrtc.remoteRenderer,',
    'showLocalFull ? webrtc.localRenderer : webrtc.remoteRenderer,'
)

# Link the Thumbnail (PIP) view
content = content.replace(
    '_isLocalMain ? webrtc.remoteRenderer : webrtc.localRenderer,',
    '_isLocalMain ? webrtc.remoteRenderer : webrtc.localRenderer,'
)

with open(path, 'w') as f:
    f.write(content)
