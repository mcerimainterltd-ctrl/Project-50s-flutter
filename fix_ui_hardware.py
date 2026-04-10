import os

path = 'lib/features/calling/screens/call_screen.dart'
with open(path, 'r') as f:
    content = f.read()

# Re-binding the mute buttons so they actually toggle the hardware tracks
content = content.replace(
    '() => setState(() => _isCamMuted = !_isCamMuted)',
    '''() {
      setState(() => _isCamMuted = !_isCamMuted);
      webrtc.localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCamMuted);
    }'''
)

content = content.replace(
    '() => setState(() => _isMicMuted = !_isMicMuted)',
    '''() {
      setState(() => _isMicMuted = !_isMicMuted);
      webrtc.localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMicMuted);
    }'''
)

with open(path, 'w') as f:
    f.write(content)
