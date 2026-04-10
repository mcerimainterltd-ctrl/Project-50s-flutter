import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Update the onTrack logic to be more aggressive
old_on_track = '''    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty && _remoteRenderer.srcObject == null) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
      }
    };'''

new_on_track = '''    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        // Force the stream to the renderer immediately
        _remoteRenderer.srcObject = e.streams[0];
        
        // Ensure all incoming tracks are enabled
        for (var track in e.streams[0].getTracks()) {
          track.enabled = true;
        }
        
        _remoteStreamController.add(e.streams[0]);
        print("Remote stream attached and tracks enabled");
      }
    };'''

content = content.replace(old_on_track, new_on_track)

# Add a safety check in joinCall to ensure speaker is on for video
content = content.replace(
    '_callState = CallState.active; _callStateController.add(CallState.active);',
    'Helper.setSpeakerphoneOn(isVideo); _callState = CallState.active; _callStateController.add(CallState.active);'
)

with open(path, 'w') as f:
    f.write(content)
