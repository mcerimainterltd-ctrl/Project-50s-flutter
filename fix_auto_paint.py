import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Make sure we explicitly initialize the renderer's srcObject 
# and ensure tracks are 'enabled' immediately.
content = content.replace(
    'localStream = await navigator.mediaDevices.getUserMedia({',
    '''localStream = await navigator.mediaDevices.getUserMedia({'''
)

# Ensure the local renderer is updated inside the async setup
content = content.replace(
    '_localRenderer.srcObject = localStream;',
    '''_localRenderer.srcObject = localStream;
    // Notify listeners that the stream is ready to be rendered
    _callStateController.add(_callState);'''
)

with open(path, 'w') as f:
    f.write(content)
