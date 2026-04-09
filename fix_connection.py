import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Ensure we aren't returning early due to a null check
if 'if (_peerConnection != null) return;' in content:
    content = content.replace('if (_peerConnection != null) return;', '// Re-initializing connection')

with open(path, 'w') as f:
    f.write(content)
