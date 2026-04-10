import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix the scope error from Build 152 by using the class variable 'isIncomingVideo'
content = content.replace(
    'Helper.setSpeakerphoneOn(isVideo);',
    'Helper.setSpeakerphoneOn(isIncomingVideo);'
)

# Ensure tracks are forced to TRUE on initialization so they show up immediately
content = content.replace(
    'for (var track in localStream!.getTracks()) {',
    'for (var track in localStream!.getTracks()) {\n      track.enabled = true;'
)

with open(path, 'w') as f:
    f.write(content)
